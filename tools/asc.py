#!/usr/bin/env python3
"""Read App Store Connect with the CI key, without installing anything.

Why it exists: "is the build ready" is a question you otherwise answer by
refreshing a web page, and the API answers it in a second. Why it looks like
this: App Store Connect wants an ES256 JWT, and neither pyjwt nor cryptography
is installed here, so openssl signs it and the DER signature is converted to the
raw r||s pair JOSE requires.

    python3 tools/asc.py builds            newest builds and their state
    python3 tools/asc.py testers           every group and who is in it
    python3 tools/asc.py certs             signing certificates on the account
    python3 tools/asc.py get <path>        any GET, e.g. v1/apps
    python3 tools/asc.py invite <email>    internal group, that tester, newest build
    python3 tools/asc.py invite-external <email> [group]
                                           external group, no account access
    python3 tools/asc.py sweep-certs [n]   revoke the dead runner certificates
    python3 tools/asc.py review-status     what external testers are waiting on
    python3 tools/asc.py submit-review     newest build to Beta App Review
    python3 tools/asc.py attach-latest [group]
                                           newest build into an external group

Five commands change something. Both invites email the person they add.
`sweep-certs` revokes certificates, and what it will and will not touch is the
whole of its docstring. `submit-review` writes the beta metadata and hands the
build to Apple. Everything else is read only.

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


def patch(path, body):
    req = urllib.request.Request(API + path.lstrip("/"),
                                 data=json.dumps(body).encode(),
                                 method="PATCH")
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


def invite(email, group_name="Bench", internal=True):
    """Add a tester to a group, making the group if it is not there yet.

    internal=True is the fast path and the narrow one: an internal tester gets
    the build within minutes and needs no Apple review, but Apple only allows it
    for people who are users on the App Store Connect account. Adding a stranger
    to an internal group fails with 409 "Tester(s) cannot be assigned", which is
    that rule and not a bug here.

    internal=False is the path for everyone else. No account access, thousands of
    testers, but a build has to pass Beta App Review before an external tester can
    install it. `review-status` says whether that has happened.
    """
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
                                        "isInternalGroup": internal,
                                        "hasAccessToAllBuilds": True},
                         "relationships": {"app": {"data": {"type": "apps",
                                                            "id": aid}}}}}
        group = post("v1/betaGroups", body)["data"]
        print("created %s group %r, with access to all builds"
              % ("internal" if internal else "external", group_name))
    else:
        was = "internal" if group["attributes"].get("isInternalGroup") else "external"
        print("group %r already exists (%s)" % (group_name, was))

    people = get("v1/betaGroups/%s/betaTesters?limit=100" % group["id"])["data"]
    mine = next((t for t in people
                 if t["attributes"].get("email", "").lower() == email.lower()), None)
    if mine:
        print("%s is already in it, state %s" % (email, mine["attributes"].get("state")))
    else:
        body = {"data": {"type": "betaTesters",
                         "attributes": {"email": email},
                         "relationships": {"betaGroups": {
                             "data": [{"type": "betaGroups", "id": group["id"]}]}}}}
        made = post("v1/betaTesters", body)["data"]["attributes"]
        # The state is read back rather than assumed. An internal tester is
        # INVITED straight away, but an external one sits at NOT_INVITED until a
        # build has passed Beta App Review: Apple will not email an invitation to
        # something nobody is allowed to install yet. Printing "invite sent" there
        # would have someone waiting on a mail that is not coming.
        state = made.get("state")
        print("added %s, state %s" % (email, state))
        if state == "NOT_INVITED":
            print("  Apple sends nothing yet: an external tester waits for a build")
            print("  to pass Beta App Review. Run review-status to see where that is.")

    if not group["attributes"].get("hasAccessToAllBuilds"):
        newest = get("v1/builds?filter[app]=%s&limit=1&sort=-version" % aid)["data"]
        if newest:
            post("v1/betaGroups/%s/relationships/builds" % group["id"],
                 {"data": [{"type": "builds", "id": newest[0]["id"]}]})
            print("attached build %s" % newest[0]["attributes"].get("version"))


# What Apple is told about the beta, kept here rather than typed into a web form
# so it is reviewable, and so resubmitting says the same thing as last time.
#
# The demo code is the crux. The app opens on an activation gate, and a reviewer
# who cannot get past it rejects the build for being unusable, which is the most
# common way a hardware companion app fails beta review. The code below is a real
# one, issued for review and for nothing else, so no pilot's name is shown to a
# stranger.
REVIEW_CODE = "HQDGN-NBHJK"

BETA_DESCRIPTION = """\
IMPKT is the companion app for a pair of boxing wraps that record punches. A \
pilot enters the activation code they were sent, reads a one page briefing, and \
runs a timed drill. The app also installs firmware on the wraps over Bluetooth.

The wraps are not needed to try it. During a drill, tapping the circle on screen \
logs a punch exactly as the hardware would, so the whole flow can be seen with \
no device present."""

WHATS_NEW = """\
Enter the activation code once on the first screen. It is remembered from then \
on, so opening the app again goes straight to the briefing.

Then start the drill and tap the circle for every punch."""

REVIEW_NOTES = """\
The first screen asks for an activation code. Use %s. There is one field and it \
takes the code, so the demo account name and password above are both that code.

No hardware is needed to review this. Open the Test tab, enter the code, tap \
"Start the drill", then tap the large circle on screen, or press the space bar, \
once for every punch. The circle logs a punch exactly as the wraps would.

The Update tab installs firmware on the wraps over Bluetooth. With no wraps \
nearby it scans and finds nothing, which is the expected result and not a \
failure. Bluetooth is used only to reach the wraps, which are the product.""" % REVIEW_CODE

CONTACT = {"contactFirstName": "Rodrigo",
           "contactLastName": "Rio-Tinto",
           "contactEmail": "rodrigo.rio.tinto@gmail.com"}
LOCALE = "en-US"


def newest_build(aid):
    data = get("v1/builds?filter[app]=%s&limit=1&sort=-version" % aid)["data"]
    if not data:
        sys.exit("no builds to submit")
    return data[0]


def set_beta_metadata(aid):
    """The app level half: what the beta is, and where feedback goes."""
    existing = get("v1/apps/%s/betaAppLocalizations" % aid)["data"]
    mine = next((l for l in existing
                 if l["attributes"].get("locale") == LOCALE), None)
    attrs = {"description": BETA_DESCRIPTION,
             "feedbackEmail": CONTACT["contactEmail"]}
    if mine:
        patch("v1/betaAppLocalizations/" + mine["id"],
              {"data": {"type": "betaAppLocalizations", "id": mine["id"],
                        "attributes": attrs}})
        print("updated the beta description")
    else:
        body = dict(attrs); body["locale"] = LOCALE
        post("v1/betaAppLocalizations",
             {"data": {"type": "betaAppLocalizations", "attributes": body,
                       "relationships": {"app": {"data": {"type": "apps",
                                                          "id": aid}}}}})
        print("wrote the beta description and feedback email")

    # The review detail's id is the app's id, and it always exists, empty. So it
    # is only ever patched, never created.
    detail = dict(CONTACT)
    detail["notes"] = REVIEW_NOTES
    detail["demoAccountRequired"] = True
    detail["demoAccountName"] = REVIEW_CODE
    detail["demoAccountPassword"] = REVIEW_CODE
    phone = os.environ.get("ASC_CONTACT_PHONE")
    if phone:
        detail["contactPhone"] = phone
    patch("v1/betaAppReviewDetails/" + aid,
          {"data": {"type": "betaAppReviewDetails", "id": aid,
                    "attributes": detail}})
    print("wrote the review contact and notes%s"
          % ("" if phone else ", with no phone number: set ASC_CONTACT_PHONE"))


def set_build_notes(build_id):
    """The per build half: what to test in this one."""
    existing = get("v1/builds/%s/betaBuildLocalizations" % build_id)["data"]
    mine = next((l for l in existing
                 if l["attributes"].get("locale") == LOCALE), None)
    if mine:
        patch("v1/betaBuildLocalizations/" + mine["id"],
              {"data": {"type": "betaBuildLocalizations", "id": mine["id"],
                        "attributes": {"whatsNew": WHATS_NEW}}})
        print("updated what to test")
    else:
        post("v1/betaBuildLocalizations",
             {"data": {"type": "betaBuildLocalizations",
                       "attributes": {"whatsNew": WHATS_NEW, "locale": LOCALE},
                       "relationships": {"build": {"data": {"type": "builds",
                                                            "id": build_id}}}}})
        print("wrote what to test")


def review_status():
    """Everything standing between an external tester and the app."""
    aid = app_id()
    build = newest_build(aid)
    ba = build["attributes"]
    print("newest build %s, %s" % (ba.get("version"), ba.get("processingState")))

    det = get("v1/builds/%s/buildBetaDetail" % build["id"])["data"]["attributes"]
    print("  external state: %s" % det.get("externalBuildState"))

    loc = get("v1/apps/%s/betaAppLocalizations" % aid)["data"]
    print("  beta description: %s" % ("yes" if loc else "MISSING"))

    bl = get("v1/builds/%s/betaBuildLocalizations" % build["id"])["data"]
    print("  what to test: %s" % ("yes" if bl and bl[0]["attributes"].get("whatsNew")
                                  else "MISSING"))

    d = get("v1/apps/%s/betaAppReviewDetail" % aid)["data"]["attributes"]
    have = [k for k in ("contactEmail", "contactPhone", "notes") if d.get(k)]
    print("  review contact: %s" % (", ".join(have) if have else "MISSING"))

    groups = get("v1/betaGroups?filter[app]=%s&limit=20" % aid)["data"]
    for g in groups:
        if g["attributes"].get("isInternalGroup"):
            continue
        builds = get("v1/betaGroups/%s/builds?limit=20" % g["id"])["data"]
        vs = [b["attributes"].get("version") for b in builds]
        print("  external group %r has build(s): %s"
              % (g["attributes"]["name"], ", ".join(vs) if vs else "none"))


def submit_review():
    """Fill everything in and hand the newest build to Beta App Review.

    Only external testers need this. An internal tester can install the moment a
    build finishes processing, which is why nothing asked for it until now.
    """
    aid = app_id()
    build = newest_build(aid)
    version = build["attributes"].get("version")

    det = get("v1/builds/%s/buildBetaDetail" % build["id"])["data"]["attributes"]
    state = det.get("externalBuildState")
    if state not in ("READY_FOR_BETA_SUBMISSION", "WAITING_FOR_BETA_REVIEW"):
        print("build %s external state is %s" % (version, state))
        if state in ("IN_BETA_TESTING", "BETA_APPROVED"):
            print("already through review, nothing to submit")
            return

    set_beta_metadata(aid)
    set_build_notes(build["id"])

    try:
        post("v1/betaAppReviewSubmissions",
             {"data": {"type": "betaAppReviewSubmissions",
                       "relationships": {"build": {"data": {"type": "builds",
                                                            "id": build["id"]}}}}})
        print("submitted build %s for Beta App Review" % version)
    except urllib.error.HTTPError as e:
        # Worth reading rather than raising: Apple names the missing field here,
        # and that is the difference between a two minute fix and a guess.
        sys.exit("Apple would not take build %s: %s"
                 % (version, e.read().decode()[:800]))


def attach_latest(group_name="Pilots"):
    """Put the newest build in an external group.

    An external group cannot be given access to all builds: Apple rejects the
    attribute, because every build an external tester sees has to pass review
    first. So each new build has to be attached, and this is that step.
    """
    aid = app_id()
    groups = get("v1/betaGroups?filter[app]=%s&limit=20" % aid)["data"]
    group = next((g for g in groups
                  if g["attributes"].get("name") == group_name), None)
    if group is None:
        sys.exit("no group called %r" % group_name)
    build = newest_build(aid)
    post("v1/betaGroups/%s/relationships/builds" % group["id"],
         {"data": [{"type": "builds", "id": build["id"]}]})
    print("attached build %s to %r" % (build["attributes"].get("version"), group_name))


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
        elif what == "invite-external":
            invite(sys.argv[2],
                   sys.argv[3] if len(sys.argv) > 3 else "Pilots",
                   internal=False)
        elif what == "sweep-certs":
            sweep_certs(int(sys.argv[2]) if len(sys.argv) > 2 else 0)
        elif what == "review-status": review_status()
        elif what == "submit-review": submit_review()
        elif what == "attach-latest":
            attach_latest(sys.argv[2] if len(sys.argv) > 2 else "Pilots")
        else: sys.exit(__doc__)
    except urllib.error.HTTPError as e:
        sys.exit("App Store Connect said %s: %s" % (e.code, e.read().decode()[:600]))
