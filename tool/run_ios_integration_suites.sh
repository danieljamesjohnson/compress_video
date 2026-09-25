#!/usr/bin/env bash
# Runs the corpus integration suites on one iOS simulator, one `flutter test` process per
# suite, with a launch watchdog that makes a hosted-simulator launch hang cheap and visible.
#
# Usage: tool/run_ios_integration_suites.sh <simulator-udid> [suite.dart ...]
#   Combined output of every attempt is appended to $LOG (default /tmp/apple_integration.log)
#   so the CI step that follows can grep the PARITY_JSON records out of it.
#
# Why a watchdog at all: `flutter test <suite> -d <sim>` discovers the Dart VM service by
# tailing the simulator's unified log through `xcrun simctl spawn <udid> log stream`
# (flutter_tools ios/simulators.dart, _IOSSimulatorLogReader). On GitHub's hosted macOS
# runners that process dies on roughly half of all launches. The tool then prints
# "No tests ran." and "Error waiting for a debug connection: The log reader failed
# unexpectedly" -- and never exits. This is a long-standing upstream flake
# (flutter/flutter#116248, #77992), not anything this plugin does, so the only lever here
# is to detect the dead launch instantly, kill it and retry from a fresh simulator boot.
#
# Measured on CI run 35826458554 before this script existed: the previous inline watchdog
# judged "did the app launch" by `wc -l > 1`, but Flutter's own preamble ("Warning: Missing
# build name", "Running Xcode build...", "Xcode build done.") pushes the log past one line
# immediately, so every hang got the full 600 s post-launch budget. Four hangs at ~12 min
# each (rebuild + 600 s + reset) consumed 48 of the step's 60 minutes and
# compress_audio_test.dart never ran. With phase-aware detection a hang costs one rebuild
# plus a few seconds (~2 min), which is why the per-suite attempt cap is 8 here and not 5.
#
# Exit codes: 0 every suite passed; a suite's own `flutter test` exit code when it failed
# with real test output (a genuine failure -- no retry); 1 when a suite hung on every attempt.
set -o pipefail

UDID="${1:?usage: $0 <simulator-udid> [suite ...]}"
shift
if [ "$#" -gt 0 ]; then
  SUITES=("$@")
else
  SUITES=(
    integration_test/media_info_test.dart
    integration_test/thumbnail_test.dart
    integration_test/compress_test.dart
    integration_test/compress_audio_test.dart
    integration_test/compress_jobs_test.dart
  )
fi

LOG="${LOG:-/tmp/apple_integration.log}"
# Budgets are overridable so the self-test (tool/run_ios_integration_suites_test.sh) can run
# the same code path in seconds.
BUILD_BUDGET="${BUILD_BUDGET:-900}"    # seconds to see "Xcode build done."
LAUNCH_BUDGET="${LAUNCH_BUDGET:-150}"  # seconds after the build for the first real test line
RUN_BUDGET="${RUN_BUDGET:-600}"        # seconds for a launched suite to finish
MAX_ATTEMPTS="${MAX_ATTEMPTS:-8}"
POLL="${POLL:-5}"
SIMCTL="${SIMCTL:-xcrun simctl}"

: > "$LOG"

reset_simulator() {
  $SIMCTL shutdown "$UDID" || true
  $SIMCTL boot "$UDID" || true
  $SIMCTL bootstatus "$UDID" -b || true
}

# Number of real test-progress lines ("MM:SS +N[ -M]: <test name>") in $1. `flutter test`'s
# own first line is always "00:00 +0: loading <suite>", which matches the same shape, so it
# is excluded: a launch only counts once a SECOND, non-loading progress line has appeared.
progress_lines() {
  grep -E '^[0-9]+:[0-9]{2} \+[0-9]+' "$1" 2>/dev/null | grep -vc ': loading ' || true
}

# Takes down the whole `flutter test` process group. SIGTERM first, but bounded: the
# Flutter tool runs shutdown hooks on SIGTERM and CI run 35857609478 showed a killed
# attempt still costing 3-4.5 minutes after its build finished, so anything still alive
# after 10 s gets SIGKILL. Never wait unbounded on a process this watchdog has given up on.
kill_tree() {
  local pid="$1" i
  kill -TERM -- -"$pid" 2>/dev/null || true
  for i in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL -- -"$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
}

# Set by run_attempt when the watchdog kills an attempt: why, and how long each phase took.
# Reported on this script's own stdout (in the ::warning line) rather than appended to the
# attempt log, because the still-running Flutter tool holds that file open without O_APPEND
# and can overwrite anything appended behind its own write offset -- run 35857609478 lost
# every such line that way.
WATCHDOG_NOTE=""

# Runs one attempt of suite $1, writing raw output to $2. Returns 0 (passed), the genuine
# `flutter test` exit code (failed with real output), or 99 (killed by the watchdog: the
# build never finished, the launch produced no test output in time, a launched suite
# overran, or the log reader died). `set -m` gives the background `flutter test` its own
# process group so kill_tree can take the whole tree down -- the Flutter tool spawns child
# processes, and killing only $pid would leave them running against the simulator.
run_attempt() {
  local suite="$1"
  local attempt_log="$2"
  : > "$attempt_log"
  set -m
  # --timeout 120s: these suites run real encodes, and `flutter test`'s 20 s default per-test
  # timeout is a slow-runner lottery -- CI run 35865459091 lost compress_test.dart's first
  # encode ("p720 scales the long side down to 1280", ~10 s on a normal runner) to it on a
  # runner whose Xcode build also took twice its usual time. Tests that declare their own
  # `timeout:` (compress_jobs_test.dart) keep it; this only raises the default.
  flutter test "$suite" -d "$UDID" -r expanded --timeout 120s > "$attempt_log" 2>&1 &
  local pid=$!
  set +m
  local phase=build
  local elapsed=0
  local started build_done=0
  started=$(date +%s)
  WATCHDOG_NOTE=""
  # $1 = reason. Kills the attempt and records the reason plus phase timings for the caller.
  give_up() {
    local kill_started build_secs='?'
    kill_started=$(date +%s)
    kill_tree "$pid"
    [ "$build_done" -gt 0 ] && build_secs=$((build_done - started))
    WATCHDOG_NOTE="watchdog: $1 (phase $phase, ${elapsed}s into it; build took ${build_secs}s, kill took $(( $(date +%s) - kill_started ))s)"
  }
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$POLL"
    elapsed=$((elapsed + POLL))
    # A dead log reader is definitive: the tool has already given up on this launch and
    # will sit there forever. Do not wait for any budget.
    if grep -qE 'Error waiting for a debug connection|^No tests ran\.' "$attempt_log"; then
      give_up "launch failed (log reader died)"
      return 99
    fi
    case "$phase" in
      build)
        if grep -q '^Xcode build done\.' "$attempt_log"; then
          phase=launch
          elapsed=0
          build_done=$(date +%s)
        elif [ "$elapsed" -ge "$BUILD_BUDGET" ]; then
              give_up "no 'Xcode build done.' within ${BUILD_BUDGET}s"
              return 99
        fi
        ;;
      launch)
        if [ "$(progress_lines "$attempt_log")" -gt 0 ]; then
          phase=run
          elapsed=0
        elif [ "$elapsed" -ge "$LAUNCH_BUDGET" ]; then
              give_up "no test output within ${LAUNCH_BUDGET}s of the build finishing"
              return 99
        fi
        ;;
      run)
        if [ "$elapsed" -ge "$RUN_BUDGET" ]; then
              give_up "suite still running ${RUN_BUDGET}s after its first test line"
              return 99
        fi
        ;;
    esac
  done
  wait "$pid"
}

reset_simulator || true
for suite in "${SUITES[@]}"; do
  attempt=1
  while :; do
    attempt_log=$(mktemp)
    status=0
    run_attempt "$suite" "$attempt_log" || status=$?
    cat "$attempt_log" | tee -a "$LOG"
    rm -f "$attempt_log"
    if [ "$status" -eq 0 ]; then
      break
    fi
    if [ "$status" -ne 99 ]; then
      echo "::error::$suite failed with real test output on attempt $attempt (exit $status) -- a genuine failure, not a launch hang; failing fast with no further retry"
      exit "$status"
    fi
    if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
      echo "::error::$suite hung at launch on all $attempt attempts (last: $WATCHDOG_NOTE)"
      exit 1
    fi
    echo "::warning::$suite hung at launch on attempt $attempt -- $WATCHDOG_NOTE; resetting the simulator and retrying"
    reset_simulator || true
    attempt=$((attempt + 1))
  done
done
