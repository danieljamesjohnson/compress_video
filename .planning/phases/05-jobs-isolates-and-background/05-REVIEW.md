---
phase: 05-jobs-isolates-and-background
reviewed: 2026-09-27T21:15:00Z
depth: standard
files_reviewed: 16
files_reviewed_list:
  - android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/ForegroundServiceHost.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/JobRegistryTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/ForegroundServiceHostTest.kt
  - darwin/compress_video/Sources/compress_video/Compression.swift
  - darwin/compress_video/Sources/compress_video/CompressionEngine.swift
  - darwin/compress_video/Sources/compress_video/JobRegistry.swift
  - example/ios/RunnerTests/RunnerTests.swift
  - example/macos/RunnerTests/RunnerTests.swift
  - lib/src/compress_job.dart
  - lib/compress_video.dart
  - test/await_compress_result_test.dart
  - test/compress_video_queue_test.dart
  - tool/verify_apk_foreground_service_manifest.sh
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-09-27T21:15:00Z
**Depth:** standard
**Files Reviewed:** 16
**Status:** issues_found

## Summary

Iteration 3 re-review of the three fixes committed against iteration 2's 05-REVIEW.md (WR-01
Android `cancelAll()` bookkeeping resurrection, WR-02 Swift `cancelAll()` missing the same reset,
WR-03 missing XCTest coverage), commits `843dc55`, `7af5d26`, `547a9b8`. `git diff` against the
iteration-2 review commit confirms only 5 files actually changed:
`android/.../JobRegistry.kt`, `android/.../JobRegistryTest.kt`,
`darwin/.../JobRegistry.swift`, and both `example/{ios,macos}/RunnerTests/RunnerTests.swift`
(confirmed byte-identical to each other, as the fix report claims). Every other file in this
phase's scope is unchanged since iteration 2's clean pass over them, so this review concentrates
on the changed files and their direct callers (`Compression.kt`/`Compression.swift`).

**WR-01 (Android)** is correctly and completely fixed. `cancelAll()` now records every jobId it is
about to cancel into a new `tornDownJobIds` set before cancelling, and `completeResult()` checks
(and drains) that set first, discarding the outcome for any jobId still present instead of letting
`resultDeferredFor`'s `getOrPut` resurrect `knownJobIds`/`resultDeferreds`. Traced the full timing
argument from the fix report (Pigeon's non-`.immediate` `Dispatchers.Main` means the cancelled
job's belated `completeResult` call always lands on a later main-Looper message than `cancelAll()`
itself) and it holds. The new `cancelAll_doesNotResurrectBookkeeping_forALiveJobsBelatedCancellationCompletion`
test registers a real `LiveJob` and explicitly simulates that belated call, which is exactly the
scenario the old, empty-`jobs`-only test could not catch — this is a real regression test, not a
restatement of the old one. `tornDownJobIds` is self-cleaning as documented (each belated call
removes its own entry) and cannot grow unboundedly across the app's lifetime. No leftover issue
found here.

**WR-03 (XCTest coverage)** is done as claimed: five new cases were added identically to both
`RunnerTests.swift` files, exercising `registerJob`/`isKnownJobId`/`isConsumedJobId`, both the
`resultOutcomes`-stash and `resultWaiters`-waiter-delivery branches of `completeResult`, and
`cancelAll()`'s bookkeeping reset. This is real, on-point coverage that did not exist before.

**WR-02 (Swift `cancelAll()` reset) is fixed for the property it was written to prove, but the fix
does not fully close the underlying race, and the new test does not catch the remaining gap** —
see WR-04 below. This is a narrower, lower-severity version of the same race class WR-01 fixed on
Android, in the one place where the Swift and Kotlin implementations were not, in fact, mirrored
symmetrically. Read closely for continuation double-resume risk as directed: found none — every
`CheckedContinuation` in `resultWaiters` is claimed via `removeValue(forKey:)` inside a
non-suspending `@MainActor` function body (either `completeResult` or `cancelAll()`'s enqueued
`Task`), so whichever of the two reaches a given jobId's entry first exclusively owns and resumes
it; there is no `await` between the read and the resume in either path, so the two can never both
resume the same continuation.

## Warnings

### WR-04: Swift `JobRegistry.cancelAll()`'s reset can still race a still-unwinding cancelled job's belated `completeResult` call, leaking a `resultOutcomes` entry forever — the same race class WR-01 fixed on Android, left open here

**File:** `darwin/compress_video/Sources/compress_video/JobRegistry.swift:118-138, 206-222`

**Issue:** WR-01's Android fix specifically targeted this timing: `cancel(jobId)`'s
`onCancelled`/`cancel` closure only flips a flag or completes a deferred *synchronously* — the
suspended `startCompress` call's own catch block, which is what actually calls `completeResult`,
only resumes later, after `cancelAll()` (and, on Android, its `.clear()` calls) has already
returned. Android's fix closes this by recording every jobId `cancelAll()` is about to cancel into
`tornDownJobIds` *before* clearing, so a belated `completeResult` call for one of those jobIds is
recognised and discarded rather than resurrecting bookkeeping.

The Swift mirror has exactly the same timing shape — `CompressionEngine`'s copy loop only observes
a cancellation flag "on its next sample" (per this file's own `cancel(jobId:)` doc comment, D-08,
an explicitly accepted per-sample latency bound) — but the WR-02 fix did not add an equivalent
generation/torn-down guard. `cancelAll()`'s synchronous loop cancels the job and removes it from
`jobs`, then enqueues a `Task { @MainActor in ... }` that clears `resultOutcomes`/`resultWaiters`/
`knownJobIds`/`consumedJobIds` and resumes any pending waiters. If the cancelled job's own
`Compression.startCompress` catch block calls `await JobRegistry.completeResult(jobId:result:)`
*after* that enqueued `Task` has already run (the expected ordering, since the per-sample copy-loop
latency is generally larger than one MainActor turnaround), `completeResult` finds no waiters
(already cleared) and falls into:

```swift
if resultOutcomes[jobId] == nil {
  resultOutcomes[jobId] = result
}
```

silently creating a fresh `resultOutcomes[jobId]` entry for a job that has already been torn down.
Nothing will ever read it — `knownJobIds` was already reset and `completeResult` never re-adds to
it (unlike Android's `resultDeferredFor`, which does), so `isKnownJobId` correctly stays `false`
and a caller cannot be misled into a stale "already consumed" state; the D-17 *user-observable*
contract is not broken. But the entry itself is now indistinguishable from a legitimate
never-consumed result and has no future `cancelAll()` guaranteed to sweep it (this was the last
one, on the same iOS "detach without process exit" scenario this file's own doc comment cites as
the reason `cancelAll()` needed a reset at all) — the exact unbounded-growth-across-engine-cycles
problem `cancelAll()`'s own doc comment says this fix exists to prevent, reintroduced for this one
timing window.

The new WR-03 regression test (`testJobRegistryCancelAllResetsKnownAndConsumedJobIdBookkeeping`)
does not catch this: its `liveJobId` is registered with `cancel: { _ in }` — a no-op closure that
never calls `completeResult` for that jobId at all, let alone belatedly after the reset `Task` has
already run. It proves the reset happens, not that a late-arriving completion can't undo part of
it — the same gap class Android's dedicated
`cancelAll_doesNotResurrectBookkeeping_forALiveJobsBelatedCancellationCompletion` test was written
specifically to close, and which has no Swift counterpart.

**Fix:** Mirror Android's `tornDownJobIds` guard in Swift: add an `@MainActor`-isolated
`tornDownJobIds: Set<String>` that `cancelAll()`'s enqueued `Task` populates with every jobId it
is cancelling (captured from the synchronous `for jobId in Array(jobs.keys)` loop, before the
`Task` clears the other four collections), and have `completeResult` check-and-remove from it
first, discarding the outcome instead of stashing into `resultOutcomes`:

```swift
static func cancelAll() {
  let jobIdsBeingCancelled = Array(jobs.keys)
  for jobId in jobIdsBeingCancelled {
    cancel(jobId: jobId)
  }
  Task { @MainActor in
    tornDownJobIds.formUnion(jobIdsBeingCancelled)
    resultOutcomes.removeAll()
    ...
  }
}

@MainActor static func completeResult(jobId: String, result: Result<CompressResultMessage, Error>) {
  if tornDownJobIds.remove(jobId) != nil { return }
  ...
}
```

Add a Swift regression test mirroring Android's: register a real `LiveJob` whose `cancel` closure
records the reason (not a no-op), call `cancelAll()`, poll until the reset `Task` has run (as the
existing test already does), then call `completeResult(jobId:result:)` for that same jobId
afterward and assert `resultOutcomes`/`isKnownJobId` do not resurrect anything reachable — the
scenario the current test's no-op `cancel` closure cannot exercise.

---

_Reviewed: 2026-09-27T21:15:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
