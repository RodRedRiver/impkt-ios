#!/usr/bin/env python3
"""Read App Store Connect with the CI key, without installing anything.

Why it exists: "is the build ready" is a question you otherwise answer by
refreshing a web page, and the API answers it in a second. Why it looks like
this: App Store Connect wants an ES256 JWT, and neither pyjwt nor cryptography
is installed here, so openssl signs it and the DER signature is converted to the
raw r||s pair JOSE requires.

    python3 tools/asc.py builds            newest builds and their state
    python3 tools/asc.py testers           internal groups and their testers
    python3 tools/asc.py certs             signing certificates on the account
    python3 tools/asc.py get <path>        any GET, e.g. v1/apps
    python3 tools/asc.py invite <email>    internal group, that tester, newest build
    python3 tools/asc.py sweep-certs [n]   revoke the dead runner certificates

Two commands change something. `invite` emails the person it adds. `sweep-certs`
revokes certificates, and what it will and will not touch is the whole of its
docstring. Everything else is read only.

The key is never printed and never leaves the machine except to Apple. Its path
and the two ids come from the environment, or from these defaults, which are
identifiers rather than secrets:
"""

import json
import os
import subprocess
import sys
import time
import urllib.request

KEY_ID    = os.environ.get("ASC_KEY_ID", "4C8FFW8VU5")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "c1cf350f-ace0-43d6-90f7-138ce1b48f8a")
KEY_PATH  = os.environ.get("ASC_KEY_PATH",
                           os.path.expanduser("~/Downloads/AuthKey_%s.p8" % KEY_ID))
BUNDLE_ID = "com.impktband.pilot"
API       = "https://api.appstoreconnect.apple.com/"


def b64(data):
    import base64
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def der_to_jose(der):
    """SEQUENCE { INTEGER r, INTEGER s } to the fixed 64 bytes JOSE wants.

    openssl emits DER, where each integer is minimal length and may carry a
    leading zero byte to keep it positive. JOSE wants both halves padded to
    exactly 32 bytes, so trimming and padding here is the whole conversion.
    """
    assert der[0] == 0x30
    i = 2 if der[1] < 0x80 else 3
    out = b""
    for _ in range(2):
        assert der[i] == 0x02
        length = der[i + 1]
        val = der[i + 2:i + 2 + length].lstrip(b"\x00")
        out += val.rjust(32, b"\x00")
        i += 2 + length
    return out


def token():
    now = int(time.time())
    header  = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    payload = {"iss": ISSUER_ID, "iat": now, "exp": now + 600,
               "aud": "appstoreconnect-v1"}
    signing_input = (b64(json.dumps(header, separators=(",", ":")).encode())
                     + b"." +
                     b64(json.dumps(payload, separators=(",", ":")).encode()))
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", KEY_PATH, "-binary"],
                         input=signing_input, capture_output=True, check=True).stdout
    return (signing_input + b"." + b64(der_to_jose(der))).decode()


def ssl_context():
    """This python has no root certificates of its own, so verification fails on
    every https call until it is handed the system bundle. Verification stays on:
    the alternative people reach for is turning it off, over a link carrying a
    signed credential."""
    import ssl
    for bundle in ("/etc/ssl/cert.pem", "/private/etc/ssl/cert.pem"):
        if os.path.exists(bundle):
            return ssl.create_default_context(cafile=bundle)
    return ssl.create_default_context()


def get(path):
    req = urllib.request.Request(API + path.lstrip("/"))
    req.add_header("Authorization", "Bearer " + token())
    with urllib.request.urlopen(req, timeout=30, context=ssl_context()) as r:
        return json.load(r)


def post(path, body):
    req = urllib.request.Request(API + path.lstrip("/"),
                                 data=json.dumps(body).encode(),
                                 method="POST")
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=30, context=ssl_context()) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}


def delete(path):
    req = urllib.request.Request(API + path.lstrip("/"), method="DELETE")
    req.add_header("Authorization", "Bearer " + token())
    with urllib.request.urlopen(req, timeout=30, context=ssl_context()) as r:
        r.read()


def app_id():
    data = get("v1/apps?filter[bundleId]=" + BUNDLE_ID)
    if not data["data"]:
        sys.exit("no app record with bundle id " + BUNDLE_ID)
    return data["data"][0]["id"]


def builds():
    aid = app_id()
    data = get("v1/builds?filter[app]=%s&limit=10&sort=-version" % aid)
    if not data["data"]:
        print("no builds yet")
        return
    for b in data["data"]:
        a = b["attributes"]
        print("build %-4s %-12s uploaded %s  expired %s"
              % (a.get("version"), a.get("processingState"),
                 a.get("uploadedDate"), a.get("expired")))


def testers():
    aid = app_id()
    groups = get("v1/betaGroups?filter[app]=%s&limit=20" % aid)
    if not groups["data"]:
        print("no beta groups: nobody can install it yet")
        return
    for g in groups["data"]:
        a = g["attributes"]
        kind = "internal" if a.get("isInternalGroup") else "external"
        link = a.get("publicLink") or "no public link"
        print("%s (%s), %s" % (a.get("name"), kind, link))
        people = get("v1/betaGroups/%s/betaTesters?limit=50" % g["id"])
        for t in people["data"]:
            ta = t["attributes"]
            print("   %s %s  %s  %s" % (ta.get("firstName") or "", ta.get("lastName") or "",
                                        ta.get("email"), ta.get("state")))
        if not people["data"]:
            print("   nobody in this group")


# A certificate this script is allowed to revoke has both of these. Neither is
# decoration: the type keeps it away from anything that ships an app, and the
# display name is what Apple puts on a certificate created through the API, which
# is the only kind CI makes. One made by a person in Xcode is named after them and
# is never matched here.
SWEEPABLE_TYPE = "DEVELOPMENT"
SWEEPABLE_NAME = "Created via API"


def certs():
    for c in get("v1/certificates?limit=200")["data"]:
        a = c["attributes"]
        mine = (a.get("certificateType") == SWEEPABLE_TYPE
                and a.get("displayName") == SWEEPABLE_NAME)
        print("%-14s %-24s expires %s  %s"
              % (a.get("certificateType"), a.get("displayName"),
                 (a.get("expirationDate") or "")[:10],
                 "sweepable" if mine else "left alone"))


def sweep_certs(keep=0):
    """Revoke the Apple Development certificates the CI runners left behind.

    Why this has to exist: the Archive step signs with automatic signing on a
    fresh GitHub runner, and a runner with an empty keychain does not reuse a
    certificate, it makes one. Apple caps a team at ten, so the eleventh push
    fails with "choose a certificate to revoke" — a signing error with nothing
    wrong with the signing.

    Why it is safe: every certificate it makes is dead the moment the run ends.
    The private key lived in that runner's keychain and the runner is destroyed,
    so what is left on the account is a public half nothing on earth can sign
    with. Revoking one cannot affect a build that already uploaded either, since
    a certificate is only consulted at signing time.

    What it will not touch, ever: anything that is not DEVELOPMENT, and anything
    whose display name is not the one Apple gives an API-created certificate. A
    distribution certificate and a certificate somebody made in Xcode on their
    own Mac are both invisible to this.

    `keep` holds back that many of the newest, which is here for running it by
    hand while wondering whether it is about to do something regrettable.
    """
    all_certs = get("v1/certificates?limit=200")["data"]
    mine = [c for c in all_certs
            if c["attributes"].get("certificateType") == SWEEPABLE_TYPE
            and c["attributes"].get("displayName") == SWEEPABLE_NAME]
    others = len(all_certs) - len(mine)

    mine.sort(key=lambda c: c["attributes"].get("expirationDate") or "", reverse=True)
    doomed = mine[keep:]

    print("%d certificate(s) on the account: %d from a runner, %d left alone"
          % (len(all_certs), len(mine), others))
    if not doomed:
        print("nothing to sweep")
        return

    for c in doomed:
        delete("v1/certificates/" + c["id"])
        print("revoked the runner certificate expiring %s"
              % (c["attributes"].get("expirationDate") or "")[:10])
    print("%d slot(s) free for this build" % len(doomed))


def invite(email, group_name="Bench"):
    aid = app_id()

    groups = get("v1/betaGroups?filter[app]=%s&limit=20" % aid)["data"]
    group = next((g for g in groups
                  if g["attributes"].get("name") == group_name), None)
    if group is None:
        # hasAccessToAllBuilds matters more than it looks: without it every future
        # CI build has to be attached to the group by hand before anyone can
        # install it, which is exactly the step that gets forgotten.
        body = {"data": {"type": "betaGroups",
                         "attributes": {"name": group_name,
                                        "isInternalGroup": True,
                                        "hasAccessToAllBuilds": True},
                         "relationships": {"app": {"data": {"type": "apps",
                                                            "id": aid}}}}}
        group = post("v1/betaGroups", body)["data"]
        print("created internal group %r, with access to all builds" % group_name)
    else:
        print("group %r already exists" % group_name)

    people = get("v1/betaGroups/%s/betaTesters?limit=100" % group["id"])["data"]
    if any(t["attributes"].get("email", "").lower() == email.lower() for t in people):
        print("%s is already in it" % email)
    else:
        body = {"data": {"type": "betaTesters",
                         "attributes": {"email": email},
                         "relationships": {"betaGroups": {
                             "data": [{"type": "betaGroups", "id": group["id"]}]}}}}
        post("v1/betaTesters", body)
        print("added %s, Apple has emailed the invite" % email)

    if not group["attributes"].get("hasAccessToAllBuilds"):
        newest = get("v1/builds?filter[app]=%s&limit=1&sort=-version" % aid)["data"]
        if newest:
            post("v1/betaGroups/%s/relationships/builds" % group["id"],
                 {"data": [{"type": "builds", "id": newest[0]["id"]}]})
            print("attached build %s" % newest[0]["attributes"].get("version"))


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "builds"
    if not os.path.exists(KEY_PATH):
        sys.exit("no key at %s; set ASC_KEY_PATH" % KEY_PATH)
    try:
        if   what == "builds":  builds()
        elif what == "testers": testers()
        elif what == "certs":   certs()
        elif what == "get":     print(json.dumps(get(sys.argv[2]), indent=2))
        elif what == "invite":  invite(sys.argv[2])
        elif what == "sweep-certs":
            sweep_certs(int(sys.argv[2]) if len(sys.argv) > 2 else 0)
        else: sys.exit(__doc__)
    except urllib.error.HTTPError as e:
        sys.exit("App Store Connect said %s: %s" % (e.code, e.read().decode()[:600]))
