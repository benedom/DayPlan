#!/bin/bash
# Builds DayPlan.app next to this script. Run: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="DayPlan.app"

echo "▸ Building (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/DayPlan"

echo "▸ Rendering icon…"
swift Scripts/MakeIcon.swift >/dev/null
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DayPlan"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing (ad-hoc)…"
codesign --force --sign - "$APP"

echo "✅ Done: $(pwd)/$APP"
echo "   Open it with:  open '$(pwd)/$APP'"
echo "   Or drag it into /Applications."
