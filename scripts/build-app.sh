#!/usr/bin/env bash
#
# Compiles the Swift package and assembles a runnable lrclrclrc.app bundle,
# ad-hoc signed with the automation entitlement. No Apple Developer account
# needed — this produces a locally-signed app that runs on this machine.
#
# Usage: bash scripts/build-app.sh [debug|release]   (default: release)

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="lrclrclrc.app"

echo "▸ swift build ($CONFIG)…"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/lrclrclrc"
if [[ ! -x "$BIN" ]]; then
  echo "✗ built binary not found at $BIN" >&2
  exit 1
fi

echo "▸ assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/lrclrclrc"
cp bundling/Info.plist "$APP/Contents/Info.plist"

echo "▸ ad-hoc signing…"
if ! codesign --force --sign - \
      --entitlements bundling/lrclrclrc.entitlements \
      --options runtime "$APP" 2>/dev/null; then
  # Fall back to a plain ad-hoc signature if hardened-runtime signing is unavailable.
  codesign --force --sign - "$APP"
fi

echo "✓ built $APP"
echo "  run it with:  open $APP"
