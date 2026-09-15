#!/usr/bin/env bash
# The single producer of corpus/*.expected.json.
#
# Default mode: re-derive every sidecar from the committed clips via ffprobe
# and diff it against the committed `<clip>.expected.json`. Any drift -
# including a hand-edited sidecar that no longer matches what ffprobe says
# about the clip - exits non-zero. Sidecars must never be hand-edited; this
# script is what proves that (see threat T-01-04 in 01-02-PLAN.md).
#
# `--write` mode: (re)generate every `<clip>.expected.json` from the
# committed clips. Use this only when the clips themselves change (i.e.
# after `generate_corpus.sh`), never to make a failing diff "pass".
#
# Field conventions (see README.md for the full rationale):
#   - rotationDegrees is UNSIGNED CLOCKWISE (matches Android/Apple), not
#     ffprobe's signed/CCW side_data rotation.
#   - widthPx/heightPx are the DISPLAYED dimensions (post-rotation), not the
#     coded ones ffprobe reports directly on the video stream.
#   - crossPlatform fields must match exactly across platforms; tolerant
#     fields (bitrate, frame rate) may differ within a documented tolerance.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

WRITE_MODE=false
if [ "${1:-}" = "--write" ]; then
  WRITE_MODE=true
fi

# Coded-frame colour-patch geometry, must match generate_corpus.sh exactly.
PATCH_BOX_X=1600
PATCH_BOX_Y=60
PATCH_BOX_W=200
PATCH_BOX_H=200
PATCH_CENTER_X=$((PATCH_BOX_X + PATCH_BOX_W / 2))
PATCH_CENTER_Y=$((PATCH_BOX_Y + PATCH_BOX_H / 2))
PROBE_POSITION_MS=1500
PROBE_COMPARE_MS=1000
RGB_TOLERANCE=24

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

probe_json() {
  ffprobe -v quiet -print_format json -show_streams -show_format "$1"
}

normalize_codec() {
  case "$1" in
    h264) echo "h264" ;;
    hevc) echo "hevc" ;;
    av1) echo "av1" ;;
    vp9) echo "vp9" ;;
    *) echo "unknown" ;;
  esac
}

# Sample the RGB triple at the centre of an 8x8 crop at ($1,$2) in the
# DISPLAYED frame, at time $3 (seconds), from clip $4. ffmpeg auto-applies
# the display matrix on decode, so cropping the extracted frame directly
# samples displayed (not coded) coordinates.
sample_rgb() {
  local x="$1" y="$2" t="$3" clip="$4"
  local crop_x=$((x - 4)) crop_y=$((y - 4))
  local raw
  raw=$(ffmpeg -y -loglevel error -ss "$t" -i "$clip" -frames:v 1 \
    -vf "crop=8:8:${crop_x}:${crop_y},scale=1:1" \
    -f rawvideo -pix_fmt rgb24 - | xxd -p)
  # raw is 6 hex chars: RRGGBB
  echo "$((16#${raw:0:2})) $((16#${raw:2:2})) $((16#${raw:4:2}))"
}

derive_sidecar() {
  local clip="$1"
  local json
  json=$(probe_json "$clip")

  local coded_w coded_h codec_name raw_rotation rotation_deg
  coded_w=$(echo "$json" | jq -r '.streams[] | select(.codec_type=="video") | .width')
  coded_h=$(echo "$json" | jq -r '.streams[] | select(.codec_type=="video") | .height')
  codec_name=$(echo "$json" | jq -r '.streams[] | select(.codec_type=="video") | .codec_name')
  raw_rotation=$(echo "$json" | jq -r '[.streams[] | select(.codec_type=="video") | .side_data_list[]? | select(.side_data_type=="Display Matrix") | .rotation] | first // 0')
  # unsigned clockwise = -(ffprobe's signed/CCW rotation), normalized to [0,360)
  rotation_deg=$(( ((-raw_rotation % 360) + 360) % 360 ))

  local width_px height_px
  if [ "$rotation_deg" = "90" ] || [ "$rotation_deg" = "270" ]; then
    width_px="$coded_h"
    height_px="$coded_w"
  else
    width_px="$coded_w"
    height_px="$coded_h"
  fi

  local duration_s duration_ms size_bytes has_audio audio_count video_bitrate frame_rate_raw frame_rate_fps
  duration_s=$(echo "$json" | jq -r '.format.duration')
  duration_ms=$(awk -v d="$duration_s" 'BEGIN{printf "%.0f", d*1000}')
  size_bytes=$(echo "$json" | jq -r '.format.size')
  audio_count=$(echo "$json" | jq '[.streams[] | select(.codec_type=="audio")] | length')
  if [ "$audio_count" -gt 0 ]; then has_audio=true; else has_audio=false; fi
  video_bitrate=$(echo "$json" | jq -r '.streams[] | select(.codec_type=="video") | .bit_rate // "null"')
  frame_rate_raw=$(echo "$json" | jq -r '.streams[] | select(.codec_type=="video") | .avg_frame_rate')
  frame_rate_fps=$(awk -F/ -v r="$frame_rate_raw" 'BEGIN{split(r,a,"/"); if (a[2]+0==0) print "null"; else printf "%.3f", a[1]/a[2]}')

  local video_codec
  video_codec=$(normalize_codec "$codec_name")

  local cross_platform tolerant
  cross_platform=$(jq -n \
    --argjson durationMs "$duration_ms" \
    --argjson durationToleranceMs 34 \
    --argjson widthPx "$width_px" \
    --argjson heightPx "$height_px" \
    --argjson rotationDegrees "$rotation_deg" \
    --argjson sizeBytes "$size_bytes" \
    --argjson hasAudio "$has_audio" \
    --argjson isHdr false \
    --arg videoCodec "$video_codec" \
    '{durationMs:$durationMs, durationToleranceMs:$durationToleranceMs, widthPx:$widthPx, heightPx:$heightPx, rotationDegrees:$rotationDegrees, sizeBytes:$sizeBytes, hasAudio:$hasAudio, isHdr:$isHdr, videoCodec:$videoCodec}')

  tolerant=$(jq -n \
    --argjson videoBitrateBps "$video_bitrate" \
    --argjson videoBitrateTolerancePct 25 \
    --argjson frameRateFps "$frame_rate_fps" \
    --argjson frameRateToleranceFps 0.5 \
    '{videoBitrateBps:$videoBitrateBps, videoBitrateTolerancePct:$videoBitrateTolerancePct, frameRateFps:$frameRateFps, frameRateToleranceFps:$frameRateToleranceFps}')

  if [ "$clip" = "portrait_rot90.mp4" ]; then
    # Transform the patch centre from CODED coordinates (where drawbox drew
    # it) to DISPLAYED coordinates (what a decoder that applies the tkhd
    # matrix - i.e. every real player, and ffmpeg's default -autorotate -
    # actually shows). For a 90-degree-clockwise display matrix, a coded
    # point (px,py) in a WxH coded frame displays at (H-py, px).
    local patch_x_px patch_y_px
    if [ "$rotation_deg" = "90" ]; then
      patch_x_px=$((coded_h - PATCH_CENTER_Y))
      patch_y_px="$PATCH_CENTER_X"
    elif [ "$rotation_deg" = "270" ]; then
      patch_x_px="$PATCH_CENTER_Y"
      patch_y_px=$((coded_w - PATCH_CENTER_X))
    else
      patch_x_px="$PATCH_CENTER_X"
      patch_y_px="$PATCH_CENTER_Y"
    fi

    read -r r1 g1 b1 <<< "$(sample_rgb "$patch_x_px" "$patch_y_px" "$(awk -v ms="$PROBE_POSITION_MS" 'BEGIN{printf "%.3f", ms/1000}')" "$clip")"
    read -r r0 g0 b0 <<< "$(sample_rgb "$patch_x_px" "$patch_y_px" "$(awk -v ms="$PROBE_COMPARE_MS" 'BEGIN{printf "%.3f", ms/1000}')" "$clip")"

    local diff_r=$(( r1 - r0 )); diff_r=${diff_r#-}
    local diff_g=$(( g1 - g0 )); diff_g=${diff_g#-}
    local diff_b=$(( b1 - b0 )); diff_b=${diff_b#-}
    if [ "$diff_r" -le "$RGB_TOLERANCE" ] && [ "$diff_g" -le "$RGB_TOLERANCE" ] && [ "$diff_b" -le "$RGB_TOLERANCE" ]; then
      fail "thumbnail probe patch at (${PATCH_CENTER_X},${PATCH_CENTER_Y}) does not distinguish ${PROBE_COMPARE_MS}ms from ${PROBE_POSITION_MS}ms (rgb ${r0},${g0},${b0} vs ${r1},${g1},${b1}, tolerance ${RGB_TOLERANCE}) - probe is useless"
    fi

    local thumbnail_probe
    thumbnail_probe=$(jq -n \
      --argjson positionMs "$PROBE_POSITION_MS" \
      --argjson patchXPx "$patch_x_px" \
      --argjson patchYPx "$patch_y_px" \
      --argjson expectedRgb "[$r1,$g1,$b1]" \
      --argjson rgbTolerance "$RGB_TOLERANCE" \
      '{positionMs:$positionMs, patchXPx:$patchXPx, patchYPx:$patchYPx, expectedRgb:$expectedRgb, rgbTolerance:$rgbTolerance}')

    jq -n --argjson crossPlatform "$cross_platform" --argjson tolerant "$tolerant" --argjson thumbnailProbe "$thumbnail_probe" \
      '{crossPlatform:$crossPlatform, tolerant:$tolerant, thumbnailProbe:$thumbnailProbe}'
  else
    jq -n --argjson crossPlatform "$cross_platform" --argjson tolerant "$tolerant" \
      '{crossPlatform:$crossPlatform, tolerant:$tolerant}'
  fi
}

CLIPS=(portrait_rot90.mp4 small_480p.mp4 noaudio_720p.mp4)
STATUS=0

for clip in "${CLIPS[@]}"; do
  if [ ! -f "$clip" ]; then
    fail "$clip not found - run generate_corpus.sh first"
  fi
  sidecar_path="${clip%.mp4}.expected.json"
  derived=$(derive_sidecar "$clip")

  if [ "$WRITE_MODE" = true ]; then
    echo "$derived" | jq -S '.' > "$sidecar_path"
    echo "wrote $sidecar_path"
  else
    if [ ! -f "$sidecar_path" ]; then
      echo "MISSING sidecar: $sidecar_path" >&2
      STATUS=1
      continue
    fi
    committed=$(jq -S '.' "$sidecar_path")
    derived_sorted=$(echo "$derived" | jq -S '.')
    if [ "$committed" != "$derived_sorted" ]; then
      echo "DRIFT in $sidecar_path:" >&2
      diff <(echo "$committed") <(echo "$derived_sorted") >&2 || true
      STATUS=1
    else
      echo "OK: $sidecar_path matches $clip"
    fi
  fi
done

exit "$STATUS"
