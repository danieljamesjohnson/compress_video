# Phase 4: Codecs, HDR and Hard Inputs - Pattern Map

**Mapped:** 2026-09-25
**Files analyzed:** 11 (7 modified, 4 new/near-new)
**Analogs found:** 11 / 11 (all files being modified are their own analog for style/shape; three genuinely new files have close in-repo analogs)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt` (modify) | validation/utility | request-response | itself (existing `validateVideoCodec`/`validateHdrMode`) | exact — same file, extend two functions |
| `darwin/compress_video/Sources/compress_video/Arguments.swift` (modify) | validation/utility | request-response | itself + mirrors `Arguments.kt` | exact |
| `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt` (modify) | service/engine | file-I/O + transform (media encode) | itself — existing `compress`/`finishSuccess`/`buildResultFromDestination` | exact — same file, add HDR/HEVC/audio branches |
| `darwin/compress_video/Sources/compress_video/CompressionEngine.swift` (modify) | service/engine | file-I/O + transform | itself — existing `compress`/`finishJob`/`buildResult` (equivalent) | exact |
| `android/src/main/kotlin/com/danjjohnson/compress_video/CodecCapabilities.kt` (new) | utility/service (capability probe) | request-response (pure query, no I/O) | `android/.../SizeGuard.kt` (pure-JVM, no Android framework import, unit-testable) and `ErrorMapping.kt` (pure mapping object) | role-match — closest shape for a small, injectable, pure-JVM-testable wrapper object |
| `darwin/compress_video/Sources/compress_video/CodecCapabilities.swift` (new) | utility/service (capability probe) | request-response | `darwin/.../ErrorMapping.swift` (pure mapping struct/enum, no I/O) and `SizeGuard.swift` | role-match |
| `lib/src/compress_options.dart` (modify) | model/validation | request-response | itself — existing `CompressOptions.validate()` | exact |
| `corpus/generate_corpus.sh` (modify — add 5 new clip blocks) | build/tooling (fixture generation) | batch/file-I/O | itself — existing per-clip blocks (Clip A `portrait_rot90`, Clip B `small_480p`, etc.) | exact — same file, additional blocks in the same style |
| `corpus/verify_corpus.sh` (modify — add sidecar derivation + CLIPS array entries) | build/tooling | batch | itself — existing `CLIPS` array / per-clip probe blocks | exact |
| `example/integration_test/hard_inputs_test.dart` (new) | test (integration) | request-response + produced-file sampling | `example/integration_test/compress_audio_test.dart` (sidecar-driven, PARITY_JSON accumulator, MP4-box audio probing) + `example/integration_test/compress_test.dart` (produced-file pixel sampling for a tone-map/orientation-style assertion) | role-match — two strong analogs, combine both patterns |
| `tool/run_ios_integration_suites.sh` (modify — add suite to `SUITES` array) | build/tooling (CI orchestration) | batch | itself — existing `SUITES=(...)` array | exact |
| `doc/HARDWARE_CHECKLIST.md` (new) | doc | — | `corpus/README.md` (field-convention/rationale doc style) and phase CONTEXT.md's own prose | role-match — no code analog, doc-style precedent only |
| `.github/workflows/ci.yml` (modify — wire new suite into `apple`/parity steps if suite budget requires split) | config (CI) | batch | itself — existing `apple` job steps (lines ~281-488) and `parity` job (~523+) | exact |

## Pattern Assignments

### `android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt` (validation, request-response)

**Analog:** itself, lines 199-212 (current code to replace)

**Current pattern to extend:**
```kotlin
// Source: android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt:199-212
fun validateVideoCodec(videoCodec: String): String? =
    if (videoCodec != "h264") "unsupportedInput" else null

fun validateHdrMode(hdrMode: String): String? =
    if (hdrMode != "toneMapToSdr") "unsupportedInput" else null
```

**Replacement shape (per RESEARCH.md "Code Examples"):**
```kotlin
fun validateVideoCodec(videoCodec: String): String? =
    if (videoCodec != "h264" && videoCodec != "hevc") "unsupportedInput" else null

fun validateHdrMode(hdrMode: String): String? =
    if (hdrMode != "toneMapToSdr" && hdrMode != "keepHdr") "unsupportedInput" else null
```

**Doc-comment convention to preserve** (lines 181-197, `validateTrimRange`): every validator has a
doc comment stating exactly which inputs return `"unsupportedInput"` and which return `null` —
update the two validators' doc comments to drop the "only accepted value in this phase" framing,
since Phase 4 is what removes that restriction.

**Call-site convention** (lines 246-260, `requireValidCompressRequest`): validators are chained
with `?:` in a fixed order and the function throws a `CompressVideoError` naming the first
violated reason — no change needed here, the two validators are already wired into this chain.

---

### `darwin/compress_video/Sources/compress_video/Arguments.swift` (validation, request-response)

**Analog:** itself, lines 229-236

Mirrors the Kotlin file exactly (RESEARCH.md confirms this): read lines 229-236, apply the
identical two-line relaxation (`videoCodec != "h264" && videoCodec != "hevc"`, `hdrMode !=
"toneMapToSdr" && hdrMode != "keepHdr"`), preserving whatever Swift-native validator return-type
convention (`String?`) the surrounding functions already use.

---

### `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt` (service/engine, file-I/O+transform)

**Analog:** itself — this file already contains every pattern this phase extends.

**Imports pattern** (lines 1-38): flat `androidx.media3.*` imports already include
`Composition`, `EditedMediaItem`, `MimeTypes`, `ChannelMixingAudioProcessor`,
`ChannelMixingMatrix`, `ExportResult`, `ExportException`. New imports needed: `MediaCodecList`/
`EncoderUtil`/`ColorInfo`/`C` (from `androidx.media3.common.C` and
`androidx.media3.transformer.EncoderUtil`) — add alongside the existing block in the same flat,
no-wildcard style.

**Composition-wrapping pattern to introduce** (currently absent — `Transformer.start` is called
directly without a `Composition`, per RESEARCH.md Pattern 1): follow the exact shape RESEARCH.md
cites, verified live via `javap`:
```kotlin
val sequence = EditedMediaItemSequence.Builder(editedMediaItem).build()
val composition = Composition.Builder(sequence)
    .setHdrMode(resolvedHdrMode)
    .build()
transformer.start(composition, tempFile.path)
```

**Audio forced-re-encode trigger — the pattern to extend** (lines 129-146):
```kotlin
// Source: TransformerEngine.kt:129-146 (existing)
val requestedAudioChannels = request.audioChannels?.toInt()
val audioProcessors: List<AudioProcessor> =
    if (request.audioMode == AudioModeMessage.REENCODE &&
        requestedAudioChannels != null &&
        inputAudioChannels != null &&
        requestedAudioChannels != inputAudioChannels
    ) {
        listOf(
            ChannelMixingAudioProcessor().apply {
                putChannelMixingMatrix(
                    ChannelMixingMatrix.createForConstantGain(
                        inputAudioChannels,
                        requestedAudioChannels,
                    ),
                )
            },
        )
    } else {
        emptyList()
    }
```
Per RESEARCH.md Pitfall 1, extend the `if` condition with an `inputAudioChannels != null &&
inputAudioChannels > 2` branch that forces a re-encode to a default target of 2 channels even
under `AudioPassthrough` (no explicit `requestedAudioChannels` in that case) — same
`ChannelMixingAudioProcessor`/`createForConstantGain` call, just a second trigger path feeding it.

**Video mime-type selection — current unconditional pattern to gate** (line ~293):
```kotlin
// Source: TransformerEngine.kt:293 (existing, inside Transformer.Builder chain)
.setVideoMimeType(MimeTypes.VIDEO_H264)
```
Replace with a value computed from the `EncoderUtil.isHardwareAccelerated` probe (RESEARCH.md
Pattern 3), independent of `HdrMode` (Pattern 4) — this is the "closest existing analog is
itself" case: the surrounding `Transformer.Builder` chain (lines ~283-297) is the pattern to
extend, not replace.

**Result-building pattern to extend** (lines 448-471, `buildResultFromDestination`):
```kotlin
// Source: TransformerEngine.kt:465-471 (existing, hardcoded)
return CompressResultMessage(
    ...
    toneMapped = false,
    hevcFallback = false,
    audioReencoded = audioReencoded,
    ...
)
```
Per RESEARCH.md Pattern 5, thread real `toneMapped`/`hevcFallback` values through from
`finishSuccess` the same way `audioReencoded`/`transmuxed`/`usedOriginal` are already threaded
(computed in `finishSuccess` at lines 401-434, passed as parameters into
`buildResultFromDestination`) — add `toneMapped: Boolean` and `hevcFallback: Boolean` parameters
following the exact same threading shape already used for `audioReencoded`.

**Error handling pattern** (existing, unchanged): every `Transformer.Listener.onError` already
routes an `ExportException` through `ErrorMapping.reasonForErrorCode` (see `ErrorMapping.kt`
below) — the OpenGL→MediaCodec fallback retry chain (RESEARCH.md Pattern 2) is new control flow
but funnels into the SAME existing typed-error boundary; no new error-handling shape needed, only
a retry loop around the existing single-attempt shape.

---

### `darwin/compress_video/Sources/compress_video/CompressionEngine.swift` (service/engine, file-I/O+transform)

**Analog:** itself — lines 140-330 (video/audio output-settings construction) and 523-640
(`finishJob`/result-building).

**Audio forced-re-encode trigger — pattern to extend** (line 160-162):
```swift
// Source: CompressionEngine.swift:160-162 (existing)
let sourceIsAAC = inputAudioCodec == "aac"
let includeAudio = inputInfo.hasAudio && audioTrack != nil && request.audioMode != .strip
let audioWillReencode = includeAudio && (request.audioMode == .reencode || !sourceIsAAC)
```
Per RESEARCH.md Pitfall 1, extend the boolean expression with `|| (sourceAudioChannelCount ?? 2) >
2` — same variable, same downstream `audioWillReencode` consumers (lines 256, 271, 424), no
restructuring needed elsewhere in the function.

**Video/audio `canApply` pre-flight guard pattern to reuse for HEVC** (lines 201-230):
```swift
// Source: CompressionEngine.swift:201-230 (existing, H.264 path)
let videoOutputSettings: [String: Any] = [
  AVVideoCodecKey: AVVideoCodecType.h264,
  AVVideoWidthKey: codedTargetWidth,
  AVVideoHeightKey: codedTargetHeight,
  AVVideoCompressionPropertiesKey: [
    AVVideoAverageBitRateKey: plan.videoBitrateBps,
    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
    AVVideoExpectedSourceFrameRateKey: plan.effectiveFps,
  ] as [String: Any],
]
...
guard writer.canApply(outputSettings: videoOutputSettings, forMediaType: .video) else {
  throw CompressVideoError(
    code: "encoderUnavailable",
    message: "This device's H.264 encoder does not support the requested output settings",
    details: nil)
}
```
Reuse this EXACT guard shape for the new HEVC dictionary (RESEARCH.md Pattern 6/7): build a
parallel `hevcOutputSettings` dict with `AVVideoCodecType.hevc` + `AVVideoColorPropertiesKey` +
`kVTProfileLevel_HEVC_Main10_AutoLevel`, gate its use on the new `CodecCapabilities.swift` hardware
probe, and apply the identical `writer.canApply(...)` guard before constructing the
`AVAssetWriterInput`. **CRITICAL pitfall already paid for once in this file** (comment at
line ~196-200): `AVVideoAverageBitRateKey` must stay INSIDE `AVVideoCompressionPropertiesKey`,
never top-level — the same rule applies to any new HEVC compression-properties dictionary.

**Audio AAC output-settings pattern to reuse for the channel-count fix** (lines 271-311): the
existing `aacOutputSettings` dict (channels, sample rate, bitrate floor, `AVChannelLayoutKey`) is
already exactly what a forced 5.1→stereo downmix needs — `targetChannels` just needs to resolve
to `2` for the new forced-re-encode-for-channel-count case exactly as it already does for an
explicit `.reencode` request (line ~296-299), no new dictionary shape.

**Result-building pattern to extend** (lines 613-638, `buildResult`):
```swift
// Source: CompressionEngine.swift:636-638 (existing, hardcoded)
toneMapped: false,
hevcFallback: false,
audioReencoded: audioReencoded,
```
Same threading-not-hardcoding change as the Android side — extend `finishJob`/`buildResult`'s
parameter list the same way `audioReencoded` is already threaded through from `compress`'s local
`audioWillReencode` (line 424) into `finishJob` (line 530) into `buildResult` (line 613).

**Error handling pattern:** `Self.mapToCompressVideoError` (used at lines ~216, 320+) is the
existing single error-mapping funnel — any new HEVC/HDR failure path (a `canApply` rejection, or
a caught `AVAssetWriter`/`AVAssetReader` error) must route through this same function or the
existing `CompressVideoError(code:message:details:)` direct-construction pattern already used for
the H.264 `canApply` guard above — no new error-handling shape.

---

### `android/src/main/kotlin/com/danjjohnson/compress_video/CodecCapabilities.kt` (new — utility/service, request-response)

**Analog:** `android/src/main/kotlin/com/danjjohnson/compress_video/ErrorMapping.kt` (pure `object`,
no Android-framework import beyond what's essential, fully unit-testable) and
`android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt` (pure-JVM, injectable inputs
rather than reading global state directly).

**Imports pattern** (from `ErrorMapping.kt` lines 1-2 — deliberately minimal):
```kotlin
package com.danjjohnson.compress_video
// ErrorMapping.kt takes NO android.* or androidx.media3.* import at all, by design, so it is
// exercisable as plain JVM code with no emulator (see its own doc comment, lines 3-10).
```
`CodecCapabilities.kt` cannot avoid a `androidx.media3.transformer.EncoderUtil` +
`androidx.media3.common.{C, ColorInfo, MimeTypes}` import (RESEARCH.md Pattern 3), but per
CONTEXT.md's "Claude's Discretion" (injectable capability probe), structure the type so its core
decision function takes the encoder list as a parameter (testable with a fake list in a JVM unit
test) rather than calling `EncoderUtil.getSupportedEncoders` internally with no seam — mirror
`ErrorMapping.reasonForErrorCode(errorCode: Int): String`'s "pure function over an injected value"
shape, not `Probe.kt`'s "reads from a real file/MediaExtractor" shape.

**Object/companion structure convention** (from `ErrorMapping.kt` lines 18, 82): a Kotlin
`object` (not a class) with `const val` constants and pure functions — `CodecCapabilities` should
follow the same `object` shape unless the injectable-encoder-list requirement forces a
constructor parameter, in which case mirror `SizeGuard`'s `data class Options` + top-level
`resolve(...)` function shape instead.

**Doc-comment convention:** every public function in this codebase carries a KDoc comment stating
exact return values for exact input conditions (see `ErrorMapping.reasonForErrorCode`'s doc,
lines 74-81, and `Arguments.validateTrimRange`'s doc, lines 181-185) — apply the same standard to
`CodecCapabilities`'s public functions (e.g. "returns `true` only when at least one encoder in
[encoders] is hardware-accelerated for [mimeType]").

---

### `darwin/compress_video/Sources/compress_video/CodecCapabilities.swift` (new — utility/service, request-response)

**Analog:** `darwin/compress_video/Sources/compress_video/ErrorMapping.swift` (pure mapping, no
I/O) — read its top-of-file doc comment and mapping-function shape and mirror it; also
`SizeGuard.swift` for the "pure function over an injected `Options`/input struct, unit-testable
without hardware" shape CONTEXT.md's discretion item calls for. The VideoToolbox call itself
(`VTCopySupportedPropertyDictionaryForEncoder`) should be isolated behind a seam (e.g. a closure
or protocol parameter) so XCTest can inject a fake "has/does not have hardware HEVC" answer,
exactly as CONTEXT.md's discretion item asks — follow whatever seam pattern (if any) `Probe.swift`
or `SizeGuard.swift` already use for testability, rather than inventing a new DI convention.

---

### `lib/src/compress_options.dart` (model/validation)

**Analog:** itself, lines ~289-293 (per RESEARCH.md's own citation).

```dart
// Current pattern (paraphrased per RESEARCH.md's citation of lines 289-293):
if (codec != VideoCodec.h264) reject(...);
if (hdr != HdrMode.toneMapToSdr) reject(...);
```
Relax both checks to accept `VideoCodec.hevc` / `HdrMode.keepHdr` (already-reserved enum values,
per CONTEXT.md's "Reusable Assets" — no enum shape change, only the `validate()` guard body
changes). Follow whatever `reject(...)`/exception-throwing convention `validate()` already uses
for its other fields (same file) — do not introduce a new validation-error shape.

---

### `corpus/generate_corpus.sh` (build/tooling, batch)

**Analog:** itself — the existing per-clip block structure (Clip A `portrait_rot90.mp4` at lines
~85-116, Clip B `small_480p.mp4` at lines ~118-150, etc.), each: `echo "Generating X..."` → define
`X`/`X_TMP` path vars → one `ffmpeg -y -loglevel error ...` invocation → `mv` into place →
`probe_json` + `jq` structural assertions → `assert_size` → final `echo "OK: ..."` line.

**Concrete ffmpeg commands to insert as new blocks** (already proven live this session, per
RESEARCH.md's "Code Examples" section — copy verbatim, adapting variable names to this file's
`CLIP`/`CLIP_TMP` convention):
```bash
# HLG10 block
ffmpeg -y -f lavfi -i testsrc2=size=1280x720:rate=30:duration=2 \
  -pix_fmt yuv420p10le -c:v libx265 -profile:v main10 \
  -color_primaries bt2020 -color_trc arib-std-b67 -colorspace bt2020nc \
  -tag:v hvc1 -t 2 "$HLG10_TMP"

# PQ/HDR10 block (with mastering-display + max-CLL side data)
ffmpeg -y -f lavfi -i testsrc2=size=1280x720:rate=30:duration=2 \
  -pix_fmt yuv420p10le -c:v libx265 -profile:v main10 \
  -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc \
  -x265-params "hdr10=1:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400" \
  -tag:v hvc1 -t 2 "$PQ10_TMP"

# PCM-in-MP4 audio block
ffmpeg -y -f lavfi -i testsrc2=size=640x480:rate=30:duration=2 \
  -f lavfi -i sine=frequency=440:duration=2 \
  -c:v libx264 -c:a pcm_s16le -ac 2 -t 2 "$PCM_TMP"

# 5.1 AAC audio block
ffmpeg -y -f lavfi -i testsrc2=size=640x480:rate=30:duration=2 \
  -f lavfi -i "sine=frequency=440:duration=2" \
  -filter_complex "[1:a]pan=5.1|c0=c0|c1=c0|c2=c0|c3=c0|c4=c0|c5=c0[a51]" \
  -map 0:v -map "[a51]" -c:v libx264 -c:a aac -b:a 384k -t 2 "$SURROUND51_TMP"

# 4K60 block (bitrate-capped per CONTEXT.md's "a few MB" cap)
ffmpeg -y -f lavfi -i testsrc2=size=3840x2160:rate=60:duration=2 \
  -c:v libx264 -b:v 4M -maxrate 4M -bufsize 2M -an -t 2 "$K4_60_TMP"
```

**Assertion pattern to reuse** (from Clip B, lines ~152-163): `probe_json` + `jq` for structural
facts (stream count, codec name, color_transfer/color_primaries for the new HDR clips) +
`assert_size "$CLIP" <max_bytes>` per-clip cap, matching the `$2 (max_bytes) is per-clip`
convention already documented at the top of the script (lines ~50-58) — the 4K60 clip in
particular needs a raised per-clip `max_bytes` argument, following the same pattern
`portrait_hibitrate_1080p60.mp4` already uses for its own higher cap.

**Reserved-name convention for real phone clips (CONTEXT.md decision):** name the synthetic clips
so a same-named real clip can later replace them without any other file (sidecars,
`sync_to_example.sh`, test file references) needing to change — follow whatever placeholder/TODO
comment convention the script already uses (see the `truncated_mdat.mp4` and `trim_source_10s.mp4"
header comments for the existing "why this clip exists" documentation style) to mark the DV
profile-8 slot as pending.

---

### `corpus/verify_corpus.sh` (build/tooling, batch)

**Analog:** itself — the `CLIPS` array (line 309) and per-clip sidecar-derivation blocks
(structure visible around lines 60-280: patch-probe derivation, edge-probe derivation, trim
derivation, then a generic per-clip loop building `crossPlatform` fields via `jq`).

Add the five new clip names to the `CLIPS` array (or a parallel array if HDR/audio-only clips
need different derived fields than the existing `thumbnailProbe`/`edgeProbe`/`trimProbe`
fields) and add whatever new derived-field block the HDR clips need (e.g. `colorTransfer`,
`colorPrimaries` read via `jq` from `ffprobe`'s `color_transfer`/`color_primaries` stream fields)
following the exact `--argjson`/`jq -n` construction pattern already used for `thumbnailProbe` at
lines ~204-206 and `edgeProbe` at lines ~248-250. Field-naming convention: `crossPlatform` for
byte-identical fields, tolerant fields documented separately — per the file's own header comment
(lines 16-19).

---

### `example/integration_test/hard_inputs_test.dart` (new — integration test)

**Analog 1:** `example/integration_test/compress_audio_test.dart` — sidecar-driven assertions,
PARITY_JSON accumulator pattern, and (for the AUDO-03 5.1/PCM cases) MP4-box-level probing since
`CompressResult` doesn't expose channel count.

**PARITY_JSON accumulator pattern to copy** (lines 22-40):
```dart
// Source: example/integration_test/compress_audio_test.dart:22-40
final SplayTreeMap<String, dynamic> _compressionParity =
    SplayTreeMap<String, dynamic>();

void _recordCompressionParity(
  String caseName, {
  String? audioCodec,
  bool? audioReencoded,
  int? channels,
}) {
  final SplayTreeMap<String, dynamic> record = SplayTreeMap<String, dynamic>();
  if (audioCodec != null) record['audioCodec'] = audioCodec;
  if (audioReencoded != null) record['audioReencoded'] = audioReencoded;
  if (channels != null) record['channels'] = channels;
  _compressionParity[caseName] = record;
}
```
`hard_inputs_test.dart` needs its own copy of this pattern (per-file convention, not a shared
helper — RESEARCH.md's "Recommended Project Structure" and the existing files' own header
comments both confirm each suite keeps its own accumulator), extended with `toneMapped: bool?`,
`hevcFallback: bool?`, `videoCodec: String?` fields for the HDR/HEVC cases, printed as one
`PARITY_JSON {...}` line at suite teardown exactly like the existing files do (grepped by CI's
`Extract cross-platform parity records` steps in `.github/workflows/ci.yml`).

**Asset-copy helper to copy verbatim** (lines 44-56, `_copyAssetToTempFile`) — every integration
suite in this codebase has its own copy of this exact function; do the same here rather than
extracting a shared helper (matches the codebase's established no-shared-test-helpers convention).

**Analog 2:** `example/integration_test/compress_test.dart` — produced-file pixel sampling
(`_samplePixelRgb`, lines 98+) is the direct analog for CONTEXT.md's "not washed out" tone-map
assertion: sample the known colour-patch pixel(s) in the produced (tone-mapped) file and assert
the RGB lands within a documented tolerance of the SDR-expected value, the same
`thumbnailProbe`/`edgeProbe` sidecar-driven tolerance-check shape already used for orientation and
letterboxing. Reuse `_samplePixelRgb`'s signature and calling convention (decode via `ui.Image`,
sample by pixel coordinate) rather than shelling out to `ffprobe`/`ffmpeg` from Dart.

**Platform-branching pattern to follow (new to this file, not in either analog):** RESEARCH.md's
Summary establishes that the Android emulator and iOS simulator can only prove the HEVC/keep-HDR
*fallback* path, while the macOS CI host can prove the real success path — structure test cases
with a `Platform.isAndroid`/`Platform.isIOS`/`Platform.isMacOS` (or an equivalent
`defaultTargetPlatform` check, matching whatever convention the existing suites use, if any, for
per-platform-only assertions — grep `compress_jobs_test.dart`/`compress_output_test.dart` for a
precedent before inventing one) branch, asserting `hevcFallback: true` on Android/iOS and
`hevcFallback: false` + `videoCodec: 'hevc'` on macOS for the real-success case.

**Error-path assertion convention:** no established analog needed — HDR/HEVC/audio failures that
DO occur (e.g. Pitfall 4's possible Main10-decode failure on the emulator) should assert a typed
`CompressVideoException` with a specific `reason`, matching the exception-assertion pattern
already used elsewhere in this suite family (grep any existing suite's `expect(() async =>
..., throwsA(...))` shape before writing a new one).

---

### `tool/run_ios_integration_suites.sh` (build/tooling, batch)

**Analog:** itself, lines ~47-54 (`SUITES` array default).

```bash
# Source: tool/run_ios_integration_suites.sh:47-54
SUITES=(
  integration_test/media_info_test.dart
  integration_test/thumbnail_test.dart
  integration_test/compress_test.dart
  integration_test/compress_audio_test.dart
  integration_test/compress_jobs_test.dart
  integration_test/compress_output_test.dart
)
```
Add `integration_test/hard_inputs_test.dart` to this array. Per CONTEXT.md's 90-minute budget
decision, if the addition pushes the Apple job over budget, split into two `SUITES` invocations
(two `tool/run_ios_integration_suites.sh <udid> <subset>` calls in `.github/workflows/ci.yml`)
rather than editing the watchdog's own timeout constants — the script already accepts an explicit
suite list as `$@` (line 44-46: `if [ "$#" -gt 0 ]; then SUITES=("$@")`), so this split needs no
script change, only a `ci.yml` change (see below).

---

### `.github/workflows/ci.yml` (config, batch)

**Analog:** itself — the existing `apple` job's per-suite step(s) that call
`tool/run_ios_integration_suites.sh`, and the existing `Extract cross-platform parity records`
steps (lines 217-226 Android, 408-417 Apple, 479-488 macOS) that `grep '^PARITY_JSON '` out of the
suite log.

No new step SHAPE is needed unless the 90-minute budget is exceeded (CONTEXT.md decision): if so,
duplicate the existing single "run Apple integration suites" step into two steps, each passing a
disjoint suite subset as extra arguments to `tool/run_ios_integration_suites.sh`, matching how the
script already supports `$@` overriding `SUITES`. The three `Extract cross-platform parity
records` steps (identical `grep` pattern across Android/Apple/macOS, differing only in the log
path) are the analog for making sure `hard_inputs_test.dart`'s new PARITY_JSON lines get captured
— no change needed there since they already grep the whole log file, not a suite allowlist.

---

### `doc/HARDWARE_CHECKLIST.md` (new — doc)

**No direct code analog** (confirmed absent, per RESEARCH.md). Closest structural precedent:
`corpus/README.md`'s field-convention/rationale documentation style (prose sections, each naming
the exact command and expected result) — follow that "exact command, exact expected result"
convention rather than a vague checklist. Content list per CONTEXT.md: HEVC hardware encode,
keep-HDR output, HDR tone-map fidelity by eye, `targetSizeMb`/estimate tolerances on a hardware
encoder (QUESTIONS.md #3) — each item needs a runnable command (mirroring how `corpus/README.md`
or `04-RESEARCH.md`'s own ffmpeg commands are written: copy-pasteable, with the tool/flags
spelled out) and a "Deferred until [x] is available" note per CONTEXT.md's own wording, matching
how `03-CONTEXT.md`'s Mac-only deferrals were phrased (see this project's git log entries
`470632b`/`4c06ac2` for that phrasing precedent).

## Shared Patterns

### Typed-error funnel (both platforms)
**Source:** `android/src/main/kotlin/com/danjjohnson/compress_video/ErrorMapping.kt` (all 22
`ExportException.errorCode` values pre-mapped) and
`darwin/compress_video/Sources/compress_video/ErrorMapping.swift` (equivalent `AVError`/`NSError`
mapping) plus `CompressionEngine.swift`'s `Self.mapToCompressVideoError`.
**Apply to:** `TransformerEngine.kt`'s new OpenGL→MediaCodec retry chain, `CompressionEngine.swift`'s
new HEVC `canApply` guard — every new failure path must throw/complete through the SAME existing
typed-error surface, adding no new `CompressVideoErrorReason` values (RESEARCH.md confirms all
plausible new codes already map to an existing bucket: `unsupportedInput`, `encoderUnavailable`,
`decoderUnavailable`, `io`).
```kotlin
// ErrorMapping.kt:82-109 -- the exhaustive `when` that already covers every new HDR/HEVC failure
fun reasonForErrorCode(errorCode: Int): String = when (errorCode) {
    ERROR_CODE_DECODING_FAILED, ERROR_CODE_DECODING_FORMAT_UNSUPPORTED -> "unsupportedInput"
    ERROR_CODE_ENCODER_INIT_FAILED, ERROR_CODE_ENCODING_FORMAT_UNSUPPORTED,
      ERROR_CODE_ENCODING_FAILED -> "encoderUnavailable"
    else -> "unknown"
}
```

### Never-larger post-check (unconditional, both platforms)
**Source:** `TransformerEngine.kt:401-402` (`val usedOriginal = tempBytes >= inputBytes`,
unconditional) and `CompressionEngine.swift`'s equivalent in `finishJob`.
**Apply to:** every new HEVC/keep-HDR/HDR-tone-map encode path — CONTEXT.md and 03-CONTEXT.md both
already establish this is never bypassed; Phase 4 adds no exception to it.

### Result-field threading, not hardcoding (both platforms)
**Source:** the existing `audioReencoded`/`transmuxed`/`usedOriginal` threading from the compress
function's local decision variables through `finishSuccess`/`finishJob` into
`buildResultFromDestination`/`buildResult` (`TransformerEngine.kt:401-471`,
`CompressionEngine.swift:step through 424→530→613-638`).
**Apply to:** the new `toneMapped`/`hevcFallback` fields, currently hardcoded `false` on both
platforms — replace with values computed the same way `audioReencoded` already is (from the
actual branch/outcome that ran, never from what the request asked for).

### Corpus generate → verify → sync pipeline (build tooling)
**Source:** `corpus/generate_corpus.sh` + `corpus/verify_corpus.sh --write` +
`corpus/sync_to_example.sh` + CI's drift-gate step (referenced in RESEARCH.md, not re-read this
session but confirmed to exist per CONTEXT.md).
**Apply to:** all 5 new corpus clips — never hand-commit a clip or sidecar; the plan's tasks must
run this exact three-script pipeline for every new fixture, matching how the existing 6 clips were
produced.

### Injectable capability probe (new pattern for this phase, precedent = `SizeGuard`'s pure-function shape)
**Source:** `SizeGuard.kt`/`SizeGuard.swift` — pure functions/objects over an explicit `Options`
input, no direct hardware/OS call inside the function under test.
**Apply to:** `CodecCapabilities.kt`/`CodecCapabilities.swift` — per CONTEXT.md's own "Claude's
Discretion" item, structure the hardware-HEVC-encoder decision as a pure function over an injected
encoder list (Android) or an injected capability-lookup closure (Apple), so JVM/XCTest unit tests
can supply a fake "no hardware HEVC" or "has hardware HEVC" answer without an emulator/simulator.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `doc/HARDWARE_CHECKLIST.md` | doc | — | No prior "hardware checklist" doc exists in this repo; use `corpus/README.md`'s prose/rationale style and CONTEXT.md's own "Deferred Item" phrasing as the closest available precedent, not a code pattern |

## Metadata

**Analog search scope:** `android/src/main/kotlin/com/danjjohnson/compress_video/`,
`darwin/compress_video/Sources/compress_video/`, `lib/src/`, `corpus/`,
`example/integration_test/`, `tool/`, `.github/workflows/`
**Files scanned:** ~25 (all files named in the phase-mapper's "likely analogs" list, plus
`compress_test.dart`/`compress_jobs_test.dart` for the pixel-sampling and platform-branching
precedents)
**Pattern extraction date:** 2026-09-25
