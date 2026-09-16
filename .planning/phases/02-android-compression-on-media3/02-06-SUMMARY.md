---
phase: 02-android-compression-on-media3
plan: 06
subsystem: compression-engine
tags: [media3, transformer, kotlin, jobs, cancel, error-mapping, statfs, coroutines]

# Dependency graph
requires:
  - phase: 02-android-compression-on-media3
    provides: "02-02's JobRegistry/TransformerEngine tracer architecture (one Transformer per job on the main Looper, CompletableDeferred-based completion) and 02-05's audio/trim/orientation-complete TransformerEngine this plan hardens rather than re-decides"
provides:
  - "Per-job progress hardened: clamped into 0..99 during polling, monotonically non-decreasing, a single explicit terminal 100 sent once before a successful/never-larger/remux reply; both Transformer.Listener terminal callbacks stop polling the instant they fire via JobRegistry.stopPolling"
  - "CompressJob._run closes the progress stream BEFORE completing result on every terminal path (success, failure, cancellation), not after -- a real ordering guarantee, not a race"
  - "Cancel: JobRegistry.cancel's existing lookup-cancel-delete-remove-notify sequence, now decoupled from Media3 entirely (LiveJob.cancelTransformer callback, not a raw Transformer reference) so it is plain-JVM-testable; CompressVideoPlugin.onDetachedFromEngine cancels every live job BEFORE clearing host API registrations (T-02-25)"
  - "ErrorMapping.kt: a pure, no-Android-import object implementing the full 22-code ExportException.errorCode -> reason table plus the out-of-space message check, extracted from TransformerEngine's own inline when-block"
  - "TransformerEngine.resolvePlan (exposed, not private) so Compression's pre-flight free-space check (StatFs against 1.2x the predicted output, before a Transformer exists) resolves the identical SizeGuard.Plan compress() itself will use"
  - "A real observed ExportException.errorCode (2000, ERROR_CODE_IO_UNSPECIFIED) from compressing the genuinely damaged truncated_mdat.mp4 corpus fixture -- 02-RESEARCH.md Open Question 2 resolved by direct observation, agreeing with the recommended mapping (io)"
affects: [phase-6-readme]

# Actuals (#2632)
actuals:
  tokens: 18981
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "JobRegistry.LiveJob holds a cancelTransformer: () -> Unit callback rather than a raw androidx.media3.transformer.Transformer reference -- Transformer's own static initializer touches Android framework internals unavailable in a plain JVM unit test (the same class of landmine as constructing a real Transformer anywhere in a test), so this decoupling is what makes CompressVideoPluginTest's detach cases possible at all without Robolectric or an emulator"
    - "ErrorMapping.kt follows the same pure-JVM-testable shape as SizeGuard.kt and MediaMath.kt: no Android/Media3 import, a table-driven test suite with one named case per code, and the table's own size asserted directly so an added code without a matching test fails the suite"
    - "TransformerEngine.resolvePlan is the single resolution both the pre-flight check (Compression.kt) and the real encode (compress()) call -- exactly SizeGuard.Plan's own established pattern (02-04) of one shared resolution neither call path can independently disagree with"
    - "A completer/future close-then-complete ordering (progress stream closes BEFORE result resolves, not in an unordered finally block) is now the pattern for any future terminal-outcome sequencing in this package -- Completer.complete schedules listeners onto a later microtask, so 'complete then close' never actually guaranteed an observer of the completed future saw an already-closed stream"

key-files:
  created:
    - android/src/main/kotlin/com/danjjohnson/compress_video/ErrorMapping.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/ErrorMappingTest.kt
    - test/compress_job_test.dart
    - example/integration_test/compress_jobs_test.dart
  modified:
    - android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/CompressVideoPlugin.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/CompressVideoPluginTest.kt
    - lib/src/compress_job.dart
    - example/integration_test/compress_test.dart

key-decisions:
  - "Progress runnable clamps polled values into 0..99, not 0..100 -- measured live this task: the exporter can report PROGRESS_STATE_AVAILABLE with progress already at 100 for several poll ticks before onCompleted actually fires (muxing/finalisation happens after the reported progress reaches its own ceiling). Reserving the single canonical 100 for the explicit onProgress(100.0) call made once, right before a successful reply, is what makes 'appears exactly once' true rather than aspirational."
  - "CompressJob._run now closes the progress stream and THEN completes result, on every terminal path -- previously (02-02) both happened in a single try/finally with result completed first and the stream closed in finally afterward, which never actually guaranteed an observer of result saw an already-closed stream (Completer.complete schedules its listeners onto a later microtask). This is a real behavioral change: a caller doing `await job.result; await subscription.asFuture()` (compress_test.dart's own pre-existing pattern) would now hang forever, since asFuture() attaches to a subscription whose done event may have already fired. Fixed compress_test.dart to attach asFuture() immediately after listen(), before awaiting result, which is the correct Dart idiom regardless of this ordering change."
  - "JobRegistry.LiveJob.transformer (a raw androidx.media3.transformer.Transformer field) was replaced with LiveJob.cancelTransformer (a () -> Unit callback) after CompressVideoPluginTest's new detach cases discovered Transformer cannot be constructed OR mocked in a plain JVM unit test -- its static initializer calls Util.isRunningOnEmulator, which NPEs against the unit-test android.jar's unmocked Build fields, and Mockito's inline mock maker still has to initialize the real class to instrument it. This is the same landmine class 02-02 already worked around for Handler/Looper in TransformerEngine's own constructor."
  - "CompressVideoPlugin.onDetachedFromEngine now cancels every live job BEFORE clearing the ProbeHostApi/ThumbnailHostApi/CompressHostApi registrations, reversing 02-02's original order -- matches T-02-25's threat-register disposition exactly ('cancels every live job... before clearing registration'), which the original code did not."
  - "TransformerEngine.mapExportException now always folds the numeric ExportException.errorCode into the failure message text, not just when Media3's own exception message happens to be null -- found while writing the truncated_mdat.mp4 real-failure case: CompressVideoException.platformDetail is ONLY populated Dart-side when the mapped reason is 'unknown' (reasonFromPlatformCode/_wrapPlatformException, established in 02-02/02-03), so a recognised reason like 'io' made the original code completely unobservable from Dart -- defeating this plan's own stated goal that a caller could paste the exact code into an issue report."
  - "The pre-flight free-space check duplicates one SizeGuard.resolve() call (once in Compression's check, once inside TransformerEngine.compress) rather than threading a pre-computed Plan through the compress() call signature -- SizeGuard.resolve is a pure, cheap function with no I/O of its own, and threading the Plan through would have meant changing compress()'s public signature for every existing call site; TransformerEngine.resolvePlan being a single shared function guarantees both call sites can never disagree, which is the property that actually matters."

patterns-established:
  - "A close-then-complete (not complete-then-close) ordering for any Completer/StreamController pair representing 'the operation's outcome' and 'a side-channel stream that must reflect it' -- so 'X happens no later than Y resolves' is an enforced invariant, not a hopeful comment."
  - "Any class needing to hold 'how to stop the current Media3 operation' should take a callback, not a concrete Transformer/Player/etc. reference -- keeps registry-shaped code plain-JVM-testable."

requirements-completed: [JOBS-01, JOBS-02, CORE-03, CORE-04]

coverage:
  - id: D1
    description: "Two jobs started together each have their own progress stream and completion future: both reach 100 and both results complete independently, with no event from one job appearing on the other's stream"
    requirement: JOBS-01
    verification:
      - kind: integration
        ref: "compress_jobs_test.dart#'two jobs started together each reach 100, complete independently, and produce two different, both-existing files...'"
        status: pass
      - kind: unit
        ref: "compress_job_test.dart#\"an event addressed to a known id reaches only that job's stream, never a second job's\""
        status: pass
    human_judgment: false
  - id: D2
    description: "A job's progress stream works correctly whether or not anyone is listening: no listener still resolves result cleanly, a late subscription after completion closes immediately, and the controller closes exactly once on each of the three terminal paths (success, failure, cancellation)"
    requirement: JOBS-01
    verification:
      - kind: unit
        ref: "compress_job_test.dart (10 cases: identity, unknown-id routing, no-listener success/failure, late subscription, closed-exactly-once x3)"
        status: pass
    human_judgment: false
  - id: D3
    description: "A single job's progress values are all within 0-100, monotonically non-decreasing, end with exactly one terminal 100, and the stream closes before or as the result completes"
    requirement: JOBS-01
    verification:
      - kind: integration
        ref: "compress_jobs_test.dart#\"a single job's progress values are all within 0-100, monotonically non-decreasing, and end with exactly one 100...\""
        status: pass
    human_judgment: false
  - id: D4
    description: "Cancelling mid-flight resolves the job's result with a cancelled CompressVideoException, closes the progress stream, and deletes the partial output file BEFORE the future resolves"
    requirement: JOBS-02
    verification:
      - kind: integration
        ref: "compress_jobs_test.dart#'cancelling mid-flight resolves as cancelled with the partial file already gone before the future resolves'"
        status: pass
    human_judgment: false
  - id: D5
    description: "Cancel is idempotent (a second cancel resolves without error and does not delete anything a second time) and a no-op after successful completion (finished output stays in place, result unchanged)"
    requirement: JOBS-02
    verification:
      - kind: integration
        ref: "compress_jobs_test.dart#'a second cancel() on the same job completes without error...'"
        status: pass
      - kind: integration
        ref: "compress_jobs_test.dart#'a cancel issued after successful completion is a no-op...'"
        status: pass
    human_judgment: false
  - id: D6
    description: "Cancelling one of several concurrent jobs leaves the others to complete normally; detaching from the Flutter engine cancels every live job, deletes every partial file, and clears host-API registrations, with no job outliving the engine"
    requirement: JOBS-02
    verification:
      - kind: integration
        ref: "compress_jobs_test.dart#'cancelling one of three jobs leaves the other two to complete normally...'"
        status: pass
      - kind: unit
        ref: "CompressVideoPluginTest.kt#onDetachedFromEngine_cancelsEveryLiveJobAndEmptiesTheRegistry, #onDetachedFromEngine_withNoLiveJobs_detachesCleanly"
        status: pass
    human_judgment: false
  - id: D7
    description: "Every one of the 22 ExportException error codes maps to a known CompressVideoErrorReason through one pure, table-driven-tested function; an unrecognised code maps to unknown with the original code preserved, never silently bucketed"
    requirement: CORE-04
    verification:
      - kind: unit
        ref: "ErrorMappingTest.kt (28 cases: 22 codes + table-size assertion + unknown-code fallback + 4 out-of-space message cases)"
        status: pass
    human_judgment: false
  - id: D8
    description: "Compressing the genuinely damaged truncated_mdat.mp4 fails with a typed CompressVideoException (not a crash or null); the observed ExportException.errorCode (2000, ERROR_CODE_IO_UNSPECIFIED) is recorded and agrees with the recommended mapping; no partial file remains"
    requirement: CORE-04
    verification:
      - kind: integration
        ref: "compress_jobs_test.dart#'compressing the genuinely damaged truncated_mdat.mp4 fails with a typed CompressVideoException...'"
        status: pass
    human_judgment: false
  - id: D9
    description: "A missing path, a zero-byte file, and a plain-text file renamed to .mp4 each fail with a typed reason and leave no file behind"
    requirement: CORE-04
    verification:
      - kind: integration
        ref: "compress_jobs_test.dart#'compressing a path that does not exist fails with reason fileNotFound'"
        status: pass
      - kind: integration
        ref: "compress_jobs_test.dart#'compressing a zero-byte file fails with reason unsupportedInput'"
        status: pass
      - kind: integration
        ref: "compress_jobs_test.dart#'compressing a plain text file renamed to .mp4 fails with a typed reason...'"
        status: pass
    human_judgment: false
  - id: D10
    description: "Every CompressResult field described by CORE-03 (output path, bytes before/after, dimensions, duration, codec, transmuxed, elapsed time) is populated and never resolves to null on any success or failure path, across all cases this plan added"
    requirement: CORE-03
    verification:
      - kind: integration
        ref: "compress_jobs_test.dart (all progress/two-job/cancel-after-success cases assert full CompressResult field values)"
        status: pass
    human_judgment: false
  - id: D11
    description: "A pre-flight free-space check (StatFs against 1.2x the predicted output) exists and runs before any Transformer is built, and an out-of-space condition surfacing mid-encode maps to outOfSpace via a message-string check"
    requirement: null
    verification: []
    human_judgment: true
    rationale: "The plan's own acceptance criteria for this truth are static (grep for StatFs/1.2/outOfSpace, all satisfied) rather than a functional trigger test -- there is no practical way to make the shared danserver emulator's filesystem genuinely run out of space in an automated integration test without risking the shared host. The code path is implemented and code-reviewed against the exact predicted-bytes arithmetic SizeGuard already unit-tests, but a human should confirm this reasoning is acceptable rather than have it auto-pass on the grep checks alone."
  - id: D12
    description: "CORE-04's flagged assumption (02-06-PLAN.md's own unresolved probe edge: DECODER_INIT_FAILED -> decoderUnavailable vs DECODING_FORMAT_UNSUPPORTED/DECODING_FAILED -> unsupportedInput, and the ENOSPC message-match for outOfSpace) is carried forward unresolved, per the plan's own instruction"
    requirement: CORE-04
    verification: []
    human_judgment: true
    rationale: "The one real failure this plan observed (truncated_mdat.mp4 -> ERROR_CODE_IO_UNSPECIFIED, 'io') did not exercise either ambiguous branch the plan flagged (DECODER_INIT_FAILED vs DECODING_FORMAT_UNSUPPORTED, or the ENOSPC message match) -- it agrees with the mapping for the code it DID produce, but does not by itself resolve A1's or A2's underlying assumption. No corpus fixture in this project reliably produces a genuine decoder-unavailable or decoding-format-unsupported failure (that would need a codec the device's hardware/software decoders both refuse, not a truncated container). Surfaced here for the verifier, not closed by fiat, per 02-06-PLAN.md's explicit instruction."

# Metrics
duration: ~48min
completed: 2026-09-15
status: complete
---

# Phase 2 Plan 06: Per-Job Cancel, Progress Hardening and Complete Error Mapping Summary

**Independent per-job progress (clamped, monotonic, one terminal 100) and cancellation (typed cancelled outcome, partial file gone before the future resolves, idempotent, cancel-all on detach), a pure table-driven mapping for all 22 `ExportException` codes, a pre-flight free-space check, and a real observed platform failure (`ERROR_CODE_IO_UNSPECIFIED`) from a genuinely damaged file.**

## Performance

- **Duration:** ~48 min
- **Started:** 2026-09-15T20:36:00-05:00 (approx.)
- **Completed:** 2026-09-15T21:16:00-05:00
- **Tasks:** 3 completed
- **Files modified:** 11 (4 created, 7 modified)

## Accomplishments

- Hardened `TransformerEngine`'s progress polling: every polled value is clamped into 0..99 and forwarded only if it is not smaller than the last one sent for that job (monotonically non-decreasing); the single canonical terminal 100 is sent once, explicitly, right before a successful/never-larger/remux reply. Both `Transformer.Listener` terminal callbacks now call `JobRegistry.stopPolling` the instant they fire, rather than relying on `JobRegistry.remove` after the suspended `compress()` call resumes.
- Fixed a real ordering gap in `CompressJob._run`: the progress stream now closes BEFORE `result` completes, on every terminal path -- previously both happened in one `try`/`finally` with no actual guarantee an observer of `result` saw an already-closed stream, since `Completer.complete` schedules its listeners onto a later microtask. Fixed the one pre-existing test (`compress_test.dart`'s tracer) whose `await job.result; await subscription.asFuture()` pattern would otherwise hang forever now that the stream can already be closed by the time `result` resolves.
- Implemented cancel end to end: `JobRegistry.cancel`'s existing stop-polling/cancel-exporter/delete-temp-file/remove/notify sequence is unchanged in behavior but now holds a `cancelTransformer` callback instead of a raw `Transformer` reference, decoupling the registry from Media3 entirely -- discovered necessary because `Transformer`'s own static initializer cannot run in a plain JVM unit test (the same landmine class as constructing a real `Transformer` anywhere in a test), which is what makes `CompressVideoPluginTest`'s new detach cases possible at all.
- Reordered `CompressVideoPlugin.onDetachedFromEngine` to cancel every live job BEFORE clearing host API registrations, matching T-02-25's threat-register disposition exactly (the prior order was reversed).
- Extracted the full `ExportException.errorCode -> CompressVideoErrorReason` table (all 22 documented codes, including the `MUXING_APPEND` code CONTEXT.md's own table did not name) from `TransformerEngine`'s inline `when` block into `ErrorMapping.kt` -- a pure Kotlin object with no Android/Media3 import, proven by `ErrorMappingTest.kt`'s 28 table-driven cases with no emulator. Added `reasonForExportFailure`'s best-effort out-of-space message check.
- Added `TransformerEngine.resolvePlan` (shared by `compress()` and the new pre-flight check) and `Compression`'s free-space check: reads the destination filesystem's free space via `StatFs` and fails with `outOfSpace` before a `Transformer` is ever built when it is less than 1.2x the predicted output.
- Observed a REAL platform failure: compressing `corpus/truncated_mdat.mp4` on the emulator produced `ExportException.errorCode=2000` (`ERROR_CODE_IO_UNSPECIFIED`, cause `ExoPlaybackException: Source error`), which maps to reason `"io"` -- agreeing with the recommended mapping and resolving 02-RESEARCH.md's Open Question 2 by direct observation rather than assumption. Also found and fixed that `CompressVideoException.platformDetail` is only populated Dart-side for the `unknown` reason, making the numeric code unobservable for any other (recognised) reason -- `mapExportException` now always folds the code into the message text.
- Added `example/integration_test/compress_jobs_test.dart` (10 cases: progress ordering, two-job independence, four cancellation cases, four real-failure cases) and `test/compress_job_test.dart` (10 platform-free unit cases).

## Task Commits

Each task was committed atomically:

1. **Task 1: Per-job progress — independent streams, monotonic values and an exact final 100** - `3d6cfb8` (feat)
2. **Task 2: Cancel — typed outcome, closed stream, deleted partial, idempotent, and cancel-all on detach** - `7031810` (feat)
3. **Task 3: The complete error mapping, a real observed failure, and the pre-flight space check** - `3718a85` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified

- `android/.../ErrorMapping.kt` *(created)* - Pure 22-code error mapping + out-of-space message check
- `android/.../ErrorMappingTest.kt` *(created)* - 28-case JVM suite, no emulator
- `android/.../TransformerEngine.kt` - Clamped/monotonic progress, `stopPolling` in terminal callbacks, `resolvePlan`, `mapExportException` via `ErrorMapping`
- `android/.../JobRegistry.kt` - `LiveJob.cancelTransformer` callback (not a raw `Transformer`), new `stopPolling`
- `android/.../Compression.kt` - Pre-flight `StatFs`-based free-space check before any `Transformer` is built
- `android/.../CompressVideoPlugin.kt` - Detach cancels jobs BEFORE clearing host API registrations
- `android/.../CompressVideoPluginTest.kt` - Two new detach cases (empties registry + deletes partial file; clean with no jobs)
- `lib/src/compress_job.dart` - `_run` closes the progress stream before completing `result`, on every terminal path
- `example/integration_test/compress_test.dart` - Fixed the tracer's `asFuture()` ordering for the new close-before-complete guarantee
- `test/compress_job_test.dart` *(created)* - 10-case platform-free Dart suite (identity, routing, no-listener, late subscription, closed-exactly-once)
- `example/integration_test/compress_jobs_test.dart` *(created)* - 10-case emulator suite (progress ordering, two-job independence, 4 cancellation cases, 4 real-failure cases)

## Decisions Made

See `key-decisions` in frontmatter for the full list. Most consequential: the close-before-complete reordering in `CompressJob._run` (a real behavior change requiring a fix to a pre-existing test), and replacing `LiveJob.transformer` with `LiveJob.cancelTransformer` (necessary for the detach path to be unit-testable at all, since `Transformer` cannot be constructed or mocked outside a real device/emulator).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The progress runnable's naive 0..100 clamp allowed 100 to appear multiple times**
- **Found during:** Task 1, first emulator run of the single-job progress-ordering case
- **Issue:** Media3's exporter can report `PROGRESS_STATE_AVAILABLE` with `progress` already at 100 for several poll ticks before `onCompleted` actually fires (muxing/finalisation happens after the reported progress reaches its own ceiling) -- the observed sequence had 100 appear 6 times, failing the plan's own "100 appears exactly once" acceptance criterion.
- **Fix:** Clamped the polling loop's own forwarded value into 0..99, reserving the single canonical 100 for the explicit `onProgress(100.0)` call already made once, right before a successful/never-larger/remux reply.
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt`
- **Verification:** `compress_jobs_test.dart`'s ordering case passes: 100 appears exactly once, as the last element
- **Committed in:** `3d6cfb8`

**2. [Rule 1 - Bug] "Closes before or as the result completes" was not actually guaranteed by the prior complete-then-close ordering**
- **Found during:** Task 1, same test, after fixing #1 above
- **Issue:** `CompressJob._run`'s `finally` block closed the progress controller AFTER the `try` block completed `_resultCompleter` -- but `Completer.complete` schedules its listeners onto a LATER microtask rather than running them synchronously, so an observer awaiting `result` could see it resolve before the stream had actually closed. A direct check (`streamDoneCompleter.isCompleted` read immediately after `await job.result`) proved this: it read `false`.
- **Fix:** Restructured `_run` to capture the eventual outcome (`success`/`failure`) in locals, run the existing `finally` block (which closes the stream) FIRST, and only THEN complete `_resultCompleter` or call `_failWith`. This is a real behavior change other code depending on the old (looser) ordering needed fixing for -- see deviation #3.
- **Files modified:** `lib/src/compress_job.dart`
- **Verification:** `compress_jobs_test.dart`'s ordering case: `streamAlreadyDoneWhenResultResolved` reads `true`
- **Committed in:** `3d6cfb8`

**3. [Rule 1 - Bug] The tracer test's pre-existing `await job.result; await subscription.asFuture()` pattern now hangs forever**
- **Found during:** Task 1, running the full `compress_test.dart` suite as a regression check after fix #2
- **Issue:** `compress_test.dart` (from 02-02) attaches `subscription.asFuture()` only AFTER `await job.result` returns. With the new close-before-complete ordering, the progress stream's `onDone` may already have fired by that point, and `asFuture()` attaching to an already-terminated subscription waits forever for a "done" event that will never come again.
- **Fix:** Moved the `asFuture()` call to immediately after `.listen()`, before awaiting `job.result` -- the correct Dart idiom regardless of ordering, and now required by it.
- **Files modified:** `example/integration_test/compress_test.dart`
- **Verification:** Full `compress_test.dart` suite (22/22) passes on the emulator
- **Committed in:** `3d6cfb8`

**4. [Rule 3 - Blocking] `Transformer` cannot be constructed OR mocked in a plain JVM unit test**
- **Found during:** Task 2, first attempt at `CompressVideoPluginTest`'s new detach case, registering a `JobRegistry.LiveJob` with `Mockito.mock(Transformer::class.java)`
- **Issue:** `Transformer`'s static initializer calls `Util.isRunningOnEmulator`, which NPEs against the unit-test `android.jar`'s unmocked `Build` fields -- and Mockito's inline mock maker still has to trigger class initialization to instrument it, so even mocking (not constructing) `Transformer` fails the same way.
- **Fix:** Replaced `JobRegistry.LiveJob.transformer: Transformer` with `LiveJob.cancelTransformer: () -> Unit`, updating `TransformerEngine`'s one registration call site to `cancelTransformer = { transformer.cancel() }`. `JobRegistry` no longer imports Media3 at all.
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt`, `TransformerEngine.kt`, `android/src/test/kotlin/com/danjjohnson/compress_video/CompressVideoPluginTest.kt`
- **Verification:** `CompressVideoPluginTest`'s two new detach cases pass; full native suite unaffected
- **Committed in:** `7031810`

**5. [Rule 2 - Missing Critical] Detach cancelled jobs AFTER clearing host API registrations, backwards from T-02-25**
- **Found during:** Task 2, reviewing `CompressVideoPlugin.onDetachedFromEngine` against the threat model before extending its test
- **Issue:** The existing order (`ProbeHostApi.setUp(...,null)`, ..., `CompressHostApi.setUp(...,null)`, THEN `JobRegistry.cancelAll()`) was the reverse of T-02-25's own disposition text ("cancels every live job through the registry and deletes every partial file BEFORE clearing registration").
- **Fix:** Moved `JobRegistry.cancelAll()` to run first.
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/CompressVideoPlugin.kt`
- **Verification:** `CompressVideoPluginTest`'s detach cases pass; behavior is otherwise unaffected (no functional dependency on registration order for the cancel path itself)
- **Committed in:** `7031810`

**6. [Rule 2 - Missing Critical] The observed numeric `ExportException.errorCode` was unobservable from Dart for any recognised reason**
- **Found during:** Task 3, writing the truncated_mdat.mp4 real-failure case
- **Issue:** `CompressVideoException.platformDetail` is only populated Dart-side when the mapped reason is `unknown` (`reasonFromPlatformCode`/`_wrapPlatformException`, established 02-02/02-03) -- for a recognised reason like `"io"`, the numeric code native sent as the error's detail was silently dropped, defeating this plan's own stated goal ("a future maintainer... can paste into an issue").
- **Fix:** `mapExportException` now always folds the numeric code into the failure `message` text (`"Media3 export failed with code $errorCode: ..."`), not only as a fallback when Media3's own exception message happened to be null.
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt`
- **Verification:** The observed real failure's message now reads `"Media3 export failed with code 2000: Asset loader error"`; `compress_jobs_test.dart`'s damaged-file case asserts the code is observable via `platformDetail` or `message`
- **Committed in:** `3718a85`

---

**Total deviations:** 6 auto-fixed (3 bugs found via real emulator behaviour requiring both production and test-code fixes, 1 blocking test-infrastructure fix, 2 missing-critical fixes for threat-model conformance and debuggability). No architectural changes; no scope creep.
**Impact on plan:** All fixes were necessary for the plan's own must-have truths and acceptance criteria to hold against real, observed platform behaviour (progress timing, `Transformer`'s own static initializer, T-02-25's exact ordering) rather than a plausible-looking implementation that happened to pass an incomplete check.

## Known Stubs

None -- every deliverable is wired to real Media3/platform behavior and proven on the emulator or in a plain JVM unit test.

## Issues Encountered

None beyond the six deviations documented above. The emulator remained stable throughout this plan's execution (no crashes).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Per-job progress and cancellation are both fully independent and fully specified; `JOBS-01`/`JOBS-02` are ready to mark complete (verified via `gsd-tools query requirements.ready-ids`: 4/4 ready, no sibling plan shares these IDs or `CORE-03`/`CORE-04` in this phase).
- **The pre-flight free-space check (D-18) is implemented and code-reviewed but not functionally integration-tested** (see coverage D11) -- there is no practical way to make the shared danserver emulator's filesystem genuinely run out of space in an automated test. A human should confirm this is acceptable, or a future phase could add a Robolectric-based unit test around a small extracted comparison function if tighter proof is wanted.
- **CORE-04's flagged assumption (A1: `DECODER_INIT_FAILED`/`DECODING_FORMAT_UNSUPPORTED` split; A2: the ENOSPC message match) is carried forward unresolved** (see coverage D12), per the plan's own instruction -- the one real failure this plan observed did not exercise either ambiguous branch.
- The `ErrorMapping.kt`/`ErrorMappingTest.kt` pure-JVM-testable pattern, and the `LiveJob.cancelTransformer` callback shape, are both available as templates for Phase 4's HEVC/HDR error-handling work, which will likely add new failure modes to map.
- This is the last plan in Phase 2's compression-engine work; `02-07-PLAN.md` (estimate()/clearCache()) remains, followed by phase-level verification.

---
*Phase: 02-android-compression-on-media3*
*Completed: 2026-09-15*

## Self-Check: PASSED

- FOUND: `android/src/main/kotlin/com/danjjohnson/compress_video/ErrorMapping.kt`, `android/src/test/kotlin/com/danjjohnson/compress_video/ErrorMappingTest.kt`, `test/compress_job_test.dart`, `example/integration_test/compress_jobs_test.dart` (all created, verified with `[ -f ]`)
- FOUND commits: `3d6cfb8`, `7031810`, `3718a85` (all present in `git log --oneline --all`)
- `cd example/android && ./gradlew :compress_video:testDebugUnitTest` -- all pass (including 28 new `ErrorMappingTest` cases and 2 new `CompressVideoPluginTest` detach cases)
- `flutter test` (root) -- 82/82 pass (10 new in `compress_job_test.dart`)
- `cd example && flutter test integration_test -d emulator-5554` -- 64/64 pass across `media_info_test.dart` (9), `compress_jobs_test.dart` (10, all new), `compress_test.dart` (22), `compress_audio_test.dart` (7), `thumbnail_test.dart` (16)
- `flutter analyze --fatal-infos --fatal-warnings` (root and `example/`) -- both clean
- `dart format --output=none --set-exit-if-changed .` -- 0 changed (root and `example/`)
- `dart pub publish --dry-run` -- exit 0, no real validation issues (only the expected "uncommitted files" notice during iteration)
- All acceptance-criteria grep checks for all three tasks re-verified against final committed files (`StatFs` x3, `1.2` x3, `outOfSpace` x2 in `ErrorMapping.kt`, no `android.`/`androidx.` import in `ErrorMapping.kt`, no `Log.` calls in `ErrorMapping.kt`/`TransformerEngine.kt`/`Compression.kt`, `jobId` x6 in `TransformerEngine.kt`, no `compressProgress`/`isCompressing` in `lib/`)
- `git status --short` clean at every commit boundary