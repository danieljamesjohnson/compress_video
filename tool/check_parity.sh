#!/usr/bin/env bash
#
# Cross-platform parity gate (01-07): diffs the crossPlatform media-info and thumbnail values
# EACH RUNNER ACTUALLY OBSERVED, turning "the Android emulator and the iOS simulator agree" into
# a diff instead of an inference from running the same test file on both. Takes two file paths,
# each expected to contain one or more "PARITY_JSON <json>" lines emitted by the integration-test
# suites (media_info_test.dart, thumbnail_test.dart) and captured by CI via tee + grep.
#
# Uses the SAME field-level contract corpus/README.md already defines for the two platforms'
# OWN per-clip assertions: `crossPlatform` fields other than durationMs must be byte-identical;
# durationMs may differ by up to the clip's own sidecar `durationToleranceMs` (never a hardcoded
# number); the thumbnail's width/height must be byte-identical and its sampled patch RGB may
# differ per channel by up to the sidecar's own `thumbnailProbe.rgbTolerance` -- the same
# tolerance each platform's own integration test already uses for JPEG re-encoding loss, reused
# here rather than re-guessed. Exits non-zero on: a missing file, an empty file, a file with no
# PARITY_JSON lines, a clip with no matching corpus sidecar, or any field outside its tolerance.
# A missing artifact is never treated as a match.
#
# Usage: tool/check_parity.sh <platform-a-parity-file> <platform-b-parity-file>
# Env: PARITY_CORPUS_DIR overrides the corpus directory (default: ../corpus relative to this
#      script) -- used by check_parity_test.sh to point at hand-written fixture sidecars.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <platform-a-parity-file> <platform-b-parity-file>" >&2
  exit 1
fi

FILE_A="$1"
FILE_B="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORPUS_DIR="${PARITY_CORPUS_DIR:-$SCRIPT_DIR/../corpus}"

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
# (e.g. {"noaudio_720p": {...}, "portrait_rot90": {...}, "thumbnail": {...}, "compression":
# {...}, ...}). Two lines for the same key with the same value merge without conflict (harmless
# on a retried suite); `jq -s` (slurp) is required because each input line is its own JSON
# document, not one array. `*` (not `+`) is required so that separate suites' own "compression"
# objects -- compress_test.dart's, compress_audio_test.dart's, etc. -- deep-merge into one
# combined case-name -> record map instead of the later suite's object replacing the earlier
# one's wholesale (jq's `+` on two objects is a shallow merge; `*` recurses).
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

FAILED=0

fail() {
  echo "MISMATCH $1" >&2
  FAILED=1
}

# Every top-level key must appear in both records -- a clip or the thumbnail entry present on
# only one platform is itself a divergence, not something to silently skip.
KEYS_A="$(printf '%s' "$MERGED_A" | jq -r 'keys[]' | sort)"
KEYS_B="$(printf '%s' "$MERGED_B" | jq -r 'keys[]' | sort)"
if [ "$KEYS_A" != "$KEYS_B" ]; then
  echo "FATAL: top-level keys differ between the two records:" >&2
  diff <(printf '%s\n' "$KEYS_A") <(printf '%s\n' "$KEYS_B") >&2 || true
  exit 1
fi

# Fields every platform must report byte-identically (corpus/README.md's `crossPlatform`
# fields, minus durationMs which gets its own tolerance-based check below).
EXACT_FIELDS="widthPx heightPx rotationDegrees sizeBytes videoCodec hasAudio isHdr"

for clip in $KEYS_A; do
  [ "$clip" = "thumbnail" ] && continue
  [ "$clip" = "compression" ] && continue

  SIDECAR="$CORPUS_DIR/$clip.expected.json"
  if [ ! -f "$SIDECAR" ]; then
    echo "FATAL: no corpus sidecar found for clip '$clip' at $SIDECAR" >&2
    FAILED=1
    continue
  fi
  TOLERANCE_MS=$(jq -r '.crossPlatform.durationToleranceMs' "$SIDECAR")

  for field in $EXACT_FIELDS; do
    VAL_A=$(printf '%s' "$MERGED_A" | jq -c --arg f "$field" '.[$ARGS.named.clip][$f]' --arg clip "$clip")
    VAL_B=$(printf '%s' "$MERGED_B" | jq -c --arg f "$field" '.[$ARGS.named.clip][$f]' --arg clip "$clip")
    if [ "$VAL_A" != "$VAL_B" ]; then
      fail "$clip.$field: A=$VAL_A B=$VAL_B (must match exactly)"
    fi
  done

  DUR_A=$(printf '%s' "$MERGED_A" | jq -r --arg clip "$clip" '.[$clip].durationMs')
  DUR_B=$(printf '%s' "$MERGED_B" | jq -r --arg clip "$clip" '.[$clip].durationMs')
  # Guard against a missing/malformed durationMs field before the bash arithmetic below: `jq -r`
  # returns the literal string "null" for an absent field, and feeding that straight into
  # `$(( ))` fails with an opaque bash syntax error instead of this script's documented,
  # debuggable MISMATCH -- undermining the debuggability every other failure mode here is
  # deliberately designed around (see the `fail()` helper and its other call sites).
  if [ "$DUR_A" = "null" ] || [ "$DUR_B" = "null" ]; then
    fail "$clip.durationMs: A=$DUR_A B=$DUR_B (field missing on at least one platform)"
    continue
  fi
  # Same guard for the sidecar's own durationToleranceMs: every committed sidecar currently
  # carries this field, but a future refactor that renames or drops it should fail clean here,
  # not with a bash `-gt` usage error below.
  if [ "$TOLERANCE_MS" = "null" ] || [ -z "$TOLERANCE_MS" ]; then
    fail "$clip.durationToleranceMs: sidecar $SIDECAR is missing crossPlatform.durationToleranceMs (A=$DUR_A B=$DUR_B)"
    continue
  fi
  DIFF=$(( DUR_A > DUR_B ? DUR_A - DUR_B : DUR_B - DUR_A ))
  if [ "$DIFF" -gt "$TOLERANCE_MS" ]; then
    fail "$clip.durationMs: A=$DUR_A B=$DUR_B diff=${DIFF}ms exceeds sidecar durationToleranceMs=${TOLERANCE_MS}ms"
  fi
done

# Thumbnail record: width/height exact; sampled patch RGB within the sidecar's documented
# rgbTolerance per channel (portrait_rot90.expected.json is the sidecar carrying thumbnailProbe).
if printf '%s' "$MERGED_A" | jq -e 'has("thumbnail")' >/dev/null; then
  PROBE_SIDECAR="$CORPUS_DIR/portrait_rot90.expected.json"
  if [ ! -f "$PROBE_SIDECAR" ]; then
    echo "FATAL: no thumbnailProbe sidecar found at $PROBE_SIDECAR" >&2
    exit 1
  fi
  RGB_TOLERANCE=$(jq -r '.thumbnailProbe.rgbTolerance' "$PROBE_SIDECAR")

  for field in widthPx heightPx; do
    VAL_A=$(printf '%s' "$MERGED_A" | jq -c --arg f "$field" '.thumbnail[$f]')
    VAL_B=$(printf '%s' "$MERGED_B" | jq -c --arg f "$field" '.thumbnail[$f]')
    if [ "$VAL_A" != "$VAL_B" ]; then
      fail "thumbnail.$field: A=$VAL_A B=$VAL_B (must match exactly)"
    fi
  done

  # Guard the sidecar's own rgbTolerance before the per-channel arithmetic loop below: an
  # absent/malformed field must fail clean, not crash the whole loop with a bash `-gt` usage
  # error on the first channel.
  if [ "$RGB_TOLERANCE" = "null" ] || [ -z "$RGB_TOLERANCE" ]; then
    fail "thumbnail.rgbTolerance: sidecar $PROBE_SIDECAR is missing thumbnailProbe.rgbTolerance"
  else
    for i in 0 1 2; do
      C_A=$(printf '%s' "$MERGED_A" | jq -r --argjson i "$i" '.thumbnail.patchRgb[$i]')
      C_B=$(printf '%s' "$MERGED_B" | jq -r --argjson i "$i" '.thumbnail.patchRgb[$i]')
      # Same missing-field guard as durationMs above: a "null" from jq must become a clean
      # MISMATCH, never an opaque bash arithmetic error.
      if [ "$C_A" = "null" ] || [ "$C_B" = "null" ]; then
        fail "thumbnail.patchRgb[$i]: A=$C_A B=$C_B (field missing on at least one platform)"
        continue
      fi
      DIFF=$(( C_A > C_B ? C_A - C_B : C_B - C_A ))
      if [ "$DIFF" -gt "$RGB_TOLERANCE" ]; then
        fail "thumbnail.patchRgb[$i]: A=$C_A B=$C_B diff=$DIFF exceeds sidecar rgbTolerance=$RGB_TOLERANCE"
      fi
    done
  fi
fi

# Compression records (03-08, D-16): a nested top-level "compression" key mapping case-name ->
# CompressResult-shaped record, emitted by the four compress_*_test.dart suites' own tearDownAll
# blocks. Unlike the media-info clip records above, a compression CASE is not the same thing as
# a corpus CLIP, so tolerances are not looked up from a $clip.expected.json sidecar: each record
# instead carries its own `durationToleranceMs` directly (the test itself reads that value from
# whichever corpus sidecar the case's clip has, exactly as every other duration assertion in this
# repo does -- this script just trusts the number the test already derived correctly, rather than
# re-deriving a clip-name-to-sidecar mapping that would have to know about every compression case
# individually). `outputBytes` is intentionally NOT exact -- the two engines produce different
# byte counts by design -- and is compared with a documented +/-50% envelope instead: a tenfold
# regression still fails, a legitimate encoder difference does not (see corpus/README.md). A
# `reason` field (typed-error-bucket cases, e.g. fileNotFound/unsupportedInput) is compared
# exactly like any other exact field; the ONE known-divergent error bucket (`truncated_mdat.mp4`
# -- Android `io`, Apple `unsupportedInput`, see corpus/README.md) is deliberately never emitted
# into a PARITY_JSON record at all, so it never reaches this gate. `elapsedMs`, if present, is
# recorded for the log only and is never read here.
if printf '%s' "$MERGED_A" | jq -e 'has("compression")' >/dev/null; then
  CASES_A="$(printf '%s' "$MERGED_A" | jq -r '.compression | keys[]' | sort)"
  CASES_B="$(printf '%s' "$MERGED_B" | jq -r '.compression | keys[]' | sort)"
  if [ "$CASES_A" != "$CASES_B" ]; then
    echo "FATAL: compression case names differ between the two records:" >&2
    diff <(printf '%s\n' "$CASES_A") <(printf '%s\n' "$CASES_B") >&2 || true
    exit 1
  fi

  # Fields every platform must report byte-identically for a given compression case.
  # durationToleranceMs is included here (not just used below) because it is itself derived
  # identically on every platform from the same corpus sidecar convention -- a divergence in
  # the tolerance value itself would indicate a real bug in the test, not a platform difference.
  COMPRESSION_EXACT_FIELDS="widthPx heightPx videoCodec audioCodec transmuxed usedOriginal audioReencoded channels reason durationToleranceMs wouldTransmux wouldUseOriginal"
  BYTES_TOLERANCE_PCT=50

  for case_name in $CASES_A; do
    for field in $COMPRESSION_EXACT_FIELDS; do
      VAL_A=$(printf '%s' "$MERGED_A" | jq -c --arg c "$case_name" --arg f "$field" '.compression[$c][$f]')
      VAL_B=$(printf '%s' "$MERGED_B" | jq -c --arg c "$case_name" --arg f "$field" '.compression[$c][$f]')
      if [ "$VAL_A" != "$VAL_B" ]; then
        fail "compression.$case_name.$field: A=$VAL_A B=$VAL_B (must match exactly)"
      fi
    done

    DUR_A=$(printf '%s' "$MERGED_A" | jq -r --arg c "$case_name" '.compression[$c].durationMs')
    DUR_B=$(printf '%s' "$MERGED_B" | jq -r --arg c "$case_name" '.compression[$c].durationMs')
    if [ "$DUR_A" != "null" ] || [ "$DUR_B" != "null" ]; then
      if [ "$DUR_A" = "null" ] || [ "$DUR_B" = "null" ]; then
        fail "compression.$case_name.durationMs: A=$DUR_A B=$DUR_B (field missing on at least one platform)"
      else
        TOL=$(printf '%s' "$MERGED_A" | jq -r --arg c "$case_name" '.compression[$c].durationToleranceMs')
        if [ "$TOL" = "null" ] || [ -z "$TOL" ]; then
          fail "compression.$case_name.durationToleranceMs: missing -- cannot check durationMs tolerance (A=$DUR_A B=$DUR_B)"
        else
          DIFF=$(( DUR_A > DUR_B ? DUR_A - DUR_B : DUR_B - DUR_A ))
          if [ "$DIFF" -gt "$TOL" ]; then
            fail "compression.$case_name.durationMs: A=$DUR_A B=$DUR_B diff=${DIFF}ms exceeds durationToleranceMs=${TOL}ms"
          fi
        fi
      fi
    fi

    BYTES_A=$(printf '%s' "$MERGED_A" | jq -r --arg c "$case_name" '.compression[$c].outputBytes')
    BYTES_B=$(printf '%s' "$MERGED_B" | jq -r --arg c "$case_name" '.compression[$c].outputBytes')
    if [ "$BYTES_A" != "null" ] || [ "$BYTES_B" != "null" ]; then
      if [ "$BYTES_A" = "null" ] || [ "$BYTES_B" = "null" ]; then
        fail "compression.$case_name.outputBytes: A=$BYTES_A B=$BYTES_B (field missing on at least one platform)"
      else
        SMALLER=$(( BYTES_A < BYTES_B ? BYTES_A : BYTES_B ))
        LARGER=$(( BYTES_A > BYTES_B ? BYTES_A : BYTES_B ))
        if [ "$LARGER" -gt 0 ] && [ "$(( SMALLER * 100 ))" -lt "$(( LARGER * BYTES_TOLERANCE_PCT ))" ]; then
          fail "compression.$case_name.outputBytes: A=$BYTES_A B=$BYTES_B differ by more than the documented +/-${BYTES_TOLERANCE_PCT}% envelope (D-16)"
        fi
      fi
    fi
  done
fi

if [ "$FAILED" -ne 0 ]; then
  echo "Parity FAILED between $FILE_A and $FILE_B" >&2
  exit 1
fi

echo "Parity OK: $FILE_A matches $FILE_B (exact fields identical; durationMs and thumbnail RGB within each clip's own sidecar tolerance)"
