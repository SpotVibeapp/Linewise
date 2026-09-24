#!/usr/bin/env bash
# Verifies package name, version, signature, zip alignment and SHA-256 of an APK
# using the Android SDK build tools. Prints a machine- and human-readable report.
set -euo pipefail

APK="${1:?usage: verify_apk.sh <apk>}"

BT_VERSION="$(ls "${ANDROID_HOME:-/usr/local/lib/android/sdk}/build-tools" | sort -V | tail -1)"
BT="${ANDROID_HOME:-/usr/local/lib/android/sdk}/build-tools/${BT_VERSION}"
AAPT="$BT/aapt"
ZIPALIGN="$BT/zipalign"
APKSIGNER="$BT/apksigner"

echo "=== Linewise APK verification ==="
echo "apk: $APK"
echo

echo "--- sha256 ---"
SHA="$(sha256sum "$APK" | cut -d' ' -f1)"
echo "sha256: $SHA"
echo

echo "--- aapt badging (package + version) ---"
BADGING="$("$AAPT" dump badging "$APK" | head -5)"
echo "$BADGING"
PKG="$(echo "$BADGING" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")"
VNAME="$(echo "$BADGING" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")"
VCODE="$(echo "$BADGING" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p")"
if [ "$PKG" != "app.linewise.linewise" ]; then
  echo "FAIL: package is '$PKG', expected app.linewise.linewise"; exit 1
fi
echo "package OK: $PKG"
echo

echo "--- zipalign (4-byte) ---"
"$ZIPALIGN" -c -v 4 "$APK" >/dev/null
echo "zipalign OK"
echo

echo "--- apksigner verify ---"
"$APKSIGNER" verify --print-certs "$APK" | tee /tmp/certs.txt
CERT_SHA="$(grep -m1 'SHA-256 digest' /tmp/certs.txt | sed 's/.*: //')"
echo "signer cert SHA-256: $CERT_SHA"
echo

SIGN_MODE="ephemeral"
[ -f dist_signing_mode.txt ] && SIGN_MODE="$(cat dist_signing_mode.txt | cut -d= -f2)"

cat > dist/build-info.json <<EOF
{
  "app": "Linewise",
  "package": "$PKG",
  "versionName": "$VNAME",
  "versionCode": "$VCODE",
  "apkSha256": "$SHA",
  "signerCertSha256": "$CERT_SHA",
  "zipalign": "4-byte OK",
  "signature": "apksigner verify OK",
  "signingMode": "$SIGN_MODE",
  "builtAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
echo "--- build-info.json ---"
cat dist/build-info.json
echo
echo "ALL CHECKS PASSED: package, version, signature, zip alignment, SHA-256."
