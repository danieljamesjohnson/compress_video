# Phase 3: Apple Compression to Parity - Research

**Researched:** 2026-09-22
**Domain:** iOS/macOS video transcoding via AVFoundation's `AVAssetReader`/`AVAssetWriter`/`AVAssetExportSession`, inside a Flutter plugin's Pigeon-typed host API, mirroring the Android engine built in Phase 2
**Confidence:** HIGH for the reader/writer pipeline shape, transmux API selection, and two facts verified directly against live headers on the target Mac (`detachFromEngine` macOS availability, `AVAssetReaderTrackOutput` scaling); MEDIUM for AVError case names and the deprecated-progress/async-export version boundary (confirmed via official Apple doc URLs surfaced in search results and a third-party SDK-header mirror, not a live fetch of the rendered doc page); LOW/flagged where noted (exact byte-level transmux padding behavior on Apple's own muxer, exact keyframe pre-roll behavior of `AVAssetReader.timeRange`, both unmeasurable without running code on the Mac).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Apple engine architecture and Android parity**
- **Engine:** `AVAssetReader` + `AVAssetWriter` for every re-encode (H.264 via
  `AVVideoCodecType.h264`, `AVVideoAverageBitRateKey` for the resolved bitrate,
  `AVVideoWidthKey`/`AVVideoHeightKey` for the resolved displayed target, AAC via
  `AVFormatIDKey: kAudioFormatMPEG4AAC`); `AVAssetExportSession` with
  `AVAssetExportPresetPassthrough` ONLY for the transmux path. This is PROJECT.md's locked
  decision; the export-session `progress` API (deprecated in iOS 27) is never used for a
  re-encode.
- **One shared Swift core in `darwin/compress_video/Sources/compress_video/`**, `#if os(iOS)` /
  `os(macOS)` only where AVFoundation genuinely differs (there should be almost none in the
  encode path). New files mirror the Android names one-to-one so a reader can diff engines:
  `SizeGuard.swift` (pure port of `SizeGuard.kt`, same rule numbering, same field names),
  `CompressionEngine.swift` (the AVAssetReader/Writer pipeline, counterpart of
  `TransformerEngine.kt`), `JobRegistry.swift`, `ErrorMapping.swift`, `PluginFiles.swift`,
  `Compression.swift` (the `CompressHostApi` implementation registered in
  `CompressVideoPlugin.swift`). `SizeGuard.swift` gets an XCTest twin of `SizeGuardTest.kt`
  with the SAME numeric cases so a divergence in the plan math fails on the Mac before it
  fails in the parity gate.
- **Orientation (ORNT-01 parity):** read with `AVAssetReaderTrackOutput` in BGRA
  (`kCVPixelFormatType_32BGRA`) so the system tone-maps HDR to SDR for free (Phase 4 keeps
  this default; keep-HDR is the opt-in). Do NOT bake rotation into pixels: set
  `AVAssetWriterInput.transform = sourceTrack.preferredTransform` and encode at the CODED
  target size (swap the displayed target back to coded orientation for 90/270), exactly
  the way phones and Android's Transformer emit files. The result's `widthPx`/`heightPx`
  come from a re-probe of the finished file through `Probe.swift` (displayed dims), never
  from the writer's settings — same rule as Android (02-RESEARCH.md Pitfall 4). The
  existing `_expectUprightAndUnpadded` pixel assertions in `compress_test.dart` are the
  proof and must pass unchanged on the simulator.
- **Frame-rate cap (CORE-08 parity):** drop frames in the reader loop by presentation
  timestamp (keep a frame when `pts >= nextKeepTime`, advance by `1/effectiveFps`), matching
  `FrameDropEffect`'s decimation; never set `AVVideoExpectedSourceFrameRateKey` as the only
  mechanism. `effectiveFps = min(maxFps, input fps)`; never upscales.
- **Transmux (CORE-06 parity):** when `SizeGuard.Plan.wouldTransmux` is true, run
  `AVAssetExportSession(preset: AVAssetExportPresetPassthrough)` with `outputFileType = .mp4`
  and `shouldOptimizeForNetworkUse = false` (Android's muxer runs with streamable output
  disabled for the same never-larger reason — do not let a `moov`-first rewrite pad a short
  remux). Progress for a transmux is reported as 0 → 100 at completion (Media3 also has no
  mid-transmux progress); `transmuxed: true` in the result.
- **Never-larger (CORE-05 parity):** identical two-stage rule: pre-check via
  `SizeGuard.Plan.wouldUseOriginal` skips the encode; post-check is unconditional,
  `usedOriginal = outputBytes >= inputBytes`, on every path including transmux — copy the
  original into the plugin-owned output path and report it. `outputPath` never names the
  caller's input file.
- **Audio:** passthrough = `AVAssetWriterInput(mediaType: .audio, outputSettings: nil,
  sourceFormatHint: sourceFormatDescription)` fed by an `AVAssetReaderTrackOutput` with
  `outputSettings: nil` (compressed samples), used only when the source track is AAC
  (`kAudioFormatMPEG4AAC`); otherwise fall back to an AAC re-encode and report
  `audioReencoded: true`. `reencode(bitrateBps, channels)` decodes to PCM and writes AAC
  with `AVEncoderBitRateKey` / `AVNumberOfChannelsKey`. `strip` adds no audio input.
  Source-side failures on 5.1/PCM must not crash (Phase 4 owns proper handling; throwing
  `unsupportedInput` is acceptable here).
- **Progress and cancel (JOBS-01/02 parity):** derive progress from the writer loop — the
  last appended video sample's presentation time over the output duration (trim-aware),
  clamped 0..99, forwarded through `CompressVideoFlutterApi.onProgress` on the main queue at
  most every 250 ms, with a single terminal `100` sent before the result reply (Phase 2's
  exact clamp rule). Cancel sets a flag the reader loop checks per sample, calls
  `AVAssetWriter.cancelWriting()` (or `exportSession.cancelExport()`), deletes the partial
  file, and completes with `cancelled`; cancelling a finished job is a no-op.
- **Threading:** each job runs its reader/writer loop on its own serial `DispatchQueue`
  (`requestMediaDataWhenReady(on:)` for both inputs); Pigeon replies and `onProgress` are
  dispatched to the main queue. `JobRegistry` (a main-queue-confined dictionary keyed by
  job id) holds the cancel closure and temp path, mirrors `liveTempFilePaths()` for
  `clearCache`, and `detachFromEngine` cancels every live job BEFORE tearing down
  registrations (T-02-25).
- **Error mapping (CORE-04 parity):** `ErrorMapping.swift` maps `AVAssetReader`/`Writer`
  `status == .failed` errors and `AVError` codes onto the same `CompressVideoErrorReason`
  names: missing file → `fileNotFound` (checked up front, symlinks resolved like 01-WR-01);
  `AVError.fileFormatNotRecognized` / no video track / unreadable → `unsupportedInput`;
  `AVError.decoderNotAvailable` / `decodeFailed` → `decoderUnavailable`;
  `AVError.encoderNotAvailable` / `encoderTemporarilyUnavailable` → `encoderUnavailable`;
  `AVError.diskFull` and a pre-flight `volumeAvailableCapacityForImportantUsage` check
  against 1.2× the predicted bytes → `outOfSpace`; everything else → `io` with the
  `NSError` domain/code folded into the message (the numeric-code-in-message rule from
  02-06). No path logs-and-swallows; every failure deletes the partial file.
- **Estimate (INFO-03 parity):** `estimate()` resolves through the same
  `SizeGuard.resolve` the job uses, over `Probe.swift`'s output, exactly as
  `Compression.estimate()` does on Android. The Dart-side ±75% emulator tolerance in
  `compress_output_test.dart` stays; the Apple hardware encoder's real accuracy is
  measured and recorded (a `doc/PRESETS.md` Apple section, generated by the same
  `tool/measure_presets.dart` on the simulator and on the macOS host).
- **Output placement (CORE-09 parity):** `PluginFiles.swift` writes everything under
  `<Caches>/compress_video/` (`FileManager.urls(for: .cachesDirectory)`), default name
  `<jobId>.mp4`, honours `outputPath` with the same parent-must-exist → `io` rule, sweeps
  with the same canonical-path containment and live-job exclusion, and the Phase 1
  thumbnails move under the same subdirectory (already done on Android in Phase 2 — make
  Apple match).

**Trim exactness and the corpus**
- **New generated corpus clip `trim_source_10s.mp4`** (10 s, 30 fps, 1280×720, H.264 + AAC,
  burnt-in timecode, ~1 Mbps; added to `generate_corpus.sh`, `verify_corpus.sh --write`
  regenerates its sidecar; single-threaded x264 for byte reproducibility, as 01-02
  established). It exists because no current clip is long enough for the 2000→7000 ms
  criterion. Its sidecar gains a `trim` block: `{ "startMs": 2000, "endMs": 7000,
  "expectedDurationMs": 5000, "toleranceMs": 34 }` — one frame at 30 fps, read by the test,
  never hardcoded.
- **CORE-07 on Apple:** trim via `AVAssetReader.timeRange` (start/end as `CMTime` with the
  track's own timescale) and re-time samples so the output starts at zero; the writer's
  `AVAssetWriterInput` receives samples with pts offset by `-start`. Audio and video use the
  same `timeRange` so A/V stay aligned. Passthrough audio is cut at the packet boundary
  (AAC priming means the audio track may be ≤ 1 packet longer than video — the duration
  assertion is on the VIDEO track / container duration, same as Android's re-probe).
- **CORE-07 on Android:** already implemented via `ClippingConfiguration`; this phase adds
  the same 2000→7000 assertion on `trim_source_10s.mp4` to `compress_test.dart` (runs on all
  three platforms) and emits a `PARITY_JSON` record for it.
- **Parity gate widens to compression:** `compress_test.dart` (and the audio/output/jobs
  suites where a value is cross-platform) emit `PARITY_JSON` lines for the deterministic
  `CompressResult` fields (`widthPx`, `heightPx`, `videoCodec`, `audioCodec`,
  `transmuxed`, `usedOriginal`, `audioReencoded`, `durationMs` with the sidecar
  tolerance); `tool/check_parity.sh` compares them with the same sidecar-driven tolerance
  rules and its self-test grows matching cases. `outputBytes` and `elapsedMs` are
  platform-tolerant (different encoders) and are NOT compared byte-for-byte — record them
  as `tolerant` with a documented ±50% envelope on bytes so a 10× regression still fails.
- **The `small_480p` 3026 ms vs 2992 ms delta (01-07 follow-up):** re-examine once the
  Apple engine lands — the plan should determine which platform's duration reading
  (Android `MediaMetadataRetriever` vs Apple `AVAsset.duration`) is the container's actual
  `mvhd`/edit-list duration and document it in `corpus/README.md`; do not "fix" a platform
  to match the other unless one is demonstrably misreading the file.

**Mac build workflow, packaging and CI**
- **Do not touch Dan's `~/flutter` (3.41.2).** Install a second SDK on the Mac at
  `~/development/flutter-stable` (`git clone -b stable https://github.com/flutter/flutter.git`,
  then `flutter precache --ios --macos`), mirroring danserver's two-SDK convention, and
  put THAT on `PATH` in every remote command. Record the recipe in `.claude/CLAUDE.md` lane
  notes; the version must satisfy the pubspec floor (current stable is 3.47.x, matching CI).
- **Source sync is push-from-danserver:** a committed `tool/mac_sync.sh` rsyncs the
  working tree (excluding `.git`, `build/`, `.dart_tool/`, `.planning/`, `**/Pods`) to
  `~/CodeProjects/compress-video` on the Mac over the existing SSH config, so uncommitted
  changes can be built without a push; `tool/mac_run.sh <suite|build>` wraps the remote
  `PATH` setup, simulator boot (`xcrun simctl boot` + `bootstatus -b`), and the
  `flutter test integration_test/<suite> -d <udid>` / `flutter build macos` invocations with
  the same perl-`alarm` bound CI uses. The Mac never needs the danserver git remote.
- **Local Apple verification uses SPM** (`flutter config --enable-swift-package-manager` on
  the Mac's second SDK) because CocoaPods is absent (QUESTIONS.md #7); **CI proves CocoaPods**
  (its existing `--no-enable-swift-package-manager` builds) AND SPM (add the missing
  dedicated SPM build step the 01-CONTEXT CI design called for, if 01-06 did not land it).
  Both install paths must build the example for iOS and macOS in CI on every Apple-relevant
  push — that is BULD-02's proof.
- **BULD-02 "fresh app" proof** is a CI step, not a manual check: `flutter create` a
  throwaway app in the runner's temp dir, add the plugin by path, `flutter build ios
  --simulator --no-codesign` and `flutter build macos --debug` under CocoaPods, then again
  under SPM. Four builds, one script (`tool/verify_fresh_app.sh`), runnable on the Mac too.
- **CI `apple` job widens** to run every `integration_test/*.dart` suite on the simulator
  (dropping the explicit two-suite allowlist and the "Phase 2 suites hang on iOS" comment),
  keeps the per-suite alarm + one retry, and adds a **macOS desktop integration run**
  (`flutter test integration_test -d macos`) so the shared core is exercised on both Apple
  platforms, not just built on macOS. The parity job compares Android vs iOS records;
  macOS records are compared against iOS in the same step (same shared core, so any delta
  is a real bug).
- **Package hygiene:** the podspec and `Package.swift` pick up new Swift files
  automatically (glob / target directory); the `PrivacyInfo.xcprivacy` resource line stays
  commented unless the plan finds a required-reason API in use (file timestamps via
  `FileManager.attributesOfItem` ARE a required-reason API category — check and, if used,
  declare `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `C617.1` and uncomment the
  resource in both manifests).

**Example app (BULD-04)**
- **Replace the Phase 2 manual-check screen** with a real, single-screen flow shared by all
  three platforms: pick a video → options panel → Compress → live progress bar with Cancel →
  result card (bytes before/after with percentage saved, dimensions, codec, `transmuxed` /
  `usedOriginal` / `audioReencoded` badges, elapsed) → inline playback of the output.
- **Picker:** `image_picker` (`pickVideo(source: gallery)`) on iOS/Android; on macOS it
  routes to `file_selector` automatically. Keep a "Use bundled corpus clip" fallback so the
  simulator/emulator integration runs and CI need no photo library. **Playback:**
  `video_player` (supports Android, iOS, macOS). Both are flutter.dev-maintained plugins —
  the lowest toolchain-rot risk available; no other new dependencies. Add the iOS
  `NSPhotoLibraryUsageDescription` and macOS `com.apple.security.files.user-selected.read-only`
  entitlements the picker needs.
- **Options panel** exposes exactly the public `CompressOptions` surface: preset segmented
  control (p360/p480/p720/p1080), optional explicit `maxLongSidePx` / `videoBitrateBps` /
  `targetSizeMb` fields (mutually visible, validated by the plugin's own synchronous
  `unsupportedInput` throw, shown as a snackbar), `maxFps`, audio mode (passthrough /
  re-encode 128 kbps stereo / strip), trim start/end ms, and an "estimate" line that calls
  `estimate()` live as options change. No hidden defaults that differ from the library's.
- **The example is also the manual UAT vehicle:** 02-UAT.md #6 (compress screen on a real
  display) is closed by running this app on the Mac desktop and the iOS simulator and
  recording a screenshot into `.planning/phases/03-*/` (agents can see the simulator via
  `xcrun simctl io <udid> screenshot`). Keep the app's Dart under `analysis_options.yaml`'s
  strict settings and add a widget test that pumps the screen with a fake result so
  `flutter test` covers it on Linux too.

### Claude's Discretion
- Exact Swift file/type names beyond the Android-mirroring rule above; whether
  `SizeGuard.swift` is a `struct`/`enum` namespace; the reader's `outputSettings` keys beyond
  BGRA; the progress sample cadence if 250 ms proves noisy on the simulator; whether the
  macOS integration run uses `-d macos` or an `xcodebuild test` target.
- Whether `trim_source_10s.mp4` also carries a second, audio-less variant; whether the
  example app's estimate line debounces.
- The order of plans, as long as the Mac SDK bring-up and `tool/mac_sync.sh` land first
  (nothing Apple-side is verifiable without them) and the CI widening lands before the
  final parity plan.

### Deferred Ideas (OUT OF SCOPE)
- iOS background-interruption semantics (`interrupted` reason, `AVAssetWriter` on
  suspension) — Phase 5 (JOBS-05).
- HEVC opt-in with hardware check, keep-HDR HEVC Main10 + `AVVideoColorPropertiesKey`,
  Dolby Vision / HLG tone-map verification with real phone clips, 5.1 / PCM audio — Phase 4.
- Job queue / concurrency limit and background-isolate messenger — Phase 5.
- CocoaPods on the Mac for local CocoaPods-path verification (QUESTIONS.md #7) — optional,
  CI covers it.
- `video_compress` compatibility layer, README preset tables (now including the Apple
  measurements this phase records) — Phase 6.
- Physical iPhone hardware-encoder runs (bitrate accuracy, elapsed time) — recorded as a
  hardware-checklist item for TEST-01 in Phase 4; the simulator's encoder is software.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CORE-01 | Same Dart call, same observable behaviour on iOS/macOS as Android | `AVAssetReader`/`AVAssetWriter` pipeline verified for H.264/AAC encode + `AVAssetExportSession` for transmux; the wire contract (`CompressHostApi`, `CompressRequestMessage`/`CompressResultMessage`) is already generated (Messages.g.swift, read this session) — only the Swift implementation is new |
| CORE-07 | Trim exact within one frame, all platforms | `AVAssetReader.timeRange` (CITED) + `AVAssetWriter.startSession(atSourceTime:)` (CITED, corrects CONTEXT.md's "offset pts by -start" phrasing to the standard non-retiming mechanism — same observable outcome) |
| BULD-02 | iOS 13+/macOS 11+, one shared Swift core, CocoaPods + SPM | Podspec (`source_files = '.../Sources/compress_video/**/*.swift'`) and `Package.swift` (whole-directory target, no explicit file list) both verified this session to pick up new files automatically — no manifest edit needed for new Swift files |
| BULD-04 | Example app: pick, compress, progress, cancel, play, all 3 platforms | `image_picker` 1.2.3 + `video_player` 2.14.0, both `publisher:flutter.dev` (VERIFIED: pub.dev API, this session); macOS picking routes through `image_picker_macos` 0.2.2+1, itself built on `file_selector_macos` (VERIFIED: pub.dev API dependency list, this session) |
</phase_requirements>

## Summary

Phase 3 builds the Apple engine on the same `AVAssetReader`/`AVAssetWriter` primitives every
credible Apple-side video compressor in the competitive field uses (`light_compressor_v2`,
`v_video_compressor` — see the project's own `VIDEO_COMPRESS_BRIEF.md`), reserving
`AVAssetExportSession` for exactly the transmux fast path, per CONTEXT.md's locked decision.
Every API surface this phase needs — reader/writer output settings, transform-preserving
rotation, trim via `timeRange`, progress derivation, cancel, and the macOS/iOS platform
differences — was either read directly from a live framework header on the target Mac this
session, or cross-checked against official `developer.apple.com` documentation URLs surfaced
by search and a mirrored SDK header. Two findings materially change how this phase must be
planned beyond what CONTEXT.md already decided:

1. **macOS's `FlutterPlugin` protocol has no `detachFromEngine` method at all.**
   `[VERIFIED: FlutterPluginMacOS.h, read directly on the Mac this session via
   ~/flutter/bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework/.../Headers/
   FlutterPluginMacOS.h]` — its entire `@optional` surface is exactly one method,
   `handleMethodCall:result:`. CONTEXT.md's "`detachFromEngine` cancels every live job BEFORE
   tearing down registrations" is an iOS-only mechanism (`detachFromEngineForRegistrar:`,
   confirmed present in the iOS `FlutterPlugin.h` header, same session). On macOS the nearest
   equivalent is `FlutterAppLifecycleDelegate.handleWillTerminate(_:)` — confirmed present in
   `FlutterAppLifecycleDelegate.h`, which macOS's `FlutterPlugin` protocol inherits from — a
   notification-based hook fired when the app is about to quit, not an engine-teardown hook.
   This is a real per-platform difference the plan must call out explicitly, not paper over
   with `#if os(iOS)` around a method that silently no-ops on macOS.

2. **The reader-side resize does not need `AVMutableVideoComposition`/`AVAssetReaderVideo
   CompositionOutput` at all.** `AVAssetReaderTrackOutput.outputSettings` accepts
   `kCVPixelBufferWidthKey`/`kCVPixelBufferHeightKey` directly alongside the pixel-format key,
   and the decoder scales during decode — confirmed via a mirrored Apple SDK header's own doc
   comment (`[CITED: theos/sdks AVAssetReaderOutput.h mirror, read this session]`) with the one
   documented caveat that this scaling is unavailable for high-bit-depth pixel formats (not
   relevant to this phase's BGRA/SDR path; relevant to Phase 4's keep-HDR work). Using a video
   composition instead would apply a layer-instruction transform to the rendered pixels — which
   is exactly the "bake rotation into pixels" behavior CONTEXT.md's orientation decision
   prohibits. The plain reader/writer pipeline with width/height keys on the reader and
   `preferredTransform` on the writer input is therefore both the simpler AND the
   decision-compliant approach; a plan that reaches for `AVMutableVideoComposition` here would
   be solving an already-solved problem the wrong way.

A third, lower-severity correction: CONTEXT.md's error-mapping prose names `AVError
.decoderNotAvailable`/`AVError.encoderNotAvailable` — neither case exists. The real Swift case
names, confirmed via direct developer.apple.com documentation-page URLs surfaced in search
results this session, are `AVError.Code.decoderNotFound`/`.encoderNotFound` (a suitable decoder/
encoder could not be found) and `.decoderTemporarilyUnavailable`/`.encoderTemporarilyUnavailable`
(one exists but is momentarily busy) — a real 22-vs-23-code-shaped mapping table task, the same
shape of gap 02-RESEARCH.md's Pitfalls #8/#9 filled for Android.

**Primary recommendation:** Build `CompressionEngine.swift` around a job-scoped, serial
`DispatchQueue`-driven `AVAssetReader`/`AVAssetWriter` copy loop (`requestMediaDataWhenReady`
on both video and audio inputs), reader `outputSettings` requesting BGRA plus the CODED target
width/height directly (no composition), `AVAssetWriterInput.transform = preferredTransform`,
`AVAssetReader.timeRange` + `AVAssetWriter.startSession(atSourceTime:)` for trim, and
`AVAssetExportSession` gated behind `#available(iOS 18, macOS 15, *)` for the modern
`export(to:as:)`/`states(updateInterval:)` async pair with a legacy
`exportAsynchronously(completionHandler:)` + polled (deprecated but functional)
`.progress` fallback below that floor — since this project's actual deployment floor (iOS 13/
macOS 11) is nine major versions below where the modern export API exists.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Compression job orchestration (start/cancel/progress) | API/Backend (Apple platform code, `CompressionEngine.swift`) | — | AVFoundation reader/writer only runs on-device; no Dart-side state beyond the shared `CompressJob` wrapper Phase 2 already built |
| Size-target math (preset/bitrate/target-size resolution, never-larger, transmux decision) | API/Backend (pure Swift, `SizeGuard.swift`) | — | Must be callable with no AVFoundation import at all — a straight line-for-line port of `SizeGuard.kt`, proven by an XCTest twin with the same numeric cases, exactly like the Android original |
| Progress delivery to Dart | API/Backend → Client (Flutter) | — | Native derives progress from the writer loop's last-appended sample PTS and forwards via the ALREADY-GENERATED `CompressVideoFlutterApi.onProgress` (Messages.g.swift, read this session) — Dart-side plumbing is unchanged from Phase 2, only the native emitter is new |
| File placement / cache management | API/Backend (Apple filesystem) | — | `<Caches>/compress_video/` convention; this phase writes `PluginFiles.swift` as a straight port of `PluginFiles.kt`'s atomic-write/sweep pattern |
| Result typing / error taxonomy | Client (Dart) mapping API/Backend (native) output | — | Dart's `reasonFromPlatformCode` mapper is reused unchanged (Phase 2 already grew the reason enum for every value this phase needs); only `ErrorMapping.swift`'s native-side table is new |
| Job identity / registry | API/Backend (`JobRegistry.swift`, new) | Client (Dart generates the `jobId`) | Same contract as Android: Dart generates the id, native only ever looks up by an id it did not create |
| Plugin lifecycle / cleanup on app teardown | API/Backend, but **platform-divergent** (iOS: `detachFromEngineForRegistrar:`; macOS: `FlutterAppLifecycleDelegate.handleWillTerminate(_:)`, no engine-detach hook exists) | — | New finding this session (Summary #1) — the plan must design two different teardown paths, not one `#if os(iOS)`-guarded single implementation with a silent macOS no-op |

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|---------------|
| `AVFoundation` (system framework) | iOS 13.0+ / macOS 11.0+ (this project's own floor, unchanged since Phase 1) | `AVAssetReader`, `AVAssetWriter`, `AVAssetExportSession`, `AVAsset`/`AVAssetTrack` | Apple's only first-party on-device transcode API; no version to pin — it ships with the OS. `Probe.swift`/`Thumbnails.swift` (Phase 1) already depend on it and already carry the `#available(iOS 16, macOS 13, *)` dual-path pattern this phase's own `CompressionEngine.swift` should reuse for any track-property load it needs beyond what `Probe`'s existing `MediaInfoMessage` already carries |
| Pigeon-generated `CompressHostApi`/`CompressVideoFlutterApi` | Already generated (`Messages.g.swift`, read this session, 951 lines) | Wire contract implementation surface | **No regeneration needed this phase** — `CompressHostApiSetup`, the `CompressRequestMessage`/`CompressResultMessage`/`EstimateMessage`/`AudioModeMessage` structs, and `CompressVideoFlutterApi.onProgress` all already exist from Phase 2's Pigeon run (Android and Apple share one `.dart` contract, generated to both languages together). Only the Swift-side implementation (`Compression: CompressHostApi`) and its registration in `CompressVideoPlugin.swift` are new — same relationship Phase 1 already established for `ProbeHostApi`/`ThumbnailHostApi` |

### Supporting (example app only)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `image_picker` | **1.2.3**, published 2026-06-30 `[VERIFIED: pub.dev API, this session — publisher:flutter.dev, 160/160 pub points, 4.39M downloads/30d]` [ASSUMED: package identity/API shape — from training knowledge, registry existence confirmed but not cross-checked against a fetched README this session] | `pickVideo(source: ImageSource.gallery)` on Android/iOS | Every platform except macOS, which routes through its federated `image_picker_macos` package automatically via Dart's plugin resolution — the app's `pubspec.yaml` only needs to depend on `image_picker` itself, never `image_picker_macos` directly |
| `image_picker_macos` (federated, transitive) | **0.2.2+1**, published 2025-10-18 `[VERIFIED: pub.dev API, this session]` | macOS picker backend | Auto-selected by Flutter's `default_package` federated-plugin mechanism (`"macos":{"default_package":"image_picker_macos"}`, confirmed in the package's own platform declaration this session) — not a direct dependency the app declares |
| `video_player` | **2.14.0**, published 2026-08-11 `[VERIFIED: pub.dev API, this session — publisher:flutter.dev, is:flutter-favorite, tags include platform:macos, 3.16M downloads/30d]` | Inline playback of the compressed output on all 3 platforms | Delegates to `video_player_avfoundation` (^2.11.0) on iOS/macOS, confirmed as its own listed macOS implementation this session; this is the only flutter.dev plugin with committed macOS video playback support |
| `file_selector` / `file_selector_macos` | Not a direct dependency — pulled in transitively by `image_picker_macos` | Underlying macOS file-picking mechanism | `[VERIFIED: pub.dev API dependency list for image_picker_macos 0.2.2+1, this session — depends on file_selector_macos ^0.9.1+1]`. This refines CONTEXT.md's "on macOS it routes to file_selector automatically" phrasing: the literal routing is `image_picker` → `image_picker_macos` → `file_selector_macos`, not a direct `file_selector` dependency the app itself declares |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `AVAssetReader`/`AVAssetWriter` for encode | `AVAssetExportSession` with a quality preset for everything (what the incumbent `video_compress` and `v_video_compressor` do) | No bitrate control (`fileLengthLimit` only), no documented resolution/bitrate per preset, deprecated `progress` — the exact defect class this rebuild exists to fix (VIDEO_COMPRESS_BRIEF.md §1/§4) |
| Reader-side `kCVPixelBufferWidthKey`/`HeightKey` resize | `AVAssetReaderVideoCompositionOutput` + `AVMutableVideoComposition(renderSize:)` | Composition layer instructions bake a transform into rendered pixels — directly conflicts with the "do not bake rotation into pixels" decision; also more code for no benefit at this phase's 8-bit BGRA path (see Summary #2) |
| `image_picker` + `video_player` | `file_picker` + a custom `VideoPlayerController`-less player, or `camera` for direct capture | Both flutter.dev-maintained and already committed as CONTEXT.md's locked choice; alternatives add toolchain-rot risk (third-party maintainers) for no functional gain in a demo app |

**Installation** (darwin package — no manifest change needed, both build systems glob the source directory):
```bash
# No pubspec/podspec/Package.swift edit required for new engine Swift files themselves.
# Only the EXAMPLE app's pubspec.yaml needs new dependencies:
cd example && flutter pub add image_picker video_player
```

**Version verification, live this session:**
```
$ curl -s https://pub.dev/api/packages/video_player/score
  {"grantedPoints":150,"maxPoints":160, ... "tags":[...,"publisher:flutter.dev",...,"platform:macos",...]}
$ curl -s https://pub.dev/api/packages/image_picker/score
  {"grantedPoints":160,"maxPoints":160, ... "tags":[...,"publisher:flutter.dev",...,"platform:macos",...]}
$ curl -s https://pub.dev/api/packages/image_picker_macos
  latest 0.2.2+1, depends on file_selector_macos ^0.9.1+1
```

## Package Legitimacy Audit

`gsd-tools query package-legitimacy check` only covers `npm`/`pypi`/`crates` ecosystems; pub.dev
is out of its scope (same situation 02-RESEARCH.md documented for Google Maven). This audit is
therefore the same manual first-party-publisher check that document used: every package below
was independently confirmed via a live `pub.dev` API fetch this session to carry the
`publisher:flutter.dev` tag (Flutter's own team, the strongest attribution pub.dev offers),
never merely assumed from package-name familiarity.

| Package | Registry | Publisher | Downloads/30d | Source Repo | Verdict | Disposition |
|---------|----------|-----------|----------------|--------------|---------|-------------|
| `image_picker` | pub.dev | `flutter.dev` `[VERIFIED]` | 4.39M | github.com/flutter/packages | OK | Approved |
| `image_picker_macos` | pub.dev | `flutter.dev` (same monorepo/publisher, transitive) | N/A (federated impl, not independently installed) | github.com/flutter/packages | OK | Approved (transitive, not declared directly) |
| `video_player` | pub.dev | `flutter.dev` `[VERIFIED]` | 3.16M | github.com/flutter/packages | OK | Approved |
| `video_player_avfoundation` | pub.dev | `flutter.dev` (transitive) | N/A | github.com/flutter/packages | OK | Approved (transitive, not declared directly) |

**Packages removed due to `[SLOP]` verdict:** none.
**Packages flagged as suspicious `[SUS]`:** none — both direct dependencies are the highest-profile
first-party Flutter plugins in the ecosystem (7,762 and 3,722 likes respectively), the same
"lowest toolchain-rot risk available" CONTEXT.md's own decision already asserted; this audit
confirms rather than merely repeats that claim.

## Architecture Patterns

### System Architecture Diagram

```
Dart caller
   |
   | CompressVideo.compress(path, options) -- generates jobId locally (unchanged from Phase 2)
   v
CompressHostApi.startCompress(path, jobId, CompressRequestMessage)
   |   [Pigeon @async; CompressHostApiSetup wraps every handler in Task { @MainActor in ... },
   |    confirmed this session in Messages.g.swift -- the call ARRIVES on the MainActor, unlike
   |    Android where the plugin itself must assert the main Looper]
   v
CompressVideoPlugin (Swift) -- registers CompressHostApi (new), owns JobRegistry
   |
   | 1. Arguments.swift validation (existing pattern, extended) -- reject bad input first
   v
Probe.swift (existing, reused) -- read input format: codec, bitrate, dims, rotation, fps, has-audio
   |
   v
SizeGuard.swift (new, pure Swift port of SizeGuard.kt, no AVFoundation import) -- resolve
   |            preset/target -> effective (targetWidthPx, targetHeightPx, videoBitrateBps,
   |            audioBitrateBps, effectiveFps); decide wouldTransmux / wouldUseOriginal
   |            -- same function backs estimate() so the two paths cannot disagree
   v
   +-- estimate() only: return EstimateMessage here, stop. No AVAssetReader/Writer touched.
   |
   v
CompressionEngine.swift (new) -- runs the copy loop on a job-scoped SERIAL DispatchQueue
   (NOT the main queue/actor the Pigeon call arrived on -- AVFoundation's reader/writer
   objects have no Looper-style single-thread requirement the way Media3's Transformer does;
   the copy loop should be moved OFF the MainActor precisely so it does not block Flutter's
   platform channel or UI, the opposite constraint from Android's Pattern 1):
     branch A (wouldTransmux): AVAssetExportSession(asset:, presetName: AVAssetExportPresetPassthrough)
       .outputFileType = .mp4; .shouldOptimizeForNetworkUse = false
       #available(iOS 18, macOS 15, *): try await export(to:as:) + states(updateInterval:) task
       else: exportAsynchronously(completionHandler:) + polled deprecated .progress
     branch B (real encode): build AVAssetReader with:
       - video AVAssetReaderTrackOutput, outputSettings requesting BGRA + CODED target W/H
       - audio AVAssetReaderTrackOutput, outputSettings nil (passthrough) OR PCM (reencode)
       - reader.timeRange = trim CMTimeRange, when trimmed
       build AVAssetWriter with:
       - video AVAssetWriterInput, outputSettings {H264, AVVideoAverageBitRateKey,
         AVVideoCompressionPropertiesKey}, .transform = sourceTrack.preferredTransform
       - audio AVAssetWriterInput, outputSettings nil (passthrough, + sourceFormatHint) OR
         AAC settings (reencode)
       writer.startSession(atSourceTime: trim start CMTime or .zero)
       requestMediaDataWhenReady(on: jobQueue) per input; frame-rate cap by dropping samples
       whose pts < nextKeepTime in this same loop
   |
   | every appended video sample: derive progress = (samplePts - trimStart) / outputDuration,
   | clamped 0..99, dispatched to main queue -> CompressVideoFlutterApi.onProgress
   v
writer.finishWriting(completionHandler:)  OR  reader/writer .status == .failed
   |                                                                    |
   v                                                                    v
Post-check: outputBytes >= inputBytes?                       reader.error / writer.error (AVError)
   |-- yes: copy/return original, usedOriginal=true                -> CompressVideoErrorReason
   |-- no: rename temp -> final path                                  (ErrorMapping.swift table)
   v                                                                    |
Re-probe output (Probe.swift, reused) for displayed widthPx/heightPx   v
   |                                                          delete partial output file
   v                                                                    |
CompressResultMessage  <-----------------------------------------------+
   |
   v
Dart: job.result completes; job.progress stream closes  (unchanged Dart-side plumbing, Phase 2)
```

### Recommended Project Structure

```
darwin/compress_video/Sources/compress_video/
├── CompressVideoPlugin.swift   # extend: register CompressHostApi, own JobRegistry, per-platform teardown
├── JobRegistry.swift           # new: jobId -> {cancel closure, tempFile} map, main-queue-confined
├── CompressionEngine.swift     # new: builds/drives AVAssetReader+Writer OR AVAssetExportSession
├── SizeGuard.swift             # new: pure preset/target math port, no AVFoundation import
├── ErrorMapping.swift          # new: AVError/status-based mapping to CompressVideoErrorReason
├── PluginFiles.swift           # new: atomic write/sweep, port of PluginFiles.kt
├── Compression.swift           # new: CompressHostApi implementation
├── Probe.swift                 # existing (Phase 1): reused unchanged for input read + output re-probe
├── Thumbnails.swift             # existing (Phase 1): unaffected except shared cache-dir constant
├── Arguments.swift             # existing (Phase 1): extend with compress-specific validators
├── MediaMath.swift             # existing (Phase 1): extend if a rounding helper is missing
└── Messages.g.swift            # generated: already contains everything this phase needs (read-only)
```

### Pattern 1: The copy loop runs OFF the MainActor, not on it (the inverse of Android's constraint)

**What:** Android's Pattern 1 (02-RESEARCH.md) requires `Transformer` to be built/driven ONLY on
the main Looper. Apple's `AVAssetReader`/`AVAssetWriter` have no such requirement — they are
plain Foundation/AVFoundation objects usable from any thread — but Pigeon's generated
`CompressHostApiSetup.setUp` wraps every incoming call in `Task { @MainActor in ... }`
`[VERIFIED: Messages.g.swift, read this session — every channel handler in
CompressHostApiSetup.setUp wraps its body in `Task { @MainActor in do { ... } }`]`. If
`Compression.startCompress` awaits the entire reader/writer copy loop inline on that MainActor
task, every `onProgress` call AND every other Pigeon message on the app (including a concurrent
`cancel` or `estimate` call, and any UI update) queues behind it until the job finishes — the
opposite failure mode from Android's (which crashes loudly with `IllegalStateException` if you
get it wrong), and easy to miss because it "works" on a fast host and only shows up as UI
jank/dropped frames on a slow one.

**When to use:** Every compression job. `Compression.startCompress` should hop OFF the MainActor
(e.g. `Task.detached` or a plain `DispatchQueue`-based continuation) to run the actual copy loop,
then hop back to the main queue only for `onProgress` calls and the final Pigeon reply — matching
this project's own `Probe.swift` pattern of doing the real work off the calling context.

**Example:**
```swift
// Messages.g.swift, read this session (CompressHostApiSetup.setUp, startCompressChannel handler):
startCompressChannel.setMessageHandler { message, reply in
  let args = message as! [Any?]
  ...
  Task { @MainActor in
    do {
      let result = try await api.startCompress(path: pathArg, jobId: jobIdArg, request: requestArg)
      reply(wrapResult(result))
    } catch {
      reply(wrapError(error))
    }
  }
}
```
`api.startCompress` itself must not block this MainActor task for the encode's duration — it
should `await` work dispatched to a job-scoped background queue and only touch `@MainActor`
state (JobRegistry, the Flutter API's `onProgress`) via explicit hops back.

### Pattern 2: Reader-side resize via `outputSettings` width/height keys, never a video composition

**What:** `AVAssetReaderTrackOutput.outputSettings` accepts `kCVPixelBufferPixelFormatTypeKey`
alongside `kCVPixelBufferWidthKey`/`kCVPixelBufferHeightKey` and the decoder scales the delivered
`CVPixelBuffer` during decode. `[CITED: theos/sdks AVAssetReaderOutput.h mirror + a WWDC-era
forum thread confirming the pattern, both read this session]` — with the one documented caveat
that scaling is unsupported for high-bit-depth pixel formats (irrelevant to this phase's 8-bit
BGRA SDR path; relevant to Phase 4's keep-HDR work, which must NOT request these keys on a
10-bit output).

**When to use:** Every real-encode job that needs to downscale — i.e. whenever
`SizeGuard.Plan`'s CODED target width/height differs from the input's own coded dimensions. Skip
the keys entirely (pass through at native coded size) when no resize is needed, mirroring
Android's Pattern 3 "only add the effect if it changes something" rule.

**Example:**
```swift
// Source: theos/sdks mirror of AVAssetReaderOutput.h (read this session), corroborated by
// developer.apple.com forum guidance on AVAssetReader+AVAssetWriter resize workflows
let codedTargetSize = /* SizeGuard.Plan's target, swapped back to CODED orientation for 90/270 */
let videoOutputSettings: [String: Any] = [
  kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
  kCVPixelBufferWidthKey as String: codedTargetSize.width,
  kCVPixelBufferHeightKey as String: codedTargetSize.height,
]
let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoOutputSettings)
```
**Anti-pattern:** reaching for `AVAssetReaderVideoCompositionOutput` +
`AVMutableVideoComposition(renderSize:)` here. A video composition's layer instructions apply a
transform to the RENDERED pixels — the exact "bake rotation into pixels" behavior CONTEXT.md's
orientation decision (ORNT-01 parity) prohibits. It is also strictly more code for the same
result at this phase's pixel format.

### Pattern 3: Trim via `AVAssetReader.timeRange` + `AVAssetWriter.startSession(atSourceTime:)`, not manual sample retiming

**What:** Setting `reader.timeRange = CMTimeRange(start: trimStartCMTime, end: trimEndCMTime)`
before `startReading()` limits which samples the reader delivers. The delivered samples still
carry their ORIGINAL-asset-timeline presentation timestamps (e.g. a sample from 2.0s into the
source still has `pts ≈ 2.0s`, not `0.0s`) — but calling `writer.startSession(atSourceTime:
trimStartCMTime)` (instead of the usual `.zero`) makes the writer compute every output sample's
timestamp RELATIVE to that session start automatically. `[CITED: Apple Technical Q&A/forum
guidance on `startSessionAtSourceTime:` semantics, read this session — "timing information in
the sample buffer, considered relative to the time passed to startSessionAtSourceTime:, will be
used to determine the timing of those samples in the output file"]` This is the standard
mechanism and needs no `CMSampleBufferCreateCopyWithNewTiming` call — CONTEXT.md's "the writer's
`AVAssetWriterInput` receives samples with pts offset by `-start`" describes the OUTPUT file's
observable timestamps, which `startSession(atSourceTime:)` already produces without manual
retiming; this is a refinement of the mechanism, not a change to the decision's observable
outcome.

**When to use:** Every trimmed job (`trimStartMs`/`trimEndMs` present). Set the SAME `timeRange`
on the one `AVAssetReader` instance before adding both the video and audio track outputs, so A/V
stay aligned (CONTEXT.md's own requirement) — `timeRange` is a reader-level property, not
per-output.

**Open sub-question (flagged below, not resolvable without running code on the Mac):** whether
`AVAssetReader.timeRange`'s internal keyframe-seek-then-discard behavior delivers the FIRST
video sample at exactly `trimStartMs`'s CMTime, or at the nearest keyframe at-or-before it with
the intervening frames silently dropped inside the reader (as opposed to delivered and needing
manual discard) — general AVFoundation guidance says the reader seeks to the preceding keyframe
internally and only VENDS samples from the requested start forward, but this project's own "one
frame" trim-exactness tolerance means the plan must verify this empirically against
`trim_source_10s.mp4` rather than trust the general claim uncritically.

### Pattern 4: Transmux via `AVAssetExportSession`, version-gated between the deprecated and modern progress APIs

**What:** This project's floor (iOS 13/macOS 11) predates the modern async export API
(`export(to:as:)` + `states(updateInterval:)`) by nine major OS versions — that pair is
**only available from iOS 18/macOS 15 on** `[CITED: multiple developer.apple.com documentation
page titles and a Swift Forums thread confirming this exact availability floor, read this
session]`. Below that floor, the only usable API is the deprecated
`exportAsynchronously(completionHandler:)` + polled `.progress`/`.status` — deprecated, but still
functional; CONTEXT.md's "the export-session progress API ... is never used for a re-encode"
already scopes this correctly (transmux is never a re-encode), so using the legacy polling API
for the transmux path's progress is compliant with that decision, not a violation of it, as long
as the (near-instant) transmux progress reporting stays the simple "0 → 100 at completion"
CONTEXT.md already specifies rather than depending on fine-grained progress at all.

**When to use:** Every job where `SizeGuard.Plan.wouldTransmux` is true.

**Example:**
```swift
// Availability confirmed via developer.apple.com doc-page titles + Swift Forums thread,
// read this session. This project's deployment floor (iOS 13/macOS 11) requires the else branch
// as the PRIMARY path, not a fallback -- the modern branch is a nice-to-have on newer OSes only.
let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
session.outputURL = tempURL
session.outputFileType = .mp4
session.shouldOptimizeForNetworkUse = false  // CONTEXT.md: no moov-first padding on a short remux
if let timeRange { session.timeRange = timeRange }

if #available(iOS 18, macOS 15, *) {
  try await session.export(to: tempURL, as: .mp4)
  // states(updateInterval:) is available for progress if ever needed; transmux reports 0->100
  // at completion per CONTEXT.md, so this loop is optional, not required, on this branch.
} else {
  await withCheckedContinuation { continuation in
    session.exportAsynchronously {
      continuation.resume()
    }
  }
  // session.status / session.error read here, post-completion
}
```

### Pattern 5: Per-platform teardown — iOS has an engine-detach hook, macOS does not

**What:** `[VERIFIED: FlutterPlugin.h (iOS) contains `detachFromEngineForRegistrar:`, and
FlutterPluginMacOS.h (macOS) contains NO such method — its entire @optional surface is
`handleMethodCall:result:` — both read directly on the target Mac this session at
`~/flutter/bin/cache/artifacts/engine/{ios-profile,darwin-x64}/.../Headers/
{FlutterPlugin.h,FlutterPluginMacOS.h}`]`. macOS's `FlutterPlugin` protocol DOES inherit from
`FlutterAppLifecycleDelegate` `[VERIFIED: same FlutterPluginMacOS.h, `@protocol FlutterPlugin
<NSObject, FlutterAppLifecycleDelegate>`]`, which declares an optional
`handleWillTerminate:(NSNotification*)` method `[VERIFIED: FlutterAppLifecycleDelegate.h, read
this session]` — fired when the `NSApplication` is about to quit, not when the plugin is
detached from a specific engine instance (macOS Flutter apps typically have exactly one engine
for the app's lifetime, so this distinction rarely matters in practice, but it is a different
event with different guarantees).

**When to use:** `#if os(iOS)` — implement `func detachFromEngine(for registrar:
FlutterPluginRegistrar)` and call `JobRegistry.cancelAll()`. `#elseif os(macOS)` — implement
`func handleWillTerminate(_ notification: Notification)` and call the same `cancelAll()`. Do NOT
write one method guarded only by availability and assume it fires on both platforms — it will
silently never fire on macOS if implemented only as `detachFromEngine`.

**Example:**
```swift
public class CompressVideoPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) { /* ... existing ... */ }

  #if os(iOS)
  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    JobRegistry.cancelAll()
  }
  #elseif os(macOS)
  public func handleWillTerminate(_ notification: Notification) {
    JobRegistry.cancelAll()
  }
  #endif
}
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Portrait/rotation handling | Manual pixel rotation + custom rotation-metadata writing | `AVAssetWriterInput.transform = sourceTrack.preferredTransform`, encode at coded (pre-rotation) size | This is exactly Phase 1's own `Probe.swift`/`MediaMath.rotationDegrees` pattern in reverse — the plugin already reads `preferredTransform` correctly; writing it back is the same primitive, not new logic |
| Resize/scaling | A `CoreImage`/`vImage` manual scaling pass on each decoded `CVPixelBuffer` | `AVAssetReaderTrackOutput.outputSettings`'s `kCVPixelBufferWidthKey`/`HeightKey` | Verified this session to scale during decode with no extra pass required (Pattern 2) |
| Trim range math | Hand-computed sample-dropping/retiming loop | `AVAssetReader.timeRange` + `AVAssetWriter.startSession(atSourceTime:)` | Both are first-party AVFoundation primitives built for exactly this (Pattern 3) |
| AAC passthrough detection | A custom bitstream sniffer | `CMFormatDescriptionGetMediaSubType` compared against `kAudioFormatMPEG4AAC`, already CONTEXT.md's locked mechanism, mirroring `Probe.swift`'s existing `fourCharacterCode(from:)` helper for video | The same format-description read pattern Phase 1 already established for video codec detection extends directly to audio |
| Free-space pre-check | A hand-rolled `statfs` wrapper | `URL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])` | First-party `URLResourceKey`, mirrors Android's `StatFs` pre-check (Compression.kt) exactly — see Pitfall below for its one documented limitation |

**Key insight:** Every "hard part" this phase's engine needs (rotation, resize, trim, audio
codec detection, free-space check) already has a first-party AVFoundation/Foundation API that
does exactly that job, the same conclusion 02-RESEARCH.md reached for Media3 — the actual work
is wiring, threading discipline (the INVERSE discipline from Android — get OFF the MainActor,
not stay ON a Looper), and measuring real behavior on the Mac, not inventing new media logic.

## Common Pitfalls

### Pitfall 1: Blocking the MainActor for the whole encode because Pigeon delivers the call there
**What goes wrong:** Every subsequent Pigeon message (a concurrent `cancel`, `estimate`, or even
Flutter's own UI thread work if `@MainActor` in this app happens to be the same actual thread)
queues behind an in-flight compression until it finishes.
**Why it happens:** `CompressHostApiSetup.setUp`'s generated handlers wrap every call body in
`Task { @MainActor in ... }` (verified this session). Naively `await`-ing the entire reader/
writer copy loop inside that same task keeps it pinned to the MainActor for the encode's
duration.
**How to avoid:** Hop off the MainActor for the actual copy loop (Pattern 1); only touch
`@MainActor`-isolated state (JobRegistry, `onProgress`) via explicit hops back.
**Warning signs:** A `cancel()` call that doesn't take effect until the job it's meant to cancel
already finished; UI jank during compression on a real device that the simulator's faster host
CPU may not reproduce.

### Pitfall 2: `detachFromEngine` silently never fires on macOS
**What goes wrong:** A live job survives past the point the plugin "detaches", because the
method that would have cancelled it is never called on macOS at all.
**Why it happens:** macOS's `FlutterPlugin` protocol has no `detachFromEngine`-shaped method
(verified this session, Summary #1 / Pattern 5).
**How to avoid:** Implement the two different platform hooks (Pattern 5) — `#if os(iOS)`
`detachFromEngine(for:)`, `#elseif os(macOS)` `handleWillTerminate(_:)` — and note in the plan
and in code comments that they are NOT equivalent events (engine-detach vs. app-about-to-quit),
just the closest available substitute.
**Warning signs:** A test asserting "detach cancels live jobs" that only ever runs on the iOS
simulator (or only in a JVM/XCTest-style unit test with no real macOS lifecycle event) would
pass while silently never exercising the macOS path at all.

### Pitfall 3: Reaching for `AVMutableVideoComposition` for resize, which bakes in rotation
**What goes wrong:** Portrait output plays sideways, or the `_expectUprightAndUnpadded` pixel
assertions fail, because a video composition's layer instructions apply a transform to rendered
pixels — duplicating what `AVAssetWriterInput.transform` is already supposed to do as metadata,
and doing it in a way this project's orientation decision explicitly prohibits.
**Why it happens:** `AVAssetReaderVideoCompositionOutput` + `renderSize` is the more commonly
blogged-about resize pattern for AVFoundation (it appears first in general search results) —
it's easy to reach for without realizing the width/height reader-output-settings keys already do
the job with no composition at all (Pattern 2).
**How to avoid:** Use `kCVPixelBufferWidthKey`/`HeightKey` on the plain
`AVAssetReaderTrackOutput`, never `AVAssetReaderVideoCompositionOutput`, for this phase's SDR
8-bit path.
**Warning signs:** Code that constructs an `AVMutableVideoComposition` anywhere in
`CompressionEngine.swift` at all — there is no reachable code path in this phase's design where
one is needed.

### Pitfall 4: Using the modern `export(to:as:)`/`states(updateInterval:)` API unconditionally
**What goes wrong:** A crash or compile-time availability error on the project's actual
deployment floor (iOS 13/macOS 11), since these APIs require iOS 18/macOS 15.
**Why it happens:** Most current (2026) Apple sample code and blog posts about
`AVAssetExportSession` progress default to the modern async API, since the deprecated
`.progress`/`exportAsynchronously` pair is now flagged deprecated in Xcode 26's own warnings —
easy to "fix the deprecation warning" by switching to the new API without checking it against
this specific project's much lower floor.
**How to avoid:** `#available(iOS 18, macOS 15, *)` gate, with the deprecated pair as the
PRIMARY path for this project (most of its target audience, and certainly the iOS 13-17/macOS
11-14 simulator/device matrix this phase must still support), not a legacy fallback (Pattern 4).
**Warning signs:** A build that only succeeds when Xcode's deployment target is bumped above
this project's documented floor — check this explicitly in CI, since the macOS runner's default
SDK may make the unavailable-API mistake compile successfully locally on a dev machine running a
recent OS while failing (or worse, silently crashing at the `#available` check on a real
iOS-13-floor device) elsewhere.

### Pitfall 5: `volumeAvailableCapacityForImportantUsageKey` returns 0 on non-APFS volumes
**What goes wrong:** A pre-flight free-space check using this key can report `0` available bytes
and refuse every compression, even with abundant real free space, if the destination filesystem
is not APFS.
**Why it happens:** `[CITED: multiple third-party bug reports/GitHub issues discussing this
exact key's APFS-only behavior, read this session — "APFS-only ... returns 0 on exFAT, NTFS and
SMB"; `volumeAvailableCapacityKey` (without "ForImportantUsage") returns the true figure on all
of them]` — this is a real, previously-reported footgun in other projects using the same key for
the same purpose.
**How to avoid:** Low risk for this phase specifically (the plugin's own default cache directory
is always on the app container's APFS volume on both iOS and macOS), but a caller-supplied
`outputPath` on macOS COULD point at a non-APFS external drive or network share — worth a
defensive fallback to `volumeAvailableCapacityKey` if the "important usage" key reports `0` while
the destination directory demonstrably exists and is writable, rather than trusting `0` as
ground truth. Flagged as a plan-time decision, not fully resolved here (see Open Questions).
**Warning signs:** A macOS-only integration test failure for the free-space pre-check that
doesn't reproduce on iOS or in CI's own runner (both APFS) — check the destination filesystem
type before assuming the pre-check logic itself is wrong.

### Pitfall 6: `AVError` case names in CONTEXT.md's prose do not exist
**What goes wrong:** A Swift `switch` over `AVError.Code` using `.decoderNotAvailable` or
`.encoderNotAvailable` fails to compile — no such case exists.
**Why it happens:** CONTEXT.md's error-mapping prose used plausible-sounding names by analogy
with the reason string `decoderUnavailable`/`encoderUnavailable` this project's OWN
`CompressVideoErrorReason` enum uses, rather than AVFoundation's actual case names.
**How to avoid:** The real names, confirmed via developer.apple.com documentation page URLs
surfaced in search results this session, are `AVError.Code.decoderNotFound` / `.encoderNotFound`
(no suitable codec) and `.decoderTemporarilyUnavailable` / `.encoderTemporarilyUnavailable` (one
exists but is momentarily busy) — both pairs map naturally onto this project's own
`decoderUnavailable`/`encoderUnavailable` reason strings; see the Code Examples section for the
full mapping table this phase's `ErrorMapping.swift` needs.
**Warning signs:** None at runtime — this is a compile-time-only pitfall, so it will be caught
immediately if hit, but worth flagging so the plan writes the CORRECT names the first time
rather than discovering the compiler error mid-implementation.

### Pitfall 7: `AVAssetReader.timeRange`'s exact keyframe/pre-roll behavior is unverified for THIS codec/GOP structure
**What goes wrong:** A trim assertion tighter than the reader's actual delivered-sample behavior
could fail even though the underlying mechanism is correct, if the reader vends a sample a few
milliseconds before or after the exact requested start due to keyframe alignment internals.
**Why it happens:** General AVFoundation guidance (search results, this session) describes the
reader seeking to a keyframe and vending forward from the requested start, but does not document
an exact contract for every codec/GOP-structure combination, and this project's own 34ms
(one-frame-at-30fps) tolerance is tight enough that "probably fine" is not good enough — 02-
RESEARCH.md's own equivalent finding for Android (Transformer's effect pipeline operating on
decoded vs. coded space) was ALSO something training/general knowledge got wrong until measured
live on the actual target.
**How to avoid:** Treat this as an Open Question requiring a live measurement against
`trim_source_10s.mp4` on the simulator before the plan can claim CORE-07 is proven, not before —
budget a task specifically for "compress with a 2000→7000ms trim and record the observed output
duration and first-frame content" as the actual verification step, not a documentation-only
claim.
**Warning signs:** A trim integration test that passes with generous tolerance but would fail if
tightened to the sidecar's own documented 34ms — that gap between "passes" and "proves the
mechanism is exact" is exactly what this pitfall describes.

### Pitfall 8: The simulator's H.264 encoder is software, same class of caveat as Android's emulator
**What goes wrong:** Elapsed-time-based assertions (e.g. "transmux completes in a fraction of
encode time") and bitrate-accuracy assertions calibrated for a hardware encoder both mis-fire on
the iOS Simulator, which uses a software H.264 encoder (well-established Apple platform
behavior; the Simulator does not have access to the host Mac's or a real device's hardware
Video Toolbox encode block for iOS-target builds).
**Why it happens:** Structurally identical to 02-RESEARCH.md's Pitfall 3/Pitfall 10 for the
Android emulator's software `c2.android.avc.encoder` — this is the same class of environment gap,
just on the other platform.
**How to avoid:** Document the same "measured, not assumed" caveat this project already applies
to `doc/PRESETS.md`'s Android section, extended with an Apple section generated from a REAL
simulator run (and, separately, a real macOS HOST run — the macOS build, unlike iOS Simulator
builds, DOES have access to real Video Toolbox hardware encode on Apple Silicon, since it isn't
a simulator at all) — `tool/measure_presets.dart` already exists and just needs to run on both.
**Warning signs:** A bitrate-accuracy tolerance tuned tight enough to pass on the macOS host
(hardware encoder) that then fails on the iOS Simulator (software encoder) or vice versa — the
plan should expect and document two different Apple-side tolerances if the two turn out to
diverge, exactly as Android's own emulator-vs-hardware gap (QUESTIONS.md #3) is still open.

### Pitfall 9: Package name for the free-disk-space key differs by exact spelling from the general-purpose one
**What goes wrong:** `volumeAvailableCapacityKey` (general) and
`volumeAvailableCapacityForImportantUsageKey` (importance-flagged) are easy to transpose or
confuse — different availability, different APFS-only caveat (Pitfall 5).
**How to avoid:** Use `volumeAvailableCapacityForImportantUsageKey` as CONTEXT.md's decision
specifies (it's the semantically-correct key for a user-initiated save, matching Apple's own
documented guidance for "things the user explicitly requested"), but be precise about the exact
name in code and comments — a typo'd key silently returns `nil` from `resourceValues`, not a
compile error.

## Code Examples

### Building the reader/writer pair for a real encode (composited from verified/cited pieces above)
```swift
// Sources: AVAssetReaderOutput.h (theos/sdks mirror, read this session) for the outputSettings
// width/height scaling keys; Apple forum/QA guidance on startSessionAtSourceTime: semantics,
// read this session, for the trim mechanism; CONTEXT.md's own locked decisions for the
// H.264/AAC output settings keys themselves (AVVideoAverageBitRateKey etc. are long-stable,
// unchanged-for-a-decade AVFoundation API -- [ASSUMED] from training knowledge, not re-verified
// this session since their shape has not changed since iOS 4).
let reader = try AVAssetReader(asset: asset)
if let trimRange { reader.timeRange = trimRange }  // Pattern 3

let videoOutputSettings: [String: Any] = [
  kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
  kCVPixelBufferWidthKey as String: codedTargetWidthPx,   // Pattern 2 -- no composition needed
  kCVPixelBufferHeightKey as String: codedTargetHeightPx,
]
let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoOutputSettings)
reader.add(videoReaderOutput)

let audioReaderOutput: AVAssetReaderTrackOutput? = audioTrack.map { track in
  // outputSettings: nil for passthrough (compressed samples); PCM settings dict for a
  // forced re-encode, decoded once here and re-encoded to AAC on the writer side.
  AVAssetReaderTrackOutput(track: track, outputSettings: passthroughOrPcmSettings)
}
if let audioReaderOutput { reader.add(audioReaderOutput) }

let writer = try AVAssetWriter(url: tempURL, fileType: .mp4)
let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
  AVVideoCodecKey: AVVideoCodecType.h264,
  AVVideoWidthKey: codedTargetWidthPx,
  AVVideoHeightKey: codedTargetHeightPx,
  AVVideoAverageBitRateKey: videoBitrateBps,
  AVVideoCompressionPropertiesKey: [
    AVVideoAverageBitRateKey: videoBitrateBps,
    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
    AVVideoExpectedSourceFrameRateKey: effectiveFps,  // hint only -- the reader loop itself
                                                       // still drops frames by PTS (CONTEXT.md's
                                                       // decision), this key does not cap fps by
                                                       // itself
  ],
])
videoWriterInput.transform = sourceTrack.preferredTransform  // rotation stays metadata-only
videoWriterInput.expectsMediaDataInRealTime = false
writer.add(videoWriterInput)

let audioWriterInput = AVAssetWriterInput(
  mediaType: .audio,
  outputSettings: audioMode == .passthrough ? nil : aacOutputSettings,
  sourceFormatHint: audioMode == .passthrough ? sourceFormatDescription : nil
)
writer.add(audioWriterInput)

writer.startWriting()
writer.startSession(atSourceTime: trimRange?.start ?? .zero)  // Pattern 3 -- no manual retiming
reader.startReading()

// requestMediaDataWhenReady(on:) loop per input, on a job-scoped serial DispatchQueue (Pattern 1)
```

### `ErrorMapping.swift`'s `AVError.Code` -> `CompressVideoErrorReason` table (Pitfall 6's correction)

`[CITED: developer.apple.com documentation page URLs surfaced in search results this session for
each case name below, cross-referenced against a mirrored SDK header's raw integer values for
the same cases — not independently confirmed against a live-rendered Apple doc page, hence CITED
rather than VERIFIED]`

```swift
// AVError.Code cases relevant to this phase (NOT an exhaustive list of AVError's ~40 cases --
// scoped to what a local-file reader/writer/export pipeline can plausibly surface):
//   .decoderNotFound                  (raw: AVErrorDecoderNotFound, -11833)
//   .encoderNotFound                  (raw: AVErrorEncoderNotFound, -11834)
//   .decoderTemporarilyUnavailable    (raw: AVErrorDecoderTemporarilyUnavailable, -11839)
//   .encoderTemporarilyUnavailable    (raw: AVErrorEncoderTemporarilyUnavailable, -11840)
//   .diskFull                         (raw: AVErrorDiskFull, -11807)
//   .fileFormatNotRecognized          (raw: AVErrorFileFormatNotRecognized, -11828)
//   .fileFailedToParse                (raw: AVErrorFileFailedToParse, -11829)
//   .exportFailed                     (raw: AVErrorExportFailed, -11820)
//   .decodeFailed                     (raw: AVErrorDecodeFailed, -11821)
//   .sessionNotRunning                (raw: AVErrorSessionNotRunning, -11803)
//   .outOfMemory                      (raw: AVErrorOutOfMemory, -11801)

func reasonForAVError(_ code: AVError.Code) -> String {
  switch code {
  case .decoderNotFound:
    return "decoderUnavailable"
  case .decoderTemporarilyUnavailable:
    return "decoderUnavailable"
  case .encoderNotFound:
    return "encoderUnavailable"
  case .encoderTemporarilyUnavailable:
    return "encoderUnavailable"
  case .diskFull:
    return "outOfSpace"
  case .fileFormatNotRecognized, .fileFailedToParse, .decodeFailed:
    return "unsupportedInput"
  case .exportFailed, .sessionNotRunning, .outOfMemory:
    return "io"
  default:
    return "unknown"
  }
}
```
A `reader.status == .failed` or `writer.status == .failed` with no `AVError`-typed underlying
error (some failures surface as a plain `NSError`) should fall back to `"io"` with the numeric
`NSError.code` folded into the message text, mirroring Android's `mapExportException`'s "always
preserve the numeric code" rule (02-06's own established pattern) exactly.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `AVAssetExportSession.progress` (polled) + `exportAsynchronously(completionHandler:)` | `states(updateInterval:)` (AsyncSequence) + `export(to:as:)` (async throws) | iOS 18/macOS 15 `[CITED, this session]` | This project's floor (iOS 13/macOS 11) is below the new API — the "old" approach is this phase's actual PRIMARY path for the transmux branch, not a fallback; the new API is an opportunistic enhancement on newer OSes only |
| `progress` deprecated further | Per a Mastodon post surfaced in search this session, `AVAssetExportSession.status`/`.progress` show deprecation warnings as of iOS 18 in Xcode; CONTEXT.md's own prose additionally cites "deprecated in iOS 27" | Ongoing (multiple Xcode releases have progressively strengthened the deprecation warning) | Confirms CONTEXT.md's instruction to never use it for a re-encode is correct regardless of the exact version the warning first appeared — the legacy API remains FUNCTIONAL through this project's full deployment range, just increasingly warned-against, which is why it is still this phase's real transmux-path mechanism below the iOS 18/macOS 15 floor |

**Deprecated/outdated:** `AVAssetExportSession.progress`/`.status`/`exportAsynchronously(completionHandler:)`
(deprecated but functional and REQUIRED below iOS 18/macOS 15, this project's actual floor).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `AVVideoAverageBitRateKey`/`AVVideoCompressionPropertiesKey`/`AVVideoProfileLevelKey` output-settings key shapes are unchanged from their long-stable (decade-plus) form | Code Examples | Very low — these are among the most stable, most-documented AVFoundation keys in the framework; if wrong, the writer's `canApply(outputSettings:forMediaType:)` pre-flight check (not yet wired into this research, worth a plan task) would catch it at construction time rather than mid-encode |
| A2 | `AVAssetReader.timeRange`'s delivered-sample start behavior is exact enough (or correctable with a small, measurable offset) to hit this project's 34ms/one-frame trim tolerance | Pattern 3, Pitfall 7 | Medium — if the reader's actual keyframe-seek behavior introduces a larger-than-one-frame offset, the plan needs an explicit "record the observed value against ground truth and document/correct it" task, the same shape of finding 01-07 already produced for `small_480p`'s duration delta; this is exactly why the Open Questions section below flags it as Mac-measurement-required rather than closed by this research |
| A3 | `volumeAvailableCapacityForImportantUsageKey` reporting `0` on a non-APFS destination is a low-probability edge case for THIS phase (default cache dir is always APFS; only a caller-supplied macOS `outputPath` to an external/network volume could trigger it) | Pitfall 5 | Low for phase completion (no corpus fixture or CI runner exercises a non-APFS destination); documented as a known limitation for RELS-02's README rather than blocking this phase, unless the plan decides to add the `volumeAvailableCapacityKey` fallback proactively |
| A4 | The AVError case names and raw values in the Code Examples table are accurate for the current iOS 26.2/macOS 26.6.2 SDK, not just historically | Code Examples, Pitfall 6 | Low-medium — these specific cases have existed with stable names since early AVFoundation versions per every source consulted; if any case name has since been renamed, the plan's XCTest error-mapping suite (mirroring `ErrorMappingTest.kt`) will fail to compile immediately, the same fail-fast property Android's `ErrorMapping.kt` port already has |

**If this table is empty:** N/A — see rows above. Every other claim in this research is either
[VERIFIED] (read directly from a live header on the target Mac or a live pub.dev API response
this session) or [CITED] (a specific developer.apple.com documentation page URL, a mirrored SDK
header, or a project-internal file read this session).

## Open Questions

1. **Exact `AVAssetReader.timeRange` first-delivered-sample offset for `trim_source_10s.mp4`'s
   specific GOP structure.**
   - What we know: the reader seeks to the preceding keyframe and vends samples from the
     requested start forward (general AVFoundation guidance, this session); `startSession(atSourceTime:)`
     computes output timestamps relative to the requested start automatically.
   - What's unclear: whether the FIRST video sample the reader actually delivers has a pts at or
     extremely close to the requested 2000ms mark, or whether there is a small, systematic,
     measurable offset for this project's specific x264-encoded GOP structure (the corpus's own
     `-g 30` keyframe interval matters here).
   - Recommendation: budget a dedicated verification task — compress `trim_source_10s.mp4` with
     the 2000→7000ms trim on the iOS simulator, record the actual output duration against the
     sidecar's `expectedDurationMs: 5000`/`toleranceMs: 34`, and document the delta in
     `corpus/README.md` alongside the already-open `small_480p` duration-delta note, rather than
     assume this passes from documentation alone (Pitfall 7).

2. **Whether the macOS host's real Video Toolbox hardware encoder and the iOS Simulator's
   software encoder produce meaningfully different bitrate-accuracy envelopes for `estimate()`.**
   - What we know: the iOS Simulator uses software H.264 encode (Pitfall 8); the macOS build
     target (not a simulator) has access to the host Mac's real Apple Silicon hardware encode.
   - What's unclear: whether this project's existing Android-emulator-derived ±75% tolerance
     comment in `compress_output_test.dart` needs a SEPARATE, tighter tolerance for the macOS
     host path, or whether one shared Apple tolerance covers both.
   - Recommendation: run `tool/measure_presets.dart` on both the simulator and the macOS host
     (CONTEXT.md's own INFO-03 decision already calls for this) and record BOTH numbers in
     `doc/PRESETS.md`'s new Apple section before deciding whether one tolerance or two are
     needed — the plan should not assume a single number without the two live measurements.

3. **Whether a defensive `volumeAvailableCapacityKey` fallback is warranted for the free-space
   pre-check, given the APFS-only limitation of the primary key (Pitfall 5).**
   - What we know: the "important usage" key returns 0 on non-APFS volumes; this phase's default
     cache directory is always APFS.
   - What's unclear: whether this project's threat model / CONTEXT.md's scope considers a
     caller-supplied macOS `outputPath` pointing at an external/network volume in-scope for this
     phase at all (it's not explicitly named in CONTEXT.md's decisions or deferred list).
   - Recommendation: treat as Claude's Discretion at plan time — a one-line defensive fallback is
     cheap to add; if the plan chooses not to, document the limitation in code comments and
     `RELS-02`'s eventual README "what this plugin deliberately does not do" section instead of
     leaving it silently unhandled.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `ssh dans-macbook-air` | All Apple-side verification | Yes `[VERIFIED, this session — used live to read framework headers]` | macOS 26.6.2, Xcode 26.2 | GitHub Actions `macos-latest` runner (already proven green in Phase 1/CI) |
| iOS Simulator runtime | iOS-side integration tests, XCTest | Yes | iOS 26.2 (iPhone 17/17 Pro/Air/16e, iPads) | none needed |
| Flutter SDK ≥3.44 on the Mac | All Apple-side `flutter` commands | **No** — `~/flutter` is 3.41.2, below this pubspec's floor | — | Install a second SDK at `~/development/flutter-stable` per CONTEXT.md's own locked decision (this phase's own first task) |
| CocoaPods | Local CocoaPods-path verification | **No** — confirmed absent, no Homebrew either, agents cannot `sudo` (QUESTIONS.md #7) | — | CI's `macos-latest` runner already proves the CocoaPods path (`--no-enable-swift-package-manager` builds, existing `apple` job); local Mac verification uses SPM only |
| `ffmpeg`/`ffprobe` on the Mac | Would be needed to generate `trim_source_10s.mp4` directly on the Mac | **No** | — | Generate the clip on danserver (ffmpeg 6.1.1 already installed, used for every other corpus clip) and push/sync it to the Mac like every other corpus asset — no local Mac generation needed |
| GitHub Actions (`apple` job, `macos-latest`) | BULD-05 (CI proof), the widened integration suite run | Yes, unblocked since 2026-09-21 | — | none needed; the repo is public, Actions minutes are uncapped |

**Missing dependencies with no fallback:** none block this phase.
**Missing dependencies with fallback:** Flutter ≥3.44 on the Mac (install second SDK, first task
of this phase per CONTEXT.md); CocoaPods locally (CI proves it instead); `ffmpeg` on the Mac
(generate corpus clips on danserver as already established).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `flutter test` (Dart unit, unchanged from Phase 1/2), XCTest via `xcodebuild test` (native unit — `RunnerTests.swift`, byte-identical on iOS/macOS per existing CI rule), `flutter test integration_test -d <simulator udid>` (iOS e2e) and `flutter test integration_test -d macos` (macOS desktop e2e, NEW this phase) — all wired by the existing `apple` CI job, which this phase widens rather than replaces |
| Config file | `example/ios/RunnerTests/RunnerTests.swift` + `example/macos/RunnerTests/RunnerTests.swift` (kept byte-identical by CI's existing `diff` step); no separate XCTest config beyond the existing Xcode scheme |
| Quick run command | `flutter test` (root Dart unit, seconds) |
| Full suite command | `cd example && flutter test integration_test -d <simulator udid>` (iOS, minutes) and `flutter test integration_test -d macos` (macOS, minutes) — both via `tool/mac_run.sh` once this phase lands it |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CORE-01 | Same call, same observable result on iOS/macOS | e2e | `flutter test integration_test/compress_test.dart -d <udid>` (existing file, platform skip removed) | Existing file, Wave 0 edit |
| CORE-07 | Trim exact within one frame, all platforms | e2e | `flutter test integration_test/compress_test.dart -d <udid>` — new 2000→7000ms case against `trim_source_10s.mp4` | Wave 0 (new corpus clip + test case) |
| BULD-02 | CocoaPods + SPM install, one shared Swift core | other (build inspection) | `tool/verify_fresh_app.sh` (new) — 4 builds (iOS/macOS × CocoaPods/SPM) | Wave 0 |
| BULD-04 | Example app: pick/compress/progress/cancel/play, all 3 platforms | widget + e2e + manual | `flutter test test/main_screen_test.dart` (new, fake `CompressVideo`) + running the app + a recorded simulator/macOS screenshot | Wave 0 |
| (parity, cross-cutting) | `CompressResult` fields match across platforms within documented tolerance | e2e + script | `flutter test integration_test/{compress,compress_audio,compress_jobs,compress_output}_test.dart` on Android/iOS/macOS + `tool/check_parity.sh` | Existing files (skip removed) + `check_parity.sh` extended for new fields |
| (native unit, cross-cutting) | `SizeGuard.swift` matches `SizeGuard.kt`'s numeric cases | unit | `xcodebuild test` — `SizeGuardTests.swift` (new, mirrors `SizeGuardTest.kt`) | Wave 0 |
| (native unit, cross-cutting) | `ErrorMapping.swift`'s `AVError` table is complete and correct (Pitfall 6) | unit | `xcodebuild test` — `ErrorMappingTests.swift` (new, mirrors `ErrorMappingTest.kt`) | Wave 0 |

### Sampling Rate

- **Per task commit:** `flutter test` (root, seconds) + `xcodebuild test` on whichever simulator
  is already booted locally, when working on the Mac
- **Per wave merge:** `flutter test integration_test -d <udid>` (iOS) AND `-d macos`, plus
  `tool/check_parity.sh` against a fresh Android emulator run
- **Phase gate:** Full CI `apple` job green (all suites, both build paths, fresh-app proof) AND
  `parity` job green (Android vs iOS vs macOS) before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `darwin/compress_video/Sources/compress_video/{SizeGuard,CompressionEngine,JobRegistry,ErrorMapping,PluginFiles,Compression}.swift` — the entire engine, none of it exists yet
- [ ] `example/ios/RunnerTests/RunnerTests.swift` + `example/macos/RunnerTests/RunnerTests.swift` — `SizeGuardTests`/`ErrorMappingTests` cases (kept byte-identical per existing CI rule)
- [ ] `corpus/trim_source_10s.mp4` + its `.expected.json` sidecar with the new `trim` block — `generate_corpus.sh`/`verify_corpus.sh --write` extension
- [ ] Platform-skip removal in all four `compress_*_test.dart` suites, plus new `PARITY_JSON` emission for `CompressResult` fields
- [ ] `tool/verify_fresh_app.sh` — the 4-build BULD-02 proof script
- [ ] `tool/mac_sync.sh` / `tool/mac_run.sh` — the Mac workflow scripts CONTEXT.md requires land first
- [ ] `example/lib/main.dart` rewrite + `test/main_screen_test.dart` (new widget test) — BULD-04
- [ ] `.github/workflows/ci.yml` `apple` job widening (drop the 2-suite allowlist, add the macOS integration run, add the dedicated SPM step if 01-06 didn't already land one) and `parity` job extension (compression fields)

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Local file-to-file plugin, no auth surface — unchanged from Phase 2's own finding |
| V3 Session Management | No | No sessions |
| V4 Access Control | No | Runs inside the host app's own sandbox (macOS additionally inside `com.apple.security.app-sandbox`, already enabled in the example's entitlements, read this session); no privilege boundary this plugin introduces |
| V5 Input Validation | Yes | `Arguments.swift`'s existing centralized, canonicalize-then-check pattern (already proven in Phase 1, read this session), extended with the same compress-specific validators Android's `Arguments.kt` grew in Phase 2 (trim range ordering, output-path parent-writable check — `Arguments.requireWritableOutputParent` already exists and needs no change) |
| V6 Cryptography | No | No cryptographic operations in this phase |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Path traversal via `outputPath`/trim manipulation | Tampering | Already mitigated by `Arguments.swift`'s existing `standardizedAbsolutePath` symlink-resolution pattern (Phase 1, read this session, mirrors Android's `canonicalFile`) — extend, don't fork, for any new compress-specific path handling |
| Resource exhaustion (unbounded job count / concurrent reader-writer pairs) | Denial of Service | Out of this phase's scope by CONTEXT.md (no queue/concurrency-limit until Phase 5, JOBS-03) — bounded on iOS by `detachFromEngine` cancelling every live job on plugin teardown; on macOS this bound is WEAKER (Pitfall 2/Pattern 5 — `handleWillTerminate` fires at app-quit, not at any earlier engine-teardown point), which the plan should note as a documented, accepted gap rather than silently assume parity with iOS |
| Disk-fill via repeated failed compressions leaving partial files | Denial of Service | CONTEXT.md's "every failure path deletes the partial file" decision, mirroring `PluginFiles.kt`'s `quietDelete` pattern in the new `PluginFiles.swift` |
| Free-space pre-check bypass on non-APFS destinations | Denial of Service (disk-fill) | Pitfall 5's `volumeAvailableCapacityForImportantUsageKey` APFS-only limitation — low severity for this phase's default cache-dir path, flagged as Open Question 3 for a caller-supplied `outputPath` |

## Sources

### Primary (HIGH confidence)
- `FlutterPluginMacOS.h`, `FlutterAppLifecycleDelegate.h` — read directly on `dans-macbook-air` this session via `~/flutter/bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework/macos-arm64_x86_64/FlutterMacOS.framework/Versions/A/Headers/`
- `FlutterPlugin.h` (iOS) — read directly on `dans-macbook-air` this session via `~/flutter/bin/cache/artifacts/engine/ios-profile/Flutter.xcframework/ios-arm64_x86_64-simulator/Flutter.framework/Headers/`
- `darwin/compress_video/Sources/compress_video/Messages.g.swift`, `Probe.swift`, `Arguments.swift`, `MediaMath.swift`, `CompressVideoPlugin.swift`, `Package.swift`, `darwin/compress_video.podspec` — all read this session from this repo
- `android/src/main/kotlin/com/danjjohnson/compress_video/{SizeGuard,ErrorMapping,TransformerEngine,JobRegistry,PluginFiles,Compression}.kt` — the parity oracle, all read this session
- `example/integration_test/{compress_test,media_info_test}.dart`, `tool/check_parity.sh`, `corpus/README.md`, `corpus/generate_corpus.sh`, `.github/workflows/ci.yml` — all read this session from this repo
- `https://pub.dev/api/packages/{image_picker,image_picker_macos,video_player}` and `/score` — fetched live this session
- `.planning/phases/02-android-compression-on-media3/02-RESEARCH.md`, `.planning/research/sources/VIDEO_COMPRESS_BRIEF.md`, `.planning/STATE.md`, `.planning/REQUIREMENTS.md` — all read this session

### Secondary (MEDIUM confidence)
- developer.apple.com documentation page titles/URLs for `AVError.Code.{decoderNotFound,encoderNotFound,decoderTemporarilyUnavailable,encoderTemporarilyUnavailable,diskFull,fileFormatNotRecognized,fileFailedToParse,exportFailed,sessionNotRunning}`, `AVAssetExportSession.states(updateInterval:)`, `AVAssetExportSession.export(to:as:)` — surfaced via WebSearch this session, page titles/existence confirmed but full rendered content not independently fetched (Apple's docs are JS-rendered and WebFetch returned only page titles)
- `github.com/theos/sdks` (`iPhoneOS9.3.sdk`/`iPhoneOS13.0.sdk` header mirrors) for `AVAssetReaderOutput.h` (resize keys) and `AVError.h` (raw integer values) — fetched this session; a third-party mirror of Apple's real SDK headers, not Apple's own hosting, hence CITED not VERIFIED
- Apple Developer Forums threads on `startSessionAtSourceTime:` semantics and `AVAssetReader.timeRange` keyframe behavior — read via search this session, corroborating but not a definitive spec document
- Swift Forums thread confirming `export(to:as:isolation:)`'s iOS 18/macOS 15 floor — read via search this session

### Tertiary (LOW confidence)
- General blog/StackOverflow-style guidance on `AVAssetReaderVideoCompositionOutput` resize patterns (used only to establish what NOT to do, per Pattern 2/Pitfall 3 — the recommendation itself rests on the theos/sdks header mirror, a Secondary source)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH for `image_picker`/`video_player`/`image_picker_macos` (all confirmed via
  live pub.dev API calls this session, including publisher and platform-support tags); HIGH for
  the podspec/`Package.swift` glob-pickup behavior (read directly from this repo's own committed
  manifests, no external claim involved)
- Architecture: HIGH for the two headline findings (macOS `detachFromEngine` absence; reader-side
  resize via output-settings keys) — both verified against live/mirrored primary sources this
  session, not carried over from training data; MEDIUM for the exact AVError case names and the
  export-API version floor (developer.apple.com URLs and page titles confirmed via search, but
  the full rendered doc page content was not independently fetched — WebFetch returned only
  titles for Apple's JS-rendered doc pages)
- Pitfalls: HIGH for the MainActor-blocking pattern (directly derivable from Messages.g.swift's
  own generated code, read this session) and the macOS teardown gap (same primary-source basis);
  MEDIUM for the exact `AVAssetReader.timeRange` keyframe/pre-roll behavior (Pitfall 7/Open
  Question 1) — this is explicitly flagged as requiring a live measurement on the Mac before the
  plan can close CORE-07, not resolved by this research alone

**Research date:** 2026-09-22
**Valid until:** 30 days for the AVFoundation API surface itself (stable, decade-plus API, very
low churn risk); re-verify the exact iOS 18/macOS 15 export-API floor and the AVError case names
against a live-rendered Apple doc page (not just search-surfaced titles) before or during
planning if a WebFetch-capable tool becomes available, since that portion of this research rests
on MEDIUM rather than HIGH confidence sourcing.
