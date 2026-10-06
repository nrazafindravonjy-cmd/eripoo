#!/usr/bin/env bash
# Runs inside the CI emulator: start-up measurements, then the foundations
# integration test. Output kept in cold_start.txt and foundations.txt.
set -euo pipefail
adb shell getprop ro.build.version.release
adb shell cat /proc/meminfo | head -1
tool/android_cold_start.sh build/app/outputs/flutter-apk/app-release.apk 2>&1 | tee cold_start.txt
adb uninstall mg.eripoo.eripoo >/dev/null 2>&1 || true
flutter test integration_test/foundations_test.dart -d emulator-5554 2>&1 | tee foundations.txt
