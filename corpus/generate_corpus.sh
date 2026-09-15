#!/usr/bin/env bash
# Generate the phase-1 corpus: three structurally phone-like clips.
#
#   portrait_rot90.mp4  - 1920x1080 coded, 90-degree clockwise tkhd display
#                          matrix (as an iPhone writes portrait video), H.264
#                          + AAC stereo, ~4s, burnt-in ms timecode plus an
#                          8-bucket colour-patch schedule for the thumbnail
#                          probe test.
#   small_480p.mp4       - already-small, low-bitrate clip, H.264 + AAC, no
#                          rotation matrix.
#   noaudio_720p.mp4     - no audio stream at all, no rotation matrix.
#
# `ffmpeg -metadata:s:v:0 rotate=90` is a verified no-op on the installed
# ffmpeg 6.1.1-3ubuntu5 (see 01-RESEARCH.md Common Pitfalls #1/#2), so the
# portrait clip's display matrix is written directly via patch_rotation.py
# after encoding.
#
# Every assertion below runs unconditionally (no `|| true`, no
# `2>/dev/null` around the assertion itself) and exits non-zero naming the
# clip on failure - a script that "succeeds" here must mean every structural
# property actually holds.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
MAX_BYTES=1500000

if [ ! -f "$FONT" ]; then
  echo "ERROR: font not found at $FONT (required for the portrait clip's burnt-in timecode)" >&2
  exit 1
fi

fail() {
  local clip="$1" msg="$2"
  echo "ASSERTION FAILED for $clip: $msg" >&2
  exit 1
}

assert_size() {
  local clip="$1"
  local size
  size=$(stat -c%s "$clip")
  if [ "$size" -gt "$MAX_BYTES" ]; then
    fail "$clip" "size ${size} bytes exceeds ${MAX_BYTES} byte cap"
  fi
}

probe_json() {
  ffprobe -v quiet -print_format json -show_streams -show_format "$1"
}

# ---------------------------------------------------------------------------
# Clip A: portrait_rot90.mp4
# ---------------------------------------------------------------------------
echo "Generating portrait_rot90.mp4..."

PORTRAIT=portrait_rot90.mp4
PORTRAIT_TMP=portrait_rot90.tmp.mp4

# Eight 500ms colour buckets (K=0..7) covering the 4s duration, painted in
# order so a later bucket overwrites an earlier one at any shared boundary.
# Colours chosen to stay far apart in every RGB channel after JPEG loss.
DRAWBOXES=""
COLORS=(red green blue yellow magenta cyan white black)
for k in "${!COLORS[@]}"; do
  start=$(awk -v k="$k" 'BEGIN{printf "%.1f", k*0.5}')
  end=$(awk -v k="$k" 'BEGIN{printf "%.1f", (k+1)*0.5}')
  DRAWBOXES="${DRAWBOXES},drawbox=x=1600:y=60:w=200:h=200:color=${COLORS[$k]}:t=fill:enable='between(t,${start},${end})'"
done

ffmpeg -y -loglevel error \
  -f lavfi -i "testsrc=size=1920x1080:rate=30:duration=4" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=4" \
  -filter_complex "[0:v]drawtext=fontfile=${FONT}:text='%{eif\:t*1000\:d}ms':fontcolor=white:fontsize=48:x=10:y=10:box=1:boxcolor=black${DRAWBOXES}[v]" \
  -map "[v]" -map 1:a \
  -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 30 -g 30 \
  -threads 1 -x264-params threads=1:sliced_threads=0 \
  -c:a aac -b:a 96k -ac 2 -ar 48000 \
  -movflags +faststart \
  -shortest \
  "$PORTRAIT_TMP"

mv "$PORTRAIT_TMP" "$PORTRAIT"
python3 patch_rotation.py "$PORTRAIT" 1080 90

PORTRAIT_JSON=$(probe_json "$PORTRAIT")
ROTATION=$(echo "$PORTRAIT_JSON" | jq -r '[.streams[] | select(.codec_type=="video") | .side_data_list[]? | select(.side_data_type=="Display Matrix") | .rotation] | first // empty')
if [ "$ROTATION" != "-90" ]; then
  fail "$PORTRAIT" "expected Display Matrix rotation -90, got '${ROTATION}'"
fi
CODED_W=$(echo "$PORTRAIT_JSON" | jq -r '.streams[] | select(.codec_type=="video") | .width')
CODED_H=$(echo "$PORTRAIT_JSON" | jq -r '.streams[] | select(.codec_type=="video") | .height')
if [ "$CODED_W" != "1920" ] || [ "$CODED_H" != "1080" ]; then
  fail "$PORTRAIT" "expected coded dimensions 1920x1080, got ${CODED_W}x${CODED_H}"
fi
assert_size "$PORTRAIT"
echo "OK: $PORTRAIT (Display Matrix rotation -90, coded ${CODED_W}x${CODED_H}, $(stat -c%s "$PORTRAIT") bytes)"

# ---------------------------------------------------------------------------
# Clip B: small_480p.mp4
# ---------------------------------------------------------------------------
echo "Generating small_480p.mp4..."

SMALL=small_480p.mp4
SMALL_TMP=small_480p.tmp.mp4

ffmpeg -y -loglevel error \
  -f lavfi -i "testsrc=size=854x480:rate=30:duration=3" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=3" \
  -map 0:v -map 1:a \
  -c:v libx264 -pix_fmt yuv420p -preset veryfast -b:v 300k -maxrate 350k -bufsize 600k \
  -threads 1 -x264-params threads=1:sliced_threads=0 \
  -c:a aac -b:a 64k -ac 2 \
  -shortest \
  "$SMALL_TMP"

mv "$SMALL_TMP" "$SMALL"

SMALL_JSON=$(probe_json "$SMALL")
V_COUNT=$(echo "$SMALL_JSON" | jq '[.streams[] | select(.codec_type=="video")] | length')
A_COUNT=$(echo "$SMALL_JSON" | jq '[.streams[] | select(.codec_type=="audio")] | length')
if [ "$V_COUNT" != "1" ] || [ "$A_COUNT" != "1" ]; then
  fail "$SMALL" "expected exactly 1 video + 1 audio stream, got ${V_COUNT} video + ${A_COUNT} audio"
fi
SIDE_DATA=$(echo "$SMALL_JSON" | jq '[.streams[] | select(.codec_type=="video") | .side_data_list[]?] | length')
if [ "$SIDE_DATA" != "0" ]; then
  fail "$SMALL" "expected no side data (no display matrix), found ${SIDE_DATA} entries"
fi
AUDIO_CODEC=$(echo "$SMALL_JSON" | jq -r '.streams[] | select(.codec_type=="audio") | .codec_name')
if [ "$AUDIO_CODEC" != "aac" ]; then
  fail "$SMALL" "expected aac audio codec, got ${AUDIO_CODEC}"
fi
assert_size "$SMALL"
echo "OK: $SMALL (1 video + 1 audio, no side data, $(stat -c%s "$SMALL") bytes)"

# ---------------------------------------------------------------------------
# Clip C: noaudio_720p.mp4
# ---------------------------------------------------------------------------
echo "Generating noaudio_720p.mp4..."

NOAUDIO=noaudio_720p.mp4
NOAUDIO_TMP=noaudio_720p.tmp.mp4

ffmpeg -y -loglevel error \
  -f lavfi -i "testsrc=size=1280x720:rate=30:duration=3" \
  -an \
  -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 30 \
  -threads 1 -x264-params threads=1:sliced_threads=0 \
  "$NOAUDIO_TMP"

mv "$NOAUDIO_TMP" "$NOAUDIO"

NOAUDIO_JSON=$(probe_json "$NOAUDIO")
NA_A_COUNT=$(echo "$NOAUDIO_JSON" | jq '[.streams[] | select(.codec_type=="audio")] | length')
if [ "$NA_A_COUNT" != "0" ]; then
  fail "$NOAUDIO" "expected zero audio streams, found ${NA_A_COUNT}"
fi
assert_size "$NOAUDIO"
echo "OK: $NOAUDIO (0 audio streams, $(stat -c%s "$NOAUDIO") bytes)"

echo "All three corpus clips generated and self-verified."
