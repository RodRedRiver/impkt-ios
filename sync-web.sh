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
FW_DIR="${FW_DIR:-$HOME/Documents/Impkt}"
DEST="$HERE/IMPKT/Resources"

if [ ! -f "$PAGE" ]; then
  echo "cannot find the pilot page at $PAGE" >&2
  echo "set PAGE=/path/to/index.html and run this again" >&2
  exit 1
fi

SITE="$(cd "$(dirname "$PAGE")/.." && pwd)"

mkdir -p "$DEST/Web"
cp "$PAGE" "$DEST/Web/index.html"
echo "page:     $(wc -c < "$DEST/Web/index.html" | tr -d ' ') bytes from $PAGE"

# Everything the page asks for with a ../ path. It is served from the bundle root
# by BundleFiles, so the layout here mirrors the website's, and the app needs no
# network at all: a pilot in a gym with no signal still gets the real page.
#
# pilots.json is the activation gate. Without it the first screen cannot check a
# code and says it could not reach the pilot list, which looks like a bad code.
# It carries no names and no codes, only records encrypted under each pilot's own
# code, so shipping it inside the app gives away nothing the website does not.
mkdir -p "$DEST/css" "$DEST/fonts"
cp "$SITE/css/pilot.css" "$DEST/css/pilot.css"
cp "$SITE/fonts/ibm-plex-sans-latin.woff2" "$DEST/fonts/" 2>/dev/null || true
cp "$SITE/fonts/ibm-plex-sans-latin-ext.woff2" "$DEST/fonts/" 2>/dev/null || true
cp "$SITE/pilots.json" "$DEST/pilots.json"
echo "styles:   css/pilot.css, $(ls "$DEST/fonts" | wc -l | tr -d ' ') font file(s)"
echo "pilots:   $(python3 -c "import json;print(len(json.load(open('$DEST/pilots.json'))['records']))") record(s)"

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

# The release before it, so the app can always offer the way back. Picked by version number, not by file date.
PREV="$(ls "$FW_DIR"/BOXING-01_v*_dfu_package.zip "$FW_DIR/../Old firmware versions"/BOXING-01_v*_dfu_package.zip 2>/dev/null \
  | sed -E 's#^(.*)/BOXING-01_v(.+)_dfu_package\.zip$#\2 \1/BOXING-01_v\2_dfu_package.zip#' | sort -t' ' -k1,1 -V \
  | awk -v cur="$VER" '$1 != cur { last=$0 } $1 == cur { exit } END { print last }' | cut -d' ' -f2-)"
if [ -n "$PREV" ] && [ -f "$PREV" ]; then
  cp "$PREV" "$DEST/firmware-previous.zip"
  printf '%s\n' "$(basename "$PREV" | sed -E 's/^BOXING-01_v(.+)_dfu_package\.zip$/\1/')" > "$DEST/firmware-previous-version.txt"
  echo "previous: v$(cat "$DEST/firmware-previous-version.txt") from $(basename "$PREV")"
fi
echo
echo "Now build in Xcode. The Update tab will offer v$VER to any wrap it can see."
