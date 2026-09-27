#!/usr/bin/env bash
#
# T-05-16: proves the built example APK's MERGED manifest actually carries the plugin's
# FOREGROUND_SERVICE/FOREGROUND_SERVICE_MEDIA_PROCESSING permissions and the typed
# ForegroundServiceHost service declaration -- 05-RESEARCH.md assumption A2 turned into a gate.
# This is deterministic and cannot race a job's lifetime the way a live `dumpsys` capture can:
# it inspects the archive itself, not a running process.
#
# Usage: tool/verify_apk_foreground_service_manifest.sh [path/to/app.apk]
# Defaults to the example app's debug APK, run from the repository root.

set -euo pipefail

APK="${1:-example/build/app/outputs/flutter-apk/app-debug.apk}"

if [ ! -f "$APK" ]; then
  echo "FATAL: no APK found at '$APK'" >&2
  exit 1
fi

SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$SDK_ROOT" ]; then
  echo "FATAL: ANDROID_HOME/ANDROID_SDK_ROOT is not set" >&2
  exit 1
fi

# Resolve aapt2 from the newest build-tools directory, exactly like
# tool/verify_apk_native_libs.sh resolves zipalign -- a future SDK bump does not need this
# script's own edit.
AAPT2_DIR=$(find "$SDK_ROOT/build-tools" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1)
if [ -z "$AAPT2_DIR" ]; then
  echo "FATAL: no build-tools directory found under $SDK_ROOT/build-tools" >&2
  exit 1
fi
AAPT2="$AAPT2_DIR/aapt2"
if [ ! -x "$AAPT2" ]; then
  echo "FATAL: aapt2 not found or not executable at $AAPT2" >&2
  exit 1
fi

echo "Dumping the merged manifest of $APK with $AAPT2"
BADGING=$("$AAPT2" dump badging "$APK")
MANIFEST_TREE=$("$AAPT2" dump xmltree "$APK" --file AndroidManifest.xml)

FAILED=0

if ! grep -q "uses-permission: name='android.permission.FOREGROUND_SERVICE'" <<<"$BADGING"; then
  echo "FATAL: merged manifest is missing android.permission.FOREGROUND_SERVICE" >&2
  FAILED=1
fi

if ! grep -q "uses-permission: name='android.permission.FOREGROUND_SERVICE_MEDIA_PROCESSING'" <<<"$BADGING"; then
  echo "FATAL: merged manifest is missing android.permission.FOREGROUND_SERVICE_MEDIA_PROCESSING" >&2
  FAILED=1
fi

if ! grep -q 'com.danjjohnson.compress_video.ForegroundServiceHost' <<<"$MANIFEST_TREE"; then
  echo "FATAL: merged manifest has no ForegroundServiceHost service declaration" >&2
  FAILED=1
fi

# foregroundServiceType's resource id 0x01010599 with value 0x00002000
# (ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING) -- both checked together so a service
# declaration that lost its type attribute during a future manifest edit still fails loudly.
if ! grep -q '0x01010599)=0x00002000' <<<"$MANIFEST_TREE"; then
  echo "FATAL: ForegroundServiceHost is missing android:foregroundServiceType=\"mediaProcessing\" (0x00002000) in the merged manifest" >&2
  FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

echo "Merged manifest carries both foreground-service permissions and the typed service declaration."
