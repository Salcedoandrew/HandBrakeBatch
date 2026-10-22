#!/bin/bash
# Builds "HandBrake Batch.app" with SwiftPM (Command Line Tools are enough) and ad-hoc signs it.
# Usage: ./build.sh [--install] [--dmg]
set -euo pipefail
cd "$(dirname "$0")"
APP="build/HandBrake Batch.app"
swift build -c release --triple arm64-apple-macosx13.0 2>&1 | grep -E "error|Compiling|Build" || true
BINS=(".build/arm64-apple-macosx/release/HandBrakeBatch")
if swift build -c release --triple x86_64-apple-macosx13.0 >/dev/null 2>&1; then
  BINS+=(".build/x86_64-apple-macosx/release/HandBrakeBatch")
fi
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/HandBrake Batch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/YouTubeRenders.json "$APP/Contents/Resources/"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep -s - "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/HandBrake Batch"))"
if [[ " $* " == *" --install "* ]]; then
  rm -rf "/Applications/HandBrake Batch.app"
  ditto "$APP" "/Applications/HandBrake Batch.app"
  echo "Installed to /Applications/HandBrake Batch.app"
fi
if [[ " $* " == *" --dmg "* ]]; then
  V=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
  DMG="build/HandBrake-Batch-$V-universal.dmg"; SRC="build/dmgsrc"
  rm -rf "$DMG" "$SRC" && mkdir -p "$SRC" && ditto "$APP" "$SRC/HandBrake Batch.app"
  if command -v create-dmg >/dev/null; then
    create-dmg --volname "HandBrake Batch" --window-size 540 360 --icon-size 100 \
      --icon "HandBrake Batch.app" 140 170 --app-drop-link 400 170 --hide-extension "HandBrake Batch.app" \
      --no-internet-enable "$DMG" "$SRC" >/dev/null
  else
    ln -s /Applications "$SRC/Applications"
    hdiutil create -volname 'HandBrake Batch' -srcfolder "$SRC" -ov -format UDZO "$DMG" >/dev/null
  fi
  rm -rf "$SRC"; echo "Built $DMG"
fi
