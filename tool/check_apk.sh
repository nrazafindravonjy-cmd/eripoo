#!/usr/bin/env bash
# Checks a built release APK (docs/RELEASE_CHECKLIST.md): merged
# permissions, clear text, debuggable flag, size budget.
# Usage: tool/check_apk.sh path/to/app-release.apk [max_bytes]
set -euo pipefail
apk="$1"
max_bytes="${2:-41943040}" # 40 MiB for one ABI (docs/PERFORMANCE.md)

aapt2="$(ls -d "${ANDROID_HOME:-$ANDROID_SDK_ROOT}"/build-tools/*/aapt2 | sort -V | tail -1)"
fail=0

echo "== permissions (merged manifest)"
perms="$("$aapt2" dump permissions "$apk" | sed -n "s/^uses-permission: name='\([^']*\)'.*/\1/p" | sort -u)"
echo "$perms"

# Runtime ("dangerous") permissions: only the camera (QR transfer), the
# microphone (spoken answers) and notifications (optional mission
# reminders) may be requested.
allowed_dangerous='android.permission.CAMERA android.permission.RECORD_AUDIO android.permission.POST_NOTIFICATIONS'
dangerous='READ_CALENDAR WRITE_CALENDAR CAMERA READ_CONTACTS WRITE_CONTACTS
GET_ACCOUNTS ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION
ACCESS_BACKGROUND_LOCATION RECORD_AUDIO READ_PHONE_STATE READ_PHONE_NUMBERS
CALL_PHONE ANSWER_PHONE_CALLS READ_CALL_LOG WRITE_CALL_LOG ADD_VOICEMAIL
USE_SIP BODY_SENSORS SEND_SMS RECEIVE_SMS READ_SMS RECEIVE_WAP_PUSH
RECEIVE_MMS READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE READ_MEDIA_IMAGES
READ_MEDIA_VIDEO READ_MEDIA_AUDIO POST_NOTIFICATIONS NEARBY_WIFI_DEVICES
BLUETOOTH_SCAN BLUETOOTH_CONNECT BLUETOOTH_ADVERTISE ACTIVITY_RECOGNITION
ACCESS_MEDIA_LOCATION'
for p in $dangerous; do
  full="android.permission.$p"
  if grep -qx "$full" <<<"$perms" && ! grep -qw "$full" <<<"$allowed_dangerous"; then
    echo "FAIL: unexpected runtime permission $full"; fail=1
  fi
done
grep -qx 'android.permission.INTERNET' <<<"$perms" || { echo "FAIL: INTERNET missing (no sync)"; fail=1; }

echo "== application flags"
tree="$("$aapt2" dump xmltree --file AndroidManifest.xml "$apk")"
grep -E 'usesCleartextTraffic|allowBackup|debuggable' <<<"$tree" || true
grep -Eq 'usesCleartextTraffic\(0x[0-9a-f]+\)=(false|0x0+)' <<<"$tree" \
  || { echo "FAIL: clear text not refused"; fail=1; }
grep -Eq 'allowBackup\(0x[0-9a-f]+\)=(false|0x0+)' <<<"$tree" \
  || { echo "FAIL: backup not disabled"; fail=1; }
if grep -Eq 'debuggable\(0x[0-9a-f]+\)=(true|0xf+)' <<<"$tree"; then
  echo "FAIL: debuggable release"; fail=1
fi

echo "== size"
size=$(stat -c %s "$apk")
echo "MEASURE apk_bytes $size (budget $max_bytes)"
[ "$size" -le "$max_bytes" ] || { echo "FAIL: APK over budget"; fail=1; }

exit $fail
