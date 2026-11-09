#!/usr/bin/env bash
# Play Store package → ~/Desktop/OneLauncher-PlayStore/: signed .aab + store graphics + texts.
# Screenshots are re-rendered from the app (test/store_shots_test.dart) and framed.
set -euo pipefail
cd "$(dirname "$0")/.."
# Version: tool/build_play.sh <name> <code> (pubspec isn't kept current; every upload needs a higher code).
V=${1:?usage: tool/build_play.sh <version name> <version code>}
N=${2:?usage: tool/build_play.sh <version name> <version code>}
DEST=~/Desktop/OneLauncher-PlayStore
echo "› App bundle $V ($N), Play build"
# PLAY_BUILD: leaves out what Play would question (lib/play_build.dart, src/play manifest, no Home SDK).
# No OMDb / TMDB keys: nothing of ours talks to a server.
PLAY_BUILD=true flutter build appbundle --release --flavor phone --split-debug-info=symbols --obfuscate \
  --build-name="$V" --build-number="$N" --dart-define=PLAY_BUILD=true >/dev/null
echo "› Screenshots + graphics"
/opt/homebrew/bin/python3.14 tool/store_icons.py >/dev/null
flutter test --update-goldens --dart-define=PLAY_BUILD=true test/store_shots_test.dart >/dev/null
/opt/homebrew/bin/python3.14 tool/store_assets.py >/dev/null  # needs Pillow
mkdir -p "$DEST/screenshots"
rm -f "$DEST"/OneLauncher-*.aab
cp build/app/outputs/bundle/phoneRelease/app-phone-release.aab "$DEST/OneLauncher-$V.aab"
cp store/icon-512.png store/feature-graphic.png store/*.md store/privacy-policy.html "$DEST/"
cp store/screenshots/*.png "$DEST/screenshots/"
ls -lh "$DEST" | awk 'NR>1 {print $5, $9}'
