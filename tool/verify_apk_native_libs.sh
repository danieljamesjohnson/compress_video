#!/usr/bin/env bash
#
# Proves the APK a user would actually ship carries no native library beyond the ones Flutter
# itself ships, and that the archive is 16 KB page-aligned (BULD-01, D-20).
#
# This is an ALLOWLIST check, not a denylist: the claim ("100 percent native compression code,
# no FFmpeg") is about what is inside the archive a developer ships, so this script enumerates
# every native-library entry in the archive and fails on anything outside an explicit
# allowlist -- rather than grepping for the absence of a name it already knows to be dangerous
# (libavcodec, libffmpeg, ...), which would say nothing about a name it does not yet know to
# look for. A future dependency could introduce a native library under any name at all; only
# enumerating everything and rejecting the unexpected catches that.
#
# Usage: tool/verify_apk_native_libs.sh [path/to/app.apk]
# Defaults to the example app's debug APK (the one the local emulator gate builds), run from the
# repository root.
#
# Let every failure propagate: a missing APK, a missing zipalign, or an unexpected native
# library all exit non-zero. Nothing here is allowed to turn a missing file or a missing tool
# into a silent pass.

set -euo pipefail

APK="${1:-example/build/app/outputs/flutter-apk/app-debug.apk}"

if [ ! -f "$APK" ]; then
  echo "FATAL: no APK found at '$APK'" >&2
  exit 1
fi

# The libraries Flutter itself ships. Confirmed live against this project's own debug build
# (2026-09-16): every one of libflutter.so (per target ABI) and
# libVkLayer_khronos_validation.so (the Vulkan validation layer debug builds bundle, arm64-v8a
# only) is present, and nothing else is. libapp.so (the AOT-compiled Dart application) and
# libdartjni.so (the Dart VM's JNI bridge on some engine builds) are release/profile-build-only
# artifacts a debug build does not produce -- listed here anyway so a future release-build run
# of this same script does not need a second allowlist.
ALLOWLIST=(
  "libflutter.so"
  "libapp.so"
  "libdartjni.so"
  "libVkLayer_khronos_validation.so"
)

NATIVE_LIB_ENTRIES=$(unzip -l "$APK" | awk '{print $4}' | grep -E '^lib/[^/]+/[^/]+\.so$' || true)

if [ -z "$NATIVE_LIB_ENTRIES" ]; then
  echo "No native library entries found in $APK"
else
  echo "Native library entries found in $APK:"
  echo "$NATIVE_LIB_ENTRIES"
fi

UNEXPECTED=""
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  base="$(basename "$entry")"
  allowed="false"
  for name in "${ALLOWLIST[@]}"; do
    if [ "$base" = "$name" ]; then
      allowed="true"
      break
    fi
  done
  if [ "$allowed" = "false" ]; then
    UNEXPECTED="${UNEXPECTED}${entry}"$'\n'
  fi
done <<<"$NATIVE_LIB_ENTRIES"

if [ -n "$UNEXPECTED" ]; then
  echo "FATAL: unexpected native library entries outside the allowlist:" >&2
  echo "$UNEXPECTED" >&2
  exit 1
fi

echo "All native library entries are on the allowlist."

# 16 KB page-alignment check -- resolve zipalign from the newest build-tools directory under
# the Android SDK root, so a future SDK bump does not need this script's own edit.
SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$SDK_ROOT" ]; then
  echo "FATAL: ANDROID_HOME/ANDROID_SDK_ROOT is not set" >&2
  exit 1
fi

ZIPALIGN_DIR=$(find "$SDK_ROOT/build-tools" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1)
if [ -z "$ZIPALIGN_DIR" ]; then
  echo "FATAL: no build-tools directory found under $SDK_ROOT/build-tools" >&2
  exit 1
fi
ZIPALIGN="$ZIPALIGN_DIR/zipalign"
if [ ! -x "$ZIPALIGN" ]; then
  echo "FATAL: zipalign not found or not executable at $ZIPALIGN" >&2
  exit 1
fi

echo "Running $ZIPALIGN -c -P 16 -v 4 against $APK"
"$ZIPALIGN" -c -P 16 -v 4 "$APK"
