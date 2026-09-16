---
phase: 02-android-compression-on-media3
reviewed: 2026-09-15T00:00:00Z
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
  critical: 1
  warning: 4
  info: 3
  total: 8
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-09-15
**Depth:** standard
**Files Reviewed:** 41
**Status:** issues_found

## Summary

Reviewed the Android Media3 Transformer compression path end to end (Kotlin engine, SizeGuard
resolver, Pigeon contract, Dart job/registry layer, corpus tooling, CI) against this phase's
stated invariants: never-larger, no swallowed failures, guaranteed cleanup on cancel/failure,
cache-directory confinement, main-Looper-only Transformer access, and monotonic single-terminal
progress.

The unconditional never-larger post-check (`TransformerEngine.finishSuccess`), the cache-sweep
symlink confinement (`PluginFiles.sweep`), the transmux/never-larger predicate purity
(`SizeGuard`), and the generated Pigeon contract are all sound and well covered by the existing
unit and integration test suites. The one blocking issue is a genuine thread-usage bug: this
phase's own documented design ("nothing here ever dispatches work to a background thread pool")
means multi-hundred-megabyte/gigabyte file copies run synchronously on the Android main thread on
two real, non-rare paths (the never-larger fast path and the never-larger post-check fallback),
which risks an ANR on exactly the large-video inputs this plugin exists to handle. A second,
narrower issue is a real (if timing-dependent) race between `cancel()` and a job's own natural
completion that can convert a just-finished successful job into a spurious `io` error and delete
its output. Both are detailed below along with several smaller robustness and edge-case gaps.

## Critical Issues

### CR-01: Full-file copy on the never-larger path runs synchronously on the main thread (ANR risk)

**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt:92-103, 397-404, 548-565`

**Issue:** `TransformerEngine.compress` is invoked directly from `Compression.startCompress`,
which is dispatched (via the Pigeon-generated `CompressHostApi.setUp`) on
`CoroutineScope(Dispatchers.Main).launch { ... }` — i.e. on the Android main Looper thread. The
file's own doc comment confirms this is deliberate: "Nothing here ever dispatches that work to a
background thread pool ... only the pre-Transformer input probe and the post-export re-probe
leave the main thread."

Two real paths in this same file perform a full, synchronous byte-for-byte file copy
(`copyFileAtomically`, `TransformerEngine.kt:548-565`) without ever switching off the calling
(main) dispatcher:

1. The never-larger **pre-check** fast path (`compress()`, lines 92-103): when
   `target.wouldUseOriginal` is true, `copyFileAtomically(inputFile, destinationFile)` runs
   immediately, before any `withContext(Dispatchers.IO)` switch.
2. The never-larger **post-check** fallback (`finishSuccess()`, lines 397-404): when the real
   temp output is not smaller than the input, the same synchronous copy runs.

Both paths are common, not exotic: any caller who compresses an already-small or
already-well-compressed clip (a very common real case — chat-app clips, previously-shared media,
screen recordings) hits path 1, and any caller whose prediction under-estimates the real output
size hits path 2. For phone videos in the multi-hundred-MB-to-several-GB range that this plugin's
own `PROJECT.md` explicitly targets, blocking the UI thread for the whole duration of a
synchronous disk-to-disk copy risks the Android watchdog triggering an ANR (Application Not
Responding) dialog, which from the end user's perspective is indistinguishable from a crash.

**Fix:** Wrap the byte-copy body of `copyFileAtomically` (or its two call sites) in
`withContext(Dispatchers.IO) { ... }`, exactly as `Probe.getMediaInfo` already does for its own
blocking native calls:

```kotlin
private suspend fun copyFileAtomically(source: File, destination: File) =
    withContext(Dispatchers.IO) {
        val temp = PluginFiles.tempFileBeside(destination)
        try {
            source.inputStream().use { input ->
                FileOutputStream(temp).use { output -> input.copyTo(output) }
            }
            PluginFiles.moveIntoPlace(temp, destination)
        } catch (e: CompressVideoError) {
            PluginFiles.quietDelete(temp)
            throw e
        } catch (e: Exception) {
            PluginFiles.quietDelete(temp)
            throw CompressVideoError("io", "Failed to copy the original file", e.message)
        }
    }
```
Since `Dispatchers.IO` always resumes back on the caller's original context once the block
completes (the same pattern this file already documents for `Probe`), this does not violate the
"Transformer only built/driven on its own creation Looper" invariant — no Transformer or
`JobRegistry` access happens inside the IO-dispatched block.

## Warnings

### WR-01: Race between `cancel()` and a job's own near-simultaneous completion can destroy a successful job's output

**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt:84-93`,
`android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt:228-253, 337-369`

**Issue:** `Transformer.Listener.onCompleted`/`onError` complete `deferred` and call
`JobRegistry.stopPolling(jobId)`, but the job is not removed from `JobRegistry` (and its
`cancelled` flag is not set) until the *coroutine continuation* resumes after `deferred.await()`
and calls `JobRegistry.remove(jobId)` (`TransformerEngine.kt:351-352`). Both the listener callback
and the coroutine continuation are scheduled as separate tasks on the main Looper, so there is a
real window — between `onCompleted` firing and the suspended `compress()` coroutine's own
continuation actually running — during which the job is still present in `JobRegistry` with
`cancelled == false`.

If `Compression.cancel(jobId)` is invoked during that window (a caller racing a `cancel()` call
against the job's own natural completion — a realistic pattern, e.g. a UI "cancel" button pressed
just as the job finishes), `JobRegistry.cancel()` will:
1. Find the job (still registered), see `cancelled == false`, proceed.
2. Call `transformer.cancel()` on an already-completed `Transformer` (undefined/benign behaviour
   per Media3, but irrelevant to the real problem below).
3. Call `PluginFiles.quietDelete(job.tempFile)` — **deleting the temp file that the still-pending
   `compress()` coroutine's `finishSuccess()` is about to move into place.**

When the `compress()` coroutine's continuation then resumes (the deferred already resolved to
`Success` from `onCompleted`, so the `cancel` never gets to flip the outcome via
`onCancelled`), it proceeds to `finishSuccess()`, which reads `tempFile.length()` — now `0`
because the file no longer exists. Since `0 < inputBytes` in the typical case, `usedOriginal`
evaluates `false` and `PluginFiles.moveIntoPlace(tempFile, destinationFile)` is attempted on a
file that no longer exists, so `tempFile.renameTo(destination)` fails and
`CompressVideoError("io", "Could not move the output into place")` is thrown. The net effect: a
job that genuinely completed successfully is reported to the caller as a spurious `io` failure,
and its compressed output is silently destroyed — not the documented `cancelled` outcome the
caller's `cancel()` call would lead them to expect.

**Fix:** Have `JobRegistry.cancel()` check for (or `TransformerEngine` record) a "already
terminal" state before deleting the temp file — for example, have the `Transformer.Listener`
callbacks mark the `LiveJob` as terminal (not just stop polling) the instant they fire, and have
`JobRegistry.cancel()` no-op (skip the `cancelTransformer()`/`quietDelete()` calls) when the job
is already terminal:

```kotlin
class LiveJob(...) {
    internal var cancelled: Boolean = false
    internal var terminal: Boolean = false // set by the Transformer.Listener callbacks
}

fun cancel(jobId: String) {
    val job = jobs[jobId] ?: return
    if (job.cancelled || job.terminal) return
    ...
}
```

### WR-02: `SizeGuard.resolve` divides by zero when the input duration is 0, producing an absurd bitrate

**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt:199-205, 219-222`

**Issue:** When `options.targetSizeMb != null` and the resolved `outputDurationMs` is `0` (e.g.
an input whose `durationMs` metadata is missing/zero — `Probe.kt` defaults `durationRawMs` to
`0.0` when `METADATA_KEY_DURATION` is absent, and `Arguments.requireReadableMediaFile` only
checks the file is non-empty, not that it has a readable duration), `outputDurationSeconds` is
`0.0`, so:

```kotlin
val targetTotalBitrateBps =
    options.targetSizeMb * BYTES_PER_MEGABYTE * BITS_PER_BYTE /
        outputDurationSeconds * MUX_OVERHEAD_FACTOR
```

evaluates to `Double.POSITIVE_INFINITY`. `.toLong()` on that value in Kotlin/JVM yields
`Long.MAX_VALUE`, which then flows into `videoBitrateBps` unclamped whenever
`input.videoBitrateBps` is also `null` (equally plausible for the same degenerate input). This
value is later passed to `VideoEncoderSettings.Builder().setBitrate(videoBitrateBps.toInt())`
(`TransformerEngine.kt:200`), where the `Long -> Int` narrowing silently wraps to a
nonsensical/negative value handed straight to the platform encoder.

**Fix:** Guard the `targetSizeMb` branch against a non-positive `outputDurationSeconds` before
dividing, and fall back to the video-bitrate floor (or reject the request) instead of producing
`Infinity`:

```kotlin
options.targetSizeMb != null -> {
    if (outputDurationSeconds <= 0.0) {
        VIDEO_BITRATE_FLOOR_BPS
    } else {
        val targetTotalBitrateBps = ...
        maxOf(targetVideoBitrateBps.toLong(), VIDEO_BITRATE_FLOOR_BPS)
    }
}
```

### WR-03: `CompressJob._run` leaves `result` permanently unresolved for any exception type other than `PlatformException`/`MissingPluginException`

**File:** `lib/src/compress_job.dart:128-183`

**Issue:** `_run`'s `try`/`catch` only handles `PlatformException` and `MissingPluginException`.
If `_api.startCompress(...)` throws anything else — for example a `TypeError` from a malformed
Pigeon codec reply, or any other unexpected Dart exception — neither `success` nor `failure` is
ever assigned. The `finally` block still runs (closing the progress stream and removing the job
from `_jobRegistry`), but nothing ever calls `_resultCompleter.complete(...)` or
`_failWith(...)`. The result: `job.result` never completes — not with a value, not with an error —
and the exception propagates instead as an unhandled async error in whatever zone the unawaited
`_run()` call executes in. A caller awaiting `job.result` for such an input hangs forever, silently
contradicting the class's own documented contract ("Never resolves to `null`" / "no failure is
swallowed").

**Fix:** Add a catch-all fallback so an unexpected exception still resolves `result` with a typed
error instead of hanging:

```dart
} on PlatformException catch (e) {
  failure = wrapPlatformException(e, 'compress');
} on MissingPluginException catch (e) {
  failure = wrapMissingPlugin(e, 'compress');
} catch (e) {
  failure = CompressVideoException(
    reason: CompressVideoErrorReason.unknown,
    message: 'Unexpected error during compress: $e',
  );
} finally {
  ...
}
```

### WR-04: Ancillary native metadata reads in `TransformerEngine` run on the main thread outside any `Dispatchers.IO` boundary

**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt:83, 478-526, 575-585`

**Issue:** `readAudioChannelCount`/`readAudioCodec` construct a `MediaExtractor` and call
`setDataSource`/`getTrackFormat` synchronously. These are called directly from `compress()`
(line 83) and from `resolvePlan()` (called by both `compress()` and `Compression.estimate()`),
both of which execute on the main Looper (per the Pigeon-generated `Dispatchers.Main` dispatch).
Unlike `Probe.getMediaInfo`, which wraps its own `MediaMetadataRetriever`/`MediaExtractor` use in
`withContext(Dispatchers.IO)`, these calls have no such boundary. `MediaExtractor.setDataSource`
performs a real (if normally fast) file-open and container-header parse; on a slow storage medium
(network-backed content URI, resolved to a local cache path, or a device under I/O pressure) this
adds unbounded jank to every `compress()`/`estimate()` call, on the UI thread.

**Fix:** Wrap these two helpers' bodies in `withContext(Dispatchers.IO) { ... }`, consistent with
how `Probe` already treats equivalent native calls.

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

**File:** `lib/src/compress_job.dart:113-126`, related to WR-01

**Issue:** `cancel()`'s own `PlatformException`/`MissingPluginException` catches are documented as
"best-effort: `result` is the authority on the eventual outcome," which is the right design in
the common case, but WR-01 shows the native authority itself can be corrupted by the race. This is
purely a consequence of WR-01 and needs no separate fix once WR-01 is addressed, but is worth
tracking so a fix to WR-01 is verified against a Dart-level integration case (a `cancel()` fired
in the same event-loop turn as the job's own completion) in addition to the existing
`compress_jobs_test.dart` cancellation coverage, none of which currently exercises this exact
timing.

### IN-03: `example/lib/main.dart`'s `_startCompress` re-subscribes to `job.progress` without awaiting the previous subscription's cancellation before starting a new job

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

_Reviewed: 2026-09-15_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
