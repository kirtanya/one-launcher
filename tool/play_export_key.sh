#!/usr/bin/env bash
# Play App Signing → "Use my own key": encrypts your release key with Google's public key so
# Play signs with the SAME key as the APKs you've shared (people can update without
# reinstalling). Passwords are read from android/key.properties and never printed.
#
# 1. Play Console → your app → Test and release → App integrity → App signing →
#    "Use a different key" / "Export and upload a key from Java keystore":
#    download pepk.jar and the encryption public key (encryption_public_key.pem).
# 2. Run: tool/play_export_key.sh ~/Downloads/pepk.jar ~/Downloads/encryption_public_key.pem
# 3. Upload the resulting ~/Desktop/OneLauncher-PlayStore/encrypted-key.zip in that same screen.
set -euo pipefail
cd "$(dirname "$0")/.."
PEPK=${1:?path to pepk.jar}; PEM=${2:?path to encryption_public_key.pem}
JAVA=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home/bin/java
[ -x "$JAVA" ] || JAVA=java
prop() { sed -n "s/^$1=//p" android/key.properties; }
STORE=$(prop storeFile); ALIAS=$(prop keyAlias)
case "$STORE" in /*) ;; *) STORE="android/app/$STORE" ;; esac
OUT=~/Desktop/OneLauncher-PlayStore/encrypted-key.zip
mkdir -p "$(dirname "$OUT")"
# pepk asks for the keystore password, then the key password: feed them on stdin.
printf '%s\n%s\n' "$(prop storePassword)" "$(prop keyPassword)" |
  "$JAVA" -jar "$PEPK" --keystore="$STORE" --alias="$ALIAS" --output="$OUT" \
    --include-cert --rsa-aes-encryption --encryption-key-path="$PEM"
echo "Done → $OUT (upload it in Play Console → App signing)"
