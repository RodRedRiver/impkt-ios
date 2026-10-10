#!/usr/bin/env python3
"""Does a plugged-in wrap do what the iOS app needs from it?

Follows the same steps the app takes, from a Mac, so a failure here is the
firmware or the radio and a pass here with a failure on the phone is the phone:

  1. find a wrap by the punch service UUID in its advertisement (never by name)
  2. connect, within the app's own 12 second deadline
  3. discover every service and characteristic
  4. check the characteristics the app and the page look up
  5. read the firmware version from Device Information and compare it with the
     firmware bundled in the app (IMPKT/Resources/firmware-version.txt)
  6. read the identity record and decode it the way the page does
  7. subscribe to the punch record and the IMU stream, and confirm bytes arrive
  8. check the Nordic DFU service is present, since an over-the-air update needs it

Usage: wrap-connect-test.py [--scan-seconds N] [--expect-version 2.24]
Exit status 0 only if every check passes.
"""
import argparse
import asyncio
import pathlib
import sys

from bleak import BleakClient, BleakScanner

PUNCH_SERVICE = "6e2a0001-b5a3-f393-e0a9-e50e24dcca9e"
CHARS = {
    "punch record": "6e2a0002-b5a3-f393-e0a9-e50e24dcca9e",
    "punch score": "6e2a0003-b5a3-f393-e0a9-e50e24dcca9e",
    "identity": "6e2a0009-b5a3-f393-e0a9-e50e24dcca9e",
}
DFU_SERVICE = "00001530-1212-efde-1523-785feabcd123"
DIS_FIRMWARE_REV = "00002a26-0000-1000-8000-00805f9b34fb"
CONNECT_DEADLINE = 12  # WrapCentral.connectTimeout

results = []


def check(name, ok, detail=""):
    results.append(ok)
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))
    return ok


def newer(a, b):
    """The same field by field comparison as Updater.isNewer."""
    x = [int(p) for p in a.split(".") if p.isdigit()]
    y = [int(p) for p in b.split(".") if p.isdigit()]
    if not x or not y:
        return False
    for i in range(max(len(x), len(y))):
        p = x[i] if i < len(x) else 0
        q = y[i] if i < len(y) else 0
        if p != q:
            return p > q
    return False


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scan-seconds", type=float, default=10)
    ap.add_argument("--expect-version")
    args = ap.parse_args()

    bundled = args.expect_version
    if not bundled:
        f = pathlib.Path(__file__).resolve().parent.parent / "IMPKT/Resources/firmware-version.txt"
        bundled = f.read_text().strip() if f.exists() else ""

    print(f"1. scanning {args.scan_seconds:.0f} s for the punch service")
    found = await BleakScanner.discover(timeout=args.scan_seconds, return_adv=True)
    wraps = [(d, a) for d, a in found.values()
             if PUNCH_SERVICE in [u.lower() for u in a.service_uuids]]
    if not check("a wrap is advertising the punch service", bool(wraps),
                 f"{len(found)} advertisers heard"):
        print("\n  Nothing advertised the punch service. If the board is plugged in and the serial\n"
              "  console works, the radio is not starting: look for an LFCLK / Bluefruit error in\n"
              "  the boot log, and see README section 0 on the 32 kHz crystal.")
        return 1
    dev, adv = max(wraps, key=lambda w: w[1].rssi)
    print(f"     {adv.local_name!r} {dev.address} {adv.rssi} dBm")

    print("2. connecting")
    client = BleakClient(dev, timeout=CONNECT_DEADLINE)
    try:
        await client.connect()
    except Exception as e:
        check(f"connected within {CONNECT_DEADLINE} s", False, repr(e))
        return 1
    check(f"connected within {CONNECT_DEADLINE} s", client.is_connected)

    try:
        print("3. discovering the GATT table")
        services = {s.uuid.lower(): s for s in client.services}
        chars = {c.uuid.lower(): c for s in client.services for c in s.characteristics}
        check("services discovered", bool(services), f"{len(services)} services, {len(chars)} characteristics")

        print("4. characteristics the app looks up")
        for label, uuid in CHARS.items():
            check(label, uuid in chars)
        check("punch service present", PUNCH_SERVICE in services)

        print("5. firmware version")
        fw = ""
        if DIS_FIRMWARE_REV in chars:
            raw = await client.read_gatt_char(DIS_FIRMWARE_REV)
            fw = "".join(ch for ch in raw.decode(errors="replace") if ch in "0123456789.")
        check("reports a firmware version", bool(fw), repr(fw))
        if fw and bundled:
            check(f"is not older than the version in the app ({bundled}), so no update is offered",
                  not newer(bundled, fw), f"wrap {fw}, app {bundled}")
        if args.expect_version and fw:
            check(f"is exactly {args.expect_version}", fw == args.expect_version)

        print("6. identity record")
        if CHARS["identity"] in chars:
            dv = bytes(await client.read_gatt_char(CHARS["identity"]))
            ok = len(dv) >= 11
            hand = {0x4C: "left", 0x52: "right"}.get(dv[1], "") if ok else ""
            check("11 bytes or more, with a hand", ok and bool(hand),
                  f"{len(dv)} bytes, hand={hand or '?'}")

        print("7. data arrives")
        got = {"punch": [], "other": 0}

        def on_punch(_, data):
            got["punch"].append(bytes(data))

        notifiers = [u for u, c in chars.items() if "notify" in c.properties and u.startswith("6e2a")]
        for u in notifiers:
            await client.start_notify(u, on_punch if u == CHARS["punch record"] else
                                      lambda _, d: got.__setitem__("other", got["other"] + 1))
        check("notifiable characteristics subscribed", bool(notifiers), f"{len(notifiers)} of them")
        await asyncio.sleep(5)
        check("telemetry bytes arrived in 5 s", got["other"] > 0 or bool(got["punch"]),
              f"{got['other']} telemetry notifications, {len(got['punch'])} punch records")
        for rec in got["punch"]:
            check("punch record is 20 bytes", len(rec) == 20, f"{len(rec)} bytes")

        print("8. over-the-air update path")
        check("Nordic DFU service present", DFU_SERVICE in services or
              any(DFU_SERVICE in u for u in services),
              "the app refuses an update without it")
    finally:
        await client.disconnect()

    print()
    print("ALL PASSED" if all(results) else f"{results.count(False)} CHECK(S) FAILED")
    return 0 if all(results) else 1


sys.exit(asyncio.run(main()))
