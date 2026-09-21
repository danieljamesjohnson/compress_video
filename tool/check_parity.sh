#!/usr/bin/env bash
#
# Cross-platform parity gate (01-07): diffs the crossPlatform media-info and thumbnail values
# EACH RUNNER ACTUALLY OBSERVED, turning "the Android emulator and the iOS simulator agree" into
# a diff instead of an inference from running the same test file on both. Takes two file paths,
# each expected to contain one or more "PARITY_JSON <json>" lines emitted by the integration-test
# suites (media_info_test.dart, thumbnail_test.dart) and captured by CI via tee + grep.
#
# Exits non-zero on: a missing file, an empty file, a file with no PARITY_JSON lines, or any
# value mismatch between the two merged records. A missing artifact is never treated as a match.
#
# Usage: tool/check_parity.sh <platform-a-parity-file> <platform-b-parity-file>

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <platform-a-parity-file> <platform-b-parity-file>" >&2
  exit 1
fi

FILE_A="$1"
FILE_B="$2"

for f in "$FILE_A" "$FILE_B"; do
  if [ ! -f "$f" ]; then
    echo "FATAL: parity file not found: $f" >&2
    exit 1
  fi
  if [ ! -s "$f" ]; then
    echo "FATAL: parity file is empty: $f" >&2
    exit 1
  fi
done

# Merges every "PARITY_JSON <json>" line in a file into one combined, key-sorted JSON object
# (e.g. {"noaudio_720p": {...}, "portrait_rot90": {...}, "thumbnail": {...}, ...}). Two lines
# for the same key with the same value merge without conflict (harmless on a retried suite);
# `jq -s` (slurp) is required because each input line is its own JSON document, not one array.
merge() {
  local file="$1"
  local lines
  lines=$(grep '^PARITY_JSON ' "$file" | sed -e 's/^PARITY_JSON //') || true
  if [ -z "$lines" ]; then
    echo "FATAL: no PARITY_JSON lines found in $file" >&2
    exit 1
  fi
  printf '%s\n' "$lines" | jq -s -S 'reduce .[] as $x ({}; . * $x)'
}

MERGED_A="$(merge "$FILE_A")"
MERGED_B="$(merge "$FILE_B")"

COMPACT_A="$(printf '%s' "$MERGED_A" | jq -S -c .)"
COMPACT_B="$(printf '%s' "$MERGED_B" | jq -S -c .)"

if [ "$COMPACT_A" = "$COMPACT_B" ]; then
  echo "Parity OK: $FILE_A matches $FILE_B"
  exit 0
fi

echo "Parity mismatch between $FILE_A and $FILE_B:" >&2
# Pretty-printed, key-sorted diff so any differing key is named on its own line, not buried in a
# single compact-JSON blob.
diff <(printf '%s' "$MERGED_A" | jq -S .) <(printf '%s' "$MERGED_B" | jq -S .) >&2 || true

exit 1
