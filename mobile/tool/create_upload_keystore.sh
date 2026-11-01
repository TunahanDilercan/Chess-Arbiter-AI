#!/usr/bin/env bash
# Creates the Google Play UPLOAD key on YOUR computer (needs a JDK: keytool).
# Play App Signing keeps the real app-signing key at Google; if this upload key
# is ever lost it can be reset from Play Console, but keep a backup anyway.
#
#   bash tool/create_upload_keystore.sh
#
# Then add the printed values as GitHub repository secrets (Settings → Secrets
# and variables → Actions) and/or create android/key.properties for local builds.
set -euo pipefail
OUT="${1:-$HOME/hakem-masasi-upload-keystore.jks}"
ALIAS=upload
if [ -e "$OUT" ]; then echo "$OUT already exists; refusing to overwrite." >&2; exit 1; fi
read -rsp "Keystore password (min 6 chars): " PASS; echo
keytool -genkeypair -v -keystore "$OUT" -storetype PKCS12 -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=Hanova, O=Hanova, C=TR"
echo
echo "Created $OUT  (back it up somewhere safe; never commit it)"
echo
echo "GitHub secrets:"
echo "  ANDROID_KEYSTORE_PASSWORD = <the password you typed>"
echo "  ANDROID_KEY_PASSWORD      = <the same password>"
echo "  ANDROID_KEY_ALIAS         = $ALIAS"
echo "  ANDROID_KEYSTORE_BASE64   = contents of ${OUT}.b64 (created now)"
base64 < "$OUT" | tr -d '\n' > "${OUT}.b64"
echo
echo "Local builds: create android/key.properties with"
echo "  storeFile=$OUT"
echo "  storePassword=…  keyPassword=…  keyAlias=$ALIAS"
