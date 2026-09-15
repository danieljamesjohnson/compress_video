# Phase 2: Android Compression on Media3 - Research

**Researched:** 2026-09-15
**Domain:** Android video transcoding via androidx.media3 Transformer, inside a Flutter plugin's Pigeon-typed host API
**Confidence:** HIGH for Media3 API surface, artifact contents, and emulator encoder capability (all read live this session from primary sources or the actual device/AARs); MEDIUM for bitrate/estimate tuning constants (must be measured on the corpus, as CONTEXT.md already requires); LOW/flagged where noted (16 KB proof on a release build, exact `ExportResult` timing semantics under transmux).

## Summary

Phase 2 builds the Android engine on **androidx.media3 1.11.1** (bumped from the 1.11.0 the
project's earlier STACK.md pinned — verified live against Google's Maven repo, released
2026-09-11). All required artifacts (`media3-transformer`, `media3-effect`, `media3-common`,
`media3-muxer`) are pulled down and inspected directly from `dl.google.com` this session:
every one of them, plus the transformer's transitive `media3-exoplayer` dependency (confirmed
via its POM — it **is** required, resolving STACK.md's open question), declares `minSdkVersion
23` and contains **zero** `.so` entries. The existing Phase-1 debug APK was independently
zipalign-verified for 16 KB pages with only Flutter's own `libflutter.so` present, which gives
a live baseline the Phase 2 build must not regress.

The Transformer API surface needed for every locked decision in `02-CONTEXT.md` was read
directly from the `androidx/media` `release` branch source (the same branch Google publishes
from) and cross-checked against the current `developer.android.com` guides: `EditedMediaItem`
+ `Composition`/`MediaItem.ClippingConfiguration` for trim, `Presentation.createForHeight`/
`createForWidthAndHeight` for scaling, `FrameDropEffect.createDefaultFrameDropEffect` for the
fps cap, `DefaultEncoderFactory` + `VideoEncoderSettings`/`AudioEncoderSettings` for bitrate
control, `ExportException`'s 22-value `ERROR_CODE_*` set for the error-reason mapping, and
`ExportResult`'s `videoConversionProcess`/`audioConversionProcess` fields for transmux
detection. One load-bearing correction to the project's own prior research: **automatic
transmux is not a global default — it is Transformer's per-track "transcode only if
necessary" behavior for a single-`MediaItem` composition**, and the explicit
`Composition.Builder.setTransmuxAudio/Video` flags this project's compress path will never
call are **ignored** whenever the composition has exactly one `MediaItem` (our case, always).
This matches CONTEXT.md's intent exactly but the mechanism is worth stating precisely so the
plan doesn't wire an irrelevant flag.

Two findings materially affect how Phase 2 must be planned, beyond what CONTEXT.md already
decided:

1. **Transformer's threading contract is a real trap for this codebase's established pattern.**
   Probe.kt and Thumbnails.kt do all their work inside `withContext(Dispatchers.IO)`, a plain
   thread-pool thread with no `Looper`. Media3 `Transformer` throws `IllegalStateException`
   from every one of `start`/`cancel`/`getProgress` if the calling thread's `Looper` isn't the
   one the `Transformer` was built on (verified directly in `Transformer.java`'s
   `verifyApplicationThread()`). CONTEXT.md's decision to build and drive each job's
   `Transformer` on the **main Looper** is correct and required — do not reuse the
   `Dispatchers.IO` idiom for the compression engine itself.
2. **All three Phase-1 corpus clips are far too low-bitrate to exercise the "produces a smaller
   output" success criterion.** They are ffmpeg `testsrc`/flat-color synthetic clips
   deliberately capped at 1.5 MB and encoded at CRF 30 / 300 kbps specifically to stay small in
   git; `portrait_rot90.mp4` is 150,610 bytes at ~193 kbps for 1080×1920, and every preset this
   phase defines (800 kbps and up) is *already bigger* than that. Run against the existing
   corpus alone, every preset would trigger the never-larger path, never the real encode path.
   Phase 2 needs one new, higher-entropy, higher-bitrate corpus clip to prove genuine shrinkage
   (see Common Pitfalls #11 and the Runtime/Corpus note below) — this is a new task the plan
   must include, not an existing-corpus gap to route around.

**Primary recommendation:** Pin `androidx.media3:media3-{transformer,effect,common,muxer}:1.11.1`
(exoplayer resolves transitively, do not declare it explicitly), build one `EditedMediaItem` +
`DefaultEncoderFactory`-configured `Transformer` per job entirely on the main Looper, derive
`transmuxed`/`usedOriginal`/error-reason purely from `ExportResult`/`ExportException` fields
rather than re-deriving them, and add one new realistic-bitrate corpus clip before writing the
"presets shrink the file" integration test.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CORE-02 | Preset or explicit target (max long side, bitrate, target size) | `Presentation.createForHeight/createForWidthAndHeight` (verified source), `VideoEncoderSettings.setBitrate` (verified source); presets/target-size math is CONTEXT.md's own formula, unchanged by this research |
| CORE-03 | Typed result never resolves to null | `ExportResult` fields verified (`fileSizeBytes`, `approximateDurationMs`, `width`/`height`, `videoMimeType`/`audioMimeType`, `videoConversionProcess`/`audioConversionProcess`); `Transformer.Listener.onCompleted`/`onError` verified as the only two terminal callbacks |
| CORE-04 | Typed failures with reason | `ExportException`'s 22 `ERROR_CODE_*` constants read verbatim from source; mapping table below |
| CORE-05 | Never-larger | Live corpus byte sizes measured this session show every existing corpus clip already undercuts every planned preset bitrate — see Summary finding #2 and Pitfall #11 |
| CORE-06 | Transmux fast path | `Composition.setTransmuxAudio/Video` javadoc read verbatim: ignored for a single-`MediaItem` composition, which is always this project's case; `ExportResult.videoConversionProcess`/`audioConversionProcess` verified as the detection mechanism |
| CORE-08 | Frame-rate cap, never upscale | `FrameDropEffect.createDefaultFrameDropEffect(float)` verified to exist in 1.11.1's `androidx.media3.effect` package and to implement `GlEffect`, composable in the same `videoEffects` list as `Presentation` |
| CORE-09 | Output directory/filename, `clearCache()` | `Transformer.start(EditedMediaItem, String path)` verified: output is a plain `String` path, not a `ParcelFileDescriptor`; atomic-write pattern already established by `Thumbnails.kt` (`writeJpegAtomically`) — reuse it |
| ORNT-01 | Upright output, no black bars | `Transformer.Builder.setPortraitEncodingEnabled` javadoc read verbatim: default `false`, rotates to landscape and writes rotation metadata (exactly `Probe.kt`'s existing re-probe path already handles) |
| AUDO-01 | Passthrough when AAC-compatible | Same single-`MediaItem` "transcode only if necessary" mechanism as CORE-06, applied to the audio track |
| AUDO-02 | Forced re-encode bitrate/channels, strip | `AudioEncoderSettings.setBitrate`/`setProfile` verified in source; `EditedMediaItem.Builder.setRemoveAudio` verified; `ChannelMixingMatrix.createForConstantGain`/`createForConstantPower` verified as the channel-count control mechanism (no direct "set channel count" on `AudioEncoderSettings`) |
| JOBS-01 | Per-job progress/completion, no global singleton | `Transformer` instance-per-job already CONTEXT.md's decision; `getProgress(ProgressHolder)` + 4 `PROGRESS_STATE_*` constants verified in source |
| JOBS-02 | Cancel deletes partial output | `Transformer.cancel()` verified synchronous, no terminal listener callback fires after it; atomic-write/delete-partial pattern from `Thumbnails.kt` extends directly |
| INFO-03 | Pre-flight estimate | Pure-Kotlin math over `Probe`'s already-verified fields; no new Media3 API needed (`SizeGuard.kt` never touches Transformer) |
| BULD-01 | Media3 build, minSdk 23, compileSdk 36, no `.so` | Verified live: all 5 required AARs (1.11.1) declare `minSdkVersion 23`, contain zero `.so` files; existing debug APK independently zipalign -P16 verified this session |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Compression job orchestration (start/cancel/progress) | API/Backend (Android platform code) | — | Media3 `Transformer` only runs on-device; no Dart-side state beyond the `CompressJob` wrapper |
| Size-target math (preset/bitrate/target-size resolution, never-larger, transmux decision) | API/Backend (pure Kotlin, `SizeGuard.kt`) | — | Must be callable without a Looper/emulator for both the real compress path and the `estimate()` pre-flight call — kept as pure logic exactly like `MediaMath.kt` |
| Progress delivery to Dart | API/Backend → Client (Flutter) | — | Native polls `getProgress` on the main Looper and forwards via the generated `CompressVideoFlutterApi.onProgress`; Dart only exposes the resulting `Stream<double>` |
| File placement / cache management | API/Backend (Android filesystem) | — | `<cacheDir>/compress_video/` convention and atomic write pattern already established by `Thumbnails.kt`; this phase extends it, does not re-decide it |
| Result typing / error taxonomy | Client (Dart) mapping API/Backend (native) output | — | Native throws `CompressVideoError(reason, message)`; Dart's existing `reasonFromPlatformCode` mapper (`compress_video_exception.dart`) is reused unchanged, only the reason enum grows |
| Job identity / registry | API/Backend (`JobRegistry.kt`, new) | Client (Dart generates the `jobId` string) | Dart generates the id (per CONTEXT.md) so two jobs started back-to-back never race on native-side id generation; native only ever looks up by an id it did not create |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `androidx.media3:media3-transformer` | **1.11.1** `[VERIFIED: dl.google.com/android/maven2/androidx/media3/media3-transformer/maven-metadata.xml, lastUpdated 20260911090254]` | `Transformer`, `EditedMediaItem`, `ExportResult`, `ExportException` | Google's own replacement for the incumbent's abandoned `otaliastudios/Transcoder`; only actively maintained on-device transcode API for Android |
| `androidx.media3:media3-effect` | 1.11.1 (same release train, verified via its own `maven-metadata.xml`) | `Presentation` (resize), `FrameDropEffect` (fps cap) | Ships the `GlEffect`/`MatrixTransformation` video-effect pipeline Transformer composes |
| `androidx.media3:media3-common` | 1.11.1 | `MediaItem.ClippingConfiguration`, `ChannelMixingAudioProcessor`, `ChannelMixingMatrix` | Shared value types and audio-processing primitives used by every media3 module |
| `androidx.media3:media3-muxer` | 1.11.1 | `InAppMp4Muxer` (default MP4 muxer since 1.9.0, per prior STACK.md research, unchanged here) | The muxer Transformer uses when no custom `Muxer.Factory` is set |

**Do not declare `androidx.media3:media3-exoplayer` explicitly.** `[VERIFIED: media3-transformer-1.11.1.pom]` — `media3-transformer` declares it as a `compile`-scope dependency itself (this resolves STACK.md's open "whether media3-exoplayer is a transitive requirement" question: yes, and it is pulled in automatically by Gradle). Declaring it a second time risks a version mismatch if a future bump only touches the transformer artifact.

**Installation** (matches the existing `android/build.gradle.kts` `dependencies {}` block style):
```kotlin
dependencies {
    implementation("androidx.media3:media3-transformer:1.11.1")
    implementation("androidx.media3:media3-effect:1.11.1")
    implementation("androidx.media3:media3-common:1.11.1")
    implementation("androidx.media3:media3-muxer:1.11.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2") // already present
}
```

**Version verification (live, this session):**
```
$ curl -s https://dl.google.com/android/maven2/androidx/media3/media3-transformer/maven-metadata.xml
  <release>1.11.1</release>  <lastUpdated>20260911090254</lastUpdated>
```
`media3-effect`, `media3-common`, `media3-muxer`, `media3-exoplayer` all report the identical
`<release>1.11.1</release>` on the same release train — confirmed with the same command
against each artifact's own `maven-metadata.xml`.

### AAR contents (live inspection, this session)

Downloaded all 5 required/transitive AARs directly from `dl.google.com` and inspected them
with `unzip`:

| Artifact | Size (.aar) | `minSdkVersion` (from `AndroidManifest.xml`) | `.so` files |
|---|---|---|---|
| media3-transformer | 506,251 B | 23 | none |
| media3-effect | 402,882 B | 23 | none |
| media3-common | 644,502 B | 23 | none |
| media3-muxer | 109,910 B | 23 | none |
| media3-exoplayer (transitive) | 1,703,377 B | 23 | none |

`[VERIFIED: dl.google.com/android/maven2/androidx/media3/<artifact>/1.11.1/<artifact>-1.11.1.aar, unzip -l + AndroidManifest.xml inspected this session]`. Total ≈3.2 MB before R8/shrinking across all
five — consistent with, slightly under, prior research's "~4 MB" estimate. **BULD-01's minSdk
23 and no-`.so` requirements are both satisfied by the dependency set itself**, before any app
code is written.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Media3 Transformer | Raw `MediaCodec`/`MediaMuxer` (what `light_compressor_v2` vendors) | ~4,000 extra lines to reimplement colour-format negotiation, GL surfaces, and muxer timestamp rules Transformer already handles — rejected in project STACK.md, unchanged here |
| Media3 Transformer | `otaliastudios/Transcoder` | H.264-only, last release 2024-11-05, open HDR issue — the dependency this project explicitly leaves behind |

## Package Legitimacy Audit

All four new dependencies are first-party `androidx.media3` artifacts published by Google to
`dl.google.com` (the official Android Gradle Plugin/Google Maven repository), the same
publisher/repo as every existing dependency this project already builds against
(`androidx.annotation`, AGP itself). `gsd_run query package-legitimacy check` targets npm/PyPI/
crates ecosystems; androidx/Google Maven artifacts are out of its scope, so this audit is a
manual first-party-publisher check instead, per the protocol's intent (avoid slopsquatting /
hallucinated packages) — there is no npm-style registry-trust ambiguity here because the
group id (`androidx.media3`) and the publishing host (`dl.google.com`) were both read directly
from Google's own release-notes page and confirmed by successfully downloading real AAR
content with real class files at that exact coordinate.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|--------------|---------|-------------|
| androidx.media3:media3-transformer | Google Maven (dl.google.com) | Media3 module since 2023; 1.11.1 released 2026-09-11 | N/A (Android AAR, not npm) | github.com/androidx/media | OK | Approved |
| androidx.media3:media3-effect | Google Maven | same release train | N/A | github.com/androidx/media | OK | Approved |
| androidx.media3:media3-common | Google Maven | same release train | N/A | github.com/androidx/media | OK | Approved |
| androidx.media3:media3-muxer | Google Maven | same release train | N/A | github.com/androidx/media | OK | Approved |
| androidx.media3:media3-exoplayer (transitive) | Google Maven | same release train | N/A | github.com/androidx/media | OK | Approved (transitive, not declared directly) |

**Packages removed due to `[SLOP]` verdict:** none.
**Packages flagged as suspicious `[SUS]`:** none.

## Architecture Patterns

### System Architecture Diagram

```
Dart caller
   |
   | CompressVideo.compress(path, options) -- generates jobId locally (monotonic + random hex)
   v
CompressHostApi.startCompress(jobId, CompressRequestMessage)   [Pigeon @async, arrives on the
   |                                                             platform/main thread]
   v
CompressVideoPlugin (Kotlin) -- registers CompressHostApi, owns JobRegistry
   |
   | 1. Arguments.kt validation (existing pattern) -- reject bad input before any file API
   v
Probe.kt (existing, reused) -- read input format: codec, bitrate, dims, rotation, fps, has-audio
   |
   v
SizeGuard.kt (new, pure Kotlin, no Looper needed) -- resolve preset/target -> effective
   |            (maxLongSidePx, videoBitrateBps, maxFps); decide wouldTransmux / wouldUseOriginal
   |            -- same function backs estimate() so the two paths cannot disagree
   v
   +-- estimate() only: return CompressEstimate here, stop. No Transformer touched.
   |
   v
TransformerEngine.kt (new) -- runs ONLY on the main Looper:
   build EditedMediaItem (ClippingConfiguration, setRemoveAudio, Effects{videoEffects=
     [Presentation.createForWidthAndHeight/Height, FrameDropEffect.createDefaultFrameDropEffect]})
   build Transformer via DefaultEncoderFactory (VideoEncoderSettings.setBitrate,
     AudioEncoderSettings.setBitrate, setEnableFallback)
   transformer.start(editedMediaItem, tempOutputPath)
   |
   | every 250ms: transformer.getProgress(holder) -> CompressVideoFlutterApi.onProgress(jobId, pct)
   |
   v
Transformer.Listener.onCompleted(Composition, ExportResult)  OR  .onError(..., ExportException)
   |                                                                    |
   v                                                                    v
Post-check: outputBytes >= inputBytes?                       ExportException.errorCode
   |-- yes: copy/return original, usedOriginal=true                -> CompressVideoErrorReason
   |-- no: rename temp -> final path                                  (mapping table below)
   v                                                                    |
Re-probe output (Probe.kt, reused) for displayed widthPx/heightPx       v
   |                                                          delete partial output file
   v                                                                    |
CompressResultMessage  <-----------------------------------------------+
   |
   v
Dart: job.result completes; job.progress stream closes
```

### Recommended Project Structure

```
android/src/main/kotlin/com/danjjohnson/compress_video/
├── CompressVideoPlugin.kt   # extend: register CompressHostApi, own JobRegistry, cancel-all on detach
├── JobRegistry.kt           # new: jobId -> {Transformer, outputFile, tempFile} map, main-thread-confined
├── TransformerEngine.kt     # new: builds EditedMediaItem/Transformer from CompressRequestMessage
├── SizeGuard.kt             # new: pure preset/target math, never-larger + transmux pre-decision, backs estimate()
├── Probe.kt                 # existing: reused unchanged for input read + output re-probe
├── Thumbnails.kt            # existing: unaffected except shared cache-dir constant
├── MediaMath.kt             # existing: extend with size/bitrate rounding helpers SizeGuard needs
├── Arguments.kt             # existing: extend with compress-specific validators (trim range, codec=h264 only, etc.)
└── Messages.g.kt            # generated: CompressHostApi, CompressVideoFlutterApi, new message types
```

### Pattern 1: One `Transformer` per job, built and driven entirely on the main Looper

**What:** `TransformerEngine` never calls `withContext(Dispatchers.IO)` around anything that
touches the `Transformer` object itself (build, `start`, `getProgress`, `cancel`). Input
probing (`Probe.kt`) can still happen on `Dispatchers.IO` *before* the `Transformer` is built,
since it doesn't touch Transformer state.

**When to use:** Every compression job, always — this is not optional per-job configuration,
it is a hard Media3 requirement.

**Example:**
```kotlin
// Source: https://raw.githubusercontent.com/androidx/media/release/libraries/transformer/src/main/java/androidx/media3/transformer/Transformer.java
// verified this session: verifyApplicationThread() throws IllegalStateException("Transformer
// is accessed on the wrong thread.") if Looper.myLooper() != the Looper the Transformer was
// built on (default: the Looper of the thread that built the Transformer.Builder, or main).
private fun verifyApplicationThread() {
    if (Looper.myLooper() != looper) {
      throw new IllegalStateException("Transformer is accessed on the wrong thread.")
    }
}
```
The class javadoc states directly: *"Transformer instances must be accessed from a single
application thread. For the vast majority of cases this should be the application's main
thread."* `[VERIFIED: Transformer.java class javadoc, read this session]`

### Pattern 2: Single-`MediaItem` transmux is automatic — do not call `setTransmuxAudio/Video`

**What:** `Composition.Builder.setTransmuxAudio(boolean)` / `setTransmuxVideo(boolean)` only
have an effect when the `Composition` contains **more than one** `MediaItem` (e.g. concatenated
sequences). For a single `MediaItem` — which is every compression job in this plugin — the
javadoc states verbatim: *"If the Composition contains one MediaItem, the value set is
ignored. The [audio/video] track will only be transcoded if necessary."* `[VERIFIED:
Composition.java, setTransmuxAudio/setTransmuxVideo javadoc, read this session]`

**When to use:** Always in this project (never build a multi-item `Composition`). Skip calling
these setters entirely — there is no reachable code path where they matter.

**Example — detecting whether Transformer actually transmuxed, after the fact:**
```kotlin
// Source: ExportResult.java, read this session (CONVERSION_PROCESS_* constants)
val videoWasTransmuxed =
    exportResult.videoConversionProcess == ExportResult.CONVERSION_PROCESS_TRANSMUXED
val audioWasTransmuxed =
    exportResult.audioConversionProcess == ExportResult.CONVERSION_PROCESS_TRANSMUXED ||
    exportResult.audioConversionProcess == ExportResult.CONVERSION_PROCESS_NA // no audio track
val transmuxed = videoWasTransmuxed && audioWasTransmuxed
```

### Pattern 3: Compose `Presentation` and `FrameDropEffect` in one `videoEffects` list

**What:** Both `Presentation` (implements `MatrixTransformation`, a video-frame-geometry effect)
and `FrameDropEffect` (implements `GlEffect`, a video-frame-rate effect) are ordinary members of
`Effects.videoEffects: List<Effect>`, set via `EditedMediaItem.Builder.setEffects(Effects)`.
They compose independently — one changes geometry, the other changes which frames are queued —
so list order between them does not change the output.

**Example:**
```kotlin
// Source: developer.android.com/media/media3/transformer/transformations (resize sample),
// FrameDropEffect.java (read this session) for the fps-cap call
import androidx.media3.effect.Presentation
import androidx.media3.effect.FrameDropEffect
import androidx.media3.common.Effects
import androidx.media3.common.audio.AudioProcessor

val videoEffects = buildList<androidx.media3.common.Effect> {
    if (effectiveLongSidePx < inputDisplayedLongSidePx) {
        add(Presentation.createForWidthAndHeight(
            effectiveWidthPx, effectiveHeightPx, Presentation.LAYOUT_SCALE_TO_FIT))
    }
    if (effectiveFps < inputFps) {
        add(FrameDropEffect.createDefaultFrameDropEffect(effectiveFps))
    }
}
val editedMediaItem = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(inputFile)))
    .setRemoveAudio(audioOptions.isStrip)
    .setEffects(Effects(audioProcessors, videoEffects))
    .build()
```
**Important distinction:** `EditedMediaItem.Builder.setFrameRate(int)` (also present in the
`transformations` guide) is a *different* API — it sets the generated frame rate when
synthesizing video from a still image, not a cap on an existing video's frame rate. Using it
for CORE-08's fps cap would be a no-op on real video input; `FrameDropEffect` is the correct
mechanism. `[VERIFIED: developer.android.com/media/media3/transformer/transformations, "Frame
Rate" section describes setFrameRate only for "generated video (e.g. images converted to
video)"; FrameDropEffect.java's own javadoc says "Drops frames to lower average frame rate"]`

### Pattern 4: Bitrate/profile control via `DefaultEncoderFactory`, never left to defaults

**Example:**
```kotlin
// Source: VideoEncoderSettings.java, AudioEncoderSettings.java, DefaultEncoderFactory.java
// (all read from androidx/media release branch this session)
val videoEncoderSettings = VideoEncoderSettings.Builder()
    .setBitrate(effectiveVideoBitrateBps)
    .setBitrateMode(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR) // default; confirmed
    .build()
val audioEncoderSettings = AudioEncoderSettings.Builder()
    .setBitrate(audioOptions.bitrateBps ?: DEFAULT_AUDIO_BITRATE_BPS)
    .build()
val encoderFactory = DefaultEncoderFactory.Builder(context)
    .setRequestedVideoEncoderSettings(videoEncoderSettings)
    .setRequestedAudioEncoderSettings(audioEncoderSettings)
    .setEnableFallback(true) // default; lets Transformer fall back rather than hard-fail
    .build()
val transformer = Transformer.Builder(context)
    .setVideoMimeType(MimeTypes.VIDEO_H264)
    .setAudioMimeType(MimeTypes.AUDIO_AAC)
    .setEncoderFactory(encoderFactory)
    .addListener(listener)
    .build() // built on the main Looper -> `looper` field defaults to the main Looper
transformer.start(editedMediaItem, tempOutputPath) // path is a plain String
```
Note `DefaultEncoderFactory.Builder(context)` defaults `enableFallback = true` and
`requestedVideoEncoderSettings = VideoEncoderSettings.DEFAULT` (`bitrateMode = BITRATE_MODE_VBR`
by default) — both read directly from source. `[VERIFIED: DefaultEncoderFactory.java lines
78-91, VideoEncoderSettings.java line 91, read this session]`

### Pattern 5: Channel-count control has no direct setter — use `ChannelMixingAudioProcessor`

**What:** `AudioEncoderSettings` (verified source) has exactly two fields: `profile` and
`bitrate`. There is no `setChannelCount`. Channel-count changes (AUDO-02's "chosen ... channel
count") go through `ChannelMixingAudioProcessor.putChannelMixingMatrix(matrix)`, added to
`Effects.audioProcessors`, where `matrix` comes from
`ChannelMixingMatrix.createForConstantGain(inputChannelCount, outputChannelCount)` or
`createForConstantPower(...)`. `[VERIFIED: AudioEncoderSettings.java (fields), 
ChannelMixingAudioProcessor.java, ChannelMixingMatrix.java, all read this session]`

### Anti-Patterns to Avoid

- **Calling `transformer.start()`/`.cancel()`/`.getProgress()` from a coroutine dispatched to
  `Dispatchers.IO` or any other non-Looper thread:** throws `IllegalStateException` at runtime,
  not a compile-time error — will pass code review and fail only on-device.
- **Declaring `androidx.media3:media3-exoplayer` as a direct dependency:** unnecessary (it's
  transitive from `media3-transformer`) and risks a version skew if only one is bumped later.
- **Calling `Composition.Builder.setTransmuxAudio/Video`:** dead code for this project — every
  composition here has exactly one `MediaItem`, where the flag is documented to be ignored.
- **Trusting `ExportResult.durationMs`:** deprecated in favor of `approximateDurationMs` — use
  the latter, and note both are documented as *approximate*; the plugin's `durationMs` result
  field should come from re-probing the actual output file with `Probe.kt`, not from
  `ExportResult`, for the same "never trust an estimate as ground truth" reason CONTEXT.md
  applies to the pre-flight `estimate()` call.
- **Using `EditedMediaItem.Builder.setFrameRate()` for the fps cap:** wrong API, see Pattern 3.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Portrait/rotation handling | Manual frame rotation + custom rotation-metadata writing | `Transformer.Builder.setPortraitEncodingEnabled(false)` (the default) | Verified: Transformer already rotates portrait video to landscape for encoding and writes rotation metadata back — the exact behavior `Probe.kt`'s existing re-probe path (built in Phase 1) already reads correctly |
| Transmux vs re-encode decision at the codec/container level | A parallel "is this file already compatible" prober duplicating Transformer's own internal AssetLoader logic | `ExportResult.videoConversionProcess`/`audioConversionProcess` read after the fact | Transformer already decides "transcode only if necessary" per track for a single-`MediaItem` composition; SizeGuard.kt's pre-flight decision only needs to *predict* this for the never-larger/estimate paths, never *implement* it |
| Bitrate estimation for AAC re-encode | A hand-rolled bits-per-channel-per-sample-rate table | `AudioEncoderSettings.setBitrate`, bounded by the emulator's own verified AAC encoder `bitrate-range = "8000-960000"` | The encoder enforces its own valid range; SizeGuard only needs to clamp into it, not replicate codec internals |
| Channel downmixing | Manual PCM channel-averaging math | `ChannelMixingMatrix.createForConstantGain/createForConstantPower` + `ChannelMixingAudioProcessor` | Verified to exist in `media3-common`; this is Google's own downmix implementation |

**Key insight:** Every "hard part" CONTEXT.md assigns to this phase (orientation, transmux
detection, bitrate control, channel mixing) already has a first-party Media3 API that does
exactly that job — the phase's actual engineering work is *wiring and measuring* (correct
threading, correct result-field mapping, corpus-verified bitrate constants), not inventing new
media logic.

## Common Pitfalls

### Pitfall 1: Building/driving `Transformer` off the main Looper
**What goes wrong:** `IllegalStateException: Transformer is accessed on the wrong thread.`
**Why it happens:** This codebase's established pattern (`Probe.kt`, `Thumbnails.kt`) is
`suspend fun ... = withContext(Dispatchers.IO) { ... }`. Copying that pattern for the
compression engine builds/starts/polls the `Transformer` from a plain thread-pool thread with
no `Looper`.
**How to avoid:** `TransformerEngine`'s job-start code path must run on the main
thread/`Dispatchers.Main` (or no dispatcher switch at all, if the incoming Pigeon call already
arrives on the main thread — confirm this for the generated `CompressHostApi`). Only the
pre-Transformer `Probe` read can use `Dispatchers.IO`.
**Warning signs:** A crash only under real device/emulator load, never in a unit test (JVM unit
tests don't exercise the Looper check the same way — verify with an emulator integration test
per the Validation Architecture section).

### Pitfall 2: Corpus clips too small/low-bitrate to prove compression actually shrinks anything
**What goes wrong:** Every existing corpus clip (`portrait_rot90.mp4` at ~193 kbps,
`small_480p.mp4` at a hardcoded 300 kbps, `noaudio_720p.mp4` at ~76 kbps — all measured live
from their own `.expected.json` sidecars this session) is already smaller than any preset this
phase defines (p360 starts at 800 kbps). An integration test that runs a preset against these
clips and asserts `outputBytes < inputBytes` will either always trigger `usedOriginal: true`
(never-larger) or fail outright — it can never observe genuine encode-and-shrink behavior.
**Why it happens:** The clips are ffmpeg `testsrc`/flat-color synthetic patterns, deliberately
capped at 1.5 MB total and CRF 30-encoded to stay small in git (`generate_corpus.sh`'s own
`MAX_BYTES=1500000` and `-crf 30`/`-b:v 300k` flags, read this session) — they were built for
Phase 1's rotation/unit/null bug classes, not for compression-ratio testing.
**How to avoid:** Add one new corpus clip generated with genuinely high-entropy content (e.g. a
`noise`/`mandelbrot` ffmpeg source, or real camera-like footage) encoded at a bitrate well above
every preset (e.g. 8-10 Mbps at 1080p, matching what a real phone actually shoots) before
writing the "preset produces a smaller output" integration test. This is a new task for this
phase's plan, not a pre-existing gap — flag it explicitly rather than silently reusing
`portrait_rot90.mp4` for a test it structurally cannot pass meaningfully.
**Warning signs:** A "smaller output" integration test that passes by hitting the
never-larger/`usedOriginal` branch instead of the real encode branch — check `ExportResult`/the
result's own `usedOriginal` field in the test assertion, not just `outputBytes < inputBytes`.

### Pitfall 3: Software H.264 encoder's dimension/alignment limits on the CI/dev emulator
**What goes wrong:** An encode targeting an odd width/height, or a size outside the encoder's
`size-range`, fails with `ERROR_CODE_ENCODING_FORMAT_UNSUPPORTED`.
**Why it happens:** The API 35 x86_64 `google_apis` emulator's only H.264 encoder is
`c2.android.avc.encoder` (software, `codec2::software`, no hardware acceleration) — confirmed
live via `adb shell dumpsys media.player` this session. Its capabilities: `alignment = "2x2"`
(width/height must be even), `size-range = "16x16-2048x2048"`, `bitrate-range =
"1-12000000"` (1–12 Mbps — every preset's bitrate fits), `feature-bitrate-modes = "VBR,CBR"`
(no CQ mode), profile/levels capped at `Main/Level 5` (no High profile).
**How to avoid:** `SizeGuard.kt`'s scaling math must round target dimensions to even numbers
(reuse/extend `MediaMath`'s existing rounding helpers) and must not target a long side above
2048 px on this emulator (not a concern for the current presets, which top out at 1920, but
worth a defensive clamp+`encoderUnavailable` if a caller sets `maxLongSidePx` above what the
device's own `MediaCodecInfo.VideoCapabilities` reports — full capability querying is deferred
to Phase 4's 4K60 work per CONTEXT.md, but this phase's SizeGuard should not silently pass a
value the current default encoder cannot honor).
**Warning signs:** Emulator-only encode failures for a resolution that worked fine on the
Phase-1 corpus (which is always even-dimensioned).

### Pitfall 4: Trusting `ExportResult.durationMs`/`approximateDurationMs` as the result's `durationMs`
**What goes wrong:** The result's reported duration silently drifts from the actual output
file's playable duration.
**Why it happens:** `ExportResult.approximateDurationMs`'s own javadoc says "the *approximate*
duration of the file ... to get the actual duration use ... `retrieveDurationUs`" — it is not
guaranteed exact. `durationMs` (the older field) is `@Deprecated` in favor of it.
**How to avoid:** Re-probe the finished output file with the existing `Probe.kt` (as CONTEXT.md
already implies for `widthPx`/`heightPx`) and use that for every field in `CompressResult`,
not `ExportResult`'s own approximations, for consistency with how the plugin already treats
"ground truth" everywhere else.
**Warning signs:** A corpus test whose duration assertion needs a wider tolerance than the
documented "within one frame" to pass would be masking this.

### Pitfall 5: Confusing `EditedMediaItem.Builder.setFrameRate()` with the fps cap
See Pattern 3's "Important distinction" above. **Warning sign:** an fps-cap integration test
that passes when run against a clip whose frame rate already matches `maxFps` and only reveals
the bug on a corpus clip authored at a higher frame rate than any current preset's `maxFps`
default (30 fps) — this project's corpus clips are all 30fps already, so this bug would be
**silent** unless a >30fps test clip is added or an explicit lower `maxFps` is exercised in a
test.

### Pitfall 6: `Composition.setTransmuxAudio`/`setTransmuxVideo` look relevant but are dead code here
See Pattern 2. **Warning sign:** a code reviewer or future contributor "fixing" a perceived gap
by wiring these setters, which will have literally zero effect for every composition this
plugin ever builds (all single-`MediaItem`).

### Pitfall 7: `AudioEncoderSettings` has no channel-count field
See Pattern 5. A plan or implementation that looks for `AudioEncoderSettings.setChannelCount`
(by analogy with `VideoEncoderSettings.setBitrate`) will not find one — channel mixing is a
separate `audioProcessors` effect, not an encoder setting.

### Pitfall 8: `ERROR_CODE_DECODER_INIT_FAILED`/`DECODING_FORMAT_UNSUPPORTED` both plausibly map to two different reasons
**What goes wrong:** CONTEXT.md's error-mapping table asks for `DECODER_INIT_FAILED`/
`DECODING_FORMAT_UNSUPPORTED`/`DECODING_FAILED` to map to `decoderUnavailable` **or**
`unsupportedInput` "per research" — the source doesn't resolve this ambiguity by itself; it's a
product decision.
**Recommendation (documented as an assumption below, not a verified fact):** map
`DECODER_INIT_FAILED` → `decoderUnavailable` (the device genuinely cannot get a decoder
instance — matches the existing enum's own doc comment: "a codec the device's hardware and
software decoders both refuse"), and `DECODING_FORMAT_UNSUPPORTED`/`DECODING_FAILED` →
`unsupportedInput` (the *file* is the problem, not device capability). This mirrors how
`ENCODER_INIT_FAILED` should map to the *new* `encoderUnavailable` reason and
`ENCODING_FORMAT_UNSUPPORTED`/`ENCODING_FAILED` to a data problem — but since there's no
"unsupported output request" reason in the current enum, both encoder-side format failures are
best mapped to `encoderUnavailable` too (there's no better bucket) — see the full mapping table
below for the concrete recommendation.

### Pitfall 9: `MUXING_APPEND` (`ERROR_CODE_MUXING_APPEND = 7003`) is a real, distinct code CONTEXT.md's mapping didn't name
**What goes wrong:** CONTEXT.md's mapping table names `MUXING_FAILED` and `MUXING_TIMEOUT`
implicitly (as "`MUXING_FAILED` → `io`") but the verified source has a third muxing error code,
`ERROR_CODE_MUXING_APPEND = 7003` ("Caused by mismatching formats in MuxerWrapper"), not
mentioned in CONTEXT.md.
**How to avoid:** Map it to `io` alongside `MUXING_FAILED`/`MUXING_TIMEOUT` — it's a muxer-layer
failure, not a decode/encode one — and note this as a deliberate completion of CONTEXT.md's
table, not a deviation from a locked decision (CONTEXT.md left "per research" open for exactly
this kind of gap).

### Pitfall 10: Software HEVC encoder on this emulator is far more limited than H.264
**What goes wrong:** irrelevant to this phase (HEVC is Phase 4's opt-in), but worth recording
now since it was discovered in the same live capability dump: `c2.android.hevc.encoder`'s
`size-range` is only `"2x2-512x512"` — dramatically smaller than the H.264 encoder's
`2048x2048`. A future phase that assumes "software fallback always works at any resolution"
will be wrong on this exact emulator.
**How to avoid:** Not this phase's problem — flagged here only so Phase 4's own research
doesn't have to rediscover it. `[VERIFIED: adb shell dumpsys media.player on emulator-5554
(API 35, x86_64, google_apis), read this session]`

### Pitfall 11: `AudioEncoderSettings` and the AAC encoder's own bitrate range must both clamp `targetSizeMb`'s derived audio bitrate
**What goes wrong:** CONTEXT.md's `targetSizeMb` formula subtracts an audio bitrate before
computing the video bitrate; if the audio side of that formula is allowed to fall outside the
device's actual AAC encoder range, the request either silently gets clamped by the codec (best
case) or fails to initialize (worst case).
**How to avoid:** The emulator's real AAC encoder (`c2.android.aac.encoder`) reports
`bitrate-range = "8000-960000"` and `max-channel-count = "6"` — verified live this session.
`SizeGuard`'s audio-bitrate math should clamp into `[8000, 960000]` before handing a value to
`AudioEncoderSettings.setBitrate`, the same defensive-clamp pattern CONTEXT.md already applies
to the 200 kbps video floor.

## Code Examples

### Building the per-job `Transformer` (composited from verified pieces above)
```kotlin
// Sources, all read this session from androidx/media's `release` branch and
// developer.android.com/media/media3/transformer/{getting-started,transformations}:
val listener = object : Transformer.Listener {
    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
        // exportResult.fileSizeBytes, .width, .height, .videoMimeType, .audioMimeType,
        // .videoConversionProcess, .audioConversionProcess -- all read here, off the
        // Looper thread's callback (same thread Transformer was built on, per the class
        // javadoc: "the listener methods are called on the same thread")
    }
    override fun onError(
        composition: Composition, exportResult: ExportResult, exportException: ExportException,
    ) {
        // exportException.errorCode -- one of the 22 ERROR_CODE_* constants below
    }
}

val transformer = Transformer.Builder(context)
    .setVideoMimeType(MimeTypes.VIDEO_H264)
    .setAudioMimeType(MimeTypes.AUDIO_AAC)
    .setEncoderFactory(encoderFactory) // see Pattern 4
    .addListener(listener)
    .build()

transformer.start(editedMediaItem, tempOutputPath) // String path; verified signature
```

### Full `ExportException.errorCode` -> `CompressVideoErrorReason` mapping

`[VERIFIED: ExportException.java, androidx/media release branch, read + grepped this session —
all 22 values quoted verbatim below]`

```java
public static final int ERROR_CODE_UNSPECIFIED = 1000;
public static final int ERROR_CODE_FAILED_RUNTIME_CHECK = 1001;
public static final int ERROR_CODE_IO_UNSPECIFIED = 2000;
public static final int ERROR_CODE_IO_NETWORK_CONNECTION_FAILED = 2001;
public static final int ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT = 2002;
public static final int ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE = 2003;
public static final int ERROR_CODE_IO_BAD_HTTP_STATUS = 2004;
public static final int ERROR_CODE_IO_FILE_NOT_FOUND = 2005;
public static final int ERROR_CODE_IO_NO_PERMISSION = 2006;
public static final int ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED = 2007;
public static final int ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE = 2008;
public static final int ERROR_CODE_DECODER_INIT_FAILED = 3001;
public static final int ERROR_CODE_DECODING_FAILED = 3002;
public static final int ERROR_CODE_DECODING_FORMAT_UNSUPPORTED = 3003;
public static final int ERROR_CODE_ENCODER_INIT_FAILED = 4001;
public static final int ERROR_CODE_ENCODING_FAILED = 4002;
public static final int ERROR_CODE_ENCODING_FORMAT_UNSUPPORTED = 4003;
public static final int ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED = 5001;
public static final int ERROR_CODE_AUDIO_PROCESSING_FAILED = 6001;
public static final int ERROR_CODE_MUXING_FAILED = 7001;
public static final int ERROR_CODE_MUXING_TIMEOUT = 7002;
public static final int ERROR_CODE_MUXING_APPEND = 7003;
```

Recommended mapping (CONTEXT.md locks the reason enum's values; this table fills the "per
research" gap it left open — see Pitfalls #8/#9 above for the reasoning):

| `ExportException.errorCode` | `CompressVideoErrorReason` |
|---|---|
| `ERROR_CODE_IO_FILE_NOT_FOUND` (2005) | `fileNotFound` |
| `ERROR_CODE_IO_UNSPECIFIED`, `IO_NETWORK_*`, `IO_INVALID_HTTP_CONTENT_TYPE`, `IO_BAD_HTTP_STATUS`, `IO_NO_PERMISSION`, `IO_CLEARTEXT_NOT_PERMITTED`, `IO_READ_POSITION_OUT_OF_RANGE` | `io` (network codes are unreachable for a local-file input but map safely to `io` if ever hit) |
| `ERROR_CODE_DECODER_INIT_FAILED` | `decoderUnavailable` |
| `ERROR_CODE_DECODING_FAILED`, `ERROR_CODE_DECODING_FORMAT_UNSUPPORTED` | `unsupportedInput` |
| `ERROR_CODE_ENCODER_INIT_FAILED`, `ERROR_CODE_ENCODING_FORMAT_UNSUPPORTED` | `encoderUnavailable` |
| `ERROR_CODE_ENCODING_FAILED` | `encoderUnavailable` |
| `ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED`, `ERROR_CODE_AUDIO_PROCESSING_FAILED` | `io` (best available bucket; these are internal pipeline failures, not input/output-shape problems) |
| `ERROR_CODE_MUXING_FAILED`, `ERROR_CODE_MUXING_TIMEOUT`, `ERROR_CODE_MUXING_APPEND` | `io` |
| `ERROR_CODE_UNSPECIFIED`, `ERROR_CODE_FAILED_RUNTIME_CHECK` | `unknown` (preserve `errorCode` as `platformDetail`, exactly as the existing `_wrapPlatformException` pattern already does for unrecognized codes) |

An `ENOSPC`-shaped `IOException` surfacing through `ERROR_CODE_IO_UNSPECIFIED` (or caught by
Transformer's own asset-loader/muxer paths as a generic IO error) should be special-cased to
`outOfSpace` when the underlying cause's message matches `ENOSPC`/"No space left on device",
per CONTEXT.md's decision — this needs a message-string check since Media3 does not have a
dedicated `ERROR_CODE_OUT_OF_SPACE`.

### Progress polling loop
```kotlin
// Source: Transformer.java PROGRESS_STATE_* constants + getProgress(ProgressHolder), read
// this session
val progressHolder = ProgressHolder()
val progressRunnable = object : Runnable {
    override fun run() {
        val state = transformer.getProgress(progressHolder)
        if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
            onProgress(jobId, progressHolder.progress.toDouble())
        }
        if (jobStillActive) {
            mainHandler.postDelayed(this, 250L)
        }
    }
}
mainHandler.post(progressRunnable)
```
`PROGRESS_STATE_NOT_STARTED = 0`, `PROGRESS_STATE_WAITING_FOR_AVAILABILITY = 1`,
`PROGRESS_STATE_AVAILABLE = 2`, `PROGRESS_STATE_UNAVAILABLE = 3` — all four verified in source.
The class javadoc also states: *"After an export completes, this method returns
PROGRESS_STATE_NOT_STARTED"* — so the polling loop must stop itself on `onCompleted`/`onError`,
not rely on `getProgress` continuing to report a final state.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `androidx.media3` 1.11.0 (this project's prior STACK.md pin) | 1.11.1 | 2026-09-11 (verified via Maven metadata `lastUpdated`) | Point release on the same 1.11.x train this project already committed to only bumping within (per CONTEXT.md's BULD-01 decision: "bump only within 1.11.x") — no API changes expected, but pin the newer patch since it was already available at research time |

**Deprecated/outdated:** `ExportResult.durationMs` (deprecated in favor of
`approximateDurationMs`, both still present in 1.11.1) — see Pitfall 4.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `DECODER_INIT_FAILED` -> `decoderUnavailable`; `DECODING_FORMAT_UNSUPPORTED`/`DECODING_FAILED` -> `unsupportedInput`; `ENCODER_INIT_FAILED`/`ENCODING_FORMAT_UNSUPPORTED`/`ENCODING_FAILED` -> `encoderUnavailable` | Code Examples, error mapping table | If wrong, a caller sees a slightly misleading reason (e.g. `unsupportedInput` instead of `decoderUnavailable`) but the call still fails safely with a typed exception — low severity, easy to adjust in a follow-up plan once corpus testing surfaces a real device's actual error codes for a genuinely undecodable file |
| A2 | An `ENOSPC`/"No space left on device" `IOException` message-string match is the right way to surface `outOfSpace`, since Media3 has no dedicated error code for it | Code Examples, error mapping table | If the message string differs across Android versions/emulator vs device, `outOfSpace` might not fire and the failure falls through to generic `io` instead — CONTEXT.md's separate pre-flight `StatFs` check is the primary defense and does not depend on this string match, so this is a secondary/best-effort path only |
| A3 | 8-10 Mbps at 1080p with high-entropy content is a realistic target bitrate for the new "proves genuine shrinkage" corpus clip | Common Pitfalls #2 | If chosen too low, the new clip might still be smaller than some future higher preset; if too high, generation/CI time or corpus size grows unnecessarily — either way, easy to re-tune once the plan's own preset-measurement task (already required by CONTEXT.md) runs |

**If this table is empty:** N/A — see rows above; all other claims in this research were
verified directly against source code, live Maven metadata, downloaded AAR contents, or the
actual emulator this session.

## Open Questions (RESOLVED in planning, 2026-09-15)

> Both questions below are answered by plan tasks: Q1 by 02-02 Task 3 (a `Looper.myLooper() == Looper.getMainLooper()` assertion at the top of `startCompress`, recorded in its SUMMARY) and Q2 by 02-06 Task 3 (compress the truncated `mdat` corpus fixture on the emulator and record the observed `ExportException.errorCode`). The text below is kept as the original statement of each question.


1. **Does the Pigeon-generated `CompressHostApi`'s Kotlin `suspend fun` land on the main thread
   by default, or does Pigeon's codegen dispatch it elsewhere?**
   - What we know: Flutter's `MethodChannel`/`BasicMessageChannel` handlers run on the platform
     (main) thread unless a `TaskQueue` is explicitly configured; Pigeon does not add a
     `TaskQueue` unless the `.dart` contract annotates one (none of Phase 1's contract does).
   - What's unclear: Pigeon's exact generated-code shape for a `suspend fun` HostApi method in
     the specific Pigeon version this project pins — whether it wraps the call in a coroutine
     scope that could hop threads before the plugin's own code runs.
   - Recommendation: the plan's first Wave-0 task should include a one-line assertion
     (`Looper.myLooper() == Looper.getMainLooper()`) at the top of the new
     `CompressHostApi.startCompress` implementation, verified once on the emulator, before
     building on top of it — cheap to check, expensive to discover wrong after the fact.

2. **Exact `ExportException` `errorCode` a real corrupted/truncated corpus clip produces on
   this emulator's software codec stack.**
   - What we know: the full set of 22 possible codes (verified above).
   - What's unclear: which specific code the software AVC decoder reports for, e.g., a
     truncated MP4 vs. an unsupported container vs. a zero-length video track — this determines
     whether Pitfall #8's recommended mapping (A1 above) is actually correct in practice.
   - Recommendation: the plan should include a corpus fixture for at least one deliberately
     broken input (reuse Phase 1's `Arguments.kt`-level validation for the obviously-bad cases
     like zero-byte files, but add one *structurally* corrupt MP4 — e.g. truncated mid-mdat —
     to observe a real `ExportException.errorCode` rather than assuming from the javadoc alone).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Android SDK / emulator | All compression work | Yes | API 35, x86_64, google_apis, `emulator-5554` | none needed |
| `androidx.media3:media3-transformer` + deps | BULD-01 | Yes (resolves from Google Maven; not yet added to `build.gradle.kts`) | 1.11.1 verified this session | none needed |
| Hardware H.264 encoder | Realistic encode-time performance | **No** — emulator only exposes `c2.android.avc.encoder` (software) | — | Software encode is functionally correct but slower than a real device; the Validation Architecture section below sizes integration-test timeouts around software-encoder measured frame rates, not hardware speed |
| GitHub Actions CI (Android job) | BULD-05 (already Phase 1 scope, re-runs here) | Yes, but the account has a billing/spending-limit block (QUESTIONS.md #6) unrelated to this phase | — | Local emulator is this phase's gate per CONTEXT.md; CI wiring must still be written and will go green once Dan clears the billing block — do not loop on CI failures whose cause is billing |
| Physical Android phone (hardware encoder/HDR checks) | Deferred to Phase 4 (CDEC-01/02/03) | No | — | Out of this phase's scope; QUESTIONS.md #3 already tracks it |

**Missing dependencies with no fallback:** none block this phase.
**Missing dependencies with fallback:** hardware encoder (software fallback is correct, just
slower — budgeted into the Validation Architecture timeouts below); CI (local emulator gate).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `flutter test` (Dart unit), Gradle `testDebugUnitTest` w/ JUnit 5 platform (native unit, already configured in `android/build.gradle.kts`), `flutter test integration_test` on a real emulator (e2e) — all three already wired by Phase 1, this phase only adds test files and CI steps to the existing pattern |
| Config file | `android/build.gradle.kts` (`testOptions.unitTests.all { it.useJUnitPlatform() }`, already present) |
| Quick run command | `flutter test` (root Dart unit tests, seconds); `cd example/android && ./gradlew :compress_video:testDebugUnitTest` (native unit tests, seconds) |
| Full suite command | `cd example && flutter test integration_test` on `emulator-5554` (minutes — see per-clip encode time estimate below) |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CORE-02 | Preset produces documented resolution/bitrate | e2e | `flutter test integration_test` (new `compress_test.dart`) | Wave 0 |
| CORE-03 | Typed result, never null | unit + e2e | `flutter test` (mapping test) + integration test | Wave 0 |
| CORE-04 | Typed failures, no swallow | unit + e2e | native JUnit test asserting every `ERROR_CODE_*` maps to a known reason (table-driven, no emulator needed) + integration test for at least one real failure path | Wave 0 |
| CORE-05 | Never-larger | e2e | integration test against `small_480p.mp4` (existing fixture, exactly as CONTEXT.md specifies) | existing fixture usable as-is |
| CORE-06 | Transmux fast path, ratio assertion | e2e | integration test: transmux elapsed < 30% of encode elapsed for the same clip (CONTEXT.md's own acceptance bar) | Wave 0 |
| CORE-08 | Fps cap, never upscale | unit (SizeGuard math) + e2e | JUnit test on `SizeGuard.kt` (pure) + integration test needs a >30fps corpus clip to be non-trivial (see Open Question doesn't block Wave 0, but note it) | Wave 0 (new higher-fps clip optional — CONTEXT.md's presets default to 30fps so a same-or-below-30fps corpus clip only proves the pass-through case) |
| CORE-09 | Output placement, `clearCache()` | e2e | integration test: default path under `<cacheDir>/compress_video/`, explicit `outputPath`, `clearCache()` removes only plugin files | Wave 0 |
| ORNT-01 | Upright, no black bars | e2e | integration test reusing `portrait_rot90.mp4`'s existing pixel-patch sidecar contract (already built in Phase 1) | existing fixture usable as-is |
| AUDO-01 | Passthrough when AAC | e2e | integration test: `ExportResult.audioConversionProcess == CONVERSION_PROCESS_TRANSMUXED` for an AAC-source clip | Wave 0 |
| AUDO-02 | Forced re-encode bitrate/channels, strip | e2e | integration test: `strip` (assert `hasAudio=false` on re-probe), `reencode` (assert `audioReencoded=true` + roughly-matching bitrate) | Wave 0 |
| JOBS-01 | Independent per-job progress | e2e | integration test: two concurrent jobs, both progress streams reach 100 independently (CONTEXT.md's own acceptance bar) | Wave 0 |
| JOBS-02 | Cancel deletes partial | e2e | integration test: start + cancel mid-flight, assert file gone and `progress` stream closed | Wave 0 |
| INFO-03 | Pre-flight estimate within ±15% | unit (SizeGuard) + e2e | JUnit test (pure math, no emulator) + integration test comparing `estimate()` output to the real encode's `ExportResult` | Wave 0 |
| BULD-01 | Media3 build, no `.so`, 16KB-safe | other (build inspection) | `unzip -l` on the built debug/release APK + `zipalign -c -P 16 -v 4` (both already proven to work on the existing Phase-1 APK this session) | Command proven this session; wire into CI as a new step |

### Sampling Rate

- **Per task commit:** `flutter test` (root) + `./gradlew :compress_video:testDebugUnitTest`
  (both seconds-fast, no emulator needed — matches Phase 1's own per-task rhythm)
- **Per wave merge:** `cd example && flutter test integration_test` on `emulator-5554`
- **Phase gate:** Full emulator integration suite green, plus the APK native-lib/zipalign
  check, before `/gsd-verify-work`

### Estimated integration-test wall-clock, from live encoder capability data

The software `c2.android.avc.encoder`'s own `measured-frame-rate-1920x1080-range = "44-49"`
and `measured-frame-rate-1280x720-range = "76-80"` (both read live this session) mean a 4-second
1080p corpus clip encodes in roughly 4s × (30fps / ~46fps) ≈ **2.6s of encode time**, plus
Transformer pipeline overhead (decode, GL passthrough, mux) — budget **10-15 seconds per
compression integration test case** as a realistic per-test timeout, not the sub-second budget
Phase 1's probe/thumbnail tests used. A phase with ~15-20 integration test cases (per the table
above) should budget **3-5 minutes of emulator wall-clock** for the full suite, in line with the
CI job's existing `-partition-size 2048`/disk-space headroom from Phase 1.

### Wave 0 Gaps

- [ ] `example/integration_test/compress_test.dart` — covers CORE-02/03/05/06/08/09, ORNT-01,
      AUDO-01/02, JOBS-01/02
- [ ] `android/src/test/kotlin/.../SizeGuardTest.kt` — pure JUnit coverage for preset/target
      math, never-larger pre-check, transmux pre-decision, estimate math (CORE-02/05/06/08,
      INFO-03)
- [ ] `android/src/test/kotlin/.../ErrorMappingTest.kt` — table-driven test asserting every one
      of the 22 `ExportException.ERROR_CODE_*` values maps to a `CompressVideoErrorReason` (no
      emulator needed; pure function over the errorCode int) — CORE-04
- [ ] New corpus fixture (Common Pitfall #2): a high-bitrate, high-entropy clip to prove genuine
      compression, plus its `.expected.json` sidecar via `corpus/verify_corpus.sh --write`
- [ ] `test/compress_options_test.dart` (Dart) — validation of `CompressOptions` argument
      rejection before crossing the channel, mirroring the existing `thumbnail_api_test.dart`
      pattern

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Local file-to-file plugin, no auth surface |
| V3 Session Management | No | No sessions |
| V4 Access Control | No | Runs inside the host app's own sandbox; no privilege boundary this plugin introduces |
| V5 Input Validation | Yes | `Arguments.kt`'s existing centralized-validation pattern (canonicalize-then-check), extended with compress-specific validators (trim range ordering, `outputPath` parent-writable check — already the same shape as `requireWritableOutputParent`) |
| V6 Cryptography | No | No cryptographic operations in this phase |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Path traversal via `outputPath`/`trimStartMs` manipulation | Tampering | Already mitigated by Phase 1's `Arguments.canonicalFile` pattern — extend, don't fork, for the new compress-specific paths |
| Resource exhaustion (unbounded job count / concurrent Transformers) | Denial of Service | Out of this phase's scope by CONTEXT.md (no queue/concurrency-limit until Phase 5, JOBS-03) — but `onDetachedFromEngine` cancelling every live job (already CONTEXT.md's decision) bounds worst-case resource use when the host app itself goes away |
| Disk-fill via repeated failed compressions leaving partial files | Denial of Service | CONTEXT.md's "every failure path deletes the partial file" decision, extending the atomic-write pattern already proven in `Thumbnails.kt` |

## Sources

### Primary (HIGH confidence)
- `https://dl.google.com/android/maven2/androidx/media3/media3-transformer/maven-metadata.xml` and the same path for `media3-effect`/`media3-common`/`media3-muxer`/`media3-exoplayer` — fetched live this session
- `https://dl.google.com/android/maven2/androidx/media3/media3-transformer/1.11.1/media3-transformer-1.11.1.pom` — fetched and read live this session (dependency graph)
- Downloaded AARs for all 5 artifacts at 1.11.1, inspected with `unzip -l` and `AndroidManifest.xml` extraction this session
- `https://raw.githubusercontent.com/androidx/media/release/libraries/transformer/src/main/java/androidx/media3/transformer/{Transformer,ExportException,ExportResult,Composition,EditedMediaItem,VideoEncoderSettings,AudioEncoderSettings,DefaultEncoderFactory}.java` — fetched and grepped this session
- `https://raw.githubusercontent.com/androidx/media/release/libraries/effect/src/main/java/androidx/media3/effect/{Presentation,FrameDropEffect}.java` — fetched this session
- `https://raw.githubusercontent.com/androidx/media/release/libraries/common/src/main/java/androidx/media3/common/{MediaItem,audio/ChannelMixingAudioProcessor,audio/ChannelMixingMatrix}.java` — fetched this session
- `adb shell dumpsys media.player` on `emulator-5554` (API 35 x86_64 google_apis) — run live this session; H.264/HEVC/AAC encoder capability blocks read directly
- `$HOME/Android/Sdk/build-tools/36.1.0/zipalign -c -P 16 -v 4` against the existing Phase-1 `example/build/app/outputs/flutter-apk/app-debug.apk` — run live this session
- This project's own `.planning/phases/01-typed-contract-ci-and-media-info/{01-04,01-05}-SUMMARY.md`, `pigeons/messages.dart`, `lib/compress_video.dart`, `lib/src/*.dart`, `android/src/main/kotlin/com/danjjohnson/compress_video/*.kt`, `android/build.gradle.kts`, `corpus/README.md`, `corpus/generate_corpus.sh`, `corpus/*.expected.json`, `.github/workflows/ci.yml` — all read this session

### Secondary (MEDIUM confidence)
- `https://developer.android.com/media/media3/transformer/getting-started` and
  `/transformations` — fetched this session for code-sample confirmation, cross-checked
  against the primary source files above (no contradictions found)

### Tertiary (LOW confidence)
- None used without a primary-source cross-check in this document.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every artifact, version, minSdk, and `.so` claim was verified by
  downloading and inspecting the actual AAR this session, not by trusting prior research or
  training data
- Architecture: HIGH — every API call shape (Transformer threading, ClippingConfiguration,
  Presentation, FrameDropEffect, DefaultEncoderFactory, ExportException/ExportResult fields) was
  read from the `androidx/media` `release` branch source directly this session
- Pitfalls: HIGH for the threading and corpus-bitrate findings (both independently discovered
  and verified this session, not carried over from prior research); MEDIUM for the exact
  error-code-to-reason mapping (a reasonable, documented recommendation, not a locked fact —
  see Assumptions Log A1/A2)

**Research date:** 2026-09-15
**Valid until:** 30 days for the Media3 API surface (stable, unlikely to break within a 1.11.x
patch bump per CONTEXT.md's own "bump only within 1.11.x" constraint); re-verify the exact
`1.11.1` pin and AAR contents if planning is delayed past a new media3 minor release.
