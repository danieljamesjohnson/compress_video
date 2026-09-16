---
phase: 02-android-compression-on-media3
fixed_at: 2026-09-15T00:00:00Z
review_path: .planning/phases/02-android-compression-on-media3/02-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-09-15
**Source review:** .planning/phases/02-android-compression-on-media3/02-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5 (fix_scope: critical+warning -- CR-01, WR-01, WR-02, WR-03, WR-04)
- Fixed: 5
- Skipped: 0

Edited and committed directly in the main checkout (`workflow.use_worktrees` is `false` in
`.planning/config.json`) -- no worktree, no temp branch. All commits landed on `main`.

## Fixed Issues

### CR-01: Full-file copy on the never-larger path runs synchronously on the main thread (ANR risk)

**Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt`
**Commit:** `bd8f30e`
**Applied fix:** Made `copyFileAtomically` a `suspend` function and wrapped its body in
`withContext(Dispatchers.IO)`, matching the pattern `Probe` already uses. Both call sites (the
never-larger pre-check in `compress()` and the post-check fallback in `finishSuccess()`) already
run in a suspend context, so no caller changes were needed beyond the function signature. Updated
the class doc comment to reflect the corrected thread-usage contract.
**Verification:** `flutter` toolchain not involved; verified via `./gradlew
:compress_video:compileDebugKotlin` (clean) and `./gradlew :compress_video:testDebugUnitTest`
(full suite passes, run after all five fixes were applied).

### WR-04: Ancillary native metadata reads in `TransformerEngine` run on the main thread outside any `Dispatchers.IO` boundary

**Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt`,
`android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt`
**Commit:** `8ba81d6`
**Applied fix:** Wrapped `readAudioCodec` and `readAudioChannelCount` bodies in
`withContext(Dispatchers.IO)`, making both `suspend fun`. This required threading `suspend`
through `resolvePlan` (which calls `readAudioCodec`) and through `Compression.requireSufficientFreeSpace`
(which calls `resolvePlan` from the already-suspend `startCompress`). `Compression.estimate` already
called `resolvePlan` from a suspend context, so no change was needed there.
**Verification:** `./gradlew :compress_video:compileDebugKotlin` and
`:compress_video:compileDebugUnitTestKotlin` both clean; full `testDebugUnitTest` suite passes.

### WR-01: Race between `cancel()` and a job's own near-simultaneous completion can destroy a successful job's output

**Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt`,
`android/src/test/kotlin/com/danjjohnson/compress_video/CompressVideoPluginTest.kt`
**Commit:** `6642460`
**Applied fix:** Added `LiveJob.terminal` (internal, default `false`), set by `stopPolling` --
which already runs synchronously inside the `Transformer.Listener`'s `onCompleted`/`onError`
terminal callbacks, the instant they fire. `JobRegistry.cancel()` now no-ops when
`job.cancelled || job.terminal`, so whichever of cancel/completion reaches the job second becomes
the no-op instead of a still-registered, not-yet-cancelled job having its temp file deleted out
from under an about-to-succeed `compress()` continuation. Added a new JVM unit test,
`cancel_afterStopPollingMarksJobTerminal_isANoOp`, that reproduces the exact ordering the review
found (`stopPolling` then `cancel` then `remove`) and asserts `cancelTransformer`/`onCancelled` are
never invoked and the temp file survives.
**Verification:** `./gradlew :compress_video:testDebugUnitTest --tests
"com.danjjohnson.compress_video.CompressVideoPluginTest"` -- all 4 tests pass, including the new
regression test. Additionally exercised end-to-end on the emulator: `example/integration_test/
compress_jobs_test.dart`'s "a cancel issued after successful completion is a no-op" case (which
directly targets this race) passed on `emulator-5554`.

### WR-02: `SizeGuard.resolve` divides by zero when the input duration is 0, producing an absurd bitrate

**Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt`,
`android/src/test/kotlin/com/danjjohnson/compress_video/SizeGuardTest.kt`
**Commit:** `102dca3`
**Applied fix:** Guarded the `options.targetSizeMb != null` bitrate branch: when
`outputDurationSeconds <= 0.0`, fall back to the existing `VIDEO_BITRATE_FLOOR_BPS` instead of
dividing (which previously produced `Double.POSITIVE_INFINITY` -> `Long.MAX_VALUE` -> a wrapped,
nonsensical value handed to the platform encoder whenever `input.videoBitrateBps` was also
`null`). Added `targetSizeMb_withZeroDurationAndNoInputBitrate_fallsBackToFloorInsteadOfOverflowing`,
using a zero-duration input with no input video bitrate (so the existing input-bitrate cap cannot
mask the bug), asserting the floor value is returned.
**Verification:** `./gradlew :compress_video:testDebugUnitTest --tests
"com.danjjohnson.compress_video.SizeGuardTest"` -- all 28 tests pass, including the new one.

### WR-03: `CompressJob._run` leaves `result` permanently unresolved for any exception type other than `PlatformException`/`MissingPluginException`

**Files modified:** `lib/src/compress_job.dart`, `test/compress_job_test.dart`
**Commit:** `a6ea3ce`
**Applied fix:** Added a catch-all `catch (e)` clause after the existing `on PlatformException`/
`on MissingPluginException` handlers in `_run`, resolving `failure` with `CompressVideoException(
reason: CompressVideoErrorReason.unknown, message: 'Unexpected error during compress',
platformDetail: '${e.runtimeType}: $e')` so `result` always completes instead of hanging forever.
Added a Dart unit test that installs a mock `startCompress` channel handler replying with a
well-formed but wrongly-typed single-element message, forcing the generated Pigeon client's own
`as CompressResultMessage` cast to throw a raw `TypeError` (an exception type neither existing
`catch` clause handles), and asserts `job.result` still fails with reason `unknown`.
**Verification:** `flutter test test/compress_job_test.dart` -- all 11 tests pass, including the
new one. `flutter analyze --fatal-infos --fatal-warnings` clean on both `lib/src/compress_job.dart`
and the whole root package.

## Skipped Issues

None -- all five in-scope findings (CR-01, WR-01 through WR-04) were fixed.

## Post-fix verification (full suite, all five fixes applied)

- `flutter analyze --fatal-infos --fatal-warnings` (root): No issues found.
- `flutter analyze --fatal-infos --fatal-warnings` (`example/`): No issues found.
- `flutter test` (root): 84/84 passed.
- `./gradlew :compress_video:testDebugUnitTest` (from `example/android`): all tests passed
  (ArgumentsTest, CompressVideoPluginTest, EffectOrderTest, ErrorMappingTest, MediaMathTest,
  SizeGuardTest).
- `flutter test integration_test/compress_jobs_test.dart -d emulator-5554` (from `example/`):
  10/10 passed, including the cancel-races-completion and cancel-after-success cases most
  relevant to WR-01.
- GitHub Actions CI was not run (billing-blocked per project instructions); not pushed --
  orchestrator handles push/PR.

Info-tier findings (IN-01, IN-02, IN-03) were out of `fix_scope` (`critical+warning`) and were
not touched.

---

_Fixed: 2026-09-15_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
