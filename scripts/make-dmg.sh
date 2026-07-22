#!/usr/bin/env bash
#
# Packages a built lrclrclrc.app into a compressed .dmg with the classic
# drag-to-Applications layout. Run scripts/build-app.sh first.
#
# Usage: bash scripts/make-dmg.sh

set -euo pipefail
cd "$(dirname "$0")/.."

APP="lrclrclrc.app"
DMG="lrclrclrc.dmg"
VOLNAME="lrclrclrc"

if [[ ! -d "$APP" ]]; then
  echo "✗ ${APP} not found — run 'bash scripts/build-app.sh' first" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications" # drag-target in the DMG window

rm -f "$DMG"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG"

echo "✓ built ${DMG}"
