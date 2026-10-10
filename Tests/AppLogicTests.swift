import Foundation

var failures = 0
func expect(_ ok: Bool, _ what: String, line: Int = #line) {
    if ok { print("  PASS  \(what)") } else { print("  FAIL  \(what)  (line \(line))"); failures += 1 }
}

print("firmware version logic")
expect(FirmwareVersion.isNewer("2.24", than: "2.21"), "2.24 is newer than 2.21")
expect(!FirmwareVersion.isNewer("2.24", than: "2.24"), "2.24 is not newer than 2.24")
expect(!FirmwareVersion.isNewer("2.21", than: "2.24"), "2.21 is not newer than 2.24")
expect(FirmwareVersion.isNewer("2.10", than: "2.9"), "2.10 is newer than 2.9, compared as numbers")
expect(!FirmwareVersion.isNewer("2.24", than: ""), "nothing is newer than a wrap that did not say")
expect(!FirmwareVersion.isNewer("", than: "2.24"), "an app with no version offers nothing")
expect(FirmwareVersion.isSame("2.24", as: "2.24.0"), "2.24 and 2.24.0 are one release")

print("the button beside a wrap")
expect(FirmwareVersion.action(bundled: "2.24", reported: "2.24") == .reinstall,
       "a wrap on 2.24 with 2.24 in the app is not offered an update")
expect(FirmwareVersion.action(bundled: "2.24", reported: "2.24").label("2.24") == "Reinstall 2.24",
       "its button reads Reinstall 2.24")
expect(FirmwareVersion.action(bundled: "2.24", reported: "2.21") == .update, "a wrap on 2.21 is offered an update")
expect(FirmwareVersion.action(bundled: "2.24", reported: "2.21").label("2.24") == "Update to 2.24",
       "its button reads Update to 2.24")
expect(FirmwareVersion.action(bundled: "2.21", reported: "2.24") == .replace, "a wrap newer than the app is not called an update")
expect(FirmwareVersion.action(bundled: "2.24", reported: "") == .install, "a wrap that has not said is not called an update")

print("the bundled firmware is the one on the sensor")
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let bundled = (try? String(contentsOf: root.appendingPathComponent("IMPKT/Resources/firmware-version.txt"), encoding: .utf8))?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
expect(bundled == "2.24", "the app bundles firmware 2.24 (found '\(bundled)')")
let previous = (try? String(contentsOf: root.appendingPathComponent("IMPKT/Resources/firmware-previous-version.txt"), encoding: .utf8))?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
expect(FirmwareVersion.isNewer(bundled, than: previous), "the way back (\(previous)) is older than the bundled release")

print("a v2.24 punch packet")
// punch_packet_t, 20 bytes little endian, as boxing_fw.ino lays it out.
var pkt = [UInt8](repeating: 0, count: 20)
func put(_ at: Int, _ v: Int) { pkt[at] = UInt8(v & 0xFF); pkt[at + 1] = UInt8((v >> 8) & 0xFF) }
put(0, 7); put(2, 853); put(4, 9120); put(6, 9400); put(8, 7350); put(10, 1250)
put(12, 180); put(14, 0); pkt[16] = 0x10 | 0x08; pkt[17] = 0; put(18, 9120)
if let p = Punch.record(Data(pkt)) {
    expect(p.seq == 7, "seq")
    expect(abs(p.score - 85.3) < 0.01, "score 85.3")
    expect(abs(p.peakG - 9.12) < 0.001, "peak 9.12 g")
    expect(abs(p.speed - 7.35) < 0.001, "speed 7.35 m/s")
    expect(p.rebuilt, "GYRO_LATE (0x10) does not hide the rebuilt flag (0x08)")
    expect(!p.replay, "GYRO_LATE is not read as a replay")
} else { expect(false, "a 20 byte v2.24 packet decodes") }
expect(Punch.record(Data(pkt.prefix(19))) == nil, "a 19 byte packet is refused")
let sliced = Data([9, 9] + pkt).dropFirst(2)
expect(Punch.record(sliced)?.seq == 7, "a Data slice (non zero startIndex) decodes the same")

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
