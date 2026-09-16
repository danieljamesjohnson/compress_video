---
phase: 02-android-compression-on-media3
reviewed: 2026-09-16T00:00:00Z
depth: standard
files_reviewed: 41
files_reviewed_list:
  - android/build.gradle.kts
  - android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/CompressVideoPlugin.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/ErrorMapping.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/MediaMath.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/Messages.g.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/PluginFiles.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/Probe.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/Thumbnails.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/ArgumentsTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/CompressVideoPluginTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/EffectOrderTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/ErrorMappingTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/MediaMathTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/SizeGuardTest.kt
  - corpus/generate_corpus.sh
  - corpus/sync_to_example.sh
  - corpus/verify_corpus.sh
  - darwin/compress_video/Sources/compress_video/Messages.g.swift
  - example/integration_test/compress_audio_test.dart
  - example/integration_test/compress_jobs_test.dart
  - example/integration_test/compress_output_test.dart
  - example/integration_test/compress_test.dart
  - example/lib/main.dart
  - example/pubspec.yaml
  - .github/workflows/ci.yml
  - lib/compress_video.dart
  - lib/src/compress_job.dart
  - lib/src/compress_options.dart
  - lib/src/compress_result.dart
  - lib/src/compress_video_exception.dart
  - lib/src/messages.g.dart
  - lib/src/presets.dart
  - pigeons/messages.dart
  - test/compress_job_test.dart
  - test/compress_options_test.dart
  - test/compress_video_exception_test.dart
  - tool/measure_presets.dart
  - tool/verify_apk_native_libs.sh
findings:
  critical: 0
  warning: 0
  info: 3
  total: 3
status: clean
---

# Phase 02: Code Review Report

**Reviewed:** 2026-09-16
**Depth:** standard
**Files Reviewed:** 41
**Status:** clean

## Summary

Re-review (iteration 2) after the fix pass recorded in `02-REVIEW-FIX.md`. Verified each of the
five in-scope findings from iteration 1 (CR-01, WR-01 through WR-04) directly against the current
code and its five corresponding commits, rather than trusting the fix report's own narrative:

- **CR-01** (`bd8f30e`): `TransformerEngine.copyFileAtomically` is now `suspend` and its body runs
  inside `withContext(Dispatchers.IO)`. Both call sites (`compress()`'s never-larger pre-check at
  line 96 and `finishSuccess()`'s post-check fallback at line 404) already ran in a suspend
  context, so the byte copy is confirmed off the main thread on both paths. Confirmed genuinely
  fixed.
- **WR-04** (`8ba81d6`): `readAudioCodec`/`readAudioChannelCount` are now `suspend`, wrapped in
  `withContext(Dispatchers.IO)`. `resolvePlan` and `Compression.requireSufficientFreeSpace` were
  correctly threaded to `suspend` to carry the dispatcher switch through; both call sites
  (`compress()`, `estimate()`, `requireSufficientFreeSpace()`) were already suspend contexts, so
  no caller needed further changes. Confirmed genuinely fixed, with no dangling non-suspend caller
  left in `android/src/main/kotlin` (verified by grep across every call site).
- **WR-01** (`6642460`): `JobRegistry.LiveJob.terminal` is set by `stopPolling`, which runs
  synchronously inside the `Transformer.Listener`'s terminal callbacks the instant they fire.
  `JobRegistry.cancel()` now no-ops on `job.cancelled || job.terminal` before touching
  `cancelTransformer()`/`quietDelete()`/`onCancelled()`. Traced both interleavings by hand:
  cancel-then-completion (existing pre-fix path, still correct — `deferred.complete` on an
  already-cancelled `deferred` is a no-op) and completion-then-cancel (the bug this fix closes —
  `cancel()` now finds `terminal == true` and returns immediately, leaving the temp file intact
  for the still-suspended `compress()` continuation to move into place). The new JVM test
  (`cancel_afterStopPollingMarksJobTerminal_isANoOp`) reproduces the exact ordering and asserts
  all three previously-corrupted side effects (`cancelTransformer`, `onCancelled`, temp-file
  deletion) do not fire. Confirmed genuinely fixed; `JobRegistry.cancelAll()` (used on plugin
  detach) composes correctly with the new no-op — it simply skips jobs that have already resolved
  on the native side, which is correct, not a regression.
- **WR-02** (`102dca3`): `SizeGuard.resolve`'s `targetSizeMb` branch now guards
  `outputDurationSeconds <= 0.0` and falls back to `VIDEO_BITRATE_FLOOR_BPS` instead of dividing.
  Confirmed the guard is checked before the division, and the fallback still passes through the
  existing `input.videoBitrateBps` cap below it. Confirmed genuinely fixed; new unit test uses a
  zero-duration input with `videoBitrateBps = null` specifically so the pre-existing input-bitrate
  cap can't mask a regression.
- **WR-03** (`a6ea3ce`): `CompressJob._run` now has a `catch (e)` (untyped, so it also catches
  `Error` subtypes like the `TypeError` its own regression test forces) after the
  `PlatformException`/`MissingPluginException` clauses, resolving `failure` with a typed
  `CompressVideoErrorReason.unknown` exception. Confirmed `result` can no longer hang: every
  exit from the `try` block now sets either `success` or `failure` before the `if`/`else if` at
  the end of `_run` runs. Confirmed genuinely fixed.

No regressions found in the five fix commits: `suspend` propagation is complete and consistent
(no caller left invoking a newly-`suspend` function from a non-suspend context), the
`Dispatchers.IO` boundaries introduced by CR-01/WR-04 never touch `Transformer` or `JobRegistry`
inside the IO-dispatched block (verified by reading both function bodies in full), and the new
`terminal` flag only narrows `cancel()`'s no-op condition (`cancelled || terminal`) rather than
changing any other code path. Project invariants re-checked directly in this pass and all still
hold: `finishSuccess`'s never-larger post-check is unconditional on every produced file
(`SizeGuard.kt`/`TransformerEngine.kt:400-407`); every failure/cancel path in `compress()` deletes
the temp file before throwing (`TransformerEngine.kt:359-366`) and `copyFileAtomically`'s own
catch blocks quiet-delete its temp file on any exception; `PluginFiles.sweep`'s symlink-escape and
directory confinement logic is untouched and still sound; every `Transformer`/`JobRegistry` access
in `TransformerEngine`/`Compression`/`JobRegistry` remains on the calling (main) Looper thread,
with only genuinely blocking I/O moved to `Dispatchers.IO`; progress is still forwarded
monotonically non-decreasing with a single canonical terminal 100 (`compress()`'s runnable clamps
to 0..99 and `onProgress(100.0)` is called exactly once per terminal path); `cancel()` is now
provably idempotent including against a same-tick natural completion; and no path returns a null
`CompressResultMessage` or silently swallows a failure (`CompressJob._run`'s catch-all closes the
last gap here).

The three Info items from iteration 1 are carried forward unchanged below — none were in
`fix_scope` and none were touched by the fix commits; re-reading their code (`Probe.kt`,
`compress_job.dart`, `example/lib/main.dart`) confirms they are still present exactly as
described.

## Info

### IN-01: `estimateVideoBitrateBpsFromSamples`'s `finally` can call `unselectTrack` on a track that was never selected

**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/Probe.kt:142-163`

**Issue:** The `try` block covers `extractor.selectTrack(videoTrackIndex)` itself; if
`selectTrack` throws, the `finally` block still unconditionally calls
`extractor.unselectTrack(videoTrackIndex)` on a track that was never successfully selected, which
could itself throw. Any such secondary exception would propagate out of
`estimateVideoBitrateBpsFromSamples` (rather than being swallowed by the already-executed
`catch` block), though it remains contained by `Probe.getMediaInfo`'s own outer
`catch (e: Exception)` wrapper, so this cannot escape as a raw crash — it would just be reported
as reason `"io"` instead of falling back to `videoBitrateBps = null` as intended.

**Fix:** Track whether `selectTrack` succeeded before calling `unselectTrack` in `finally`, or
wrap the `unselectTrack` call itself in a `try`/`catch` that swallows only that secondary failure.

### IN-02: `CompressJob.cancel()` and native-side cancellation do not surface a distinct "cancel arrived after natural completion" signal to the caller

**File:** `lib/src/compress_job.dart:113-126`, related to (now-fixed) WR-01

**Issue:** `cancel()`'s own `PlatformException`/`MissingPluginException` catches are documented as
"best-effort: `result` is the authority on the eventual outcome," which is the right design now
that WR-01 is fixed — the native authority itself is no longer corrupted by the race. Still worth
tracking: the Dart-level integration coverage for the exact same-tick-cancel-vs-completion timing
now exists (`example/integration_test/compress_jobs_test.dart`'s "a cancel issued after successful
completion is a no-op" case, confirmed present and passing per `02-REVIEW-FIX.md`), so this item
is now closer to "documented and covered" than an open gap — downgraded in spirit but left as Info
since it is not a code change, just a note that this is exercised end to end.

### IN-03: `example/lib/main.dart`'s `_startCompress` re-subscribes to `job.progress` without a job-generation guard

**File:** `example/lib/main.dart:239` (demo code — Info per review scope)

**Issue:** `await _progressSubscription?.cancel();` is awaited before creating the new job's
subscription, which is correct; however `_job`, `_progress` and `_result` are mutated via
`setState` from multiple async callbacks without any check that this is still the "current"
job (e.g. if a user manages to trigger `_startCompress` twice in a row, despite the button being
disabled while `isRunning`). This is demo-only code with no external consumers, so it is Info,
not a shipping defect.

**Fix (optional, for polish):** Track a job generation counter and ignore callbacks from a
superseded job, or simply rely on the button's `isRunning` guard (already present) as sufficient
for the demo's purposes.

---

_Reviewed: 2026-09-16_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
