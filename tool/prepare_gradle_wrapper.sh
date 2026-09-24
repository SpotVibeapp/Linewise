#!/usr/bin/env bash
# Copies Gradle wrapper binaries (gradlew + gradle-wrapper.jar) from a throwaway
# `flutter create` template into android/. The wrapper jar is a binary artifact
# generated from the pinned Flutter SDK instead of being committed to git.
#
# Also runs a parse-level diagnostics pass and, if `dart format` cannot parse
# the sources, commits the error report to ci/ so the failure is visible even
# when run logs are not downloadable.
set -euo pipefail

DIAG=ci/last-dart-format-diag.txt
# Parse-level check only (formatting drift is auto-repaired by `dart format .`
# in the workflow and must not fail the build). Exit 65 = a file cannot parse.
if dart format --output=none . >"$DIAG" 2>&1; then
  rm -f "$DIAG"
else
  git config user.name "linewise-ci"
  git config user.email "linewise-ci@users.noreply.github.com"
  git add "$DIAG"
  git commit -m "ci: dart format diagnostics [ci-diag]" || true
  git push origin "HEAD:${GITHUB_REF_NAME:-arena/01a0d452-linewise}" \
    || echo "::warning::diag push failed"
fi

if [ -f android/gradle/wrapper/gradle-wrapper.jar ]; then
  echo "gradle-wrapper.jar already present"
  exit 0
fi

TMPL="$(mktemp -d)"
flutter create --no-pub --platforms android --org app.linewise --project-name linewise "$TMPL/tmpl" >/dev/null

cp "$TMPL/tmpl/android/gradlew" android/gradlew
cp "$TMPL/tmpl/android/gradlew.bat" android/gradlew.bat
chmod +x android/gradlew
mkdir -p android/gradle/wrapper
cp "$TMPL/tmpl/android/gradle/wrapper/gradle-wrapper.jar" android/gradle/wrapper/
# Our own gradle-wrapper.properties (pinned Gradle 8.3) stays authoritative.
rm -rf "$TMPL"
echo "gradle wrapper prepared from Flutter template"
