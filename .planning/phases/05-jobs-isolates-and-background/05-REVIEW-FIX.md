---
phase: 05-jobs-isolates-and-background
fixed_at: 2026-09-27T20:35:00Z
review_path: .planning/phases/05-jobs-isolates-and-background/05-REVIEW.md
iteration: 2
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 5: Code Review Fix Report

**Fixed at:** 2026-09-27T20:35:00Z
**Source review:** .planning/phases/05-jobs-isolates-and-background/05-REVIEW.md
**Iteration:** 2

**Summary:**
- Findings in scope: 3
- Fixed: 3
- Skipped: 0

`fix_scope` was `critical_warning`. 05-REVIEW.md (iteration 2) reported 0 Critical and 3
Warning findings (WR-01, WR-02, WR-03); all three were fixed.

## Fixed Issues

### WR-01: `JobRegistry.cancelAll()` (Android) can silently resurrect the bookkeeping D-17/CR-02 clears, for exactly the jobs it just cancelled

**Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt`, `android/src/test/kotlin/com/danjjohnson/compress_video/JobRegistryTest.kt`
**Commit:** 843dc55
**Applied fix:** `cancel(jobId)`'s `onCancelled` callback only completes a `CompletableDeferred`
synchronously; the suspended `Compression.startCompress` call that actually calls
`completeResult` resumes on a LATER main-Looper message (Pigeon dispatches every
`CompressHostApi` call via the non-`.immediate` `Dispatchers.Main`). `cancelAll()`'s three
`.clear()` calls previously ran and returned before that resumption, so the belated
`completeResult` call silently re-added the jobId to `knownJobIds` via `resultDeferredFor`'s
`getOrPut` -- defeating the D-17 guarantee for exactly the case (a job still in flight at
detach) `cancelAll()` exists to handle.

Implemented the review's third suggested option (bypass the two-map bookkeeping for a
cancelled-via-`cancelAll` job): added a self-cleaning `tornDownJobIds` set that `cancelAll()`
populates with every jobId it cancels, before its `.clear()` calls run. `completeResult()` now
checks (and removes from) `tornDownJobIds` first and discards the outcome for any jobId still
present, instead of resurrecting `knownJobIds`/`resultDeferreds` bookkeeping `cancelAll()`
already tore down. `tornDownJobIds` only ever holds entries for jobs currently unwinding from
the most recent `cancelAll()` call -- it self-empties as each belated `completeResult` call
arrives and is discarded, so it never grows across the app's lifetime.

Added a new JVM regression test
(`cancelAll_doesNotResurrectBookkeeping_forALiveJobsBelatedCancellationCompletion`) that
registers a real `JobRegistry.LiveJob` (with `mainHandler`/`progressRunnable` Mockito-mocked,
since this is a plain JVM test with no Robolectric shadow layer and a real `Handler` would
throw against the unmocked Android stub jar), calls `cancelAll()`, asserts `isKnownJobId` is
already `false`, then simulates the belated `completeResult` call the real cancellation
completion would trigger later and asserts `isKnownJobId` stays `false` across it -- the
regression class the existing empty-`jobs` test could not catch. Verified:
`:compress_video:testDebugUnitTest` (all `JobRegistryTest` cases pass, including the new one,
with no compiler warnings) and the full Android unit test suite (all suites pass).

### WR-02: iOS/macOS `JobRegistry.cancelAll()` never resets `knownJobIds`/`consumedJobIds`/`resultOutcomes`/`resultWaiters` -- Android's D-17 cleanup has no Swift counterpart

**Files modified:** `darwin/compress_video/Sources/compress_video/JobRegistry.swift`
**Commit:** 7af5d26
**Applied fix:** Added the same four-collection reset Android's `cancelAll()` performs
(`resultOutcomes`, `resultWaiters`, `knownJobIds`, `consumedJobIds`). These four collections
are `@MainActor`-isolated (unlike `jobs`, which is plain `nonisolated` state), so the reset
runs inside a `Task { @MainActor in ... }` that `cancelAll()` enqueues -- the same
fire-and-forget hop-to-MainActor pattern already used elsewhere in this package
(`Compression.swift`'s progress-forwarding `Task { @MainActor [flutterApi] in ... }`) -- rather
than making `cancelAll()` itself `async`/`@MainActor`, which would force its two plain,
non-`async` `FlutterPlugin` call sites (iOS's `detachFromEngine(for:)`, macOS's
`handleWillTerminate(_:)`) to become `@MainActor`-isolated too, a change outside this fix's
scope and not something the review's own suggested snippet (a bare synchronous
`.removeAll()` sequence) would have compiled as written given `cancelAll()`'s existing
signature.

Every continuation in `resultWaiters` is drained and resumed with a typed `CompressVideoError`
(`code: "unknown"`) before the dictionary is cleared, rather than dropped by a bare
`.removeAll()` -- an unresumed `CheckedContinuation` is a Swift Concurrency runtime misuse (it
must be resumed exactly once), so silently discarding it the way Android's plain,
continuation-free bookkeeping safely can is not an option on this platform.

### WR-03: The new CR-02 `JobRegistry`/`Compression` additions have zero dedicated test coverage on iOS/macOS

**Files modified:** `example/ios/RunnerTests/RunnerTests.swift`, `example/macos/RunnerTests/RunnerTests.swift`
**Commit:** 547a9b8
**Applied fix:** Added 5 new XCTest cases to the `// MARK: - JobRegistry` section, mirroring
`JobRegistryTest.kt`'s 4 cases plus explicit coverage of the `resultWaiters` waiter-delivery
branch `completeResult` also has (a code path Kotlin's `CompletableDeferred`-based design has
no equivalent branch for): `registerJob` makes a jobId known but not consumed; a fresh jobId is
not known; `completeResult` (stash) then `awaitResult` returns the outcome and marks it
consumed; `awaitResult` called first is resumed by a later `completeResult` call (the
waiter-delivery branch, using a `@MainActor`-isolated test plus a same-executor enqueued `Task`
to deterministically force that ordering without a race); and `cancelAll()` resets
known/consumed bookkeeping for both a genuinely live, cancelled job and a CR-02-only-registered
one (this last case also directly proves the WR-02 fix above, polling briefly since
`cancelAll()`'s reset now runs on an enqueued `Task`).

Added byte-identically to `example/ios/RunnerTests/RunnerTests.swift` and
`example/macos/RunnerTests/RunnerTests.swift` (`diff` confirms identical after every edit,
matching this file's own existing convention and CI's diff check).

**Verification caveat (applies to all three fixes above):** no Swift toolchain is available on
danserver, and this run did not attempt to reach the MacBook Air. The Swift changes in
`JobRegistry.swift` and both `RunnerTests.swift` files were verified by careful manual
re-reading (Tier 1: type/actor-isolation correctness against the surrounding file and its
existing `@MainActor` patterns) and a brace-balance check (`grep -c '{' `/`'}'`, equal on all
three files), not by an actual `swiftc`/Xcode build. This matches the same caveat iteration 1's
WR-01 fix (Android+Swift `awaitCompressResult` guard) recorded, and should be confirmed by
CI's macOS/iOS jobs before these three findings are considered fully closed on the Apple side.
The Android side of WR-01 (this iteration's own JobRegistry.kt/JobRegistryTest.kt changes) was
fully compiled and test-run locally via `:compress_video:testDebugUnitTest`, with no caveat.

`flutter analyze --fatal-infos --fatal-warnings` (no issues), `flutter test` (100/100 passing),
`dart format` (0 files changed, checked with the `flutter-stable` SDK per project convention),
and `:compress_video:testDebugUnitTest` (full Android suite, all passing) were all re-run after
every fix in this iteration -- none affected by, or affecting, these changes beyond the two new
`JobRegistryTest.kt` cases already covered above.

## Skipped Issues

None -- all three findings in scope were fixed.

---

_Fixed: 2026-09-27T20:35:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
