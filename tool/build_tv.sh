#!/usr/bin/env bash
# Builds One Launcher TV (Android TV / Google TV) for release → ~/Desktop/APKs/OneLauncherTV-<version>.apk
#  - 32- and 64-bit ARM (many TVs, incl. the Acer R4 we test on, are 32-bit only), engine compressed
#  - Dart symbols split out + obfuscated, like the phone build
#  - Shows & films search: Stremio addon manifest links read from ./catalog_sources.txt (gitignored —
#    links can hold personal tokens; never printed or committed). One link per line, '#' comments.
#    Without the file the TV uses the public Cinemeta + WatchHub. After install the TV keeps its own
#    list (Customise → Search → Sources); links new to a later build are added to it.
# Usage: tool/build_tv.sh            tool/build_tv.sh --install <tv-ip:port>
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/app/outputs/flutter-apk
V=$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)
CATALOG=()
SOURCES=""
if [ -s catalog_sources.txt ]; then
  # First word of each line that isn't blank or a comment, joined by spaces (links never contain one).
  SOURCES=$(awk '{ sub(/^[ \t\r]+/, ""); sub(/[ \t\r]+$/, ""); if ($0 == "" || substr($0, 1, 1) == "#") next; print $1 }' catalog_sources.txt | paste -sd ' ' -)
fi
if [ -n "$SOURCES" ]; then
  CATALOG=(--dart-define=CATALOG_SOURCES="$SOURCES")
  echo "› Catalog sources: $(wc -w <<<"$SOURCES" | tr -d ' ') (catalog_sources.txt)"
else
  echo "› No catalog_sources.txt: search uses the public Cinemeta + WatchHub"
fi

# A title's page: critics' scores from OMDb (./omdb.key) and reviews from TMDB (./tmdb.key, a v4
# read access token). Both gitignored; their contents are never printed. Without a file that part
# of the page is just left out.
KEYS=()
key() { tr -d ' \t\r\n' < "$1"; }
if [ -s omdb.key ]; then KEYS+=(--dart-define=OMDB_KEY="$(key omdb.key)"); echo "› Scores: OMDb (omdb.key)"; else echo "› No omdb.key: no Rotten Tomatoes / Metacritic"; fi
if [ -s tmdb.key ]; then KEYS+=(--dart-define=TMDB_TOKEN="$(key tmdb.key)"); echo "› Reviews: TMDB (tmdb.key)"; else echo "› No tmdb.key: no reviews"; fi

echo "› TV build (arm + arm64, compressed)"
flutter build apk --release --flavor tv -t lib/main_tv.dart --split-debug-info=symbols --obfuscate \
  --target-platform android-arm,android-arm64 -P compressLibs=true ${CATALOG[@]+"${CATALOG[@]}"} ${KEYS[@]+"${KEYS[@]}"} >/dev/null
mkdir -p ~/Desktop/APKs
cp "$OUT/app-tv-release.apk" ~/Desktop/APKs/OneLauncherTV-$V.apk
ls -lh ~/Desktop/APKs/OneLauncherTV-$V.apk | awk '{print $5, $9}'

if [ "${1:-}" = "--install" ] && [ -n "${2:-}" ]; then
  ADB=~/Library/Android/sdk/platform-tools/adb
  "$ADB" -s "$2" install -r ~/Desktop/APKs/OneLauncherTV-$V.apk
  "$ADB" -s "$2" shell am start -n com.kirtanya.one_launcher.tv/com.kirtanya.one_launcher.TvActivity >/dev/null
fi
