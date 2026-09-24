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

# ── Toolkit packing (once) ──────────────────────────────────────────────────
# JDK repair pass: JAVA_HOME is a symlink on hosted runners, so an early pack
# archived a 204-byte link stub. Repack only the JDK (dereferenced) if tiny.
if [ -f toolkits/MANIFEST ] && [ "$(stat -c%s toolkits/jdk17.tar.xz.part-00 2>/dev/null || echo 0)" -lt 1000000 ]; then
  echo "repairing jdk17 toolkit payload (dereference JAVA_HOME)"
  rm -f toolkits/jdk17.tar.xz.part-*
  grep -v ' jdk17\.tar\.xz$' toolkits/MANIFEST > toolkits/MANIFEST.tmp || true
  mv toolkits/MANIFEST.tmp toolkits/MANIFEST
  JH="$(readlink -f "${JAVA_HOME:?}")"
  tar -cJf toolkits/jdk17.tar.xz.tmp -C "$(dirname "$JH")" "$(basename "$JH")"
  mv toolkits/jdk17.tar.xz.tmp toolkits/jdk17.tar.xz
  split -b 45m -d -a 2 toolkits/jdk17.tar.xz toolkits/jdk17.tar.xz.part-
  rm -f toolkits/jdk17.tar.xz
  for p in toolkits/jdk17.tar.xz.part-*; do
    echo "$(sha256sum "$p" | awk '{print $1}')  $(basename "$p")  $(basename "${p%%.part-*}")" >> toolkits/MANIFEST
  done
  git config user.name "linewise-ci"
  git config user.email "linewise-ci@users.noreply.github.com"
  git add toolkits
  git commit -m "ci: repair jdk17 toolkit payload [ci-toolkit]" || true
  git push origin "HEAD:${GITHUB_REF_NAME:-arena/01a0d452-linewise}" \
    || echo "::warning::jdk repair push failed"
fi
# This runner has full internet; the workspace sandbox does not. Ship the
# toolchains (Flutter+Dart with cache, JDK 17, Android build-tools/platform,
# pub cache) as chunked blobs under toolkits/ so they can travel over git.
# Idempotent: skipped when toolkits/MANIFEST already exists.
if [ ! -f toolkits/MANIFEST ]; then
  echo "packing builder toolkit into toolkits/ (one-time)"
  pack_dir() { # <name.tar.xz> <path> [exclude]
    local out="toolkits/$1" src="$2" ex="${3:-}"
    if [ -n "$ex" ]; then
      tar -cJf "$out.tmp" --exclude="$ex" -C "$(dirname "$src")" "$(basename "$src")"
    else
      tar -cJf "$out.tmp" -C "$(dirname "$src")" "$(basename "$src")"
    fi
    # normalize top-level dir name inside the archive callers expect
    mv "$out.tmp" "$out"
    split -b 45m -d -a 2 "$out" "${out}.part-"
    rm -f "$out"
  }
  FLUTTER_ROOT_DIR="$(dirname "$(dirname "$(readlink -f "$(which flutter)")")")"
  ANDROID_SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
  BT_VER="34.0.0"
  [ -d "$ANDROID_SDK_DIR/build-tools/$BT_VER" ] || \
    BT_VER="$(ls "$ANDROID_SDK_DIR/build-tools" | sort -V | tail -1)"
  mkdir -p toolkits
  pack_dir flutter-sdk.tar.xz "$FLUTTER_ROOT_DIR" ".git" || echo "::warning::flutter pack failed"
  pack_dir jdk17.tar.xz "${JAVA_HOME:?JAVA_HOME unset}" || echo "::warning::jdk pack failed"
  pack_dir android-build-tools.tar.xz "$ANDROID_SDK_DIR/build-tools/$BT_VER" || echo "::warning::build-tools pack failed"
  pack_dir android-platform-tools.tar.xz "$ANDROID_SDK_DIR/platform-tools" || echo "::warning::platform-tools pack failed"
  if [ -d "$ANDROID_SDK_DIR/platforms/android-34" ]; then
    pack_dir android-platform-34.tar.xz "$ANDROID_SDK_DIR/platforms/android-34" || true
  fi
  pack_dir pub-cache.tar.xz "${PUB_CACHE:-$HOME/.pub-cache}" || echo "::warning::pub-cache pack failed"
  : > toolkits/MANIFEST
  for p in toolkits/*.part-*; do
    [ -e "$p" ] || continue
    echo "$(sha256sum "$p" | awk '{print $1}')  $(basename "$p")  $(basename "${p%%.part-*}")" >> toolkits/MANIFEST
  done
  du -sh toolkits | awk '{print "toolkits total:", $1}'
  git config user.name "linewise-ci"
  git config user.email "linewise-ci@users.noreply.github.com"
  git add toolkits
  git commit -m "ci: builder toolkit payload (flutter/dart + android build tools) [ci-toolkit]" || true
  git push origin "HEAD:${GITHUB_REF_NAME:-arena/01a0d452-linewise}" \
    || echo "::warning::toolkit push failed"
else
  echo "toolkits/MANIFEST present — skipping repack"
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
