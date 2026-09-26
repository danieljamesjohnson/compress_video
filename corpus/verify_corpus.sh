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
#   - thumbnailProbe is derived for every clip that carries the 8-bucket
#     colour-patch schedule (currently portrait_rot90.mp4 and
#     portrait_hibitrate_1080p60.mp4). edgeProbe is derived only for
#     portrait_hibitrate_1080p60.mp4, which alone carries the white border.
#
# truncated_mdat.mp4 is deliberately excluded from sidecar derivation: it is
# a structurally damaged fixture whose whole point is that decoding its media
# data fails, so it has no "ground truth" to derive beyond "ffprobe can still
# read a video stream and a duration from it" - checked separately below,
# never diffed against a `.expected.json`.

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

# Clips carrying the 8-bucket colour-patch schedule (thumbnailProbe).
PATCH_CLIPS=(portrait_rot90.mp4 portrait_hibitrate_1080p60.mp4)
# The one clip that also carries the white edge border (edgeProbe).
EDGE_CLIP=portrait_hibitrate_1080p60.mp4
EDGE_BORDER_PX=24
EDGE_INSET_PX=4
EDGE_RGB_TOLERANCE=48
# The deliberately damaged clip: no sidecar, checked separately below.
DAMAGED_CLIP=truncated_mdat.mp4
# The one clip long enough to express a trim range (Phase 3, D-13). Its
# sidecar gains a `trim` block on top of the standard crossPlatform/tolerant
# blocks every other clip in CLIPS already gets.
TRIM_CLIP=trim_source_10s.mp4
TRIM_START_MS=2000
TRIM_END_MS=7000
TRIM_MIN_INSIDE_MS=500

# Clips carrying an `hdr`/`hdrProbe` sidecar block (Phase 4, D-01). Coded-frame patch
# geometry, must match generate_corpus.sh's hdr_hlg10.mp4/hdr_pq10.mp4 drawbox calls exactly.
# No rotation matrix on any HDR clip, so coded coordinates ARE displayed coordinates.
HDR_CLIPS=(hdr_hlg10.mp4 hdr_pq10.mp4)
HDR_PATCH_BOX_W=160
HDR_PATCH_BOX_H=160
HDR_PATCH_Y=40
HDR_PATCH_XS=(40 240 440 640)
HDR_PATCH_CHANNELS=(r g b none)
# Documented floors/margin for a later plan's tone-mapped-output sample (04-05): this box
# cannot author a reference tone-map, so this sidecar records colour IDENTITY (which patch is
# which) and thresholds, never an expected RGB triple.
HDR_MIN_SATURATION=40
HDR_MIN_WHITE_LUMA=120
HDR_DOMINANCE_MARGIN=20

is_hdr_clip() {
  local needle="$1" c
  for c in "${HDR_CLIPS[@]}"; do
    [ "$c" = "$needle" ] && return 0
  done
  return 1
}

# Clips carrying an `audio` sidecar block (Phase 4, D-09/D-10): the source's real codec and
# channel count, read directly from ffprobe rather than normalized, since this block is about
# what the source really is, not the normalize_codec() bucket used for cross-platform video.
AUDIO_PROBE_CLIPS=(pcm_audio_480p.mov surround51_480p.mp4)

is_audio_probe_clip() {
  local needle="$1" c
  for c in "${AUDIO_PROBE_CLIPS[@]}"; do
    [ "$c" = "$needle" ] && return 0
  done
  return 1
}

is_patch_clip() {
  local needle="$1" c
  for c in "${PATCH_CLIPS[@]}"; do
    [ "$c" = "$needle" ] && return 0
  done
  return 1
}

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

  # isHdr is derived from the clip's own probed colour transfer, not hardcoded: arib-std-b67
  # (HLG) and smpte2084 (PQ/HDR10) are the two transfer functions this corpus's HDR clips carry.
  local color_transfer is_hdr
  color_transfer=$(echo "$json" | jq -r '.streams[] | select(.codec_type=="video") | .color_transfer // "unknown"')
  case "$color_transfer" in
    arib-std-b67|smpte2084) is_hdr=true ;;
    *) is_hdr=false ;;
  esac

  local cross_platform tolerant
  cross_platform=$(jq -n \
    --argjson durationMs "$duration_ms" \
    --argjson durationToleranceMs 34 \
    --argjson widthPx "$width_px" \
    --argjson heightPx "$height_px" \
    --argjson rotationDegrees "$rotation_deg" \
    --argjson sizeBytes "$size_bytes" \
    --argjson hasAudio "$has_audio" \
    --argjson isHdr "$is_hdr" \
    --arg videoCodec "$video_codec" \
    '{durationMs:$durationMs, durationToleranceMs:$durationToleranceMs, widthPx:$widthPx, heightPx:$heightPx, rotationDegrees:$rotationDegrees, sizeBytes:$sizeBytes, hasAudio:$hasAudio, isHdr:$isHdr, videoCodec:$videoCodec}')

  tolerant=$(jq -n \
    --argjson videoBitrateBps "$video_bitrate" \
    --argjson videoBitrateTolerancePct 25 \
    --argjson frameRateFps "$frame_rate_fps" \
    --argjson frameRateToleranceFps 0.5 \
    '{videoBitrateBps:$videoBitrateBps, videoBitrateTolerancePct:$videoBitrateTolerancePct, frameRateFps:$frameRateFps, frameRateToleranceFps:$frameRateToleranceFps}')

  local result
  result=$(jq -n --argjson crossPlatform "$cross_platform" --argjson tolerant "$tolerant" \
    '{crossPlatform:$crossPlatform, tolerant:$tolerant}')

  if is_patch_clip "$clip"; then
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

    result=$(jq -n --argjson base "$result" --argjson thumbnailProbe "$thumbnail_probe" '$base + {thumbnailProbe:$thumbnailProbe}')
  fi

  if [ "$clip" = "$EDGE_CLIP" ]; then
    # Four points, each inset EDGE_INSET_PX from the midpoint of one
    # DISPLAYED edge. EDGE_INSET_PX (4) is well inside EDGE_BORDER_PX (24),
    # so every point lands inside the painted white border regardless of
    # rotation. sample_rgb already samples displayed coordinates.
    local t_s
    t_s=$(awk -v ms="$PROBE_POSITION_MS" 'BEGIN{printf "%.3f", ms/1000}')
    local top_x=$((width_px / 2)) top_y="$EDGE_INSET_PX"
    local bottom_x=$((width_px / 2)) bottom_y=$((height_px - EDGE_INSET_PX))
    local left_x="$EDGE_INSET_PX" left_y=$((height_px / 2))
    local right_x=$((width_px - EDGE_INSET_PX)) right_y=$((height_px / 2))

    local tr tg tb br bg bb lr lg lb rr rg rb
    read -r tr tg tb <<< "$(sample_rgb "$top_x" "$top_y" "$t_s" "$clip")"
    read -r br bg bb <<< "$(sample_rgb "$bottom_x" "$bottom_y" "$t_s" "$clip")"
    read -r lr lg lb <<< "$(sample_rgb "$left_x" "$left_y" "$t_s" "$clip")"
    read -r rr rg rb <<< "$(sample_rgb "$right_x" "$right_y" "$t_s" "$clip")"

    local name pr pg pb dr dg db entry
    for entry in "bottom:$br:$bg:$bb" "left:$lr:$lg:$lb" "right:$rr:$rg:$rb"; do
      IFS=: read -r name pr pg pb <<< "$entry"
      dr=$(( tr - pr )); dr=${dr#-}
      dg=$(( tg - pg )); dg=${dg#-}
      db=$(( tb - pb )); db=${db#-}
      if [ "$dr" -gt "$EDGE_RGB_TOLERANCE" ] || [ "$dg" -gt "$EDGE_RGB_TOLERANCE" ] || [ "$db" -gt "$EDGE_RGB_TOLERANCE" ]; then
        fail "edge probe: $name border sample (${pr},${pg},${pb}) disagrees with top (${tr},${tg},${tb}) beyond tolerance ${EDGE_RGB_TOLERANCE} for $clip"
      fi
    done

    if [ "$tr" -le "$EDGE_RGB_TOLERANCE" ] && [ "$tg" -le "$EDGE_RGB_TOLERANCE" ] && [ "$tb" -le "$EDGE_RGB_TOLERANCE" ]; then
      fail "edge probe: border colour (${tr},${tg},${tb}) is not distinguishable from black (tolerance ${EDGE_RGB_TOLERANCE}) for $clip - probe is useless"
    fi

    local edge_probe
    edge_probe=$(jq -n \
      --argjson borderPx "$EDGE_BORDER_PX" \
      --argjson insetPx "$EDGE_INSET_PX" \
      --argjson expectedRgb "[$tr,$tg,$tb]" \
      --argjson rgbTolerance "$EDGE_RGB_TOLERANCE" \
      '{borderPx:$borderPx, insetPx:$insetPx, expectedRgb:$expectedRgb, rgbTolerance:$rgbTolerance}')

    result=$(jq -n --argjson base "$result" --argjson edgeProbe "$edge_probe" '$base + {edgeProbe:$edgeProbe}')
  fi

  if [ "$clip" = "$TRIM_CLIP" ]; then
    if [ "$TRIM_END_MS" -le "$TRIM_START_MS" ]; then
      fail "trim range for $clip: endMs ($TRIM_END_MS) must be strictly greater than startMs ($TRIM_START_MS)"
    fi
    local inside_ms=$(( duration_ms - TRIM_END_MS ))
    if [ "$inside_ms" -lt "$TRIM_MIN_INSIDE_MS" ]; then
      fail "trim range for $clip: endMs ($TRIM_END_MS) leaves only ${inside_ms}ms inside the clip's measured duration (${duration_ms}ms) - must be at least ${TRIM_MIN_INSIDE_MS}ms"
    fi

    local expected_duration_ms=$(( TRIM_END_MS - TRIM_START_MS ))
    # One frame at the clip's own measured frame rate, rounded UP to the next
    # whole millisecond (ceiling) - matches the fixed 34ms durationToleranceMs
    # convention every other 30fps clip in this corpus already carries above,
    # so this value tracks the fixture if it is ever regenerated at a
    # different frame rate rather than staying a hand-picked literal.
    local tolerance_ms
    tolerance_ms=$(awk -v fps="$frame_rate_fps" 'BEGIN{v=1000/fps; c=int(v); if (v>c) c+=1; print c}')

    local trim_block
    trim_block=$(jq -n \
      --argjson startMs "$TRIM_START_MS" \
      --argjson endMs "$TRIM_END_MS" \
      --argjson expectedDurationMs "$expected_duration_ms" \
      --argjson toleranceMs "$tolerance_ms" \
      '{startMs:$startMs, endMs:$endMs, expectedDurationMs:$expectedDurationMs, toleranceMs:$toleranceMs}')

    result=$(jq -n --argjson base "$result" --argjson trim "$trim_block" '$base + {trim:$trim}')
  fi

  if is_hdr_clip "$clip"; then
    local bit_depth
    bit_depth=$(echo "$json" | jq -r '.streams[] | select(.codec_type=="video") | (.bits_per_raw_sample // "10")')

    local hdr_block
    hdr_block=$(jq -n \
      --arg colorTransfer "$color_transfer" \
      --arg colorPrimaries "$(echo "$json" | jq -r '.streams[] | select(.codec_type=="video") | .color_primaries')" \
      --argjson bitDepth "$bit_depth" \
      '{colorTransfer:$colorTransfer, colorPrimaries:$colorPrimaries, bitDepth:$bitDepth}')

    # Patch geometry/identity only -- ffmpeg cannot author a reference tone-map, so this block
    # deliberately records WHAT the patches are and WHERE they are, plus documented thresholds
    # a later plan's real sampled output is checked against, never an expected RGB triple.
    local patches="[]" i x y channel
    for i in "${!HDR_PATCH_XS[@]}"; do
      x=$(( HDR_PATCH_XS[i] + HDR_PATCH_BOX_W / 2 ))
      y=$(( HDR_PATCH_Y + HDR_PATCH_BOX_H / 2 ))
      channel="${HDR_PATCH_CHANNELS[i]}"
      patches=$(jq -n --argjson base "$patches" --argjson xPx "$x" --argjson yPx "$y" --arg dominantChannel "$channel" \
        '$base + [{xPx:$xPx, yPx:$yPx, dominantChannel:$dominantChannel}]')
    done

    local hdr_probe
    hdr_probe=$(jq -n \
      --argjson patches "$patches" \
      --argjson minSaturation "$HDR_MIN_SATURATION" \
      --argjson minWhiteLuma "$HDR_MIN_WHITE_LUMA" \
      --argjson dominanceMargin "$HDR_DOMINANCE_MARGIN" \
      '{patches:$patches, minSaturation:$minSaturation, minWhiteLuma:$minWhiteLuma, dominanceMargin:$dominanceMargin}')

    result=$(jq -n --argjson base "$result" --argjson hdr "$hdr_block" --argjson hdrProbe "$hdr_probe" '$base + {hdr:$hdr, hdrProbe:$hdrProbe}')
  fi

  if is_audio_probe_clip "$clip"; then
    local raw_audio_codec audio_channels
    raw_audio_codec=$(echo "$json" | jq -r '.streams[] | select(.codec_type=="audio") | .codec_name')
    audio_channels=$(echo "$json" | jq -r '.streams[] | select(.codec_type=="audio") | .channels')

    local audio_block
    audio_block=$(jq -n --arg codec "$raw_audio_codec" --argjson channels "$audio_channels" '{codec:$codec, channels:$channels}')

    result=$(jq -n --argjson base "$result" --argjson audio "$audio_block" '$base + {audio:$audio}')
  fi

  echo "$result"
}

# Assert the deliberately damaged clip still probes as a video file with a
# readable duration, without deriving (or diffing against) any sidecar.
check_damaged_clip() {
  local clip="$1"
  if [ ! -f "$clip" ]; then
    fail "$clip not found - run generate_corpus.sh first"
  fi
  if [ ! -s "$clip" ]; then
    fail "$clip is empty"
  fi
  local has_video duration
  has_video=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=codec_type -of csv=p=0 "$clip" 2>/dev/null || true)
  if [ "$has_video" != "video" ]; then
    fail "$clip does not probe as a video stream (got '${has_video}') - the damaged fixture must still be readable as a video file"
  fi
  duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$clip" 2>/dev/null || true)
  if [ -z "$duration" ]; then
    fail "$clip has no readable duration - the damaged fixture must still report one"
  fi
  echo "CHECK: $clip still probes as video (duration ${duration}s), no sidecar by design"
}

CLIPS=(portrait_rot90.mp4 small_480p.mp4 noaudio_720p.mp4 portrait_hibitrate_1080p60.mp4 trim_source_10s.mp4 hdr_hlg10.mp4 hdr_pq10.mp4 pcm_audio_480p.mov surround51_480p.mp4 uhd_4k60.mp4)
STATUS=0

for clip in "${CLIPS[@]}"; do
  if [ ! -f "$clip" ]; then
    fail "$clip not found - run generate_corpus.sh first"
  fi
  # Strip whatever video extension the clip has (.mp4 or .mov -- pcm_audio_480p.mov is the one
  # fixture that isn't .mp4, see its own comment in generate_corpus.sh) to get the sidecar name.
  clip_stem="${clip%.mp4}"
  clip_stem="${clip_stem%.mov}"
  sidecar_path="${clip_stem}.expected.json"
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

check_damaged_clip "$DAMAGED_CLIP"

exit "$STATUS"
