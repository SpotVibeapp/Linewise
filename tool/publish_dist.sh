#!/usr/bin/env bash
# Publishes the signed APK: commits dist/ artifacts to the working branch and
# creates (or updates) a GitHub Release with the APK attached for download.
set -euo pipefail

APK_SRC="build/app/outputs/flutter-apk/app-release.apk"
VERSION="$(sed -n 's/^version: \(.*\)/\1/p' pubspec.yaml)"
TAG="v${VERSION%%+*}"

mkdir -p dist
cp "$APK_SRC" "dist/linewise-${TAG}.apk"
( cd dist && sha256sum "linewise-${TAG}.apk" > SHA256SUMS )

# Commit dist/ + verification report to the branch so the APK lives in the repo.
git config user.name "linewise-ci"
git config user.email "linewise-ci@users.noreply.github.com"
git add dist pubspec.lock 2>/dev/null || git add dist
if [ -n "$(git status --porcelain)" ]; then
  git commit -m "ci: signed APK ${TAG} + verification report [ci-dist]"
  git push origin "HEAD:${GITHUB_REF_NAME}"
fi

# GitHub Release (downloadable APK).
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "dist/linewise-${TAG}.apk" dist/SHA256SUMS dist/build-info.json --clobber
else
  NOTES="$(printf 'Signed Linewise %s (versionCode %s)\n\n```\n%s\n```\n' \
    "$TAG" "$(sed -n 's/.*"versionCode": "\([^"]*\)".*/\1/p' dist/build-info.json)" \
    "$(cat dist/build-info.json)")"
  gh release create "$TAG" "dist/linewise-${TAG}.apk" dist/SHA256SUMS dist/build-info.json \
    --title "Linewise $TAG" \
    --notes "$NOTES"
fi
echo "Published $TAG"
