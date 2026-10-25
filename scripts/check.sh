#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .verification
exec > >(tee .verification/check.log) 2>&1
flutter pub get
dart format lib test
flutter analyze
flutter test
cd android
./gradlew :app:compileDebugKotlin :app:lintDebug --stacktrace
