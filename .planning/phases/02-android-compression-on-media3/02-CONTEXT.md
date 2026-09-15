# Phase 2: Android Compression on Media3 - Context

**Gathered:** 2026-09-15
**Status:** Ready for planning
**Mode:** Smart discuss, autonomous run — recommended answers auto-accepted (unattended). Every decision below is a default Dan can override.

<domain>
## Phase Boundary

On Android, one call turns a local video into a smaller, upright H.264/AAC MP4 with a typed
result, through the Pigeon contract Phase 1 established. This phase delivers presets and explicit
targets, never-larger, transmux fast path, frame-rate cap, output placement and `clearCache()`,
upright portrait output, audio passthrough / re-encode / strip, per-job progress and cancel, the
pre-flight estimate, and the Media3 build proof (minSdk 23, compileSdk 36, no `.so`).

Requirements in scope: CORE-02, CORE-03, CORE-04, CORE-05, CORE-06, CORE-08, CORE-09, ORNT-01,
AUDO-01, AUDO-02, JOBS-01, JOBS-02, INFO-03, BULD-01.

Out of scope here: the Apple engine (Phase 3), HEVC/HDR/tone-mapping/5.1 (Phase 4), queueing,
isolates and foreground service (Phase 5), compat shim and pub.dev (Phase 6). The Dart contract
must still reserve the fields those phases need (`toneMapped`, `hevcFallback`, codec choice) so
the wire format does not churn.

Environment at discuss time (2026-09-15):
- Phase 1 delivered: `CompressVideo` (const ctor, optional `BinaryMessenger`), `getMediaInfo`,
  `getThumbnail`, `getThumbnailFile`; `CompressVideoException` + `CompressVideoErrorReason`
  (`fileNotFound, unsupportedInput, decoderUnavailable, io, cancelled, unknown`);
  `pigeons/messages.dart` with `ProbeHostApi`, `ThumbnailHostApi`, `MediaInfoMessage`; Kotlin
  `Probe.kt`, `Thumbnails.kt`, `MediaMath.kt`, `Arguments.kt`, `CompressVideoPlugin.kt`;
  corpus clips `portrait_rot90.mp4` (1920x1080 coded, 90° matrix, AAC), `small_480p.mp4`,
  `noaudio_720p.mp4` with ffprobe sidecars; emulator `compress_video_api35` (API 35 x86_64);
  CI on GitHub Actions (Linux + path-gated macOS).
- **CI is currently blocked by a GitHub Actions billing/spending limit (QUESTIONS.md #6).**
  Phase 2's gate is the local emulator; CI wiring must still be written and must go green once
  Dan clears the block. Executors must not loop on CI failures whose cause is billing.
- Phase 1 is parked as `needs_human` at 01-06/01-07 (Apple CI confirmation, parity gate). Phase 2
  must not edit `darwin/` beyond regenerating `Messages.g.swift` when the contract changes.

</domain>

<decisions>
## Implementation Decisions

### Compression API and job model
- `CompressJob compress(String path, {CompressOptions options = const CompressOptions()})` on
  `CompressVideo` returns a job object immediately (no `Future` to get the job). `CompressJob`
  exposes `String id`, `Stream<double> progress` (0-100, broadcast, completes when the job ends),
  `Future<CompressResult> result`, `Future<void> cancel()`, `bool get isCancelled`. There is no
  global progress stream and no "is compressing" singleton; two jobs started together are fully
  independent.
- `CompressOptions` is an immutable class with `const` constructor: `preset` (`CompressPreset`
  enum, resolution-named: `p360`, `p480`, `p720` (default), `p1080`), explicit targets
  `maxLongSidePx`, `videoBitrateBps`, `targetSizeMb` (double) which override the preset when
  set, `maxFps` (default 30), `audio` (`AudioOptions`), `trimStartMs` / `trimEndMs` (nullable),
  `outputPath` (nullable), `codec` reserved as `VideoCodec.h264` default (HEVC opt-in is Phase 4;
  the field exists, only h264 is accepted here), `hdr` reserved (`HdrMode.toneMapToSdr` default,
  Phase 4 implements). Invalid combinations throw `unsupportedInput` before crossing the channel,
  exactly like Phase 1's thumbnail validators.
- `CompressResult` (immutable, dartdoc on every field): `outputPath`, `inputBytes`, `outputBytes`,
  `widthPx`, `heightPx` (displayed), `durationMs`, `videoCodec`, `audioCodec` (nullable when
  stripped), `transmuxed`, `usedOriginal`, `toneMapped` (always false this phase), `hevcFallback`
  (always false this phase), `audioReencoded`, `elapsedMs`. The call never resolves to `null`.
- Cancel semantics: `cancel()` completes `result` with `CompressVideoException(reason:
  cancelled)`, the `progress` stream closes, and the partial output file is deleted before the
  future completes. Cancelling an already-finished job is a no-op. This keeps Phase 1's
  "errors are typed exceptions" rule; there is no second result-union type.
- Contract additions in `pigeons/messages.dart`: `CompressRequestMessage`,
  `CompressResultMessage`, `EstimateMessage`; `CompressHostApi` with `@async startCompress(String
  jobId, CompressRequestMessage)`, `@async cancel(String jobId)`, `@async estimate(String path,
  CompressRequestMessage)`, `@async clearCache()`; `@FlutterApi CompressVideoFlutterApi` with
  `onProgress(String jobId, double percent)`. Job ids are generated in Dart from a monotonic
  counter plus random hex (no new dependency). All three generated outputs (Dart, Kotlin, Swift)
  are regenerated together and the Swift output must still compile in CI once CI is available.
- `CompressVideoErrorReason` gains `encoderUnavailable`, `outOfSpace`, `interrupted` (documented;
  `interrupted` is thrown only by iOS in Phase 5, but the enum value exists now).

### Size targeting, transmux and never-larger
- Presets live in one Dart file (`lib/src/presets.dart`) as `(maxLongSidePx, videoBitrateBps at
  30 fps)` constants: seed with p360 = 640 / 800 kbps, p480 = 854 / 1.2 Mbps, p720 = 1280 / 2.5
  Mbps, p1080 = 1920 / 5 Mbps, then MEASURE output sizes on the corpus in this phase and adjust;
  record the measured MB/minute per preset in `doc/PRESETS.md` (generated from the constants,
  used by the README in Phase 6). Never upscale: the effective long side is
  `min(maxLongSidePx, input displayed long side)` and the effective fps is `min(maxFps, input)`.
- `targetSizeMb` → video bitrate = `(targetBytes * 8 / durationSeconds) - audioBitrateBps -
  3% mux overhead`, floored at 200 kbps. Documented tolerance for the real output vs the target
  is ±15%; the corpus integration test asserts it.
- Transmux (CORE-06): when the input video is H.264 and audio is AAC (or absent), displayed long
  side ≤ target, fps ≤ cap, and video bitrate ≤ 1.15 × target bitrate, the job runs Transformer
  with no video effects and matching MIME types so Media3 transmuxes; `transmuxed: true` and the
  result's `elapsedMs` must be a fraction of an encode.
- Never-larger (CORE-05): (a) pre-check — if the estimate predicts output ≥ input bytes the job
  skips the encode entirely; (b) post-check — after any encode, if output bytes ≥ input bytes the
  plugin copies the original to the output path (or returns the original path when no
  `outputPath` was given and the cache copy is unnecessary — decide in planning, document it) and
  reports `usedOriginal: true`. The `small_480p.mp4` corpus clip is the test for this.
- Frame-rate cap (CORE-08): Media3 `FrameDropEffect` at the effective fps; research must confirm
  the exact API in media3 1.11 and its interaction with `Presentation` scaling.

### Orientation, audio and output files
- Orientation (ORNT-01): use Transformer's default handling (encode in the coded orientation and
  carry rotation metadata, as phones do) and re-probe the output with `Probe.kt` so the result's
  `widthPx`/`heightPx` are displayed dims. The corpus test asserts the portrait clip's output is
  1080x1920 displayed, that a thumbnail of the output at 1500 ms is upright by the Phase 1
  pixel-patch method, and that the frame has no letterboxing (a probe of edge pixels against the
  clip's known colour bands). If Transformer bakes rotation into pixels instead, that is equally
  acceptable as long as those assertions hold.
- Audio: `AudioOptions` sealed/enum-like with `passthrough` (default), `reencode(bitrateBps,
  channels)`, `strip`. Passthrough applies only when the source audio is MP4-compatible AAC;
  otherwise the engine re-encodes to AAC and reports `audioReencoded: true` (5.1/PCM handling
  is Phase 4, but the default path must not crash on them — it may throw `unsupportedInput`).
  Strip uses Media3 `setRemoveAudio(true)`; re-encode uses `setAudioMimeType(AUDIO_AAC)` and the
  media3 audio encoder settings / channel mixing that research confirms.
- Output (CORE-09): every file the plugin writes lives under `<cacheDir>/compress_video/`;
  default compression output is `<jobId>.mp4` there; `outputPath` writes exactly there (parent
  must exist, else `io`). `clearCache()` deletes only the contents of that directory. Phase 1's
  thumbnail default location moves into the same subdirectory in this phase (small, documented
  change; update the Phase 1 tests accordingly). Cancelled and failed jobs delete their partial
  output before completing.
- Trim: `trimStartMs`/`trimEndMs` are in the contract now and Android implements them with
  Media3 `ClippingConfiguration`; a basic corpus assertion (duration within one frame) runs here,
  and the strict cross-platform CORE-07 parity assertion remains Phase 3's.

### Jobs, errors, estimate and build
- Threading: create each job's `Transformer` on the main Looper (Media3 requires a Looper thread
  for its API calls; the work happens on its own threads). A `JobRegistry` maps job id →
  Transformer + output file. Progress is polled with `getProgress` every 250 ms on the main
  handler and forwarded through `CompressVideoFlutterApi.onProgress`; the final 100 is sent
  before the result reply. `onDetachedFromEngine` cancels every live job and deletes partials.
- Error mapping (CORE-04): Media3 `ExportException.errorCode` → reason (`IO_FILE_NOT_FOUND` →
  `fileNotFound`; other `IO_*` → `io`; `DECODER_INIT_FAILED`/`DECODING_FORMAT_UNSUPPORTED`/
  `DECODING_FAILED` → `decoderUnavailable` or `unsupportedInput` per research;
  `ENCODER_INIT_FAILED`/`ENCODING_FORMAT_UNSUPPORTED`/`ENCODING_FAILED` → `encoderUnavailable`;
  `MUXING_FAILED` → `io`); a pre-flight free-space check (`StatFs` on the output dir vs the
  estimate × 1.2) throws `outOfSpace` before encoding, and an `ENOSPC` during encode maps to
  `outOfSpace`. No failure path logs-and-swallows; every failure path deletes the partial file.
- Estimate (INFO-03): a pure Kotlin function (`SizeGuard.kt`) over Probe output + options that
  returns predicted `outputBytes`, `durationMs`, `widthPx`/`heightPx`, `wouldTransmux`,
  `wouldUseOriginal`, without decoding a frame; exposed as `Future<CompressEstimate>
  estimate(path, {options})` in Dart. The same function drives the transmux and never-larger
  pre-checks so estimate and behaviour cannot disagree. Tolerance ±15% vs the real encode,
  asserted on the corpus.
- Build (BULD-01): `androidx.media3:media3-transformer`, `media3-effect`, `media3-common`,
  `media3-muxer` at 1.11.0 (verify latest stable during research; bump only within 1.11.x);
  minSdk stays 23, compileSdk 36, AGP 9 built-in Kotlin as Phase 1 set up. CI (and a local
  script) unzips the example debug APK and asserts the only `lib/**/*.so` entries are Flutter's
  own (`libflutter.so`, `libapp.so`, and any `libdartjni`/`libVkLayer` Flutter ships), and runs
  `zipalign -c -P 16 -v 4` for 16 KB alignment.

### Claude's Discretion
- Exact class/file names under `lib/src/` and `android/.../`, the `AudioOptions` encoding
  (sealed class vs enum + fields), the job-id format, the poll interval if 250 ms proves noisy,
  and whether the never-larger post-check copies the original or returns its path when no
  `outputPath` was supplied (document whichever is chosen in the dartdoc).
- Whether to add a minimal "compress" screen to the example app now for manual checks (the
  full example app is Phase 3's BULD-04); integration tests are the required verification.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/compress_video.dart`: `CompressVideo` entry point with `_validateThumbnailArgs`,
  `_wrapPlatformException`, `_wrapMissingPlugin` — extend, do not fork, for compress/estimate.
- `lib/src/compress_video_exception.dart`: reason enum and exception; add the three new reasons.
- `lib/src/media_info.dart`: the immutable-model-with-dartdoc pattern to copy for
  `CompressOptions`, `CompressResult`, `CompressEstimate`.
- `pigeons/messages.dart` + generation script/CI drift check from 01-04: add the new messages
  and APIs there; regenerate all three outputs together.
- Android: `Probe.kt` (re-probe outputs), `MediaMath.kt` (scaled sizes, clamps), `Arguments.kt`
  (validators, error throwing pattern), `CompressVideoPlugin.kt` (host API registration on
  the main thread), `Thumbnails.kt` (atomic write + cache placement pattern).
- Corpus: `corpus/*.expected.json` sidecars and the pixel-patch thumbnail contract; the
  `small_480p.mp4` clip is the never-larger fixture, `noaudio_720p.mp4` the no-audio fixture.
- Tests: `example/integration_test/{media_info,thumbnail}_test.dart` patterns, Gradle unit tests
  under `android/src/test`, `test/*_test.dart` argument-validation tests.

### Established Patterns
- Units in field names (`Ms`, `Px`, `Bps`, `Bytes`, `Fps`); nullable = unknown, never 0.
- Native throws `FlutterError(code = reason name)`; Dart maps to `CompressVideoException`.
- All host methods `@async`; native work off the platform thread; replies on the platform thread.
- STATE.md/ROADMAP.md hand-edited (never `gsd-tools` STATE writers); commits per task.

### Integration Points
- `CompressVideoPlugin.kt` registers the new `CompressHostApi` and holds the `JobRegistry`.
- `.github/workflows/ci.yml` gains the APK native-lib/zipalign assertion and the new
  integration tests; CI itself is blocked on QUESTIONS.md #6 until Dan acts.
- `doc/PRESETS.md` (new) feeds the Phase 6 README; `doc/TOOLCHAIN.md` gets the media3 pin.

</code_context>

<specifics>
## Specific Ideas

- Measure, don't assume: a phase task must run every preset on `portrait_rot90.mp4` and record
  output bytes, dims, fps and elapsed time into `doc/PRESETS.md`; those numbers are what the
  README will publish.
- The transmux path's speed claim ("a fraction of the encode time") is asserted as a ratio in the
  integration test (transmux elapsed < 30% of the encode elapsed for the same clip), not eyeballed.
- Two-job independence test: start two compressions of different clips, assert both progress
  streams reach 100 independently, cancel a third mid-flight and assert its partial file is gone.
- Keep Phase 1's `getMediaInfo` behaviour bit-for-bit; the only Phase 1 code this phase changes
  is the thumbnail default directory (moving under `compress_video/`) and the reason enum.

</specifics>

<deferred>
## Deferred Ideas

- HEVC opt-in with hardware check and fallback; HDR tone-mapping; 5.1/PCM audio — Phase 4.
- Job queue / concurrency limit, background isolate messenger, foreground service — Phase 5.
- Full example app with picker, progress UI and playback — Phase 3 (BULD-04).
- `video_compress` compatibility layer and README preset table publication — Phase 6.
- Exact-frame cross-platform trim parity — Phase 3 (CORE-07).

</deferred>
