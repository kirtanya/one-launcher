#!/usr/bin/env bash
# Play Store package → ~/Desktop/OneLauncher-PlayStore/: signed .aab + store graphics + texts.
# Screenshots are re-rendered from the app (test/store_shots_test.dart) and framed.
set -euo pipefail
cd "$(dirname "$0")/.."
V=$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)
DEST=~/Desktop/OneLauncher-PlayStore
echo "› App bundle $V"
flutter build appbundle --release --flavor phone --split-debug-info=symbols --obfuscate >/dev/null
echo "› Screenshots + graphics"
flutter test --update-goldens test/store_shots_test.dart >/dev/null
python3 tool/store_assets.py >/dev/null
mkdir -p "$DEST/screenshots"
rm -f "$DEST"/OneLauncher-*.aab
cp build/app/outputs/bundle/phoneRelease/app-phone-release.aab "$DEST/OneLauncher-$V.aab"
cp store/icon-512.png store/feature-graphic.png store/*.md store/privacy-policy.html "$DEST/"
cp store/screenshots/*.png "$DEST/screenshots/"
ls -lh "$DEST" | awk 'NR>1 {print $5, $9}'
