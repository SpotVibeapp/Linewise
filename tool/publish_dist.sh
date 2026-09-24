#!/usr/bin/env bash
# Publishes the signed APK through two independent channels:
#   1) a GitHub Release with the APK attached (downloadable)
#   2) a dist/ commit pushed to the working branch (APK in the repo)
# Either channel alone is enough for delivery.
set -uo pipefail

APK_SRC="build/app/outputs/flutter-apk/app-release.apk"
VERSION="$(sed -n 's/^version: \(.*\)/\1/p' pubspec.yaml)"
TAG="v${VERSION%%+*}"

mkdir -p dist
cp "$APK_SRC" "dist/linewise-${TAG}.apk"
( cd dist && sha256sum "linewise-${TAG}.apk" > SHA256SUMS )

# ---- Channel 1: GitHub Release (downloadable APK) ----
VCODE="$(sed -n 's/.*"versionCode": "\([^"]*\)".*/\1/p' dist/build-info.json)"
NOTES="$(printf 'Signed Linewise %s (versionCode %s)\n\n```\n%s\n```\n' \
  "$TAG" "$VCODE" "$(cat dist/build-info.json)")"
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "dist/linewise-${TAG}.apk" dist/SHA256SUMS dist/build-info.json --clobber \
    && echo "Release $TAG updated with the APK." \
    || echo "::warning::release upload failed"
else
  gh release create "$TAG" "dist/linewise-${TAG}.apk" dist/SHA256SUMS dist/build-info.json \
    --title "Linewise $TAG" \
    --notes "$NOTES" \
    && echo "Release $TAG created with the APK." \
    || echo "::warning::release creation failed"
fi

# ---- Channel 2: commit dist/ to the working branch ----
git config user.name "linewise-ci"
git config user.email "linewise-ci@users.noreply.github.com"
git add dist
if [ -n "$(git status --porcelain)" ]; then
  git commit -m "ci: signed APK ${TAG} + verification report [ci-dist]" || true
  git push origin "HEAD:${GITHUB_REF_NAME}" \
    && echo "dist/ committed to ${GITHUB_REF_NAME}." \
    || echo "::warning::dist push failed — use the Release or workflow artifact"
fi
echo "Published $TAG"
