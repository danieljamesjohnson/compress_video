#!/usr/bin/env bash
# Runs tool/measure_presets.dart's own documented reproduction procedure (its own header
# comment: copy into example/integration_test/, flutter test, remove) against one device, and
# extracts the machine-readable `MEASURE ...` lines to a file for doc/PRESETS.md's Apple
# section (03-07-PLAN.md task 3, 03-RESEARCH.md Pitfall 8/Open Question 2).
#
# This is a measurement harness, not an assertion suite -- a `flutter test` failure here still
# exits non-zero (so CI surfaces it), but the file itself contains no `expect(...)` calls
# (tool/measure_presets.dart's own header explains why: a failed run must never look like a
# passed assertion).
#
# Bounded and retried the same way the corpus suites are (04-03, CI run 36247184701): CI run
# 36247184701's "Measure presets on the iOS simulator" step wedged for 55+ minutes with no end
# in sight -- a bare `flutter test` here has no launch watchdog of its own, so the well-known
# hosted-simulator launch hang (flutter/flutter#116248/#77992, tool/run_ios_integration_suites.sh's
# own header explains it in full) can hold this step for the job's 360-minute limit, blocking
# the suites/XCTest/SPM steps that run after it. Rather than reimplement that watchdog, this
# script sources run_ios_integration_suites.sh for its `run_attempt`/`reset_device`/`run_suites`
# functions and drives them against a single synthetic "suite" (the copied measurement test),
# capped at 3 attempts -- a measurement is not worth retrying 8 times the way a real corpus
# suite is. .github/workflows/ci.yml additionally gives both "Measure presets" steps their own
# `timeout-minutes: 20` and `continue-on-error: true` as a second, independent bound: a hung or
# failed measurement must never block the job, only doc/PRESETS.md's own numbers.
#
# Usage: tool/measure_presets_ci.sh <device-id> <output-file>
#   device-id     a `flutter devices` id (a simulator UDID, or `macos`)
#   output-file   where the extracted `MEASURE ...` lines are written
#
# Run from the repository root; operates on example/.
set -uo pipefail

DEVICE_ID="${1:?usage: $0 <device-id> <output-file>}"
OUTPUT_FILE="${2:?usage: $0 <device-id> <output-file>}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COPIED_TEST="$REPO_ROOT/example/integration_test/measure_presets_test.dart"

cleanup() {
  rm -f "$COPIED_TEST"
}
trap cleanup EXIT

cp "$REPO_ROOT/tool/measure_presets.dart" "$COPIED_TEST"

RAW_LOG="$(mktemp)"

# Sourcing (not executing) run_ios_integration_suites.sh: its own bottom guard
# (`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]`) means sourcing it only defines functions/vars --
# it does not itself run any suite loop. The positional args below become that script's own
# $1/$2 for the duration of the source, setting UDID and SUITES exactly as if it had been
# invoked directly with one suite. MAX_ATTEMPTS/LOG are read via its own `${VAR:-default}`
# expansions, so setting them here before sourcing overrides those defaults.
MAX_ATTEMPTS=3
LOG="$RAW_LOG"
export MAX_ATTEMPTS LOG
(
  cd "$REPO_ROOT/example"
  # shellcheck source=/dev/null
  source "$REPO_ROOT/tool/run_ios_integration_suites.sh" "$DEVICE_ID" \
    "integration_test/measure_presets_test.dart"
  run_suites
)
STATUS=$?

# run_suites already streamed every attempt's output live (via its own `tee -a "$LOG"`), so
# $RAW_LOG only needs reading here for the MEASURE-line extraction, not re-printing.
grep '^MEASURE ' "$RAW_LOG" > "$OUTPUT_FILE" || true
echo "Wrote $(wc -l < "$OUTPUT_FILE") MEASURE lines to $OUTPUT_FILE"

exit "$STATUS"
