#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_kotlin="${KOTLIN_HOME:-/Applications/Android Studio.app/Contents/plugins/Kotlin/kotlinc}"
task_java="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
mkdir -p .verification
JAVA_HOME="$task_java" "$task_kotlin/bin/kotlinc" \
  android/app/src/main/kotlin/dev/sam/speedtest/TransferEngine.kt \
  test/native/TransferEngineChecks.kt -include-runtime -d .verification/engine-checks.jar
"$task_java/bin/java" -jar .verification/engine-checks.jar "$@"
