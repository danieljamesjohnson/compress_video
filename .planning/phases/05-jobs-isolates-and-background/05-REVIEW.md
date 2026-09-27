---
phase: 05-jobs-isolates-and-background
reviewed: 2026-09-27T00:00:00Z
depth: standard
files_reviewed: 25
files_reviewed_list:
  - android/src/main/AndroidManifest.xml
  - android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/ForegroundServiceHost.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/ForegroundServiceHostTest.kt
  - darwin/compress_video/Sources/compress_video/Compression.swift
  - darwin/compress_video/Sources/compress_video/CompressionEngine.swift
  - darwin/compress_video/Sources/compress_video/ErrorMapping.swift
  - darwin/compress_video/Sources/compress_video/JobRegistry.swift
  - example/android/app/src/main/kotlin/com/danjjohnson/compress_video_example/MainActivity.kt
  - example/integration_test/jobs_background_test.dart
  - example/integration_test/compress_jobs_test.dart
  - example/ios/RunnerTests/RunnerTests.swift
  - example/macos/RunnerTests/RunnerTests.swift
  - lib/compress_video.dart
  - lib/src/compress_job.dart
  - lib/src/compress_options.dart
  - lib/src/compress_video_exception.dart
  - pigeons/messages.dart
  - test/compress_job_test.dart
  - test/compress_video_queue_test.dart
  - tool/run_ios_integration_suites.sh
  - tool/verify_apk_foreground_service_manifest.sh
  - .github/workflows/ci.yml
findings:
  critical: 2
  warning: 2
  info: 1
  total: 5
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-09-27T00:00:00Z
**Depth:** standard
**Files Reviewed:** 25
**Status:** issues_found

## Summary

Phase 5 adds a Dart FIFO job queue, a background-isolate result escape hatch
(`awaitCompressResult`), an Android `mediaProcessing` foreground service, and iOS
background-task wrapping. The Dart-side queue (`CompressVideo`/`CompressJob`) is careful and
well tested: admission, concurrency limiting, cancel-while-queued, and settlement are all
covered by `test/compress_video_queue_test.dart` and hold up under inspection — I found no
defect in the FIFO pump, the active-job counter, or the cancel-while-queued path.

The two platform engines (`TransformerEngine.kt` / `CompressionEngine.swift`) are also
carefully built, with the terminal-callback/`terminal` flag race (WR-01 in the code's own
numbering) closed correctly on both platforms, and `completeResult`/`completeResult` protected
against double-completion.

The two areas that do have real gaps are exactly the ones flagged for extra scrutiny:
`ForegroundServiceHost`'s ref-counted service lifecycle has an unguarded startup race that can
leave the foreground service (and its notification) running with zero hosted jobs, and
`awaitCompressResult`'s per-job outcome store has no defined behavior — other than hanging
forever — for a job id that was never started or whose outcome was already consumed once, on
both platforms. Neither is exercised by the current test suite.

## Critical Issues

### CR-01: ForegroundServiceHost can be left running (with a stale "0 videos" notification) if the last hosted job detaches before the service has actually started

**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/ForegroundServiceHost.kt:145-177`

**Issue:** `attach()`/`detach()` communicate with the real, running `Service` instance only
through the nullable companion `instance` field, which is set in `onCreate()` and cleared in
`onDestroy()`. `attach()` for the very first hosted job calls
`context.startForegroundService(Intent(...))`, which is asynchronous: `onCreate()`/
`onStartCommand()` for the new `Service` instance are dispatched as a *later* message on the
same main-Looper queue `attach()` itself runs on, not synchronously inside the
`startForegroundService()` call.

If that first job (and only job) then calls `detach()` before the queued `onCreate()`/
`onStartCommand()` has actually run, `ref.detach(jobId)` correctly reports `shouldStop = true`,
but `instance` is still `null` at that point, so `instance?.stopSelf()` silently no-ops:

```kotlin
fun detach(jobId: String) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return
    val shouldStop = ref.detach(jobId)
    if (shouldStop) {
        instance?.stopSelf()   // no-op: instance is still null
    }
}
```

When the deferred `onStartCommand()` eventually runs, it calls `startForeground(...)` with
`ref.hostedCount` already back at `0` (the job already detached), producing a service that is
now genuinely in the foreground-service state, showing a `"0 videos"` notification, with
**nothing left registered to ever stop it** until some later, unrelated job happens to attach
and detach again (which self-heals it, since by then `instance` is non-null). Until that
happens, this violates the documented invariant "the [detach] that empties the count stops it
(D-09)" and the review's own "service never outliving jobs" requirement — the service and its
notification linger indefinitely, consuming the daily foreground-service quota and confusing
the user with a stale notification.

The project's own code comments establish that a job can complete in ~220ms
(`JobRegistry.kt`'s `resultDeferredFor` doc comment), so a job finishing before an
`ActivityManagerService`-mediated service start has completed is not a purely theoretical
window.

**Fix:** Don't gate `stopSelf()` on the nullable `instance` alone. Either track "service start
requested but not yet confirmed" state in the companion and defer the stop request until
`onCreate()`/`onStartCommand()` actually runs (checking `ref.hostedCount == 0` there and calling
`stopSelf()` immediately if so), or route `attach`/`detach` through a small pending-intent-style
queue so a `detach()` arriving before `onCreate()` is guaranteed to be observed once the service
does start:

```kotlin
override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    ensureNotificationChannel()
    startForeground(NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING)
    if (ref.hostedCount == 0) {
        // Every hosted job already detached before this callback ran -- stop immediately
        // rather than leaving a zero-job service in the foreground state.
        stopSelf(startId)
    }
    return START_NOT_STICKY
}
```

## Warnings

### WR-01: `awaitCompressResult` hangs forever (never fails typed) for a job id that was never started or whose result was already consumed

**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt:170-202`,
`android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt:108-114`;
`darwin/compress_video/Sources/compress_video/JobRegistry.swift:113-157`,
`darwin/compress_video/Sources/compress_video/Compression.swift:112-115`

**Issue:** On Android, `Compression.awaitCompressResult` does:

```kotlin
override suspend fun awaitCompressResult(jobId: String): CompressResultMessage {
    requireMainLooper("awaitCompressResult")
    requireValidJobId(jobId)
    val outcome = JobRegistry.resultDeferredFor(jobId).await()
    JobRegistry.forgetResult(jobId)
    return outcome.getOrElse { throw it }
}
```

`requireValidJobId` only checks the `<counter>-<hex>` *format*, not whether `startCompress` was
ever called for that id. `resultDeferredFor` uses `getOrPut`, so a never-started (but
well-formed) job id creates a brand-new, never-completing `CompletableDeferred` and this call
suspends **forever** — no typed error, no timeout. The same is true for a *second*
`awaitCompressResult` call on a job whose result was already consumed once: `forgetResult`
removes the map entry, so the second call's `getOrPut` creates a fresh deferred that nothing
will ever complete.

On iOS/macOS, `JobRegistry.awaitResult` has the identical shape:

```swift
static func awaitResult(jobId: String) async throws -> CompressResultMessage {
    if let outcome = resultOutcomes.removeValue(forKey: jobId) {
      return try outcome.get()
    }
    return try await withCheckedThrowingContinuation { continuation in
      resultWaiters[jobId, default: []].append(continuation)
    }
}
```

An unknown or already-consumed `jobId` appends a continuation to `resultWaiters` that nothing
will ever resume.

This is exactly the scenario the phase's own contract calls out
(`pigeons/messages.dart`'s `awaitCompressResult` dartdoc: "Resolves once the job ... reaches a
terminal outcome") without documenting or guarding the "never started" / "called twice" cases.
The current Dart wrapper (`CompressJob._run`) only ever calls it once, for a job it always
starts first, so this is not reachable through the shipped `compress_video` package today — but
`CompressHostApi` is a Pigeon-generated `@HostApi()` any native or Dart caller can invoke
directly, and nothing here stops a future caller (or a retry after a dropped platform-channel
reply) from hitting this hang with no diagnosable error, directly contradicting this project's
stated core value that no call "returns null" or hangs.

**Fix:** Track known-but-not-yet-registered vs. genuinely-unknown job ids (for example, record
every id `startCompress` was ever invoked for, even after its result is forgotten, and reject an
`awaitCompressResult` call for anything outside that set with a typed `CompressVideoError`/
`unsupportedInput`-style failure), or bound the wait with a timeout that fails typed instead of
hanging indefinitely.

### WR-02: The shared `ForegroundServiceHost` notification is never refreshed when a job detaches, only when one attaches

**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/ForegroundServiceHost.kt:90-108, 163-177`

**Issue:** `attach()` calls `instance?.refreshNotification()` (or triggers `startForeground`
via a fresh service start) so the notification reflects the current `ref.hostedCount` and the
most-recently-attached job's `notificationTitle`/`notificationText`. `detach()` never calls
`refreshNotification()`:

```kotlin
fun detach(jobId: String) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return
    val shouldStop = ref.detach(jobId)
    if (shouldStop) {
        instance?.stopSelf()
    }
    // no refreshNotification() call when shouldStop is false
}
```

With `maxConcurrentJobs > 1` and Android's foreground service opted in, if job B (the
most-recently-attached, whose title/text are showing) finishes while job A is still running,
the notification keeps displaying job B's stale title/text and the pre-detach hosted count
(e.g. "2 videos") until some later, unrelated `attach()` happens to refresh it. This is
untested: `ForegroundServiceHostTest.kt` only exercises the pure `Ref` bookkeeping, never the
real `Service`'s notification content across a partial detach.

**Fix:** Call `instance?.refreshNotification()` from `detach()` too, whenever `shouldStop` is
`false` (i.e., other jobs remain hosted), mirroring what `attach()` already does for the
non-first-job case.

## Info

### IN-01: `verify_apk_foreground_service_manifest.sh` doesn't check `android:exported="false"` on the merged manifest

**File:** `tool/verify_apk_foreground_service_manifest.sh`

**Issue:** The script (T-05-16) verifies both foreground-service permissions, the
`ForegroundServiceHost` service declaration, and its `foregroundServiceType` value, but never
asserts `exported=false` on the merged service entry, even though the review's own stated
correctness bar for this manifest explicitly includes "exported=false". The source
`AndroidManifest.xml` does declare it correctly today (`android:exported="false"`), but a future
edit that drops or flips that attribute (making the service targetable by other apps on the
device) would not be caught by this CI gate.

**Fix:** Add a check against the `aapt2 dump xmltree` output for the exported attribute (resource
id `0x01010010`) being `0x0` (false) on the `ForegroundServiceHost` service node, alongside the
existing `foregroundServiceType` check.

---

_Reviewed: 2026-09-27T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
