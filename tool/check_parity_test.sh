#!/usr/bin/env bash
#
# Fixture-based self-test for check_parity.sh (01-07): proves the gate itself catches an
# out-of-tolerance divergence and passes a within-tolerance one, using tiny hand-written
# fixtures and PARITY_CORPUS_DIR rather than a real corpus run. Exits non-zero if either case
# behaves the wrong way.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/corpus"

cat > "$TMP/corpus/fixture_clip.expected.json" <<'JSON'
{
  "crossPlatform": {
    "durationMs": 1000,
    "durationToleranceMs": 34,
    "widthPx": 100,
    "heightPx": 200,
    "rotationDegrees": 0,
    "sizeBytes": 500,
    "videoCodec": "h264",
    "hasAudio": true,
    "isHdr": false
  }
}
JSON

cat > "$TMP/corpus/portrait_rot90.expected.json" <<'JSON'
{"thumbnailProbe": {"rgbTolerance": 24}}
JSON

FAILED=0

# Case 1: within tolerance -- durationMs differs by 20ms (<=34), one RGB channel differs by 10
# (<=24). Must PASS.
{
  echo 'PARITY_JSON {"fixture_clip":{"durationMs":1000,"hasAudio":true,"heightPx":200,"isHdr":false,"rotationDegrees":0,"sizeBytes":500,"videoCodec":"h264","widthPx":100}}'
  echo 'PARITY_JSON {"thumbnail":{"heightPx":10,"patchRgb":[100,100,100],"widthPx":10}}'
} > "$TMP/a_within.txt"
{
  echo 'PARITY_JSON {"fixture_clip":{"durationMs":1020,"hasAudio":true,"heightPx":200,"isHdr":false,"rotationDegrees":0,"sizeBytes":500,"videoCodec":"h264","widthPx":100}}'
  echo 'PARITY_JSON {"thumbnail":{"heightPx":10,"patchRgb":[100,110,100],"widthPx":10}}'
} > "$TMP/b_within.txt"

if PARITY_CORPUS_DIR="$TMP/corpus" bash "$SCRIPT_DIR/check_parity.sh" "$TMP/a_within.txt" "$TMP/b_within.txt" > "$TMP/within.out" 2>&1; then
  echo "PASS: within-tolerance fixture correctly passes"
else
  echo "SELF-TEST FAILED: expected the within-tolerance fixture to PASS. Output:" >&2
  cat "$TMP/within.out" >&2
  FAILED=1
fi

# Case 2: outside tolerance -- durationMs differs by 40ms (>34). Must FAIL and name the field.
{
  echo 'PARITY_JSON {"fixture_clip":{"durationMs":1000,"hasAudio":true,"heightPx":200,"isHdr":false,"rotationDegrees":0,"sizeBytes":500,"videoCodec":"h264","widthPx":100}}'
} > "$TMP/a_outside.txt"
{
  echo 'PARITY_JSON {"fixture_clip":{"durationMs":1040,"hasAudio":true,"heightPx":200,"isHdr":false,"rotationDegrees":0,"sizeBytes":500,"videoCodec":"h264","widthPx":100}}'
} > "$TMP/b_outside.txt"

if PARITY_CORPUS_DIR="$TMP/corpus" bash "$SCRIPT_DIR/check_parity.sh" "$TMP/a_outside.txt" "$TMP/b_outside.txt" > "$TMP/outside.out" 2>&1; then
  echo "SELF-TEST FAILED: expected the out-of-tolerance fixture to FAIL. Output:" >&2
  cat "$TMP/outside.out" >&2
  FAILED=1
elif ! grep -q 'fixture_clip.durationMs' "$TMP/outside.out"; then
  echo "SELF-TEST FAILED: out-of-tolerance failure did not name the differing field. Output:" >&2
  cat "$TMP/outside.out" >&2
  FAILED=1
else
  echo "PASS: out-of-tolerance fixture correctly fails and names fixture_clip.durationMs"
fi

if [ "$FAILED" -ne 0 ]; then
  echo "check_parity.sh self-test: FAILED" >&2
  exit 1
fi

echo "check_parity.sh self-test: PASSED"
