#!/bin/bash
# The app's own logic, tested with the Swift compiler alone: no Xcode, no simulator, no phone.
# FirmwareVersion.swift, Punch.swift and ConnectionLog.swift are Foundation only on purpose, so they compile here.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
# main.swift is what makes the test file a program; the sources are compiled with it.
cp "$HERE/Tests/AppLogicTests.swift" "$OUT/main.swift"
swiftc -o "$OUT/app-logic-tests" "$OUT/main.swift" \
  "$HERE/IMPKT/FirmwareVersion.swift" "$HERE/IMPKT/Punch.swift" "$HERE/IMPKT/ConnectionLog.swift"
"$OUT/app-logic-tests" "$HERE"
