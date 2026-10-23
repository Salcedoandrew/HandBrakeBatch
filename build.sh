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
# Bundle the official HandBrakeCLI (universal, notarized by HandBrake), cached in .cache/ and checked against
# the SHA-256 published on handbrake.fr/checksums.php and the GitHub release.
HB_VER=1.11.2; HB_SHA=14463aa81038aaa3ce421dc6cee65fd6c82fdabda040931541ccca38939299fa
HB_DMG=".cache/HandBrakeCLI-$HB_VER.dmg"
if ! echo "$HB_SHA  $HB_DMG" | shasum -a 256 -c - >/dev/null 2>&1; then
  mkdir -p .cache; echo "Downloading HandBrakeCLI $HB_VER…"
  curl -fL --progress-bar -o "$HB_DMG" "https://github.com/HandBrake/HandBrake/releases/download/$HB_VER/HandBrakeCLI-$HB_VER.dmg"
  echo "$HB_SHA  $HB_DMG" | shasum -a 256 -c - >/dev/null || { echo "HandBrakeCLI checksum mismatch"; rm -f "$HB_DMG"; exit 1; }
fi
MNT=$(mktemp -d); hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$HB_DMG" >/dev/null
LIC="$APP/Contents/Resources/HandBrakeCLI-license"; mkdir -p "$APP/Contents/Resources/bin" "$LIC"
ditto "$MNT/HandBrakeCLI" "$APP/Contents/Resources/bin/HandBrakeCLI"
cp "$MNT/doc/COPYING" "$MNT/doc/LICENSE" "$LIC/"
hdiutil detach "$MNT" >/dev/null; rmdir "$MNT" 2>/dev/null || true
echo "HandBrakeCLI $HB_VER is (c) the HandBrake Team, GPL-2.0 (see COPYING). Unmodified official build from
https://github.com/HandBrake/HandBrake/releases/tag/$HB_VER (source: HandBrake-$HB_VER-source.tar.bz2 there)." > "$LIC/NOTICE.txt"
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
