---
phase: 01-typed-contract-ci-and-media-info
plan: 05
subsystem: thumbnails
tags: [pigeon, kotlin, mediametadataretriever, android-emulator, ci, coroutines, jpeg]

# Dependency graph
requires:
  - phase: 01-01
    provides: Android SDK + headless KVM emulator on danserver, GitHub remote, CI on Linux+macOS
  - phase: 01-02
    provides: portrait_rot90.mp4 corpus clip with its thumbnailProbe sidecar block (position, displayed patch coordinates, expected RGB, tolerance) and noaudio_720p.mp4 for the concurrency case
  - phase: 01-04
    provides: "pigeons/messages.dart's ThumbnailHostApi (declared in full, unimplemented until now); Probe.kt/MediaMath.kt/Arguments.kt's suspend-fun-on-Dispatchers.IO + centralised-validation shape, reused directly by Thumbnails.kt; CI's emulator integration step, which now also runs this plan's suite"
provides:
  - "CompressVideo.getThumbnail(path, {positionMs, quality, maxDimensionPx}): Uint8List JPEG bytes for the frame at an exact millisecond, rotation-correct, proven end-to-end on the real Android emulator by pixel-sampling the corpus's colour-patch schedule"
  - "CompressVideo.getThumbnailFile(path, {positionMs, quality, maxDimensionPx, outputPath}): same frame, written atomically to a unique cache-directory name or a caller-chosen path, never touching the input file"
  - "Thumbnails.kt: the ThumbnailHostApi implementation, registered/torn down in CompressVideoPlugin alongside Probe"
  - "MediaMath.scaledSize/clampPositionMs: pure, unit-tested longer-side cap (never upscales) and duration clamp, reusable by 01-06's Swift Thumbnails"
  - "Arguments.validatePositionMs/validateQuality/validateMaxDimensionPx/validateOutputPath/requireValidThumbnailArgs/requireWritableOutputParent: native-side thumbnail argument validation mirroring the Dart-side checks"
  - "37 native JUnit tests (up from 16), 31 root Dart tests (up from 20), 25 emulator integration tests (up from 9) -- all green"
affects: [01-06, 01-07]

# Actuals (#2632)
actuals:
  tokens: 15394
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One frame-extraction-and-encode helper (Thumbnails.extractThumbnailJpeg) shared by getThumbnail and getThumbnailFile, so bytes-vs-file is purely a difference in what happens to the resulting JPEG bytes -- unit handling (the single positionMs*1000 conversion, the clamp, the scale) can never drift between the two entry points."
    - "Atomic file writes: write to a temp file beside the destination, File.renameTo() into place, delete the temp file on every failure path. Applies to any future native file-writing call in this plugin (compression output in Phase 2 will want the same shape)."
    - "MediaMetadataRetriever.getScaledFrameAtTime's dstWidth/dstHeight are a fit-within bounding box (scaled by whichever dimension is more constraining), not independent exact targets -- confirmed live on the emulator, not from documentation. A target box that isn't perfectly proportional (ours rounds width and height separately) can come back a pixel off in the non-constraining dimension. Fixed by unconditionally snapping the decoded frame to the exact MediaMath.scaledSize dimensions with one Bitmap.createScaledBitmap pass, on both the API 27+ and pre-27 code paths -- this is now the pattern for any future scaled-decode call on this platform."
    - "Native-side validation mirrors Dart-side validation deliberately (Arguments.kt's four pure validators + requireValidThumbnailArgs): the Dart side gives a fast local failure without crossing the channel; the native side is the authority for any caller that reaches the generated host API another way."

key-files:
  created:
    - android/src/main/kotlin/com/danjjohnson/compress_video/Thumbnails.kt
    - example/integration_test/thumbnail_test.dart
    - test/thumbnail_api_test.dart
  modified:
    - lib/compress_video.dart
    - android/src/main/kotlin/com/danjjohnson/compress_video/CompressVideoPlugin.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/MediaMath.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/MediaMathTest.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/ArgumentsTest.kt
    - example/lib/main.dart

key-decisions:
  - "positionMs < 0 is unsupportedInput (no frame before the start of a clip is a caller bug, not something to silently clamp); positionMs > durationMs clamps to the last frame via MediaMath.clampPositionMs (duration reporting is approximate and both platforms' own frame APIs already clamp); quality must be 1-100 inclusive; maxDimensionPx caps the longer displayed side, never upscales, and must be positive when given; unique thumbnail names are compress_video_thumb_<epoch millis>_<8 random hex>.jpg inside a compress_video subdirectory of the app cache directory -- all exactly as CONTEXT.md's open decisions were resolved in the plan."
  - "MediaMetadataRetriever.getScaledFrameAtTime's dst width/height are a fit-within bounding box, not independent exact targets (found live on the emulator: a maxDimensionPx=1919 request returned height 1918, not 1919, because our independently-rounded target box wasn't perfectly proportional to the source aspect ratio and the retriever's box-fit picked the more-constraining dimension). Fixed by always snapping the decoded frame to the exact target size with an explicit Bitmap.createScaledBitmap pass, on every API level -- this makes MediaMath.scaledSize's pure-math contract exactly what callers observe, regardless of platform decode-box semantics."
  - "getThumbnail and getThumbnailFile's Dart method signatures and shared validation helper were both written in Task 1's commit (they share one _validateThumbnailArgs helper and one exception-wrapping pair), even though getThumbnailFile's native implementation didn't land until Task 2. This kept the Dart-side validation logic as one cohesive, non-duplicated unit rather than splitting it across two commits."

patterns-established:
  - "Atomic destination writes (temp file + renameTo, delete-on-failure, never touching the source) -- the shape any future file-producing native call (compression output) in this plugin should reuse."
  - "Native validation mirrors Dart validation as defense-in-depth, not duplication for its own sake: the native functions are pure and independently unit-tested, and are the authority for non-Dart callers of the generated host API."

requirements-completed: []  # INFO-02 is also declared by 01-06-PLAN.md and 01-07-PLAN.md, both still pending in this phase. Verified via `gsd-tools query requirements.ready-ids`: INFO-02 reports blocked, not ready -- the shared-ID gate (#2388) correctly withholds marking it Complete until every declaring plan finishes, exactly as 01-04-SUMMARY.md documented for BULD-03/INFO-01/BULD-05.

coverage:
  - id: D1
    description: "getThumbnail returns upright, rotation-correct JPEG bytes for the exact requested millisecond on Android: positionMs is converted to microseconds at exactly one point, the exact-frame decode option (OPTION_CLOSEST) is used rather than the nearest-keyframe option, and the retriever's own rotation correction is trusted (no hand-rolled rotation math). Proven by decoding the returned JPEG and pixel-sampling the corpus's colour-patch schedule: the 1500ms sample matches the sidecar's expectedRgb within tolerance and the 1000ms sample differs from it in at least one channel."
    requirement: "INFO-02"
    verification:
      - kind: e2e
        ref: "example/integration_test/thumbnail_test.dart, 'getThumbnail of the portrait clip at the sidecar position is upright, at the sidecar moment' + 'getThumbnail at a different moment samples a different colour...' -- both pass on emulator-5554"
        status: pass
      - kind: manual_procedural
        ref: "example/lib/main.dart's new thumbnail panel, run on emulator-5554 and screenshotted: the 1500ms thumbnail renders upright with the burnt-in '1500ms' timecode legible and the expected yellow colour band visible at the probe patch location"
        status: pass
    human_judgment: false
  - id: D2
    description: "getThumbnailFile writes the same JPEG atomically (temp file + renameTo) to a unique compress_video_thumb_<epoch millis>_<8 random hex>.jpg name inside the app cache directory by default, or exactly to a caller-supplied outputPath after canonicalising it and requiring an existing, writable parent directory (io reason otherwise, no partial file left behind). The input file is never opened for writing on any code path, including every failure path -- proven by asserting its length and modification time are unchanged after every thumbnail call in the suite."
    requirement: "INFO-02"
    verification:
      - kind: e2e
        ref: "example/integration_test/thumbnail_test.dart: uniqueness (two different, simultaneously-existing files), default-destination-in-cache-dir, explicit-outputPath-honoured, missing-parent-directory-yields-io-with-no-file-left-behind, and input-file-untouched cases -- all pass on emulator-5554"
        status: pass
      - kind: unit
        ref: "android/src/test/kotlin/.../ArgumentsTest.kt: requireWritableOutputParent_missingParentDirectory_rejectedAsIo, requireWritableOutputParent_existingWritableParent_returnsCanonicalPath"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every boundary, scaling, quality, error and concurrency case in the thumbnail contract is asserted: positionMs exactly at duration returns a valid frame and well beyond it clamps to the same frame (MediaMath.clampPositionMs, pinned by a JVM unit test and an emulator test); maxDimensionPx at/below/above the longer displayed side (native size / proportional downscale / never upscale, MediaMath.scaledSize); a lower quality produces a strictly smaller JPEG; a zero-byte file and a text file both yield unsupportedInput and a missing path yields fileNotFound; two getThumbnailFile calls on two different clips started with Future.wait both complete and produce two different files. Dart-side validation for both calls is proven to never cross the platform channel for a rejected argument (a mock handler fails the test if invoked), and native-side Arguments validators mirror the same four checks as the authority for non-Dart callers."
    requirement: "INFO-02"
    verification:
      - kind: e2e
        ref: "example/integration_test/thumbnail_test.dart, 10 additional cases -- 25 total integration tests, all pass on emulator-5554"
        status: pass
      - kind: unit
        ref: "android/src/test/kotlin/.../MediaMathTest.kt + ArgumentsTest.kt, 21 additional cases -- 37 total native JUnit tests, all pass"
        status: pass
      - kind: unit
        ref: "test/thumbnail_api_test.dart, 11 tests: every rejection case fails the test if the ThumbnailHostApi channel is invoked"
        status: pass
    human_judgment: false
  - id: D4
    description: "CI stays green with the new thumbnail suite added to the same emulator integration step 01-04 wired, and the unaffected Apple job (iOS simulator + macOS via CocoaPods and SPM) still passes on the same run."
    requirement: "BULD-05"
    verification:
      - kind: e2e
        ref: "gh run view 35002031136 -> conclusion success; Android job's Analyze/Pigeon-regen/Gradle-unit-tests/emulator-integration/corpus-verify/dry-run-publish/build-apk steps and the Apple job's iOS+macOS CocoaPods and SPM builds all completed success"
        status: pass
    human_judgment: false

# Metrics
duration: 47min
completed: 2026-09-15
status: complete
---

# Phase 1 Plan 05: Android Thumbnails Summary

**Both thumbnail calls (`getThumbnail`, `getThumbnailFile`) working end-to-end on the Android emulator, rotation-correct at an exact requested millisecond, with every boundary, scaling, quality, uniqueness, error and concurrency case in the contract proven by 25 emulator integration tests and 37 native unit tests, CI green.**

## Performance

- **Duration:** 47 min
- **Started:** 2026-09-15T17:00:00Z (approx.)
- **Completed:** 2026-09-15T17:47:00Z
- **Tasks:** 3 completed
- **Files modified:** 10 (3 created, 7 modified)

## Accomplishments

- Wrote `Thumbnails.kt`: one `extractThumbnailJpeg` helper shared by both `getThumbnail` and `getThumbnailFile`, off the platform thread via `Dispatchers.IO` exactly as `Probe.kt` does. `positionMs` is converted to microseconds at exactly one point in the file; the exact-frame decode option (`OPTION_CLOSEST`) is used instead of the nearest-keyframe option, so the returned frame is the one at the requested moment, not a preceding sync frame. No hand-rolled rotation math — the retriever's own rotation correction is trusted and proven by pixel-sampling the corpus's colour-patch schedule on the real emulator.
- Found and fixed a real platform quirk that only showed up on-device: `MediaMetadataRetriever.getScaledFrameAtTime`'s `dstWidth`/`dstHeight` act as a fit-within bounding box (scaled by whichever dimension is more constraining), not independent exact targets. A `maxDimensionPx=1919` request came back as height 1918, not 1919, because the independently-rounded target box wasn't perfectly proportional to the source aspect ratio. Fixed by unconditionally snapping the decoded frame to the exact `MediaMath.scaledSize` dimensions with one `Bitmap.createScaledBitmap` pass on every API level, making the pure-math contract exactly what callers observe.
- `getThumbnailFile` writes atomically: a temp file beside the destination, `File.renameTo()` into place, deleted on every failure path — a failure mid-write never leaves a truncated JPEG, and the input video is never opened for writing on any code path (asserted by checking its length and modification time are unchanged after every call in the suite).
- `MediaMath.scaledSize` (longer-side cap, never upscales, null-safe) and `MediaMath.clampPositionMs` (past-end clamps to the last frame, exactly-at-duration passes through) are pure, unit-tested, and reused by the single `Thumbnails.kt` call site.
- `Arguments.kt` gained four pure thumbnail validators plus `requireValidThumbnailArgs` and `requireWritableOutputParent`, mirroring the Dart-side checks in `lib/compress_video.dart` as the authority for any caller reaching the generated host API another way.
- 37 native JUnit tests (up from 16), 31 root Dart tests (up from 20, including the new `test/thumbnail_api_test.dart` which fails if a rejected argument ever reaches the channel), and 25 emulator integration tests (up from 9) — all green, first try after the one platform-quirk fix above.
- CI stayed green on the same run that added this suite to the emulator integration step 01-04 wired: run `35002031136`, both Android and Apple jobs `success`.

## Task Commits

1. **Task 1: getThumbnail — upright JPEG bytes at an exact millisecond position** - `61e9cbe` (feat)
2. **Task 2: getThumbnailFile — unique names, cache placement and a caller-chosen output path** - `5b0222b` (feat)
3. **Task 3: Boundary, scaling, quality and concurrency contract, with pure-logic unit tests** - `9552543` (feat)

**Plan metadata:** (this commit, docs)

## Files Created/Modified

- `android/src/main/kotlin/com/danjjohnson/compress_video/Thumbnails.kt` - `ThumbnailHostApi` implementation: frame extraction, scaling, encode, atomic file write
- `lib/compress_video.dart` - `getThumbnail`/`getThumbnailFile`, shared Dart-side validation and exception-wrapping helpers
- `android/src/main/kotlin/com/danjjohnson/compress_video/CompressVideoPlugin.kt` - Registers/tears down `Thumbnails` alongside `Probe`
- `android/src/main/kotlin/com/danjjohnson/compress_video/MediaMath.kt` - `scaledSize`, `clampPositionMs`
- `android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt` - Thumbnail argument validators, `requireValidThumbnailArgs`, `requireWritableOutputParent`
- `android/src/test/kotlin/.../MediaMathTest.kt`, `ArgumentsTest.kt` - 21 new native unit tests
- `example/integration_test/thumbnail_test.dart` - 25 emulator integration tests (orientation, moment, uniqueness, cache/outputPath, boundary, scaling, quality, errors, concurrency)
- `test/thumbnail_api_test.dart` - Dart-side validation, asserts the channel is never invoked for a rejected argument
- `example/lib/main.dart` - Renders the portrait clip's 1500ms thumbnail beneath the media-info fields

## Decisions Made

See `key-decisions` in frontmatter. Most consequential: the live-verified `getScaledFrameAtTime` fit-within-box behaviour (not documented anywhere I found — discovered by a real test failure on the emulator) and its fix, which now guarantees every thumbnail's dimensions exactly match `MediaMath.scaledSize`'s pure-math contract regardless of platform decode-box semantics.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `MediaMetadataRetriever.getScaledFrameAtTime`'s dst width/height are a fit-within box, not independent exact targets**
- **Found during:** Task 3, first emulator run of the new `maxDimensionPx=1919` scaling test
- **Issue:** The test asserted the returned thumbnail's height was exactly 1919 (one pixel below the clip's native 1920px longer side). The actual decoded frame came back at height 1918. Root cause: `getScaledFrameAtTime`'s `dstWidth`/`dstHeight` parameters define a bounding box that the retriever fits the source into, scaled by whichever of the two ratios is more constraining — not two independent exact output dimensions. `MediaMath.scaledSize` rounds width and height separately, so the computed target box (1079, 1919) is not perfectly proportional to the source's exact 1080:1920 aspect ratio; the retriever's box-fit picked the (very slightly) more-constraining width ratio, yielding height 1918 instead of 1919.
- **Fix:** After decoding (on both the API 27+ `getScaledFrameAtTime` path and the pre-27 `getFrameAtTime` path), unconditionally check the decoded frame's dimensions against the exact `MediaMath.scaledSize` target and, if they differ, snap to the exact target with one `Bitmap.createScaledBitmap` pass. This makes the observable output dimensions exactly match the pure-math contract on every API level, independent of platform decode-box rounding.
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/Thumbnails.kt`
- **Verification:** `maxDimensionPx one pixel below the longer side downscales proportionally` and the rest of the 25-test integration suite pass on emulator-5554; the 37-test native unit suite (whose `scaledSize` assertions describe the exact target, not the retriever's raw output) is unaffected since it was already testing the pure function in isolation
- **Committed in:** `9552543`

No other deviations. Every acceptance-criteria grep check (`* 1000` count = 1, `CompressFormat.JPEG` count = 1, `compress_video_thumb_` count = 1, `fun scaledSize`/`fun clampPositionMs` counts = 1, zero `android.util.Log`/`println(` in hand-written Kotlin) passed on the first read of the final files.

## Issues Encountered

None beyond the platform-quirk deviation above, which was caught by the plan's own test and fixed within the same task before committing.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `pigeons/messages.dart`'s `ThumbnailHostApi` contract is now fully implemented on Android; plan 01-06 (Apple) implements the same two methods in Swift against the identical contract, and can reuse `Thumbnails.kt`'s shape (one shared extraction-and-encode helper, atomic file writes, native-side validation mirroring Dart) directly.
- `INFO-02` remains unchecked in `REQUIREMENTS.md` (verified via `gsd-tools query requirements.ready-ids`, which reports it `blocked`, not `ready`) — it is shared with 01-06 and 01-07, both still pending in this phase. The shared-ID gate correctly withholds marking it `Complete` until every declaring plan finishes, matching the pattern 01-04-SUMMARY.md documented for `BULD-03`/`INFO-01`/`BULD-05`.
- CI's emulator integration step now runs both `media_info_test.dart` and `thumbnail_test.dart` on every push; 01-06's Apple job addition (XCTest coverage for the same contract) runs on the same CI trigger without needing new wiring.
- Ready for `01-06-PLAN.md` (Apple core: Probe, Thumbnails, XCTest on iOS and macOS).

---
*Phase: 01-typed-contract-ci-and-media-info*
*Completed: 2026-09-15*

## Self-Check: PASSED

- FOUND: all 3 created files and all 7 modified files listed above (verified with `[ -f ]`)
- FOUND commits: 61e9cbe, 5b0222b, 9552543 (all present in `git log --oneline --all`)
- `flutter analyze --fatal-infos --fatal-warnings` (root, clean), `dart format --output=none --set-exit-if-changed .` (0 changed)
- `flutter test` (root): 31/31 pass, including `test/thumbnail_api_test.dart`
- `example/android && ./gradlew :compress_video:testDebugUnitTest`: 37/37 pass
- `example/integration_test` on `emulator-5554`: 25/25 thumbnail tests pass (34/34 combined with the pre-existing 9 media-info tests)
- `bash corpus/verify_corpus.sh`: no drift
- `dart pub publish --dry-run`: 0 warnings
- `grep -c '\* 1000' Thumbnails.kt` = 1; `grep -c 'CompressFormat.JPEG'` = 1; `grep -Ec 'compress_video_thumb_'` = 1; `grep -Ec 'renameTo'` >= 1; `grep -Ec 'android\.util\.Log|println\('` = 0 across all hand-written plugin Kotlin
- Latest CI run (35002031136) conclusion: `success` — Android job (Analyze, Pigeon regen, Gradle unit tests, emulator integration, corpus verify, dry-run publish, build APK) and Apple job (iOS CocoaPods + XCTest, macOS + XCTest, iOS SPM) both `completed success`
- `git status --short` clean at every commit boundary
