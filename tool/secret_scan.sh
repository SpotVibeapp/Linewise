#!/usr/bin/env bash
# Fails the build if anything credential-shaped is tracked in git.
set -euo pipefail

FAIL=0

echo "Scanning tracked files for credentials..."
if git ls-files | grep -E '\.(jks|keystore|p12|pepk|pem)$'; then
  echo "FAIL: keystore/key files must never be committed"; FAIL=1
fi
if git ls-files | grep -E '(^|/)key\.properties$'; then
  echo "FAIL: key.properties must never be committed"; FAIL=1
fi

PATTERNS=(
  'apiKey=[A-Za-z0-9_-]{8,}'
  '-----BEGIN .*PRIVATE KEY-----'
  'storePassword=.+'
  'keyPassword=.+'
)
for p in "${PATTERNS[@]}"; do
  if git grep -nE -e "$p" -- ':!tool/secret_scan.sh' ':!tool/prepare_signing.sh' ':!toolkits' ':!test' ':!*.md' | grep -v '<redacted>'; then
    echo "FAIL: pattern '$p' found in tracked files"; FAIL=1
  fi
done

if [ "$FAIL" -eq 0 ]; then
  echo "Secret scan clean."
else
  exit 1
fi
