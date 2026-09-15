---
phase: 02-android-compression-on-media3
plan: 02
subsystem: compression
tags: [pigeon, media3-transformer, kotlin, android-emulator, coroutines, tracer]

# Dependency graph
requires:
  - phase: 02-01
    provides: "corpus/portrait_hibitrate_1080p60.mp4 (the only corpus clip with a source bitrate above every preset this phase defines) and its expected.json sidecar (edgeProbe, thumbnailProbe, crossPlatform/tolerant blocks), mirrored into example/assets/corpus/"
provides:
  - "pigeons/messages.dart's compression half of the wire contract: AudioModeMessage, CompressRequestMessage, CompressResultMessage, EstimateMessage, CompressHostApi (startCompress/cancel/estimate/clearCache), CompressVideoFlutterApi.onProgress -- regenerated into all three languages"
  - "CompressVideoErrorReason's final shape: nine values, the original six plus encoderUnavailable/outOfSpace/interrupted, in that order"
  - "The published Dart compression API: CompressVideo.compress/estimate/clearCache, CompressOptions (preset/explicit-target/audio/trim/codec/hdr with full validate()), CompressResult, CompressEstimate, CompressJob (id/progress/result/cancel/isCancelled), kPresetSpecs seed constants -- no global progress stream, no in-flight singleton"
  - "A working single-preset compression on Android: one Transformer per job built/driven/cancelled entirely on the main Looper, a JobRegistry, PluginFiles' atomic-write helpers, and a re-probe-for-truth CompressResultMessage -- proven end to end against the corpus's high-bitrate clip"
affects: [02-03, 02-04, 02-05, 02-06, 02-07]

# Actuals (#2632)
actuals:
  tokens: 41500
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: ["androidx.media3:media3-transformer:1.11.1", "androidx.media3:media3-effect:1.11.1", "androidx.media3:media3-common:1.11.1", "androidx.media3:media3-muxer:1.11.1"]
  patterns:
    - "TransformerEngine.compress: a suspend fun that builds/starts a Transformer, registers a JobRegistry.LiveJob carrying a CompletableDeferred<ExportOutcome>, polls getProgress every 250ms via mainHandler.postDelayed, and awaits the deferred -- resolved from either terminal Transformer.Listener callback or JobRegistry.cancel's onCancelled callback. Nothing here ever switches dispatcher around a Transformer call; only the pre/post Probe calls leave the main thread, and both resume back onto it automatically."
    - "PluginFiles.kt centralises the cache-subdirectory/atomic-write/quiet-delete shapes Thumbnails.kt already established, so the compression engine's temp-file-then-rename pattern and Thumbnails' JPEG writer can never drift apart."
    - "CompressJob.start (lib/src/compress_job.dart) owns the entire async lifecycle of a job -- generating the id, calling startCompress, completing result/closing progress on every terminal path -- so CompressVideo.compress itself only validates, resolves the preset into a wire request, and delegates; no job-completion logic lives in two places."
    - "Kotlin doc comments that describe an intentional ABSENCE (\"we do not call setTransmuxAudio\", \"never Dispatchers.IO\", \"not a Future<CompressJob>\") must avoid the literal forbidden substring, because the plan's own acceptance-criteria greps are blunt substring matches over the whole file, comments included -- four such false positives were found and fixed by rephrasing (see Deviations)."

key-files:
  created:
    - android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/PluginFiles.kt
    - lib/src/presets.dart
    - lib/src/compress_options.dart
    - lib/src/compress_result.dart
    - lib/src/compress_job.dart
    - test/compress_options_test.dart
    - example/integration_test/compress_test.dart
  modified:
    - pigeons/messages.dart
    - lib/src/messages.g.dart
    - android/src/main/kotlin/com/danjjohnson/compress_video/Messages.g.kt
    - darwin/compress_video/Sources/compress_video/Messages.g.swift
    - lib/src/compress_video_exception.dart
    - test/compress_video_exception_test.dart
    - lib/compress_video.dart
    - android/build.gradle.kts
    - android/src/main/kotlin/com/danjjohnson/compress_video/CompressVideoPlugin.kt

key-decisions:
  - "The Media3 effect pipeline (Presentation, FrameDropEffect) operates on the DECODED, display-oriented frame, not the coded pre-rotation frame -- measured live on the emulator, resolving 02-RESEARCH.md's flagged ambiguity. Computing the Presentation target by swapping into 'coded space' for a 90deg-rotated input produced an incorrect 406px-wide output instead of the expected 720; passing MediaInfoMessage's own displayed dimensions straight through, with no swap, produced the correct 720x1280. TransformerEngine.kt documents this finding inline so no later plan re-derives it."
  - "MediaMath.normalizeCodec (Phase 1, unmodified per this plan's scope) only recognises video MIME tokens and has no AAC case, so reusing it for the result's audioCodec field silently reported 'unknown' for every real audio track. Added a small local normalizeAudioCodec in TransformerEngine.kt (audio/mp4a-latm -> aac) rather than extending MediaMath.kt, since AUDO-01/AUDO-02 (the requirements that own audio-codec normalisation properly) are out of this plan's scope."
  - "The never-larger post-check (usedOriginal) is implemented only as a post-encode byte comparison in this plan -- there is no pre-flight estimate short-circuit, since estimate()/SizeGuard are plan 02-07's scope. This is sufficient for CORE-02/CORE-03/JOBS-01/BULD-01 (this plan's requirements); CORE-05's full never-larger contract is 02-04's job."
  - "cancel() only best-effort-forwards to the native CompressHostApi.cancel and marks isCancelled; JobRegistry.cancel resolves the pending CompletableDeferred with a cancelled ExportOutcome so the suspended startCompress call actually returns rather than hanging. Full cancel-deletes-partial-output verification (JOBS-02) is 02-06's scope, not this plan's requirements list -- the mechanism exists and is wired, but is not separately integration-tested here."

patterns-established:
  - "Every native file the compression engine writes goes through PluginFiles' cache-subdir/temp-file/atomic-rename helpers, mirroring Thumbnails.kt exactly, so a future audio/video/muxer output path has one obvious place to write to."
  - "CompletableDeferred<ExportOutcome> (Success/Failure/Cancelled) is the bridge between Transformer's two possible terminal callbacks and JobRegistry's independent cancel path -- the shape any later Android engine change (SizeGuard's own async needs, trim, HDR) should reuse rather than inventing a second completion mechanism."

requirements-completed: []  # CORE-02 (also 02-01 [done]/02-03/02-04, both pending), CORE-03 (also 02-06, pending), JOBS-01 (also 02-06, pending), BULD-01 (also 02-07, pending). Verified via `gsd-tools query requirements.ready-ids`: 0/4 ready. The shared-ID gate (#2388) correctly withholds all four until every declaring plan finishes.

coverage:
  - id: D1
    description: "pigeons/messages.dart's compression contract (AudioModeMessage, CompressRequestMessage, CompressResultMessage, EstimateMessage, CompressHostApi, CompressVideoFlutterApi) regenerates deterministically into Dart/Kotlin/Swift, and CompressVideoErrorReason has exactly nine values with the original six unchanged and in order"
    requirement: "CORE-03"
    verification:
      - kind: other
        ref: "dart run pigeon --input pigeons/messages.dart && dart format lib/src/messages.g.dart && git diff --exit-code -- pigeons/messages.dart lib/src/messages.g.dart android/.../Messages.g.kt darwin/.../Messages.g.swift (run twice against the committed state; clean both times)"
        status: pass
      - kind: unit
        ref: "test/compress_video_exception_test.dart (enum shape/order + all 9 reasonFromPlatformCode round-trips)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The public Dart compression API exists, validates every documented invalid combination before crossing the channel, and CompressVideo.compress returns a CompressJob synchronously with no global progress stream or in-flight singleton anywhere in the package"
    requirement: "JOBS-01"
    verification:
      - kind: unit
        ref: "test/compress_options_test.dart (24 cases: every validate() rejection, channel-avoidance, job id format/uniqueness)"
        status: pass
      - kind: other
        ref: "grep -c 'CompressJob compress(' = 1, grep -c 'Future<CompressJob>' = 0, ! grep -REq 'compressProgress|isCompressing' lib/ succeeds"
        status: pass
    human_judgment: false
  - id: D3
    description: "Compressing portrait_hibitrate_1080p60.mp4 with default options produces a strictly smaller (4,454,349 -> 1,241,142 bytes), upright (720x1280) H.264+AAC MP4 with usedOriginal/transmuxed both false, a non-null audioCodec, a per-job progress stream reaching 100, and the input file provably untouched -- proven end to end on the real emulator, not mocked"
    requirement: "CORE-02"
    verification:
      - kind: e2e
        ref: "example/integration_test/compress_test.dart on emulator-5554 -- 1/1 pass"
        status: pass
      - kind: unit
        ref: "example/android ./gradlew :compress_video:testDebugUnitTest -- 37/37 pass (unchanged Phase 1 suite plus CompressVideoPluginTest's now-larger attach/detach wiring)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The CORE-03 flagged assumption this plan proceeds on -- every CompressResult field is non-null on every success path except audioCodec, which is null exactly when the audio track was stripped or absent -- is recorded here as an open question for verification, per the plan's own instruction, not closed by this plan"
    requirement: "CORE-03"
    verification: []
    human_judgment: true
    rationale: "02-02-PLAN.md explicitly flags this as an unresolved assumption the deterministic edge probe could not classify and instructs the executor to surface it, not resolve it by fiat. Whether some other CompressResult field can legitimately be unknown on some real device is a product/device-matrix question the corpus alone cannot answer; a human (or a later plan's broader device testing) should confirm or refute it."

# Metrics
duration: 49min
completed: 2026-09-15
status: complete
---

# Phase 2 Plan 02: Compression Contract, Dart API, and Working Tracer Summary

**The compression half of the Pigeon contract in all three languages, a validated Dart `compress`/`estimate`/`clearCache` API with per-job progress and no global state, and one real 8.7Mbps 60fps portrait clip compressed to a smaller upright 720x1280 H.264+AAC file via Media3 Transformer on the real Android emulator.**

## Performance

- **Duration:** 49 min
- **Started:** 2026-09-15T17:05:00-05:00 (approx.)
- **Completed:** 2026-09-15T17:54:00-05:00
- **Tasks:** 3 completed
- **Files modified:** 19 (10 created, 9 modified)

## Accomplishments
- Extended `pigeons/messages.dart` with the full compression contract (`AudioModeMessage`, `CompressRequestMessage`, `CompressResultMessage`, `EstimateMessage`, `CompressHostApi`, `CompressVideoFlutterApi`) and appended `encoderUnavailable`/`outOfSpace`/`interrupted` to `CompressVideoErrorReason`; regenerated all three language outputs, verified byte-identical on a second run, and confirmed only `Messages.g.swift` changed under `darwin/`
- Built the full published Dart type surface: `lib/src/presets.dart` (seed preset constants), `lib/src/compress_options.dart` (`CompressOptions.validate()` covering every documented invalid combination), `lib/src/compress_result.dart` (`CompressResult`/`CompressEstimate`), `lib/src/compress_job.dart` (`CompressJob` with its own progress stream, result future, cancel, and a per-job registry with no global state), and wired `CompressVideo.compress`/`estimate`/`clearCache` in `lib/compress_video.dart`
- Implemented the Android tracer: `PluginFiles.kt` (cache-dir/atomic-write helpers), `JobRegistry.kt` (main-thread-confined job map with a cancel path), `TransformerEngine.kt` (one `Transformer` per job, built/started/polled/cancelled entirely on the main Looper via a `CompletableDeferred`, inline preset-target resolution, full `ExportException` error-code mapping), and `Compression.kt` (`CompressHostApi` implementation asserting the main Looper and validating the job-id format on every call)
- Proved the whole path end to end on `emulator-5554`: compressing the high-bitrate corpus clip with default (`p720`) options produced a 1,241,142-byte output from a 4,454,349-byte input (72% smaller) in ~5.6s, upright at 720x1280, `usedOriginal`/`transmuxed` both `false`, a non-null `audioCodec`, a progress stream that reached 100, and the input file's length/mtime provably unchanged
- Found and fixed a real platform ambiguity flagged in advance by 02-RESEARCH.md and the plan itself: Media3's effect pipeline (`Presentation`) operates on the DECODED, display-oriented frame, not the coded pre-rotation frame -- discovered via a first failing emulator run (406px width instead of 720) and fixed by removing the coded-space swap entirely
- 37 native Gradle unit tests, 60 root Dart tests, and 26 emulator integration tests (9 media-info + 1 compress + 16 thumbnail, all pre-existing Phase 1 suites unaffected) all green

## Task Commits

1. **Task 1: Extend the Pigeon contract with the compression messages and the three new error reasons** - `a7efb9a` (feat)
2. **Task 2: The Dart type surface — options, presets, result, estimate and the job object** - `040f636` (feat)
3. **Task 3: Tracer — one call turns the high-bitrate corpus clip into a smaller upright MP4 on the emulator** - `a550ee4` (feat)

**Plan metadata:** (this commit, docs)

## Files Created/Modified
- `pigeons/messages.dart`, `lib/src/messages.g.dart`, `android/.../Messages.g.kt`, `darwin/.../Messages.g.swift` - Compression wire contract, regenerated
- `lib/src/compress_video_exception.dart`, `test/compress_video_exception_test.dart` - Nine-value error taxonomy
- `lib/src/presets.dart` - `PresetSpec`/`kPresetSpecs` seed constants
- `lib/src/compress_options.dart` - `CompressOptions`, presets/codec/hdr/audio enums, sealed `AudioOptions`, `validate()`
- `lib/src/compress_result.dart` - Immutable `CompressResult`/`CompressEstimate`
- `lib/src/compress_job.dart` - `CompressJob`, job registry, `CompressVideoFlutterApiImpl`, job id generator
- `lib/compress_video.dart` - `compress`/`estimate`/`clearCache`, shared request-building helper
- `test/compress_options_test.dart` - 24 validation/id-generation tests
- `android/build.gradle.kts` - Pinned media3 transformer/effect/common/muxer 1.11.1
- `android/.../PluginFiles.kt` - Cache-dir, atomic write/delete helpers
- `android/.../JobRegistry.kt` - Main-thread job map with cancel/cancelAll
- `android/.../TransformerEngine.kt` - The Transformer build/start/poll/cancel engine
- `android/.../Compression.kt` - `CompressHostApi` implementation
- `android/.../CompressVideoPlugin.kt` - Registers `CompressHostApi`, cancels live jobs on detach
- `example/integration_test/compress_test.dart` - The tracer's end-to-end proof

## Decisions Made
See `key-decisions` in frontmatter for the full list. Most consequential: the live-measured finding that Media3's effect pipeline works in display-oriented (not coded) space for a rotated input, which every later plan building on `TransformerEngine.kt` now inherits correctly documented rather than as a landmine.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The effect pipeline's coded-space swap produced a 406px-wide output instead of 720**
- **Found during:** Task 3, first emulator run of `compress_test.dart`
- **Issue:** The plan's own inline resolution instructed converting the target size to "coded space" (swapping width/height for a 90/270-degree input) before calling `Presentation.createForHeight`, reasoning that the effect pipeline operates on the coded, pre-rotation frame. On the real emulator, this produced a 406px-wide output (from `720 * 1080/1920` rounded) instead of the expected 720x1280 -- proof the effect pipeline actually receives the already-rotated, display-oriented frame.
- **Fix:** Removed the coded-space swap entirely; `resolveTarget` now computes the target directly from `MediaInfoMessage`'s own displayed `widthPx`/`heightPx`, with no space conversion. Re-ran: output came back exactly 720x1280.
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt`
- **Verification:** `example/integration_test/compress_test.dart` passes on `emulator-5554`
- **Committed in:** `a550ee4`

**2. [Rule 2 - Missing Critical] `audioCodec` reported `"unknown"` for every real audio track**
- **Found during:** Task 3, first passing emulator run (test only asserted non-null, but the actual value was semantically meaningless)
- **Issue:** `MediaMath.normalizeCodec` (Phase 1, unmodified) only recognises video MIME tokens (`video/avc`, `video/hevc`, etc.) and has no case for AAC's `audio/mp4a-latm`, so reusing it for the compression result's `audioCodec` field silently fell through to `"unknown"` for every audio track -- passing the letter of the plan's "non-null audioCodec" acceptance criterion while defeating the field's purpose.
- **Fix:** Added a small, local `normalizeAudioCodec` function inside `TransformerEngine.kt` (`audio/mp4a-latm` -> `"aac"`, else `"unknown"`) rather than extending `MediaMath.kt`, since `MediaMath.kt` is outside this plan's `files_modified` list and audio-codec normalisation properly belongs to the AUDO-01/AUDO-02 requirements of a later plan.
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt`
- **Verification:** Re-ran the tracer with a temporary debug print; confirmed `audioCodec=aac` (previously `unknown`)
- **Committed in:** `a550ee4`

**3. [Rule 3 - Blocking] Kotlin compile error: `CoroutineScope.cancel()` unresolved**
- **Found during:** Task 3, first `./gradlew :compress_video:compileDebugKotlin`
- **Issue:** `progressScope.cancel()` failed to resolve because `kotlinx.coroutines.cancel` (the extension function) was not imported alongside `CoroutineScope`/`SupervisorJob`/`Dispatchers`/`launch`.
- **Fix:** Added `import kotlinx.coroutines.cancel`.
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt`
- **Verification:** Gradle compile succeeds
- **Committed in:** `a550ee4`

**4. [Rule 1 - Bug] `CompressVideoPluginTest` broke: eager `Looper.getMainLooper()` in a plain JVM unit test**
- **Found during:** Task 3, first `./gradlew :compress_video:testDebugUnitTest`
- **Issue:** `Compression`'s default `engine: TransformerEngine = TransformerEngine(context)` parameter eagerly constructed `TransformerEngine`, whose `mainHandler` field called `Handler(Looper.getMainLooper())` at construction time -- which throws under the plain JVM unit test the existing `CompressVideoPluginTest` runs (no real Android `Looper` available, and the test never calls `compress()`).
- **Fix:** Made `mainHandler` a `by lazy` property, so `Looper.getMainLooper()` is only touched on first real use (inside `compress()`), not at `TransformerEngine` construction.
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt`
- **Verification:** `./gradlew :compress_video:testDebugUnitTest` -- 37/37 pass, including `CompressVideoPluginTest`
- **Committed in:** `a550ee4`

**5. [Plan authoring bug] Four acceptance-criteria greps flagged doc comments describing an intentional absence**
- **Found during:** Tasks 1 and 3, re-running the plan's own literal grep checks after writing correct documentation
- **Issue:** The same class of false positive as 02-01's documented plan-text discrepancies: a doc comment correctly explaining "this is NOT a `Future<CompressJob>`", "no `class CompressHostApi`" (Kotlin generates HostApis as `interface`, matching the existing `ProbeHostApi`/`ThumbnailHostApi` pattern -- not a regression), "do not declare `media3-exoplayer`", and "never `Dispatchers.IO`" each contain the literal substring the corresponding acceptance-criteria grep checks for zero/one occurrences of, over the whole file including comments.
- **Fix:** Rephrased each comment to preserve its meaning without the literal substring (e.g. "not a `Future<CompressJob>`" -> "returning a `CompressJob` synchronously, with no `Future` wrapping it"). Did not weaken or remove any of the documentation.
- **Files modified:** `lib/compress_video.dart`, `android/build.gradle.kts`, `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt`
- **Verification:** Every grep in the plan's acceptance criteria for both tasks now returns its expected count
- **Committed in:** `a7efb9a`, `a550ee4`

---

**Total deviations:** 5 auto-fixed (2 bugs found via real device behaviour, 1 missing-critical audio-codec mapping, 1 blocking compile error, 1 blocking test-infrastructure fix), plus 1 documented plan-authoring false-positive class (4 instances) fixed by rephrasing comments, not by weakening documentation.
**Impact on plan:** All fixes were necessary for correctness (items 1, 2), buildability (items 3, 4), or to make the plan's own literal acceptance criteria pass against real, correct code (item 5) rather than against a coincidentally-matching grep. No scope creep -- item 2's audio-codec fix stayed local to `TransformerEngine.kt` rather than touching `MediaMath.kt`, respecting this plan's stated file boundary.

## Issues Encountered

The Android emulator (`emulator-5554`, headless on danserver) crashed twice during this plan's execution with a segfault in its own crash-reporting handler, once mid-Gradle-build and once shortly after a successful boot. `dmesg`/`journalctl` confirmed the box's kernel OOM-killer fired around the same time, killing an unrelated Docker container (`sqlservr`) on this shared, multi-agent host -- consistent with genuine system-wide memory pressure from other concurrent agent sessions, not a bug in this plan's code. Both times, relaunching the emulator (`sg kvm -c 'emulator -avd compress_video_api35 ...'`) and re-running the test succeeded. No code change was made in response to this; it is recorded here per the "verify before claiming done" contract, not as a deviation.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The Pigeon compression contract, the Dart type surface, and the proven `TransformerEngine`/`JobRegistry`/`PluginFiles`/`Compression` architecture are all in place; every remaining plan in this phase (02-03 `SizeGuard` and the full preset/target/never-larger math, 02-04 measuring real presets, 02-05 audio, 02-06 cancel/error-mapping depth, 02-07 estimate/clearCache) extends this shape rather than re-deciding it.
- **CORE-03's flagged assumption is still open** (see coverage D4): every `CompressResult` field is assumed non-null except `audioCodec`. This should be confirmed or refuted before the phase closes, ideally during 02-06's error-mapping work or a broader device pass.
- `CORE-02`, `CORE-03`, `JOBS-01`, `BULD-01` remain unchecked in `REQUIREMENTS.md` -- all four are shared with sibling plans still pending in this phase (verified via `gsd-tools query requirements.ready-ids`: 0/4 ready). The shared-ID gate correctly withholds marking any of them `Complete` until every declaring plan finishes.
- Ready for `02-03-PLAN.md` (`SizeGuard`: the full preset/explicit-target/target-size resolution this plan's inline version was always meant to be replaced by).

---
*Phase: 02-android-compression-on-media3*
*Completed: 2026-09-15*

## Self-Check: PASSED

- FOUND: all 10 created files and all 9 modified files listed above (verified with `[ -f ]`)
- FOUND commits: a7efb9a, 040f636, a550ee4 (all present in `git log --oneline --all`)
- Re-ran plan-level verification after all fixes: `dart run pigeon` + `dart format` twice -> byte-identical, working tree clean against committed state; `git status --porcelain darwin/ | grep -v Messages.g.swift` -> empty
- `flutter test` (root, 60/60 pass), `flutter analyze --fatal-infos --fatal-warnings` (root and example/, both clean), `dart format --output=none --set-exit-if-changed .` (0 changed)
- `example/android && ./gradlew :compress_video:testDebugUnitTest`: 37/37 pass
- `example/integration_test` on `emulator-5554`: 26/26 pass (9 media-info + 1 compress + 16 thumbnail)
- All acceptance-criteria grep checks for all three tasks re-verified against final committed files
- `git status --short` clean at every commit boundary
