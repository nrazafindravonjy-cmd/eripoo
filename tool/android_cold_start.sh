#!/usr/bin/env bash
# Measures cold start and memory of an installed-from-scratch APK on the
# connected device (adb). Prints `MEASURE <name> <value>` lines.
#
#   tool/android_cold_start.sh build/app/outputs/flutter-apk/app-release.apk
#
# Budgets (docs/PERFORMANCE.md), optional: COLD_START_BUDGET_MS (median)
# and PSS_BUDGET_KIB (memory after start). Exceeding one fails the run.
set -euo pipefail
apk="$1"
pkg=mg.eripoo.eripoo
activity="$pkg/.MainActivity"

adb uninstall "$pkg" >/dev/null 2>&1 || true
adb install -r "$apk" >/dev/null

start_ms() {
  adb shell am force-stop "$pkg"
  sleep 2
  adb shell am start -W -n "$activity" | awk '/TotalTime/ {print $2}'
}

# First launch creates the keys and the encrypted database.
echo "MEASURE cold_start_first_launch_ms $(start_ms)"
sleep 5
runs=()
for _ in 1 2 3 4 5; do
  runs+=("$(start_ms)")
  sleep 4
done
echo "MEASURE cold_start_runs_ms $(IFS=,; echo "${runs[*]}")"
sorted=$(printf '%s\n' "${runs[@]}" | sort -n | sed -n 3p)
echo "MEASURE cold_start_median_ms $sorted"
if [ -n "${COLD_START_BUDGET_MS:-}" ] && [ "$sorted" -gt "$COLD_START_BUDGET_MS" ]; then
  echo "FAIL: cold start median $sorted ms over budget $COLD_START_BUDGET_MS ms"
  exit 1
fi

sleep 5
pss=$(adb shell dumpsys meminfo "$pkg" | awk '/TOTAL PSS:/ {print $3; exit} /TOTAL:/ {print $2; exit}')
echo "MEASURE memory_total_pss_kib_after_start $pss"
if [ -n "${PSS_BUDGET_KIB:-}" ] && [ "$pss" -gt "$PSS_BUDGET_KIB" ]; then
  echo "FAIL: memory after start $pss KiB over budget $PSS_BUDGET_KIB KiB"
  exit 1
fi

# The app must still be alive (no crash at start-up).
if adb shell pidof "$pkg" >/dev/null; then
  echo "MEASURE app_alive_after_start true"
else
  echo "MEASURE app_alive_after_start false"
  exit 1
fi

# "Clear data" from Android settings: keys and database disappear
# together, the next start must be a clean first start (no crash).
adb shell pm clear "$pkg" >/dev/null
echo "MEASURE cold_start_after_clear_data_ms $(start_ms)"
sleep 5
if adb shell pidof "$pkg" >/dev/null; then
  echo "MEASURE app_alive_after_clear_data true"
else
  echo "MEASURE app_alive_after_clear_data false"
  exit 1
fi
adb logcat -d -s flutter:E AndroidRuntime:E | tail -20 || true
