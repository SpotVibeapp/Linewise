#!/usr/bin/env bash
# Materializes android/key.properties + keystore WITHOUT ever printing secrets.
#
# Preferred: repository Actions secrets (encrypted at rest) provide a persistent
# release keystore:
#   ANDROID_KEYSTORE_BASE64  - base64 of a PKCS12/JKS keystore
#   ANDROID_KEYSTORE_PASSWORD
#   ANDROID_KEY_ALIAS
#   ANDROID_KEY_PASSWORD
#
# Fallback (no secrets configured): an ephemeral keystore is generated for this
# build only. The APK is fully signed and installable, but signature continuity
# across releases requires configuring the secrets above (see docs/BUILDING.md).
set -euo pipefail

mkdir -p android/app
if [ -n "${ANDROID_KEYSTORE_BASE64:-}" ]; then
  printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 -d > android/app/linewise-release.p12
  cat > android/key.properties <<EOF
storeFile=app/linewise-release.p12
storePassword=${ANDROID_KEYSTORE_PASSWORD}
keyAlias=${ANDROID_KEY_ALIAS}
keyPassword=${ANDROID_KEY_PASSWORD}
EOF
  echo "SIGNING_MODE=persistent-secrets" > dist_signing_mode.txt
  echo "Signing: persistent keystore from Actions secrets (values not printed)."
else
  # PKCS12 requires the key password to equal the store password.
  STORE_PASS="$(openssl rand -hex 24)"
  KEY_PASS="$STORE_PASS"
  keytool -genkeypair -v \
    -keystore android/app/linewise-release.p12 \
    -storetype PKCS12 \
    -alias linewise \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$STORE_PASS" -keypass "$STORE_PASS" \
    -dname "CN=Linewise Release, OU=Mobile, O=Linewise, L=NA, S=NA, C=US" \
    >/dev/null 2>&1
  cat > android/key.properties <<EOF
storeFile=app/linewise-release.p12
storePassword=${STORE_PASS}
keyAlias=linewise
keyPassword=${KEY_PASS}
EOF
  echo "SIGNING_MODE=ephemeral" > dist_signing_mode.txt
  echo "Signing: EPHEMERAL keystore generated for this build."
  echo "For signature continuity across releases, configure Actions secrets:"
  echo "  ANDROID_KEYSTORE_BASE64 / ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD"
fi
