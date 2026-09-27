---
phase: 05-jobs-isolates-and-background
plan: 01
subsystem: api
tags: [dart, queue, concurrency, compress-video]

# Dependency graph
requires:
  - phase: 04-codecs-hdr-and-hard-inputs
    provides: a stable per-job compress()/CompressJob contract (progress, cancel, typed errors, never-larger) with nothing left to change at the native layer
provides:
  - "CompressVideo({int maxConcurrentJobs = 1}) and a per-instance Dart FIFO job queue"
  - "CompressJob.isQueued, the one new public member this plan's discretion section authorized"
  - "createQueuedCompressJob, a library-internal factory + admission-closure pattern other 05-0x plans can reuse for deferred-start scenarios"
affects: [05-02-background-isolate, 05-03-android-foreground-service, 05-04-ios-suspension, 05-05-phase-signoff]

# Actuals (#2632)
actuals:
  tokens: 14706
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Deferred-start factory + admission closure: CompressJob.queued's factory returns a job plus a plain closure that starts it, keeping the class's new public surface to exactly one member (isQueued) while still letting a sibling file (CompressVideo) drive admission."
    - "Structural (not timing-based) concurrency proof: emulator tests observe CompressJob.isQueued from inside a whenComplete callback attached to the SAME future the queue's internal pump already listens on, exploiting Dart's same-future listener-ordering guarantee instead of racing real encode timings."

key-files:
  created:
    - test/compress_video_queue_test.dart
  modified:
    - lib/compress_video.dart
    - lib/src/compress_job.dart
    - example/integration_test/compress_jobs_test.dart
    - README.md
    - CHANGELOG.md
    - test/compress_job_test.dart
    - test/compress_options_test.dart
    - test/media_info_mapping_test.dart
    - test/thumbnail_api_test.dart
    - example/integration_test/compress_audio_test.dart
    - example/integration_test/compress_output_test.dart
    - example/integration_test/compress_test.dart
    - example/integration_test/hard_inputs_test.dart
    - example/integration_test/media_info_test.dart
    - example/integration_test/thumbnail_test.dart
    - example/lib/src/compression_runner.dart
    - tool/measure_presets.dart

key-decisions:
  - "CompressVideo's constructor dropped `const` (plan's own D-14 discretion): a queue is per-instance mutable state, and const canonicalisation would otherwise make two `const CompressVideo()` expressions silently share one queue."
  - "The queue's admission capability is returned as a plain closure from a top-level factory (createQueuedCompressJob), not a public method on CompressJob -- keeps the class's new public API to exactly CompressJob.isQueued."
  - "Cancel-while-queued splices the job directly out of CompressVideo's pending queue via a callback set at creation time, so the active-job count is never touched for a job that never started (05-RESEARCH.md Pitfall 1)."
  - "The emulator's concurrency-2 proof reads CompressJob.isQueued structurally inside a same-future whenComplete callback rather than comparing real-clock progress timestamps, after the timestamp-based version proved flaky against a cheap clip's own admission latency."

requirements-completed: [JOBS-03]

coverage:
  - id: D1
    description: "CompressVideo gains maxConcurrentJobs (default 1, validated >= 1) and a per-instance FIFO queue gating compress()"
    requirement: JOBS-03
    verification:
      - kind: unit
        ref: "test/compress_video_queue_test.dart#Default limit (1) / Limit 2 / Constructor validation groups"
        status: pass
      - kind: integration
        ref: "example/integration_test/compress_jobs_test.dart#Queue: default concurrency runs three jobs strictly one at a time"
        status: pass
    human_judgment: false
  - id: D2
    description: "CompressJob.isQueued and the deferred-start mechanism (createQueuedCompressJob); CompressJob.start preserved for the immediate-start path"
    requirement: JOBS-03
    verification:
      - kind: unit
        ref: "test/compress_video_queue_test.dart (isQueued asserted in every group)"
        status: pass
      - kind: integration
        ref: "example/integration_test/compress_jobs_test.dart (isQueued asserted in both queue groups)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Cancel-while-queued resolves the same typed cancelled failure a running cancel produces, without reaching the platform, and never starves the queue"
    requirement: JOBS-03
    verification:
      - kind: unit
        ref: "test/compress_video_queue_test.dart#Cancel while queued group (2 cases)"
        status: pass
      - kind: integration
        ref: "example/integration_test/compress_jobs_test.dart#cancelling a job while it is still queued behind a running one..."
        status: pass
    human_judgment: false
  - id: D4
    description: "Two CompressVideo instances queue completely independently"
    requirement: JOBS-03
    verification:
      - kind: unit
        ref: "test/compress_video_queue_test.dart#Per-instance independence"
        status: pass
    human_judgment: false
  - id: D5
    description: "maxConcurrentJobs: 2 runs exactly two jobs at once on a real device, never three"
    requirement: JOBS-03
    verification:
      - kind: integration
        ref: "example/integration_test/compress_jobs_test.dart#maxConcurrentJobs: 2 runs exactly two of three jobs at once..."
        status: pass
    human_judgment: false
  - id: D6
    description: "README/CHANGELOG document the queue's public contract"
    requirement: JOBS-03
    verification:
      - kind: other
        ref: "grep -c maxConcurrentJobs README.md (4) and CHANGELOG.md (3); dart pub publish --dry-run exit 0"
        status: pass
    human_judgment: false

duration: 90min
completed: 2026-09-27
status: complete
---

# Phase 5 Plan 1: Dart FIFO job queue with a concurrency gate Summary

**`CompressVideo({int maxConcurrentJobs = 1})` gates every `compress()` call through a per-instance FIFO queue, proven sequential-by-default and exactly-N-concurrent on a real Android emulator, with cancel-while-queued indistinguishable from a running cancel and zero native-side changes.**

## Performance

- **Duration:** ~90 min (includes emulator boot, two full-suite emulator verification passes, and a CI-gate coordination wait)
- **Tasks:** 3 (tracer + TDD unit suite + device concurrency-2/docs)
- **Commits:** 3 (`6a4195e`, `848e443`, `df2007e`)
- **Files modified:** 18 (1 created)

## Accomplishments

- `CompressVideo` gained `maxConcurrentJobs` (default 1, validated `>= 1` with a typed `unsupportedInput` failure) and a private FIFO queue (`_pending` + `_activeJobCount`) that gates every `compress()` call, admitting entries in submission order as slots free.
- `CompressJob` gained exactly one new public member, `isQueued`, plus a library-internal `createQueuedCompressJob` factory that separates "create and register a job" from "issue its platform call" — the admission capability is returned as a plain closure, not a public method, so no caller can start a job it doesn't own.
- Cancelling a still-queued job splices it out of the pending queue via a callback set at creation time and resolves it through the exact same typed-cancellation path a natively-cancelled job uses — byte-identical `reason` and message, so a caller cannot tell from the exception whether the job had started. The active-job count is never touched on this path (05-RESEARCH.md Pitfall 1).
- `test/compress_video_queue_test.dart` (new, 9 cases) proves default-limit ordering, limit-2 concurrency, constructor validation, cancel-while-queued (including "frees nothing it did not take" with 1 running + 2 queued), failure/cancellation both advancing the queue, per-instance independence, and the progress/result invariant across queue position — all with a fake `CompressHostApi`, no device, concurrency asserted from recorded call order only.
- Three real-device proofs added to `example/integration_test/compress_jobs_test.dart`: three jobs from a default instance run strictly sequentially (timestamps, not await-order); `maxConcurrentJobs: 2` runs exactly two of three at once (proven structurally via `isQueued`, not real-clock progress timing — see Deviations); and cancelling a job queued behind a running one resolves `cancelled` with no file at its `outputPath`.
- README gained "Compressing a video" and "Queueing several compressions" sections (the former was a pre-existing gap — `compress()`/`CompressJob` had never been documented since Phase 2); CHANGELOG records `maxConcurrentJobs`/`isQueued` as additions and the constant-constructor removal as the breaking change.

## Task Commits

1. **Task 1: End-to-end "three queued jobs run one at a time"** — `6a4195e` (feat)
2. **Task 2: Limit, cancel-while-queued, per-instance independence (TDD)** — `848e443` (test)
3. **Task 3: `maxConcurrentJobs: 2` on device + documentation** — `df2007e` (feat)

_Task 2 produced no separate GREEN commit — see TDD Gate Compliance below._

## Files Created/Modified

- `lib/compress_video.dart` — `maxConcurrentJobs`, the FIFO queue (`_pending`, `_activeJobCount`, `_pumpQueue`, `_onJobSettled`), constructor validation, dropped `const`.
- `lib/src/compress_job.dart` — `isQueued`, `createQueuedCompressJob` (deferred-start factory + admission closure), cancel-while-queued path; `CompressJob.start`'s immediate-path contract preserved unchanged.
- `test/compress_video_queue_test.dart` — new, 9 cases, no-device fake-host-API suite.
- `example/integration_test/compress_jobs_test.dart` — 3 new real-device queue cases; parity-accumulator comment updated.
- `README.md` — new "Compressing a video" / "Queueing several compressions" sections; fixed a stale `const CompressVideo()` sample and a stale "What this phase ships" intro.
- `CHANGELOG.md` — new Phase 5 queue entry, breaking-change note for the constant-constructor removal.
- 11 other test/example files — mechanical `const CompressVideo compressVideo = CompressVideo();` → `final` fix, forced by the constructor no longer being `const` (see Deviations).

## Decisions Made

- Dropped `const` from `CompressVideo`'s constructor now, while the package is still unpublished, rather than deferring past a version bump (plan's own reversibility note).
- Kept `CompressJob.start`'s exact factory name/behaviour for the immediate-start path even though `compress()` no longer calls it directly (it's now built on `createQueuedCompressJob` + immediate `admit()`), per the plan's explicit "no existing caller or test changes shape" instruction.
- Chose to observe `isQueued` structurally (inside a `whenComplete` callback riding the same future the internal pump listens on) for the device concurrency-2 proof, after a real-clock timestamp version proved flaky — see Deviations.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The plan's own grep for `const CompressVideo(` missed a pattern that dropping `const` broke everywhere**
- **Found during:** Task 1, immediately after dropping `const`
- **Issue:** The plan's discretion section asserted "no call site changes" based on `grep -c 'const CompressVideo('` finding only the constructor declaration. That literal-string grep doesn't match the actual pattern used across the codebase: `const CompressVideo compressVideo = CompressVideo();` (const applied to the *variable*, not a parenthesized constructor call at the same spot). 13 files used this pattern and failed to compile once the constructor was no longer `const`.
- **Fix:** Changed each occurrence to `final CompressVideo compressVideo = CompressVideo();` (or `static final` for the one static case in `example/lib/src/compression_runner.dart`).
- **Files modified:** `tool/measure_presets.dart`, `test/compress_options_test.dart`, `test/media_info_mapping_test.dart`, `test/thumbnail_api_test.dart`, `test/compress_job_test.dart`, `example/integration_test/{media_info_test,compress_audio_test,compress_output_test,compress_jobs_test,compress_test,hard_inputs_test,thumbnail_test}.dart`, `example/lib/src/compression_runner.dart`.
- **Verification:** `flutter analyze --fatal-infos --fatal-warnings` clean on both packages.
- **Committed in:** `6a4195e`

**2. [Rule 1 - Bug] Sharing one `CompressVideo` instance across a whole test file starved every test after the first, once a default concurrency-1 queue existed**
- **Found during:** Task 1, first `flutter test` run after the queue landed
- **Issue:** `test/compress_job_test.dart` declared one `CompressVideo` at `main()` scope, shared by every test. Several early cases deliberately install a hanging `startCompress` mock and never resolve the jobs they create (testing progress-routing in isolation). Before this plan, that was harmless — every `compress()` call started immediately regardless of other calls' state. With the new default-concurrency-1 queue, those permanently-unresolved jobs occupied the shared instance's one concurrency slot forever, so every later test's own `compress()` call queued behind them and timed out (7 of 92 unit tests failed with 30s timeouts).
- **Fix:** Construct a fresh `CompressVideo` in a `setUp()` block instead of once for the whole file, so each test gets its own independent queue (matching D-04's own per-instance-independence philosophy).
- **Files modified:** `test/compress_job_test.dart`
- **Verification:** `flutter test` — all 92 unit tests pass (was 76/83 before the fix, now 92/92 including the new queue suite).
- **Committed in:** `6a4195e`

**3. [Rule 1 - Bug] The concurrency-2 emulator test's timing-based assertions were flaky against a cheap clip's own admission latency**
- **Found during:** Task 3, first emulator run of the new `maxConcurrentJobs: 2` case
- **Issue:** The initial implementation asserted job C's first-progress timestamp fell within an interval bounded by jobs A and B's completion timestamps. Against `small_480p.mp4` (the plan's specified clip, chosen for cheapness), the job's own admission-to-first-progress latency (~150ms) was comparable to or larger than the real gap between A and B's completions, making the upper-bound assertion fail on a build with a genuinely correct queue (observed: expected `<=181`, actual `334`).
- **Fix:** Replaced the timing-based upper-bound and A/B-overlap checks with a structural proof: a `whenComplete` callback attached to jobs A/B's own `result` future reads `jobC.isQueued` at that exact moment. Because the queue's own internal completion listener is attached first (inside `compress()`, before the test's own listener), it always runs first in the same microtask turn — so this reads "had C already been admitted?" deterministically, independent of real encode speed. The initial "three jobs run strictly one at a time" (Task 1) test's own timestamp comparisons were re-checked and left as-is, since strict FIFO with limit 1 makes sequential `await` order match real completion order by construction (no flakiness risk there).
- **Files modified:** `example/integration_test/compress_jobs_test.dart`
- **Verification:** Re-ran on the emulator three times after the fix; all green, including the previously-flaky assertion.
- **Committed in:** `df2007e`

**4. [Rule 2 - Missing critical documentation] `compress()`/`CompressJob` had never been documented in README.md**
- **Found during:** Task 3, writing the queue's own documentation
- **Issue:** README.md's "Usage" section only covered `getMediaInfo`/`getThumbnail` (a Phase 1 leftover); "What this phase ships" still said "Compression itself, presets, jobs, progress and cancellation land in later versions" — false since Phase 2. The plan's instruction to document the queue "under Usage" implicitly assumed compress() was already documented there.
- **Fix:** Added a "Compressing a video" section covering `compress()`/`CompressJob`/`progress`/`cancel`/`result` before the new "Queueing several compressions" section, and rewrote the stale "What this phase ships" intro to reflect current reality.
- **Files modified:** `README.md`
- **Verification:** Manual read-through; `dart pub publish --dry-run` (which lints README structure) exits 0.
- **Committed in:** `df2007e`

---

**Total deviations:** 4 auto-fixed (1 blocking, 2 bugs, 1 missing documentation)
**Impact on plan:** All four were necessary for correctness (compilation, test suite integrity, non-flaky device proof) or for the plan's own stated documentation goal to have a coherent home. No scope creep beyond what each fix required.

## TDD Gate Compliance

Task 2 (`tdd="true"`) produced only a `test(05-01)` commit (`848e443`), no separate `feat(05-01)` commit of its own. This is because the RED phase found nothing to fix: Task 1's `feat(05-01)` commit (`6a4195e`, which precedes it) already implemented the queue's cancel-while-queued path exactly per 05-RESEARCH.md Pitfall 1's guidance (splicing the pending entry out via a callback that never touches the active-job count), so all 9 of Task 2's cases passed against the existing implementation with zero further production-code changes. The plan-level GREEN gate check (`git log --grep="^feat(05-01)"`) is satisfied by Task 1's prior commit. This is a legitimate outcome of building the general mechanism generically in the tracer task, not a skipped gate.

## Issues Encountered

None beyond the deviations documented above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- JOBS-03 is fully proven: default sequential queueing, `maxConcurrentJobs: 2` concurrency, cancel-while-queued, per-instance independence, and the cross-position invariant are all covered by unit tests (no device) and real-device emulator tests.
- `lib/compress_video.dart` and `lib/src/compress_job.dart` are the two files 05-02 (background isolate) will extend next; both are stable and the native engines remain provably untouched (`git diff --stat` for this plan lists no path under `android/src/main/` or `darwin/compress_video/Sources/`, and the Pigeon contract is unchanged).
- No blockers for 05-02.

---
*Phase: 05-jobs-isolates-and-background*
*Completed: 2026-09-27*

## Self-Check: PASSED

- All key files found on disk (`test/compress_video_queue_test.dart`, `lib/compress_video.dart`, `lib/src/compress_job.dart`, `README.md`, `CHANGELOG.md`).
- All three task commits (`6a4195e`, `848e443`, `df2007e`) present in git log.
- Plan-level `<verification>` re-run: `flutter analyze` (root + example) clean, `flutter test` 92/92, full `example/integration_test` directory 100/100 on the emulator, `dart format` clean (stable SDK), `dart pub publish --dry-run` exit 0 / 0 warnings, no diff under `android/src/main/` or `darwin/compress_video/Sources/`, `pigeons/messages.dart`/`lib/src/messages.g.dart` unchanged.
