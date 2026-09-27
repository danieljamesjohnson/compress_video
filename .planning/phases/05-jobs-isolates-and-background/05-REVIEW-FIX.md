---
phase: 05-jobs-isolates-and-background
fixed_at: 2026-09-27T22:10:00Z
review_path: .planning/phases/05-jobs-isolates-and-background/05-REVIEW.md
iteration: 3
findings_in_scope: 1
fixed: 1
skipped: 0
status: all_fixed
---

# Phase 5: Code Review Fix Report

**Fixed at:** 2026-09-27T22:10:00Z
**Source review:** .planning/phases/05-jobs-isolates-and-background/05-REVIEW.md
**Iteration:** 3

**Summary:**
- Findings in scope: 1
- Fixed: 1
- Skipped: 0

`fix_scope` was `critical_warning`. 05-REVIEW.md (iteration 3) reported 0 Critical and 1 Warning
finding (WR-04); it was fixed. `workflow.use_worktrees` is `false` for this project, so this run
edited and committed directly on `main` in the primary checkout -- no worktree was created and no
worktree cleanup applies.

## Fixed Issues

### WR-04: Swift `JobRegistry.cancelAll()`'s reset can still race a still-unwinding cancelled job's belated `completeResult` call, leaking a `resultOutcomes` entry forever

**Files modified:** `darwin/compress_video/Sources/compress_video/JobRegistry.swift`, `example/ios/RunnerTests/RunnerTests.swift`, `example/macos/RunnerTests/RunnerTests.swift`
**Commit:** 52cba90
**Applied fix:** Mirrored Android's `tornDownJobIds` guard (the same fix class WR-01 closed on
the Kotlin side last iteration) in Swift. `cancelAll()`'s synchronous loop already captures
`jobIdsBeingCancelled` before cancelling each job; its enqueued `Task { @MainActor in ... }` now
adds that same array into a new `@MainActor`-isolated `tornDownJobIds: Set<String>` as its first
step, before clearing `resultOutcomes`/`resultWaiters`/`knownJobIds`/`consumedJobIds`.
`completeResult(jobId:result:)` now checks `tornDownJobIds.remove(jobId) != nil` first (before
the existing `resultWaiters` waiter-delivery branch) and returns immediately, discarding the
outcome, if the jobId was one this exact `cancelAll()` already tore down -- rather than falling
through to `if resultOutcomes[jobId] == nil { resultOutcomes[jobId] = result }` and silently
creating an unreachable entry for a job with no bookkeeping left to reference it and no
guaranteed future `cancelAll()` to sweep it. `tornDownJobIds` is self-cleaning exactly like
Android's set: each belated `completeResult` call removes its own entry, so it only ever holds
jobIds currently unwinding from the most recent `cancelAll()`, never growing across the plugin's
lifetime.

Extended the WR-03 XCTests in both `example/ios/RunnerTests/RunnerTests.swift` and
`example/macos/RunnerTests/RunnerTests.swift` byte-identically with a new case,
`testJobRegistryCancelAllDoesNotResurrectBookkeepingForALiveJobsBelatedCompleteResultCall`,
mirroring Android's `cancelAll_doesNotResurrectBookkeeping_forALiveJobsBelatedCancellationCompletion`
test added last iteration. Unlike the existing `cancelAll()` reset test (whose live job's
`cancel` closure is a no-op that never calls `completeResult`), the new case's `LiveJob` is
registered with a `cancel` closure that genuinely records its reason, then: calls `cancelAll()`;
polls (as the existing test already does) until `isKnownJobId` confirms the enqueued reset `Task`
has run; and only then calls `completeResult(jobId:result:)` for that same jobId, simulating
`Compression.startCompress`'s own catch block resuming on a later main-queue turn than
`cancelAll()`'s own call stack. Asserts `isKnownJobId` stays `false` across that belated call --
the same indirect proof Android's test uses, since `resultOutcomes`/`resultDeferreds` are private
on both platforms and neither test can inspect them directly. `diff` confirms both
`RunnerTests.swift` files remain byte-identical after the edit.

**Verification caveat:** no Swift toolchain is available on danserver, and this run did not
attempt to reach the MacBook Air (this fix ran in the foreground, as instructed, not as an
autonomous/background task that could have justified the round-trip). Verified by careful manual
re-reading against the surrounding file's existing `@MainActor`/actor-isolation patterns (Tier 1)
and a brace/paren-balance check across all three modified files (Tier 3 fallback -- no
`node`/`python`-equivalent syntax checker exists for Swift; counts matched pre- and post-edit).
All verification and the commit ran in the main checkout at
`/home/dan/CodeProjects/compress-video` (no worktree -- `workflow.use_worktrees` is `false`), so
these results are reproducible directly from that tree. This matches the same caveat iterations 1
and 2 recorded for this phase's Swift-side fixes, and should be confirmed by CI's macOS/iOS jobs
or a MacBook Air run before this finding is considered fully closed on the Apple side.

`flutter analyze`/`flutter test`/`dart format` were not re-run for this iteration since no Dart
source changed -- only `darwin/` Swift sources and the two `RunnerTests.swift` XCTest files,
neither of which those Dart-toolchain gates cover.

## Skipped Issues

None -- the one finding in scope was fixed.

## Post-fix CI follow-up (same pass, coordinator-directed)

CI run 36341131702 reported the plugin itself compiles, but both `RunnerTests.swift` files
failed to compile: `RunnerTests.swift:1432/1439/1441/1443`, `"'await' in an autoclosure that does
not support concurrency"` and `"call to main actor-isolated static method 'isKnownJobId'/
'isConsumedJobId' in a synchronous nonisolated context"`.

**Root cause:** `XCTAssert*`'s condition/message parameters, and the `||` operator's
right-hand-side parameter, are plain (non-`async`) `@autoclosure`s. Writing `await
JobRegistry.isKnownJobId(...)` directly inside either one is rejected by the compiler even though
the enclosing test method is itself `async` -- the `await` needs a local `let` binding first.

**Commit:** 9278860 (`fix(05): XCTests bind main-actor JobRegistry calls before asserting`)

**Files modified:** `example/ios/RunnerTests/RunnerTests.swift`, `example/macos/RunnerTests/RunnerTests.swift`

**Lines fixed** (pre-existing iteration-2 test `testJobRegistryCancelAllResetsKnownAndConsumedJobIdBookkeeping`, plus this iteration's own new WR-04 test):
- The `stillKnown = (await ...) || (await ...)` polling-loop line -- split into two bound `let`s (`liveStillKnown`, `otherStillKnown`) before the `||`.
- `XCTAssertFalse(await JobRegistry.isKnownJobId(liveJobId), ...)` -- bound to `liveKnownAfterReset` first.
- `XCTAssertFalse(await JobRegistry.isKnownJobId(knownJobId), ...)` -- bound to `knownAfterReset` first.
- `XCTAssertFalse(await JobRegistry.isConsumedJobId(consumedJobId), ...)` -- bound to `consumedAfterReset` first.
- This iteration's own new `testJobRegistryCancelAllDoesNotResurrectBookkeepingForALiveJobsBelatedCompleteResultCall`'s final `XCTAssertFalse(await JobRegistry.isKnownJobId(jobId), ...)` -- bound to `knownAfterBelatedCompleteResult` first (had the identical bug, introduced in this same iteration's WR-04 commit before this follow-up).

No other `await`-inside-autoclosure sites were found elsewhere in either file (checked every
`XCTAssert*` call and every `||`/`&&` use across both `// MARK: - JobRegistry` sections).
`example/ios/RunnerTests/RunnerTests.swift` was edited directly, then copied byte-for-byte onto
`example/macos/RunnerTests/RunnerTests.swift`; `diff` confirms both files remain identical, and a
brace/paren-balance check (open/close counts equal) passed on both post-edit. Same verification
caveat as above applies: no Swift toolchain on danserver, so this was not compiled locally --
CI's next run against commit 9278860 is the actual confirmation.

---

_Fixed: 2026-09-27T22:10:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 3_
