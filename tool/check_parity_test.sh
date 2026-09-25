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

# Case 3 (WR-03): durationMs missing entirely on one platform. Must FAIL with a clean MISMATCH
# naming the field as missing -- never a bash arithmetic syntax error from feeding jq's literal
# "null" string into `$(( ))`.
{
  echo 'PARITY_JSON {"fixture_clip":{"hasAudio":true,"heightPx":200,"isHdr":false,"rotationDegrees":0,"sizeBytes":500,"videoCodec":"h264","widthPx":100}}'
} > "$TMP/a_missing_duration.txt"
{
  echo 'PARITY_JSON {"fixture_clip":{"durationMs":1000,"hasAudio":true,"heightPx":200,"isHdr":false,"rotationDegrees":0,"sizeBytes":500,"videoCodec":"h264","widthPx":100}}'
} > "$TMP/b_missing_duration.txt"

if PARITY_CORPUS_DIR="$TMP/corpus" bash "$SCRIPT_DIR/check_parity.sh" "$TMP/a_missing_duration.txt" "$TMP/b_missing_duration.txt" > "$TMP/missing_duration.out" 2>&1; then
  echo "SELF-TEST FAILED: expected the missing-durationMs fixture to FAIL. Output:" >&2
  cat "$TMP/missing_duration.out" >&2
  FAILED=1
elif ! grep -q 'MISMATCH fixture_clip.durationMs.*field missing' "$TMP/missing_duration.out"; then
  echo "SELF-TEST FAILED: missing-durationMs failure did not produce a clean MISMATCH naming the field as missing (got a bash arithmetic error instead?). Output:" >&2
  cat "$TMP/missing_duration.out" >&2
  FAILED=1
else
  echo "PASS: missing-durationMs fixture correctly fails cleanly and names fixture_clip.durationMs as missing"
fi

# Case 4 (IN-02/WR-03): thumbnail.patchRgb missing entirely on one platform. Must FAIL with a
# clean MISMATCH naming each missing channel -- same guard, for the per-channel arithmetic loop.
{
  echo 'PARITY_JSON {"fixture_clip":{"durationMs":1000,"hasAudio":true,"heightPx":200,"isHdr":false,"rotationDegrees":0,"sizeBytes":500,"videoCodec":"h264","widthPx":100}}'
  echo 'PARITY_JSON {"thumbnail":{"heightPx":10,"widthPx":10}}'
} > "$TMP/a_missing_rgb.txt"
{
  echo 'PARITY_JSON {"fixture_clip":{"durationMs":1000,"hasAudio":true,"heightPx":200,"isHdr":false,"rotationDegrees":0,"sizeBytes":500,"videoCodec":"h264","widthPx":100}}'
  echo 'PARITY_JSON {"thumbnail":{"heightPx":10,"patchRgb":[100,100,100],"widthPx":10}}'
} > "$TMP/b_missing_rgb.txt"

if PARITY_CORPUS_DIR="$TMP/corpus" bash "$SCRIPT_DIR/check_parity.sh" "$TMP/a_missing_rgb.txt" "$TMP/b_missing_rgb.txt" > "$TMP/missing_rgb.out" 2>&1; then
  echo "SELF-TEST FAILED: expected the missing-patchRgb fixture to FAIL. Output:" >&2
  cat "$TMP/missing_rgb.out" >&2
  FAILED=1
elif ! grep -q 'MISMATCH thumbnail.patchRgb\[0\].*field missing' "$TMP/missing_rgb.out"; then
  echo "SELF-TEST FAILED: missing-patchRgb failure did not produce a clean MISMATCH naming the channel as missing (got a bash arithmetic error instead?). Output:" >&2
  cat "$TMP/missing_rgb.out" >&2
  FAILED=1
else
  echo "PASS: missing-patchRgb fixture correctly fails cleanly and names thumbnail.patchRgb[0] as missing"
fi

# --- Compression records (03-08, D-16): fixture cases proving check_parity.sh's new
# "compression" case-name -> record handling, in both directions, for every new field kind:
# exact fields (transmuxed, videoCodec), the tolerance-based durationMs check (using the
# record's own embedded durationToleranceMs, not a corpus sidecar), and the +/-50% outputBytes
# envelope. No corpus sidecar is needed for any of these -- compression cases carry their own
# tolerances directly.

# Case 5: all four compression fields within tolerance/matching. Must PASS.
{
  echo 'PARITY_JSON {"compression":{"bytes_ok":{"outputBytes":1000000,"transmuxed":true,"videoCodec":"h264","durationMs":1000,"durationToleranceMs":34},"transmux_ok":{"transmuxed":true},"codec_ok":{"videoCodec":"h264"},"duration_ok":{"durationMs":1000,"durationToleranceMs":34}}}'
} > "$TMP/a_compression_within.txt"
{
  echo 'PARITY_JSON {"compression":{"bytes_ok":{"outputBytes":700000,"transmuxed":true,"videoCodec":"h264","durationMs":1020,"durationToleranceMs":34},"transmux_ok":{"transmuxed":true},"codec_ok":{"videoCodec":"h264"},"duration_ok":{"durationMs":1020,"durationToleranceMs":34}}}'
} > "$TMP/b_compression_within.txt"

if PARITY_CORPUS_DIR="$TMP/corpus" bash "$SCRIPT_DIR/check_parity.sh" "$TMP/a_compression_within.txt" "$TMP/b_compression_within.txt" > "$TMP/compression_within.out" 2>&1; then
  echo "PASS: within-tolerance compression fixture (bytes ratio 0.7, matching flags/codec, duration within tolerance) correctly passes"
else
  echo "SELF-TEST FAILED: expected the within-tolerance compression fixture to PASS. Output:" >&2
  cat "$TMP/compression_within.out" >&2
  FAILED=1
fi

# Case 6: outputBytes ratio 0.4 -- below the documented 50% envelope. Must FAIL naming the field.
{
  echo 'PARITY_JSON {"compression":{"bytes_bad":{"outputBytes":1000000}}}'
} > "$TMP/a_compression_bytes.txt"
{
  echo 'PARITY_JSON {"compression":{"bytes_bad":{"outputBytes":400000}}}'
} > "$TMP/b_compression_bytes.txt"

if PARITY_CORPUS_DIR="$TMP/corpus" bash "$SCRIPT_DIR/check_parity.sh" "$TMP/a_compression_bytes.txt" "$TMP/b_compression_bytes.txt" > "$TMP/compression_bytes.out" 2>&1; then
  echo "SELF-TEST FAILED: expected the out-of-envelope outputBytes fixture to FAIL. Output:" >&2
  cat "$TMP/compression_bytes.out" >&2
  FAILED=1
elif ! grep -q 'compression.bytes_bad.outputBytes' "$TMP/compression_bytes.out"; then
  echo "SELF-TEST FAILED: out-of-envelope outputBytes failure did not name the field. Output:" >&2
  cat "$TMP/compression_bytes.out" >&2
  FAILED=1
else
  echo "PASS: out-of-envelope outputBytes fixture (ratio 0.4) correctly fails and names compression.bytes_bad.outputBytes"
fi

# Case 7 (T-03-36 teeth demonstration): flipping the transmuxed flag. Must FAIL naming the
# field -- this is the "deliberately corrupted fixture" the plan requires be demonstrated once.
{
  echo 'PARITY_JSON {"compression":{"transmux_bad":{"transmuxed":true}}}'
} > "$TMP/a_compression_transmux.txt"
{
  echo 'PARITY_JSON {"compression":{"transmux_bad":{"transmuxed":false}}}'
} > "$TMP/b_compression_transmux.txt"

if PARITY_CORPUS_DIR="$TMP/corpus" bash "$SCRIPT_DIR/check_parity.sh" "$TMP/a_compression_transmux.txt" "$TMP/b_compression_transmux.txt" > "$TMP/compression_transmux.out" 2>&1; then
  echo "SELF-TEST FAILED: expected the flipped-transmuxed-flag fixture to FAIL. Output:" >&2
  cat "$TMP/compression_transmux.out" >&2
  FAILED=1
elif ! grep -q 'compression.transmux_bad.transmuxed' "$TMP/compression_transmux.out"; then
  echo "SELF-TEST FAILED: flipped-transmuxed-flag failure did not name the field. Output:" >&2
  cat "$TMP/compression_transmux.out" >&2
  FAILED=1
else
  echo "PASS: flipped transmuxed flag correctly fails and names compression.transmux_bad.transmuxed (T-03-36 teeth demonstration)"
fi

# Case 8: a differing videoCodec. Must FAIL naming the field.
{
  echo 'PARITY_JSON {"compression":{"codec_bad":{"videoCodec":"h264"}}}'
} > "$TMP/a_compression_codec.txt"
{
  echo 'PARITY_JSON {"compression":{"codec_bad":{"videoCodec":"hevc"}}}'
} > "$TMP/b_compression_codec.txt"

if PARITY_CORPUS_DIR="$TMP/corpus" bash "$SCRIPT_DIR/check_parity.sh" "$TMP/a_compression_codec.txt" "$TMP/b_compression_codec.txt" > "$TMP/compression_codec.out" 2>&1; then
  echo "SELF-TEST FAILED: expected the differing-videoCodec fixture to FAIL. Output:" >&2
  cat "$TMP/compression_codec.out" >&2
  FAILED=1
elif ! grep -q 'compression.codec_bad.videoCodec' "$TMP/compression_codec.out"; then
  echo "SELF-TEST FAILED: differing-videoCodec failure did not name the field. Output:" >&2
  cat "$TMP/compression_codec.out" >&2
  FAILED=1
else
  echo "PASS: differing videoCodec correctly fails and names compression.codec_bad.videoCodec"
fi

# Case 9: durationMs outside its OWN embedded durationToleranceMs (not a corpus sidecar value).
# Must FAIL naming the field.
{
  echo 'PARITY_JSON {"compression":{"duration_bad":{"durationMs":1000,"durationToleranceMs":34}}}'
} > "$TMP/a_compression_duration.txt"
{
  echo 'PARITY_JSON {"compression":{"duration_bad":{"durationMs":1040,"durationToleranceMs":34}}}'
} > "$TMP/b_compression_duration.txt"

if PARITY_CORPUS_DIR="$TMP/corpus" bash "$SCRIPT_DIR/check_parity.sh" "$TMP/a_compression_duration.txt" "$TMP/b_compression_duration.txt" > "$TMP/compression_duration.out" 2>&1; then
  echo "SELF-TEST FAILED: expected the out-of-tolerance compression durationMs fixture to FAIL. Output:" >&2
  cat "$TMP/compression_duration.out" >&2
  FAILED=1
elif ! grep -q 'compression.duration_bad.durationMs' "$TMP/compression_duration.out"; then
  echo "SELF-TEST FAILED: out-of-tolerance compression durationMs failure did not name the field. Output:" >&2
  cat "$TMP/compression_duration.out" >&2
  FAILED=1
else
  echo "PASS: out-of-tolerance compression durationMs correctly fails and names compression.duration_bad.durationMs"
fi

# Case 10: a compression case present on only one platform. Must FAIL loud (FATAL), not silently
# skip the missing case -- the same "never treat a missing artifact as a match" contract the
# top-level clip-key check already enforces (T-03-35).
{
  echo 'PARITY_JSON {"compression":{"only_on_a":{"videoCodec":"h264"}}}'
} > "$TMP/a_compression_onlyone.txt"
{
  echo 'PARITY_JSON {"compression":{}}'
} > "$TMP/b_compression_onlyone.txt"

if PARITY_CORPUS_DIR="$TMP/corpus" bash "$SCRIPT_DIR/check_parity.sh" "$TMP/a_compression_onlyone.txt" "$TMP/b_compression_onlyone.txt" > "$TMP/compression_onlyone.out" 2>&1; then
  echo "SELF-TEST FAILED: expected the case-present-on-only-one-platform fixture to FAIL. Output:" >&2
  cat "$TMP/compression_onlyone.out" >&2
  FAILED=1
elif ! grep -q 'compression case names differ' "$TMP/compression_onlyone.out"; then
  echo "SELF-TEST FAILED: case-present-on-only-one-platform failure did not report the FATAL case-name diff. Output:" >&2
  cat "$TMP/compression_onlyone.out" >&2
  FAILED=1
else
  echo "PASS: a compression case present on only one platform correctly fails loudly (FATAL, T-03-35)"
fi

if [ "$FAILED" -ne 0 ]; then
  echo "check_parity.sh self-test: FAILED" >&2
  exit 1
fi

echo "check_parity.sh self-test: PASSED"
