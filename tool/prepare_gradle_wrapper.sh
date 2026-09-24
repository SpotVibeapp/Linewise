#!/usr/bin/env bash
# Copies Gradle wrapper binaries (gradlew + gradle-wrapper.jar) from a throwaway
# `flutter create` template into android/. The wrapper jar is a binary artifact
# generated from the pinned Flutter SDK instead of being committed to git.
set -euo pipefail

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
