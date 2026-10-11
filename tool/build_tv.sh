#!/usr/bin/env bash
# Builds One Launcher TV (Android TV / Google TV) for release → ~/Desktop/OneLauncherTV-<version>.apk
#  - 32- and 64-bit ARM (many TVs, incl. the Acer R4 we test on, are 32-bit only), engine compressed
#  - Dart symbols split out + obfuscated, like the phone build
#  - Shows & films search: TMDB key read from ./tmdb.key (gitignored; never printed or committed).
#    Without it the TV app still builds; search then covers apps only.
# Usage: tool/build_tv.sh            tool/build_tv.sh --install <tv-ip:port>
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/app/outputs/flutter-apk
V=$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)
TMDB=()
if [ -s tmdb.key ]; then TMDB=(--dart-define=TMDB_KEY="$(tr -d '[:space:]' < tmdb.key)"); echo "› TMDB key found"; else echo "› No tmdb.key: shows & films search off"; fi

echo "› TV build (arm + arm64, compressed)"
flutter build apk --release --flavor tv -t lib/main_tv.dart --split-debug-info=symbols --obfuscate \
  --target-platform android-arm,android-arm64 -P compressLibs=true ${TMDB[@]+"${TMDB[@]}"} >/dev/null
cp "$OUT/app-tv-release.apk" ~/Desktop/OneLauncherTV-$V.apk
ls -lh ~/Desktop/OneLauncherTV-$V.apk | awk '{print $5, $9}'

if [ "${1:-}" = "--install" ] && [ -n "${2:-}" ]; then
  ADB=~/Library/Android/sdk/platform-tools/adb
  "$ADB" -s "$2" install -r ~/Desktop/OneLauncherTV-$V.apk
  "$ADB" -s "$2" shell am start -n com.kirtanya.one_launcher.tv/com.kirtanya.one_launcher.TvActivity >/dev/null
fi
