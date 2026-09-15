#!/usr/bin/env bash
# Generate the corpus: five structurally phone-like (or deliberately damaged) clips.
#
#   portrait_rot90.mp4          - 1920x1080 coded, 90-degree clockwise tkhd
#                                  display matrix (as an iPhone writes portrait
#                                  video), H.264 + AAC stereo, ~4s, burnt-in ms
#                                  timecode plus an 8-bucket colour-patch
#                                  schedule for the thumbnail probe test.
#   small_480p.mp4               - already-small, low-bitrate clip, H.264 +
#                                  AAC, no rotation matrix.
#   noaudio_720p.mp4             - no audio stream at all, no rotation matrix.
#   portrait_hibitrate_1080p60.mp4 - 1920x1080 coded, 60fps, high-entropy
#                                  (mandelbrot) source at ~8Mbps so a preset
#                                  encode can only shrink it by genuinely
#                                  re-encoding; same colour-patch schedule and
#                                  90-degree tkhd matrix as portrait_rot90.mp4,
#                                  plus a 24px pure-white border for the
#                                  no-letterbox edge probe (Phase 2).
#   truncated_mdat.mp4           - a faststart MP4 truncated mid-mdat: the
#                                  moov atom (and therefore duration) survives,
#                                  but decoding the media data fails on a real
#                                  platform codec (Phase 2).
#
# `ffmpeg -metadata:s:v:0 rotate=90` is a verified no-op on the installed
# ffmpeg 6.1.1-3ubuntu5 (see 01-RESEARCH.md Common Pitfalls #1/#2), so the
# portrait clips' display matrices are written directly via patch_rotation.py
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
DEFAULT_MAX_BYTES=1500000

if [ ! -f "$FONT" ]; then
  echo "ERROR: font not found at $FONT (required for the portrait clip's burnt-in timecode)" >&2
  exit 1
fi

fail() {
  local clip="$1" msg="$2"
  echo "ASSERTION FAILED for $clip: $msg" >&2
  exit 1
}

# $2 (max_bytes) is per-clip so a high-bitrate fixture can carry a wider cap
# without raising it for any other clip; it defaults to DEFAULT_MAX_BYTES so
# every pre-existing call site keeps its original 1.5MB cap unchanged.
assert_size() {
  local clip="$1"
  local max_bytes="${2:-$DEFAULT_MAX_BYTES}"
  local size
  size=$(stat -c%s "$clip")
  if [ "$size" -gt "$max_bytes" ]; then
    fail "$clip" "size ${size} bytes exceeds ${max_bytes} byte cap"
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
assert_size "$PORTRAIT" "$DEFAULT_MAX_BYTES"
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
assert_size "$SMALL" "$DEFAULT_MAX_BYTES"
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
assert_size "$NOAUDIO" "$DEFAULT_MAX_BYTES"
echo "OK: $NOAUDIO (0 audio streams, $(stat -c%s "$NOAUDIO") bytes)"

# ---------------------------------------------------------------------------
# Clip D: portrait_hibitrate_1080p60.mp4
# ---------------------------------------------------------------------------
# Every existing corpus clip is far below every preset bitrate Phase 2
# defines (portrait_rot90.mp4 is ~193kbps; p360, the lowest preset, starts at
# 800kbps) - a "preset shrinks the file" test against them can only ever hit
# the never-larger path. This clip uses a high-entropy (mandelbrot) source at
# 60fps and ~8Mbps so genuine re-encoding, the 30fps frame-rate cap, upright
# portrait output and the no-letterbox check are all observable in one
# fixture. Same 8-bucket colour-patch schedule and coded coordinates as
# portrait_rot90.mp4 (the existing thumbnail probe contract applies
# unchanged), plus a 24px pure-white border for the no-letterbox edge probe.
echo "Generating portrait_hibitrate_1080p60.mp4..."

HIBITRATE=portrait_hibitrate_1080p60.mp4
HIBITRATE_TMP=portrait_hibitrate_1080p60.tmp.mp4
HIBITRATE_MAX_BYTES=6000000
HIBITRATE_MIN_BYTES=2000000
BORDER_PX=24

# Same colour-patch geometry/order/timing as portrait_rot90.mp4's DRAWBOXES.
HIBITRATE_DRAWBOXES=""
for k in "${!COLORS[@]}"; do
  start=$(awk -v k="$k" 'BEGIN{printf "%.1f", k*0.5}')
  end=$(awk -v k="$k" 'BEGIN{printf "%.1f", (k+1)*0.5}')
  HIBITRATE_DRAWBOXES="${HIBITRATE_DRAWBOXES},drawbox=x=1600:y=60:w=200:h=200:color=${COLORS[$k]}:t=fill:enable='between(t,${start},${end})'"
done

# A solid pure-white 24px border around the whole coded frame, drawn AFTER
# the colour patch so nothing overwrites it. verify_corpus.sh's edgeProbe
# samples inset points on this border; a letterboxed (black-bar) output
# would fail that sample.
HIBITRATE_BORDER=",drawbox=x=0:y=0:w=1920:h=${BORDER_PX}:color=white:t=fill"
HIBITRATE_BORDER="${HIBITRATE_BORDER},drawbox=x=0:y=$((1080 - BORDER_PX)):w=1920:h=${BORDER_PX}:color=white:t=fill"
HIBITRATE_BORDER="${HIBITRATE_BORDER},drawbox=x=0:y=0:w=${BORDER_PX}:h=1080:color=white:t=fill"
HIBITRATE_BORDER="${HIBITRATE_BORDER},drawbox=x=$((1920 - BORDER_PX)):y=0:w=${BORDER_PX}:h=1080:color=white:t=fill"

ffmpeg -y -loglevel error \
  -f lavfi -i "mandelbrot=size=1920x1080:rate=60" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=4" \
  -filter_complex "[0:v]drawtext=fontfile=${FONT}:text='%{eif\:t*1000\:d}ms':fontcolor=white:fontsize=48:x=10:y=10:box=1:boxcolor=black${HIBITRATE_DRAWBOXES}${HIBITRATE_BORDER}[v]" \
  -map "[v]" -map 1:a \
  -c:v libx264 -pix_fmt yuv420p -preset veryfast -g 60 -b:v 8M -maxrate 8M -bufsize 8M \
  -threads 1 -x264-params threads=1:sliced_threads=0 \
  -c:a aac -b:a 128k -ac 2 -ar 48000 \
  -movflags +faststart \
  -shortest \
  "$HIBITRATE_TMP"

mv "$HIBITRATE_TMP" "$HIBITRATE"
python3 patch_rotation.py "$HIBITRATE" 1080 90

HIBITRATE_JSON=$(probe_json "$HIBITRATE")
HIBITRATE_ROTATION=$(echo "$HIBITRATE_JSON" | jq -r '[.streams[] | select(.codec_type=="video") | .side_data_list[]? | select(.side_data_type=="Display Matrix") | .rotation] | first // empty')
if [ "$HIBITRATE_ROTATION" != "-90" ]; then
  fail "$HIBITRATE" "expected Display Matrix rotation -90, got '${HIBITRATE_ROTATION}'"
fi
HIBITRATE_CODED_W=$(echo "$HIBITRATE_JSON" | jq -r '.streams[] | select(.codec_type=="video") | .width')
HIBITRATE_CODED_H=$(echo "$HIBITRATE_JSON" | jq -r '.streams[] | select(.codec_type=="video") | .height')
if [ "$HIBITRATE_CODED_W" != "1920" ] || [ "$HIBITRATE_CODED_H" != "1080" ]; then
  fail "$HIBITRATE" "expected coded dimensions 1920x1080, got ${HIBITRATE_CODED_W}x${HIBITRATE_CODED_H}"
fi
HIBITRATE_FPS_RAW=$(echo "$HIBITRATE_JSON" | jq -r '.streams[] | select(.codec_type=="video") | .avg_frame_rate')
HIBITRATE_FPS=$(awk -F/ -v r="$HIBITRATE_FPS_RAW" 'BEGIN{split(r,a,"/"); if (a[2]+0==0) print "0"; else printf "%.0f", a[1]/a[2]}')
if [ "$HIBITRATE_FPS" != "60" ]; then
  fail "$HIBITRATE" "expected avg frame rate 60, got ${HIBITRATE_FPS_RAW} (~${HIBITRATE_FPS})"
fi
HIBITRATE_BITRATE=$(echo "$HIBITRATE_JSON" | jq -r '.streams[] | select(.codec_type=="video") | .bit_rate // 0')
if [ "$HIBITRATE_BITRATE" -le 6000000 ]; then
  fail "$HIBITRATE" "expected video bitrate above 6000000, got ${HIBITRATE_BITRATE}"
fi
HIBITRATE_V_COUNT=$(echo "$HIBITRATE_JSON" | jq '[.streams[] | select(.codec_type=="video")] | length')
HIBITRATE_A_COUNT=$(echo "$HIBITRATE_JSON" | jq '[.streams[] | select(.codec_type=="audio")] | length')
if [ "$HIBITRATE_V_COUNT" != "1" ] || [ "$HIBITRATE_A_COUNT" != "1" ]; then
  fail "$HIBITRATE" "expected exactly 1 video + 1 audio stream, got ${HIBITRATE_V_COUNT} video + ${HIBITRATE_A_COUNT} audio"
fi
assert_size "$HIBITRATE" "$HIBITRATE_MAX_BYTES"
HIBITRATE_SIZE=$(stat -c%s "$HIBITRATE")
if [ "$HIBITRATE_SIZE" -le "$HIBITRATE_MIN_BYTES" ]; then
  fail "$HIBITRATE" "size ${HIBITRATE_SIZE} bytes is not above ${HIBITRATE_MIN_BYTES} byte floor"
fi
echo "OK: $HIBITRATE (Display Matrix rotation -90, coded ${HIBITRATE_CODED_W}x${HIBITRATE_CODED_H}, ${HIBITRATE_FPS}fps, bitrate ${HIBITRATE_BITRATE}, ${HIBITRATE_SIZE} bytes)"

# ---------------------------------------------------------------------------
# Clip E: truncated_mdat.mp4
# ---------------------------------------------------------------------------
# Deliberately structurally damaged: faststart writes the moov atom at the
# front of the file, so ffprobe (and path validation) still see a valid
# video stream and duration after truncation, but the media data itself is
# incomplete - a decode of this file reaches the platform codec and fails
# there, giving the error-mapping work a real ExportException to observe
# instead of an assumption from a javadoc. Has no sidecar on purpose (see
# verify_corpus.sh) - it is never fed to a "does the output match ground
# truth" assertion, only to "does decoding it fail the way we expect".
echo "Generating truncated_mdat.mp4..."

TRUNCATED=truncated_mdat.mp4
TRUNCATED_SRC=truncated_mdat.src.mp4

ffmpeg -y -loglevel error \
  -f lavfi -i "testsrc=size=854x480:rate=30:duration=2" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=2" \
  -map 0:v -map 1:a \
  -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 30 \
  -threads 1 -x264-params threads=1:sliced_threads=0 \
  -c:a aac -b:a 64k -ac 2 \
  -movflags +faststart \
  -shortest \
  "$TRUNCATED_SRC"

SRC_SIZE=$(stat -c%s "$TRUNCATED_SRC")
TRUNCATED_SIZE=$(awk -v s="$SRC_SIZE" 'BEGIN{printf "%d", s*0.6}')
head -c "$TRUNCATED_SIZE" "$TRUNCATED_SRC" > "$TRUNCATED"
rm -f "$TRUNCATED_SRC"

TRUNCATED_DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$TRUNCATED" 2>/dev/null || true)
if [ -z "$TRUNCATED_DURATION" ]; then
  fail "$TRUNCATED" "expected ffprobe to still report a duration after truncation, got empty"
fi
TRUNCATED_HAS_VIDEO=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=codec_type -of csv=p=0 "$TRUNCATED" 2>/dev/null || true)
if [ "$TRUNCATED_HAS_VIDEO" != "video" ]; then
  fail "$TRUNCATED" "expected ffprobe to still report a video stream after truncation, got '${TRUNCATED_HAS_VIDEO}'"
fi
echo "OK: $TRUNCATED (truncated to 60% of ${SRC_SIZE} bytes = $(stat -c%s "$TRUNCATED") bytes, duration ${TRUNCATED_DURATION}s still readable)"

echo "All five corpus clips generated and self-verified."
