#!/bin/bash
# Build the Beta tab's app from beta/ and copy it into the app bundle.
#
# beta/ is the Lovable project, as it came out of Lovable, plus the band link in
# src/lib/band.ts. `npm run build:app` builds it as a single page under /Beta/ with
# the web-only parts (install prompt, update polling) switched off, and what lands in
# IMPKT/Resources/Beta is committed, like the Test tab's page, so the GitHub build
# needs no Node. Run this after changing anything in beta/, then commit both.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/beta"
DEST="$HERE/IMPKT/Resources/Beta"

cd "$SRC"
[ -d node_modules ] || npm install --no-audit --no-fund
npm run build:app >/dev/null

# The page and its assets, and nothing else. The splash screens, store screenshots and
# web manifest are for installing it as a website, which the app has already done.
rm -rf "$DEST"
mkdir -p "$DEST"
cp dist-app/client/index.html "$DEST/index.html"
cp -R dist-app/client/assets "$DEST/assets"

echo "beta:     $(du -sh "$DEST" | cut -f1 | tr -d ' ') in IMPKT/Resources/Beta"
echo "Now build in Xcode. The Beta tab will open it."
