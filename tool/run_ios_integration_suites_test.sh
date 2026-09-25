#!/usr/bin/env bash
# Self-test for tool/run_ios_integration_suites.sh: runs it against a fake `flutter` that
# replays the exact output shapes seen on CI -- a clean pass, the "log reader failed" launch
# failure followed by a hang, a silent launch hang, a build that never finishes, a genuine test
# failure, and (03-08, CI run 36195780910) the macOS-specific "leftover app instance" launch
# failure and its own build-done marker -- with the budgets shrunk to seconds.
#
# Usage: bash tool/run_ios_integration_suites_test.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/run_ios_integration_suites.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
# Fake `flutter test`: behaviour for call N is line N of $FAKE_SEQUENCE.
cat > "$WORK/bin/flutter" <<'EOF'
#!/usr/bin/env bash
suite="$2"
n=$(( $(cat "$FAKE_COUNTER" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$FAKE_COUNTER"
mode=$(sed -n "${n}p" "$FAKE_SEQUENCE")
echo "00:00 +0: loading /Users/runner/work/example/$suite"
echo "Warning: Missing build name (CFBundleShortVersionString)."
echo "Warning: Missing build number (CFBundleVersion)."
echo "Action Required: You must set a build name and number in the pubspec.yaml file version field before submitting to the App Store."
echo "Running Xcode build..."
case "$mode" in
  nobuild)
    sleep 1000 ;;
  logreader)
    echo "Xcode build done.                                           37.2s"
    echo "No tests ran."
    echo "Error waiting for a debug connection: The log reader failed unexpectedly"
    sleep 1000 ;;
  silent)
    echo "Xcode build done.                                           95.9s"
    sleep 1000 ;;
  stubborn)
    # Ignores SIGTERM like a Flutter tool stuck in its shutdown hooks; only SIGKILL ends it.
    trap '' TERM
    echo "Xcode build done.                                           95.9s"
    echo "No tests ran."
    echo "Error waiting for a debug connection: The log reader failed unexpectedly"
    while :; do sleep 1; done ;;
  pass)
    echo "Xcode build done.                                           95.9s"
    echo "00:00 +0: getMediaInfo matches the corpus sidecar for portrait_rot90"
    echo "00:01 +1: getMediaInfo matches the corpus sidecar for small_480p"
    echo "00:01 +2: (tearDownAll)"
    echo 'PARITY_JSON {"small_480p":{"durationMs":3000}}'
    echo "00:04 +2: All tests passed!"
    exit 0 ;;
  realfail)
    echo "Xcode build done.                                           95.9s"
    echo "00:00 +0: getMediaInfo matches the corpus sidecar for portrait_rot90"
    echo "00:01 +0 -1: getMediaInfo matches the corpus sidecar for small_480p [E]"
    echo "  Expected: 3000"
    echo "00:02 +0 -1: Some tests failed."
    exit 1 ;;
  macpass)
    # The macOS desktop target's own build-done marker (CI run 36195780910) -- no "Xcode build
    # done." line at all, since macOS builds through Flutter's own build system, not xcodebuild.
    echo "Building macOS application..."
    echo "✓ Built build/macos/Build/Products/Debug/compress_video_example.app"
    echo "00:00 +0: getMediaInfo matches the corpus sidecar for portrait_rot90"
    echo "00:01 +1: getMediaInfo matches the corpus sidecar for small_480p"
    echo "00:01 +2: (tearDownAll)"
    echo 'PARITY_JSON {"small_480p":{"durationMs":3000}}'
    echo "00:04 +2: All tests passed!"
    exit 0 ;;
  macfail)
    # The exact shape CI run 36195780910 hit on every suite after the first: a leftover app
    # instance from a prior suite means `open` re-activates it instead of launching fresh, so
    # no new VM-service port ever opens and the log reader gives up.
    echo "Building macOS application..."
    echo "✓ Built build/macos/Build/Products/Debug/compress_video_example.app"
    echo "No tests ran."
    echo "Error waiting for a debug connection: The log reader stopped unexpectedly, or never started."
    echo "Failed to load \"$suite\": Unable to start the app on the device."
    sleep 1000 ;;
  *)
    echo "fake flutter: unknown mode '$mode' for call $n" >&2
    exit 64 ;;
esac
EOF
chmod +x "$WORK/bin/flutter"

# Fake `pkill`: records every invocation (device reset calls) instead of touching any real
# process on this machine, and always reports "no matching process" (exit 1) like a clean
# environment would -- reset_device's own `|| true` already tolerates that.
: > "$WORK/pkill.log"
cat > "$WORK/bin/pkill" <<EOF
#!/usr/bin/env bash
echo "pkill \$*" >> "$WORK/pkill.log"
exit 1
EOF
chmod +x "$WORK/bin/pkill"

failures=0
# Overridden to "macos" around the macOS-specific cases below; every other case leaves this at
# the default iOS-simulator fake UDID, exercising reset_device's simctl branch as before.
TARGET_DEVICE="FAKE-UDID"
run_case() {
  local name="$1" expect_status="$2" expect_pattern="$3" max_seconds="$4"
  shift 4
  export FAKE_SEQUENCE="$WORK/seq" FAKE_COUNTER="$WORK/counter"
  printf '%s\n' "$@" > "$FAKE_SEQUENCE"
  rm -f "$FAKE_COUNTER"
  : > "$WORK/pkill.log"
  local out="$WORK/out" status=0 start end
  start=$(date +%s)
  PATH="$WORK/bin:$PATH" LOG="$WORK/combined.log" SIMCTL=true \
    POLL=1 BUILD_BUDGET=3 LAUNCH_BUDGET=3 RUN_BUDGET=5 MAX_ATTEMPTS=3 \
    bash "$SCRIPT" "$TARGET_DEVICE" "${SUITES[@]}" > "$out" 2>&1 || status=$?
  end=$(date +%s)
  local ok=1
  [ "$status" -eq "$expect_status" ] || ok=0
  grep -qE "$expect_pattern" "$out" || ok=0
  [ $((end - start)) -le "$max_seconds" ] || ok=0
  if [ "$ok" -eq 1 ]; then
    echo "PASS  $name (exit $status in $((end - start))s)"
  else
    echo "FAIL  $name: expected exit $expect_status matching /$expect_pattern/ within ${max_seconds}s; got exit $status in $((end - start))s"
    sed 's/^/      | /' "$out"
    failures=$((failures + 1))
  fi
}

SUITES=(integration_test/media_info_test.dart)
run_case "clean pass" 0 'All tests passed' 6 pass
run_case "log reader died once, then passed" 0 'hung at launch on attempt 1 .*retrying' 10 logreader pass
run_case "silent launch hang on every attempt" 1 'hung at launch on all 3 attempts' 20 silent silent silent
run_case "build never finishes, then passes" 0 "no build-done marker within 3s" 12 nobuild pass
run_case "log reader died and the tool ignores SIGTERM: SIGKILL bounds the attempt" 0 'log reader died.*kill took 1[0-9]s' 20 stubborn pass
run_case "genuine failure fails fast with no retry" 1 'genuine failure, not a launch hang' 6 realfail pass
# A retry must never be attempted after a genuine failure: the second `pass` above is a
# trap, and the counter proves only one flutter call was made.
[ "$(cat "$WORK/counter")" = "1" ] || { echo "FAIL  genuine failure triggered a retry"; failures=$((failures + 1)); }

SUITES=(integration_test/media_info_test.dart integration_test/thumbnail_test.dart)
run_case "two suites, hang in the middle" 0 'All tests passed' 14 pass logreader pass
grep -c '^PARITY_JSON ' "$WORK/combined.log" | grep -qx 2 || { echo "FAIL  combined log should carry both suites' PARITY_JSON lines"; failures=$((failures + 1)); }
# The watchdog's reason and timings travel in the ::warning line on the script's stdout, never
# in the attempt log (the Flutter tool can overwrite anything appended there).
grep -q 'hung at launch on attempt 1 -- watchdog: launch failed (log reader died or app failed to start) (phase [a-z]*, [0-9]*s into it; build took [0-9?]*s, kill took [0-9]*s)' "$WORK/out" || { echo "FAIL  watchdog reason/timings missing from the warning line"; sed 's/^/      | /' "$WORK/out"; failures=$((failures + 1)); }

# --- macOS device mode (03-08, CI run 36195780910) ---
TARGET_DEVICE="macos"

SUITES=(integration_test/media_info_test.dart)
run_case "macOS build-done marker (a checkmark line, never 'Xcode build done.')" 0 'All tests passed' 6 macpass
# reset_device's macOS branch runs once before this single suite even starts (the "kill any
# leftover instance before every suite" call), regardless of whether anything actually needed
# killing.
grep -q 'pkill -x compress_video_example' "$WORK/pkill.log" || { echo "FAIL  reset_device did not pkill by executable name before the macOS suite"; failures=$((failures + 1)); }
grep -q 'pkill -f compress_video_example.app' "$WORK/pkill.log" || { echo "FAIL  reset_device did not pkill by bundle path before the macOS suite"; failures=$((failures + 1)); }

run_case "macOS leftover-app-instance launch failure is retried and recovers (T-03-37)" 0 'All tests passed' 10 macfail macpass
grep -q '^Failed to load .*Unable to start the app on the device\.' "$WORK/combined.log" || { echo "FAIL  macOS launch-failure fixture text missing from the combined log"; failures=$((failures + 1)); }
grep -q 'hung at launch on attempt 1 -- watchdog: launch failed (log reader died or app failed to start)' "$WORK/out" || { echo "FAIL  the macOS 'Unable to start the app on the device' shape was not classified as a retryable launch failure"; sed 's/^/      | /' "$WORK/out"; failures=$((failures + 1)); }
# Two pkill invocations expected: the pre-suite reset, then the retry-after-failure reset --
# proving reset_device runs BOTH before the suite starts and after the watchdog kills a hung
# attempt, which is the actual fix for a leftover instance surviving into the next launch.
[ "$(grep -c 'pkill -x compress_video_example' "$WORK/pkill.log")" -ge 2 ] || { echo "FAIL  expected at least 2 pre-suite/retry pkill invocations, got: $(cat "$WORK/pkill.log")"; failures=$((failures + 1)); }

TARGET_DEVICE="FAKE-UDID"

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
