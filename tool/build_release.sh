#!/usr/bin/env bash
# Builds One Launcher for release, as small as possible without changing how it runs:
#  - Dart debug symbols split out (kept in symbols/ for crash reports) + obfuscated names
#  - big-figure fonts subset (tool/subset_fonts.py), unused icon fonts tree-shaken
#  - phone build: 64-bit only, engine stored uncompressed → smallest installed size, fastest start
#  - share builds: engine compressed → smallest download
# Usage: tool/build_release.sh            (phone + share files + TV app → ~/Desktop)
set -euo pipefail
cd "$(dirname "$0")/.."
FLAGS=(--release --flavor phone --split-debug-info=symbols --obfuscate) # phone app (a TV flavor exists too)
OUT=build/app/outputs/flutter-apk

echo "› Phone build (arm64, uncompressed)"
flutter build apk "${FLAGS[@]}" --target-platform android-arm64 >/dev/null
cp "$OUT/app-phone-release.apk" "$OUT/one-launcher-phone.apk"

echo "› Share build: 64-bit phones (compressed)"
flutter build apk "${FLAGS[@]}" --target-platform android-arm64 -P compressLibs=true >/dev/null
cp "$OUT/app-phone-release.apk" ~/Desktop/OneLauncher.apk

echo "› Share build: every phone incl. older 32-bit ones (compressed)"
flutter build apk "${FLAGS[@]}" --target-platform android-arm,android-arm64 -P compressLibs=true >/dev/null
cp "$OUT/app-phone-release.apk" ~/Desktop/OneLauncher-all-phones.apk

cp "$OUT/one-launcher-phone.apk" "$OUT/app-phone-release.apk" # leave the phone build as the default output
ls -lh "$OUT/one-launcher-phone.apk" ~/Desktop/OneLauncher.apk ~/Desktop/OneLauncher-all-phones.apk ~/Desktop/OneLauncherTV.apk | awk '{print $5, $9}'
