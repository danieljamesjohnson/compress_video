# Phase 3: Apple Compression to Parity - Context

**Gathered:** 2026-09-22
**Status:** Ready for planning
**Mode:** Smart discuss, autonomous run — recommended answers auto-accepted (unattended). Every decision below is a default Dan can override.

<domain>
## Phase Boundary

On iOS and macOS, the same `CompressVideo.compress` / `estimate` / `clearCache` calls Phase 2
delivered on Android produce the same observable result: a smaller, upright H.264/AAC MP4 with a
typed `CompressResult`, presets and explicit targets, never-larger, transmux fast path, frame-rate
cap, audio passthrough / re-encode / strip, per-job progress and cancel, typed errors, and the
pre-flight estimate — all through the existing Pigeon contract (`CompressHostApi`,
`CompressVideoFlutterApi`), with **no wire-format change**. Trim is honoured exactly on all three
platforms (CORE-07). The package installs through both CocoaPods and SPM from one shared Swift
core (BULD-02), and the example app becomes a real picker → options → progress → cancel → play
app on Android, iOS and macOS (BULD-04).

Requirements in scope: CORE-01, CORE-07, BULD-02, BULD-04.

Out of scope here: HEVC / HDR keep / tone-mapping / 5.1 (Phase 4 — but `videoCodec: "h264"` and
`hdrMode: "toneMapToSdr"` must be validated and rejected-if-other exactly as Android does);
queueing, isolates, foreground service, iOS interruption semantics (Phase 5 — `interrupted` is
NOT thrown in this phase; an `AVAssetWriter` failure during backgrounding maps to `io` for now,
documented); compat shim and pub.dev (Phase 6). Phase 2's outstanding UAT items (02-UAT.md) are
not this phase's work, except where a Phase 3 fixture incidentally closes one.

Environment at discuss time (2026-09-22), verified live over `ssh dans-macbook-air`:
- MacBook Air M4, 16 GB, macOS 26.6.2, **Xcode 26.2**, iOS 26.2 simulator runtime with iPhone 17 /
  17 Pro / Air / 16e and iPad simulators available, 31 GB free disk.
- **Flutter on the Mac is 3.41.2 stable at `~/flutter`** — BELOW this package's pubspec floor
  (`flutter: '>=3.44.0'`, `sdk: ^3.12.1`). `flutter pub get` will refuse the package until a newer
  SDK is used. See "Mac build workflow" below for the decision.
- **No CocoaPods, no Homebrew** on the Mac (QUESTIONS.md #7, needs Dan's password). Local Apple
  builds use the SPM path; CI's `macos-latest` runner proves CocoaPods.
- **The Mac cannot reach the danserver bare repo** (`git@danserver...: Permission denied`), but
  `git ls-remote https://github.com/danieljamesjohnson/compress_video.git` works (repo is public).
  `rsync`, `git`, `jq`, `perl` are present; **no `ffmpeg`/`ffprobe`** on the Mac.
- GitHub Actions is unblocked (repo public since 2026-09-21); the `apple` job is path-gated and
  currently runs only `media_info_test.dart` + `thumbnail_test.dart` on the simulator, with the
  Phase 2 `compress_*_test.dart` suites explicitly excluded (they hang on iOS today because no
  Swift `CompressHostApi` exists). This phase must widen that.
- Android is the reference implementation: `TransformerEngine.kt` (738 lines), `SizeGuard.kt`
  (pure plan resolution), `JobRegistry.kt`, `ErrorMapping.kt`, `PluginFiles.kt`, `Compression.kt`.
  Phase 2 is `executed` with human verification deferred (02-UAT.md, 6 items); its code is the
  parity oracle for this phase.
- The corpus's longest clip is 4 s (`portrait_rot90`, `portrait_hibitrate_1080p60`); success
  criterion 2 (trim 2000→7000 ms) is **unsatisfiable with the current corpus** — a longer
  generated clip is required (see Trim decisions).

</domain>

<decisions>
## Implementation Decisions

### Apple engine architecture and Android parity
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

### Trim exactness and the corpus
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

### Mac build workflow, packaging and CI
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

### Example app (BULD-04)
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

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `darwin/.../Probe.swift`, `Thumbnails.swift`, `Arguments.swift`, `MediaMath.swift` (Phase 1):
  the Swift probe already normalises codecs, resolves displayed dims from
  `preferredTransform`, and has the path-validation / `CompressVideoError` throwing pattern
  (WR-01 symlink resolution) to reuse for `Compression.swift`.
- `darwin/.../Messages.g.swift`: `CompressHostApi` protocol, `CompressHostApiSetup`,
  `CompressVideoFlutterApi.onProgress` are ALREADY generated (Phase 2 regenerated all three
  outputs) — only the implementation and its registration in `CompressVideoPlugin.swift`
  are missing.
- Android reference: `SizeGuard.kt` (rules 1-7, port verbatim), `TransformerEngine.kt`
  (`finishSuccess`, `resolvePlan`, `buildSizeGuardInput/Options`, `mapExportException`),
  `JobRegistry.kt`, `ErrorMapping.kt` (22-code table), `PluginFiles.kt` (`cacheSubDir`,
  `sweep`), `Compression.kt` (`requireValidJobId`, main-thread rules).
- Tests: `example/integration_test/compress_{,audio,jobs,output}_test.dart` (3,288 lines)
  are the parity suite — they currently `skip` on non-Android at the top of each file; the
  phase's definition of done is removing those skips and passing on the simulator and on
  macOS. `SizeGuardTest.kt`, `EffectOrderTest.kt`, `ErrorMappingTest.kt` are the XCTest
  templates. `example/{ios,macos}/RunnerTests/RunnerTests.swift` are byte-identical by CI
  rule — new Swift unit tests go there, in both copies.
- Corpus: `corpus/generate_corpus.sh`, `verify_corpus.sh --write`, `sync_to_example.sh`, and
  the `example/pubspec.yaml` asset list (must gain the new clip + sidecar).
- Parity: `tool/check_parity.sh` + `tool/check_parity_test.sh`, the `PARITY_JSON` line
  convention, and the CI `parity` job (01-07).
- Measurement: `tool/measure_presets.dart` regenerates `doc/PRESETS.md`; run it on the
  simulator and macOS for an Apple section.

### Established Patterns
- Units in field names; nullable = unknown; native throws `CompressVideoError(code: <reason>)`;
  Dart wraps to `CompressVideoException`; all host methods `@async`, work off the platform
  thread, replies on it.
- Never-larger is unconditional on every delivered file (Phase 2 lane note); the transmux
  fast path must not be exempted.
- Measure, don't assume: preset outputs, tolerances and platform deltas are recorded from
  real runs into `doc/PRESETS.md` / `corpus/README.md`, with the emulator/simulator caveat
  stated.
- STATE.md / ROADMAP.md / REQUIREMENTS.md are hand-edited only; commit per task; push to
  both `origin` and `github`.
- CI's `reactivecircus` `script:` lines are separate shells; macOS steps use perl `alarm`,
  not GNU `timeout`.

### Integration Points
- `CompressVideoPlugin.swift`: register `CompressHostApiSetup.setUp(binaryMessenger:api:
  Compression(...))` and construct `CompressVideoFlutterApi(binaryMessenger:)` for progress;
  add `detachFromEngine(for:)` to cancel live jobs.
- `.github/workflows/ci.yml` `apple` job (suite allowlist, SPM step, fresh-app step, macOS
  integration run) and `parity` job (compress records, macOS-vs-iOS).
- `example/lib/main.dart` (rewrite), `example/pubspec.yaml` (assets, `image_picker`,
  `video_player`), `example/ios/Runner/Info.plist`, `example/macos/Runner/*.entitlements`.
- `.claude/CLAUDE.md` lane notes: Mac second-SDK recipe, `tool/mac_sync.sh` / `mac_run.sh`
  usage, simulator UDIDs.
- `QUESTIONS.md` #7 stays open (CocoaPods on the Mac); nothing in this phase needs it locally.

</code_context>

<specifics>
## Specific Ideas

- The phase's headline proof is mechanical, not narrative: the SAME four `compress_*_test.dart`
  suites, unmodified except for removing the platform skip and adding the trim/parity records,
  green on the Android emulator, the iOS simulator and the macOS host, plus a green `parity`
  job diffing their `PARITY_JSON` records.
- Port `SizeGuard.kt` line-for-line and prove it with the same numbers: if
  `SizeGuardTest.kt` has a case `(input, options) -> plan`, `SizeGuardTests.swift` has the
  identical case. Estimate/behaviour parity across platforms then follows from one function
  existing twice with the same tests, not from hope.
- Take a screenshot of the example app mid-compression and after playback on the iOS
  simulator (`xcrun simctl io <udid> screenshot`) and on macOS (`screencapture` over SSH
  may need screen-recording permission — if it does, record that as a QUESTIONS.md item and
  fall back to the simulator screenshot only), commit them under the phase directory, and
  reference them from 02-UAT.md #6.
- Be explicit in the dartdoc and README-facing docs about what "same observable result"
  means: same dimensions, codec, flags and duration; DIFFERENT bytes and elapsed time
  because the encoders differ. Do not promise byte parity.

</specifics>

<deferred>
## Deferred Ideas

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

</deferred>
