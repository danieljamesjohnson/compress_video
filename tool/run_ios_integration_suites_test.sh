#!/usr/bin/env bash
# Self-test for tool/run_ios_integration_suites.sh: runs it against a fake `flutter` that
# replays the exact output shapes seen on CI (run 35826458554) -- a clean pass, the
# "log reader failed" launch failure followed by a hang, a silent launch hang, a build that
# never finishes, and a genuine test failure -- with the budgets shrunk to seconds.
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
  *)
    echo "fake flutter: unknown mode '$mode' for call $n" >&2
    exit 64 ;;
esac
EOF
chmod +x "$WORK/bin/flutter"

failures=0
run_case() {
  local name="$1" expect_status="$2" expect_pattern="$3" max_seconds="$4"
  shift 4
  export FAKE_SEQUENCE="$WORK/seq" FAKE_COUNTER="$WORK/counter"
  printf '%s\n' "$@" > "$FAKE_SEQUENCE"
  rm -f "$FAKE_COUNTER"
  local out="$WORK/out" status=0 start end
  start=$(date +%s)
  PATH="$WORK/bin:$PATH" LOG="$WORK/combined.log" SIMCTL=true \
    POLL=1 BUILD_BUDGET=3 LAUNCH_BUDGET=3 RUN_BUDGET=5 MAX_ATTEMPTS=3 \
    bash "$SCRIPT" FAKE-UDID "${SUITES[@]}" > "$out" 2>&1 || status=$?
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
run_case "build never finishes, then passes" 0 "no 'Xcode build done.' within 3s" 12 nobuild pass
run_case "genuine failure fails fast with no retry" 1 'genuine failure, not a launch hang' 6 realfail pass
# A retry must never be attempted after a genuine failure: the second `pass` above is a
# trap, and the counter proves only one flutter call was made.
[ "$(cat "$WORK/counter")" = "1" ] || { echo "FAIL  genuine failure triggered a retry"; failures=$((failures + 1)); }

SUITES=(integration_test/media_info_test.dart integration_test/thumbnail_test.dart)
run_case "two suites, hang in the middle" 0 'All tests passed' 14 pass logreader pass
grep -c '^PARITY_JSON ' "$WORK/combined.log" | grep -qx 2 || { echo "FAIL  combined log should carry both suites' PARITY_JSON lines"; failures=$((failures + 1)); }
# The combined log must not carry the dead attempt's error as if it were a result line.
grep -q 'watchdog: launch failed (log reader died)' "$WORK/combined.log" || { echo "FAIL  watchdog reason missing from combined log"; failures=$((failures + 1)); }

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
