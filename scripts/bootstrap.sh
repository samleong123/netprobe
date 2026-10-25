#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is missing from PATH. Install Flutter and restart your terminal."
  exit 1
fi
# Generate only the machine-specific Flutter metadata and Gradle wrapper in a temporary project.
task_scaffold="$(mktemp -d "${TMPDIR:-/tmp}/speedtest-scaffold.XXXXXX")"
trap 'rm -rf "$task_scaffold"' EXIT
flutter create --platforms=android --org=dev.sam --project-name=speedtest --no-pub "$task_scaffold"
cp "$task_scaffold/android/gradlew" android/gradlew
cp "$task_scaffold/android/gradlew.bat" android/gradlew.bat
cp "$task_scaffold/android/gradle/wrapper/gradle-wrapper.jar" android/gradle/wrapper/gradle-wrapper.jar
cp "$task_scaffold/android/local.properties" android/local.properties
cp "$task_scaffold/.metadata" .metadata
chmod +x android/gradlew
flutter pub get
echo "Project ready. Run flutter run on an Android device."
