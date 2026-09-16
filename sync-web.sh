#!/bin/bash
# Copy the live pilot page and the current firmware into the app bundle.
#
# The page has one home, stryke-systems/test/index.html, and the app carries a
# copy rather than a fork. Run this before a build so the app and the website are
# never explaining two different products, and so a firmware release and an app
# release are the same event.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PAGE="${PAGE:-$HOME/stryke-systems/test/index.html}"
FW_DIR="${FW_DIR:-$HOME/Documents/boxing-fw}"
DEST="$HERE/IMPKT/Resources"

if [ ! -f "$PAGE" ]; then
  echo "cannot find the pilot page at $PAGE" >&2
  echo "set PAGE=/path/to/index.html and run this again" >&2
  exit 1
fi

mkdir -p "$DEST/Web"
cp "$PAGE" "$DEST/Web/index.html"
echo "page:     $(wc -c < "$DEST/Web/index.html" | tr -d ' ') bytes from $PAGE"

# The newest DFU package, which is what a phone installs. The .uf2 is for the
# drag-and-drop bootloader over USB and is no use to the app.
ZIP="$(ls -t "$FW_DIR"/BOXING-01_v*_dfu_package.zip 2>/dev/null | head -1 || true)"
if [ -z "$ZIP" ]; then
  echo "no DFU package in $FW_DIR — run ./build.sh dfu-zip there first" >&2
  exit 1
fi
cp "$ZIP" "$DEST/firmware.zip"

VER="$(basename "$ZIP" | sed -E 's/^BOXING-01_v(.+)_dfu_package\.zip$/\1/')"
printf '%s\n' "$VER" > "$DEST/firmware-version.txt"
echo "firmware: v$VER from $(basename "$ZIP")"
echo
echo "Now build in Xcode. The Update tab will offer v$VER to any wrap it can see."
