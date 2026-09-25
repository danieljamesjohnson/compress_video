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
# Usage: tool/measure_presets_ci.sh <device-id> <output-file>
#   device-id     a `flutter devices` id (a simulator UDID, or `macos`)
#   output-file   where the extracted `MEASURE ...` lines are written
#
# Run from the repository root; operates on example/.
set -euo pipefail

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
(
  cd "$REPO_ROOT/example"
  flutter test integration_test/measure_presets_test.dart -d "$DEVICE_ID"
) | tee "$RAW_LOG"

grep '^MEASURE ' "$RAW_LOG" > "$OUTPUT_FILE"
echo "Wrote $(wc -l < "$OUTPUT_FILE") MEASURE lines to $OUTPUT_FILE"
