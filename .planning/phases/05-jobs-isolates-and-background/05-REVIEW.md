---
phase: 05-jobs-isolates-and-background
reviewed: 2026-09-27T20:00:00Z
depth: standard
files_reviewed: 27
files_reviewed_list:
  - android/src/main/AndroidManifest.xml
  - android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/ForegroundServiceHost.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/ForegroundServiceHostTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/JobRegistryTest.kt
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
  - test/await_compress_result_test.dart
  - tool/run_ios_integration_suites.sh
  - tool/verify_apk_foreground_service_manifest.sh
  - .github/workflows/ci.yml
findings:
  critical: 0
  warning: 3
  info: 0
  total: 3
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-09-27T20:00:00Z
**Depth:** standard
**Files Reviewed:** 27
**Status:** issues_found

## Summary

Re-review (iteration 2) of the four fixes applied against the prior 05-REVIEW.md: CR-01
(`ForegroundServiceHost` start/detach race), WR-01 (notification not refreshed on detach), WR-02
(`awaitCompressResult` hanging for unknown/consumed job ids, both platforms — this is the fix
report's own "WR-01" by its numbering, keyed CR-02 in code comments), and IN-01 (manifest script
missing an `exported=false` assertion).

**CR-01** (`ForegroundServiceHost.onStartCommand` re-checking `ref.hostedCount == 0` and calling
`stopSelf(startId)`) is correct and covered by a new, on-point regression test
(`singleAttachThenDetach_leavesZeroHostedJobs_forADeferredStartCommandToObserve`).

**WR-01/notification-refresh** (`detach()` now calling `instance?.refreshNotification()` in the
`else` branch) is correct as written; no new test was added (acknowledged in the fix report —
still blocked on the same missing-Robolectric constraint as before, not a regression).

**IN-01** (the manifest script's new `exported=false` check) is well done: it isolates the
`ForegroundServiceHost` `<service>` block via `awk` before grepping, so it cannot be satisfied by
a different node's `exported=false` attribute, and the fix report documents a real negative test
against a synthetic manifest fragment proving the isolation has teeth.

**CR-02/`awaitCompressResult`** (the `knownJobIds`/`consumedJobIds` guard) is the fix most worth
scrutinizing, per the dispatch brief, and it is where this pass found real gaps. The Kotlin half
is correct and has a dedicated, passing JVM test suite (`JobRegistryTest.kt`). The Swift half
(`JobRegistry.swift`/`Compression.swift`) is a faithful line-for-line mirror of the Kotlin logic
and — read carefully for type/actor-isolation correctness — appears free of compile errors: every
`@MainActor`-isolated call is properly `await`ed, `Result<CompressResultMessage, Error>` optional
comparisons don't require `Equatable`, and the `if let ..., !waiters.isEmpty` conditional-binding
syntax is valid. But two things are missing that the Kotlin half has and that this fix's own
"mirror Kotlin exactly" design intent calls for: it never resets `knownJobIds`/`consumedJobIds`/
`resultOutcomes`/`resultWaiters` on `cancelAll()` (a real platform-parity gap, WR-03 below), and
it has zero dedicated unit-test coverage for any of the new CR-02 members (`registerJob`,
`isKnownJobId`, `isConsumedJobId`, `completeResult`'s waiter-delivery branch, `awaitResult`) —
`RunnerTests.swift` on both iOS and macOS still only exercises the pre-existing `register`/`find`/
`cancel`/`cancelAll` surface, not one line of the new CR-02 additions (WR-04 below). Given the fix
report itself states the Swift side was verified by manual re-reading only (no local Swift
toolchain, Mac unreachable) and the compiling CI run had not finished at review time, this is the
one area of the four fixes that has not actually been proven correct by any test on the affected
platforms.

Separately, re-reading Android's own `cancelAll()` bookkeeping-reset (D-17, the mechanism CR-02's
`JobRegistryTest.kt` exercises) against how it is actually driven in production surfaced a real
race in the reset itself for a job that is genuinely in-flight at the moment of detach — the
common case cancelAll exists for — detailed as WR-02 below. The existing
`cancelAll_resetsKnownAndConsumedJobIdBookkeeping` test does not catch it because it never
registers a live `LiveJob` with a real cancel-triggered coroutine resumption; it only asserts the
synchronous bookkeeping-clear on jobs that were never actually "live" to begin with.

Everything else at this depth — the Dart FIFO queue, the two engines' encode/copy logic, the
iOS background-task guard's exactly-once `end()`, and the rest of the plumbing — was re-read and
holds up; no new issues found there beyond the three below.

## Warnings

### WR-01: `JobRegistry.cancelAll()` (Android) can silently resurrect the bookkeeping D-17/CR-02 clears, for exactly the jobs it just cancelled

**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt:130-142`

**Issue:** `cancelAll()`'s own doc comment states its purpose plainly: "a jobId from before
detach is simply unknown afterwards rather than stuck reporting a stale 'already consumed'
outcome." The implementation:

```kotlin
fun cancelAll() {
    for (jobId in jobs.keys.toList()) {
        cancel(jobId)
    }
    resultDeferreds.clear()
    knownJobIds.clear()
    consumedJobIds.clear()
}
```

`cancel(jobId)` synchronously mutates `jobs`/`cancelled` and invokes `job.onCancelled(reason)` —
for a real job (`TransformerEngine.attemptExport`), this is
`{ reason -> attemptDeferred.complete(ExportOutcome.Cancelled(reason)) }`. Completing that
`CompletableDeferred` schedules — it does not synchronously run — the resumption of the suspended
`attemptExport`/`compress()`/`Compression.startCompress` call chain that is parked on
`attemptDeferred.await()`: Pigeon's generated dispatch (`Messages.g.kt`) launches every
`CompressHostApi` call via `CoroutineScope(Dispatchers.Main).launch { ... }` — the
non-`.immediate` `Dispatchers.Main`, whose `isDispatchNeeded` always returns `true` regardless of
the calling thread, so every resumption goes through `Handler.post()` and runs on a *later*
main-Looper message, never inline within `cancel()`'s own call stack.

That means `cancelAll()`'s three `.clear()` calls run and return *before* any of the jobs it just
cancelled have actually unwound back through `Compression.startCompress`'s catch block, which is
the code that calls `JobRegistry.completeResult(jobId, Result.failure(e))` for a cancellation.
When that catch block does eventually run (on the next main-Looper message, after `cancelAll()`
has already returned to its own caller), `completeResult` calls `resultDeferredFor(jobId)`, whose
very first line is `knownJobIds.add(jobId)` — silently re-adding the jobId `cancelAll()` just
removed, and creating a brand-new `resultDeferreds` entry for it that nothing will ever clear
again (this was the *last* detach; there is no next `cancelAll()` coming to clean it up). The
existing regression test
(`JobRegistryTest.kt`'s `cancelAll_resetsKnownAndConsumedJobIdBookkeeping`) does not exercise this
path at all — it calls `cancelAll()` with `jobs` empty (no `LiveJob` was ever `register`ed in that
test), so there is no `onCancelled` callback to race, and the assertions pass by construction. The
scenario this misses — a plugin detaching while a job is still genuinely running — is precisely
the scenario `cancelAll()` exists to handle.

Net effect: on plugin detach with at least one still-running job, that job's `knownJobIds`/
`resultDeferreds` entries survive the detach cleanup indefinitely (this is a static Kotlin
`object`, so state persists across a `FlutterEngine` detach/reattach in the same process — e.g. a
cached-engine or add-to-app host). Not a hang or a crash (the leftover deferred does get completed
with the cancellation failure, so nothing reads it and blocks), but it is exactly the state D-17
says a caller should not observe past detach, and it silently defeats the guarantee the new
`JobRegistryTest.kt` suite claims to prove for the one case (a job still in flight) that actually
matters.

**Fix:** Either drain in-flight cancellations before clearing (e.g., collect the jobIds `cancelAll`
processed and re-clear just those entries once each has genuinely settled), or make the reset
resilient by having `cancelAll()` record a "detach generation" counter that `resultDeferredFor`/
`completeResult` check before re-adding to `knownJobIds` (refusing to resurrect an entry from a
generation than has already been torn down), or simplest: have `JobRegistry.cancel()`'s cancellation
path bypass the two-map bookkeeping entirely (a cancelled-via-`cancelAll` job doesn't need a
resurrectable `awaitCompressResult` entry at all, since the plugin is detaching). At minimum, add a
regression test that registers a real `LiveJob` (with an `onCancelled` that completes a
`CompletableDeferred` the way the real engine does) before calling `cancelAll()`, and asserts
`isKnownJobId` stays `false` after that deferred's resumption has actually run — the current test's
empty-`jobs` setup cannot catch this class of bug.

### WR-02: iOS/macOS `JobRegistry.cancelAll()` never resets `knownJobIds`/`consumedJobIds`/`resultOutcomes`/`resultWaiters` — Android's D-17 cleanup has no Swift counterpart

**File:** `darwin/compress_video/Sources/compress_video/JobRegistry.swift:98-104`

**Issue:** Android's `cancelAll()` (see WR-01 above) explicitly clears `resultDeferreds`,
`knownJobIds`, and `consumedJobIds` alongside cancelling every live job, with a doc comment
citing D-17 as the rationale. Swift's `cancelAll()` — called from both `CompressVideoPlugin.swift`
teardown paths (iOS's `detachFromEngine`, macOS's `handleWillTerminate`) — only touches `jobs`:

```swift
static func cancelAll() {
    for jobId in Array(jobs.keys) {
        cancel(jobId: jobId)
    }
    // no reset of resultOutcomes / resultWaiters / knownJobIds / consumedJobIds
}
```

`knownJobIds`, `consumedJobIds`, and any stashed `resultOutcomes` entries (from a job whose
caller never called `awaitCompressResult`, or one cancelled before that call arrived) are never
cleared on this platform, on either teardown path. This is a genuine parity gap introduced by the
CR-02 fix itself: every other member of the CR-02 pair (`registerJob`/`resultDeferredFor`,
`isKnownJobId`, `isConsumedJobId`, `completeResult`/`awaitResult` marking `consumedJobIds`) was
built as a deliberate line-for-line mirror of the Kotlin implementation (per this file's own doc
comments, e.g. "mirrors Android's `JobRegistry.kt` `knownJobIds`"), but the detach-reset half of
that mirror was left out. Since `JobRegistry` is a Swift `enum` with only `static` state, this is
process-lifetime state: on iOS, `detachFromEngine` can run without the process exiting (e.g. an
add-to-app host tearing down and later recreating a `FlutterEngine`), so this is a real,
unbounded accumulation across engine lifecycles, not merely a moot leak that a process exit
would resolve.

**Fix:** Add the same three-collection reset Android's `cancelAll()` performs, guarded the same
way:

```swift
static func cancelAll() {
    for jobId in Array(jobs.keys) {
        cancel(jobId: jobId)
    }
    resultOutcomes.removeAll()
    resultWaiters.removeAll()
    knownJobIds.removeAll()
    consumedJobIds.removeAll()
}
```

(Note: if WR-01's fix on Android moves toward a "detach generation" guard instead of a bare
`.clear()`, mirror whatever that ends up being here too, rather than re-diverging.)

### WR-03: The new CR-02 `JobRegistry`/`Compression` additions have zero dedicated test coverage on iOS/macOS

**File:** `darwin/compress_video/Sources/compress_video/JobRegistry.swift:143-204`,
`darwin/compress_video/Sources/compress_video/Compression.swift:117-145`;
`example/ios/RunnerTests/RunnerTests.swift`, `example/macos/RunnerTests/RunnerTests.swift`

**Issue:** Android's half of the CR-02 fix ships with a new, dedicated `JobRegistryTest.kt` (4
cases) directly exercising `isKnownJobId`, `isConsumedJobId`, `resultDeferredFor`,
`completeResult`, `forgetResult`, and `cancelAll`'s reset. The Swift half adds five new members to
`JobRegistry.swift` (`registerJob`, `isKnownJobId`, `isConsumedJobId`, the `resultWaiters`-delivery
branch of `completeResult`, and `awaitResult`'s two return paths) and rewrites
`Compression.awaitCompressResult`'s guard logic — none of which is touched by any test in either
`example/ios/RunnerTests/RunnerTests.swift` or `example/macos/RunnerTests/RunnerTests.swift` (the
existing `// MARK: - JobRegistry` sections in both files, confirmed by grep, only cover the
pre-existing `register`/`find`/`cancel`/`cancelAll`/`liveTempFilePaths` surface). The only test
added anywhere for this fix on the Dart side (`test/await_compress_result_test.dart`) mocks the
platform channel's reply and therefore proves the generated Dart proxy decodes the error shape
correctly — it proves nothing about the native Swift implementation that is supposed to produce
that reply.

The fix report itself is explicit about this gap: no Swift toolchain was available on danserver
and the Mac was unreachable, so the Swift changes "were... verified by careful manual re-reading
only... not by an actual `swiftc`/Xcode build," with the note "This should be confirmed by CI's
macOS/iOS jobs... before this finding is considered fully closed on the Apple side." Given the
dispatch brief for this re-review flags this exact code as not yet compiled, and this review found
a real, related gap in the same file (WR-02 above) that a unit test would very plausibly have
caught, the absence of any XCTest coverage for the new logic is worth calling out explicitly
rather than only relying on a CI compile to pass.

**Fix:** Add XCTest cases mirroring `JobRegistryTest.kt`'s four cases to both
`example/ios/RunnerTests/RunnerTests.swift` and `example/macos/RunnerTests/RunnerTests.swift`
(`registerJob` makes a jobId known; a fresh jobId is not known; `completeResult` + `awaitResult`
marks it consumed; `cancelAll` resets known/consumed bookkeeping — the last of which would also
have caught WR-02 above once written against a real registered `LiveJob`). `resultOutcomes`/
`resultWaiters`/`knownJobIds`/`consumedJobIds` are all `private`, so these would need either an
`internal`/`@testable import` visibility change or a small test-only accessor, matching however
the existing `JobRegistry` tests already get access to its other private state (if they do; if
`jobs` is already `private` and tested via `@testable import compress_video`, the same import
covers this).

---

_Reviewed: 2026-09-27T20:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
