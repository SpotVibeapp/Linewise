#!/usr/bin/env bash
# Copies Gradle wrapper binaries (gradlew + gradle-wrapper.jar) from a throwaway
# `flutter create` template into android/. The wrapper jar is a binary artifact
# generated from the pinned Flutter SDK instead of being committed to git.
#
# Also runs a parse-level diagnostics pass and, if `dart format` cannot parse
# the sources, commits the error report to ci/ so the failure is visible even
# when run logs are not downloadable.
set -euo pipefail

push_diag() { # <file> <subject>
  git config user.name "linewise-ci"
  git config user.email "linewise-ci@users.noreply.github.com"
  git add "$1"
  git commit -m "ci: $2 diagnostics [ci-diag]" || true
  git push origin "HEAD:${GITHUB_REF_NAME:-arena/01a0d452-linewise}" \
    || echo "::warning::diag push failed"
}

# Parse-level check only (formatting drift is auto-repaired by `dart format .`
# in the workflow and must not fail the build). Exit 65 = a file cannot parse.
FORMAT_DIAG=ci/last-dart-format-diag.txt
if dart format --output=none . >"$FORMAT_DIAG" 2>&1; then
  rm -f "$FORMAT_DIAG"
else
  {
    echo "diagnostics: dart format could not parse the sources:"
    dart format --output=none . 2>&1 || true
  } >"$FORMAT_DIAG"
  push_diag "$FORMAT_DIAG" "dart format"
fi

# Capture `flutter analyze` and `flutter test` output into the repo so findings
# stay visible even when workflow logs cannot be downloaded. The workflow's own
# steps remain the pass/fail gates; this only publishes evidence.
if flutter pub get >/dev/null 2>&1; then
  ANALYZE_DIAG=ci/last-analyze-diag.txt
  if flutter analyze >"$ANALYZE_DIAG" 2>&1; then
    rm -f "$ANALYZE_DIAG"
  else
    push_diag "$ANALYZE_DIAG" "flutter analyze"
  fi
  TEST_DIAG=ci/last-test-diag.txt
  if flutter test >"$TEST_DIAG" 2>&1; then
    rm -f "$TEST_DIAG"
  else
    push_diag "$TEST_DIAG" "flutter test"
  fi
  BUILD_DIAG=ci/last-build-diag.txt
  if flutter build apk --release >"$BUILD_DIAG" 2>&1; then
    rm -f "$BUILD_DIAG"
  else
    push_diag "$BUILD_DIAG" "flutter build"
  fi
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
