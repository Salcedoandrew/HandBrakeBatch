#!/bin/bash
# Builds "HandBrake Batch.app" with SwiftPM (Command Line Tools are enough) and ad-hoc signs it.
# Usage: ./build.sh [--install]
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
if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/HandBrake Batch.app"
  ditto "$APP" "/Applications/HandBrake Batch.app"
  echo "Installed to /Applications/HandBrake Batch.app"
fi
