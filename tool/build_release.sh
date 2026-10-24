#!/usr/bin/env bash
# Builds One Launcher for release, as small as possible without changing how it runs:
#  - Dart debug symbols split out (kept in symbols/ for crash reports) + obfuscated names
#  - big-figure fonts subset (tool/subset_fonts.py), unused icon fonts tree-shaken
#  - phone build: 64-bit only, engine stored uncompressed → smallest installed size, fastest start
#  - share builds: engine compressed → smallest download
# Usage: tool/build_release.sh            (phone + share files → ~/Desktop/APKs)
set -euo pipefail
cd "$(dirname "$0")/.."
FLAGS=(--release --flavor phone --split-debug-info=symbols --obfuscate) # phone app (a TV flavor exists too)
OUT=build/app/outputs/flutter-apk
V=$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml) # share files carry the version so they don't mix

# One Stream titles' critics' scores (OMDb, ./omdb.key) and reviews (TMDB, ./tmdb.key: a v4 read
# access token). Both gitignored, never printed; without a file that part is just left out.
key() { tr -d ' \t\r\n' < "$1"; }
KEYS=() # only your own phone build carries the keys; share files don't (anyone could pull them out)
if [ -s omdb.key ]; then KEYS+=(--dart-define=OMDB_KEY="$(key omdb.key)"); echo "› Scores: OMDb (omdb.key)"; fi
if [ -s tmdb.key ]; then KEYS+=(--dart-define=TMDB_TOKEN="$(key tmdb.key)"); echo "› Reviews: TMDB (tmdb.key)"; fi

echo "› Phone build (arm64, uncompressed)"
flutter build apk "${FLAGS[@]}" ${KEYS[@]+"${KEYS[@]}"} --target-platform android-arm64 >/dev/null
cp "$OUT/app-phone-release.apk" "$OUT/one-launcher-phone.apk"

echo "› Share build: 64-bit phones (compressed)"
flutter build apk "${FLAGS[@]}" --target-platform android-arm64 -P compressLibs=true >/dev/null
mkdir -p ~/Desktop/APKs
cp "$OUT/app-phone-release.apk" ~/Desktop/APKs/OneLauncher-$V.apk

echo "› Share build: every phone incl. older 32-bit ones (compressed)"
flutter build apk "${FLAGS[@]}" --target-platform android-arm,android-arm64 -P compressLibs=true >/dev/null
cp "$OUT/app-phone-release.apk" ~/Desktop/APKs/OneLauncher-$V-all-phones.apk

cp "$OUT/one-launcher-phone.apk" "$OUT/app-phone-release.apk" # leave the phone build as the default output
ls -lh "$OUT/one-launcher-phone.apk" ~/Desktop/APKs/OneLauncher-$V.apk ~/Desktop/APKs/OneLauncher-$V-all-phones.apk | awk '{print $5, $9}'
