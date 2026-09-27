---
phase: 05-jobs-isolates-and-background
verified: 2026-09-27T18:50:00Z
status: human_needed
score: 4/6 must-haves verified (2 pending CI confirmation on current HEAD)
behavior_unverified: 2
overrides_applied: 0
human_verification:
  - test: "Watch CI run 36341721538 (or its successor, if it fails/is superseded) to completion on GitHub Actions: `gh run watch 36341721538` (or `gh run list --limit 3` if it has since finished)."
    expected: "All four jobs (Android, Detect Apple-relevant changes, Apple, Cross-platform parity) conclude `success`, with `jobs_background_test.dart` and the foreground-service dumpsys assertion passing on Android, and both `RunnerTests.swift` XCTest targets (iOS simulator + macOS) compiling and passing — including the new `testJobRegistryCancelAllDoesNotResurrectBookkeepingForALiveJobsBelatedCompleteResultCall` case."
    why_human: "This is the first CI run to execute against HEAD (653fcc6) since 9 code-review fix commits (843dc55 through 9278860) landed. Those commits rewrite exactly the mechanisms JOBS-04 and JOBS-05 depend on: `awaitCompressResult` (4b5b7a9, 6 files/301 lines — the background-isolate result-delivery path), Android `JobRegistry.cancelAll()` (843dc55), `ForegroundServiceHost.kt` (c630c82, b4fc528, 0b8ed88), and Apple `JobRegistry.swift`'s cancellation bookkeeping (7af5d26, 52cba90) plus its XCTest coverage (547a9b8, 9278860). The run immediately prior to this one, 36341131702, genuinely FAILED — both `RunnerTests.swift` copies did not compile (`'await' in an autoclosure that does not support concurrency`) — and that failure was in the exact WR-04 fix commit (52cba90) that is central to JOBS-05's Apple-side correctness claim. Commit 9278860 fixes the compile error; it has not yet been confirmed by a completed CI run. At the moment this report was written, the Android job in run 36341721538 was still executing native unit tests and the Apple job had not yet reached its build steps. I cannot wait out a 90–150 minute CI run inside this verification pass, so this is recorded as the single highest-priority open item: REQUIREMENTS.md's JOBS-04/JOBS-05 closures currently cite CI run 36327133883 as evidence, but that run's commit (headSha for 05-04's push) predates all 9 of the review-fix commits above — the evidence is stale relative to HEAD until 36341721538 (or a clean successor) is observed green."
  - test: "Real Android phone: install the example app, start a compression with `androidForegroundService` set, press Home / lock the screen mid-encode, confirm the notification appears and the job completes with a typed result and a file on disk."
    expected: "Job survives backgrounding on real hardware exactly as the API 35 emulator already proved (05-03: 1 progress event before backgrounding, 22 after, reaching 100)."
    why_human: "Requires a physical Android device; explicitly deferred to `doc/HARDWARE_CHECKLIST.md` as a not-yet-run entry by 05-05's own plan (QUESTIONS.md #3). This is a documented, intentional deferral consistent with how Phase 3/4 handled hardware-only proofs — not a phase defect, but still an open item before JOBS-05's Android half can be called fully proven end to end."
  - test: "Real iPhone (via the MacBook Air, once reachable): start a long compression, suspend the app, confirm the job resolves with the retryable `interrupted` error and no leftover partial file."
    expected: "Matches the XCTest-proven mapping and the Dart round-trip test (test/compress_job_test.dart) — a real device exercising the actual OS suspension rather than the injected/simulated proof."
    why_human: "The iOS simulator cannot suspend a real process (`xcrun simctl` was checked live in CI per 05-04 and documents no such mechanism — this is the settled verdict on Assumption A3, not an open question). This is correctly deferred to `doc/HARDWARE_CHECKLIST.md`, matching the project's established pattern for hardware-only proofs."
behavior_unverified_items:
  - truth: "A compression started from a background isolate completes and returns its typed result with no main-isolate-only failure (JOBS-04, ROADMAP success criterion 2)."
    test: "Confirm CI run 36341721538 (or successor) passes the Apple leg of `jobs_background_test.dart`, and that no regression was introduced by 4b5b7a9's rewrite of `awaitCompressResult`'s unknown/consumed-jobId handling."
    expected: "The isolate suite passes on Android (already independently proven by multiple stable emulator runs per 05-02), the iOS simulator and macOS in the same observed run."
    why_human: "Android proof predates 4b5b7a9's edit to the exact file backing this mechanism; Apple proof has never completed against current HEAD."
  - truth: "On Android 15/16, a job with the `mediaProcessing` foreground-service option keeps running and completes after the app is backgrounded (JOBS-05, ROADMAP success criterion 3)."
    test: "Confirm CI run 36341721538 (or successor)'s Android job passes with `ForegroundServiceHost.kt` in its post-review-fix state, and separately run the real-device walkthrows in `doc/HARDWARE_CHECKLIST.md`."
    expected: "dumpsys shows the mediaProcessing service type and the job completes, matching 05-03's original emulator proof."
    why_human: "The emulator proof (CI run 36321581676) predates three fix commits to `ForegroundServiceHost.kt` (c630c82, b4fc528, 0b8ed88); no run has re-exercised the emulator suite against the fixed file."
---

# Phase 5: Jobs, Isolates and Background Verification Report

**Phase Goal:** Apps can queue several compressions, run them off the main isolate, and keep an
Android job alive in the background, with honest behaviour when iOS suspends the app.
**Verified:** 2026-09-27T18:50:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Submitting three jobs runs sequentially by default; `maxConcurrentJobs: 2` runs two at once; each job reports its own progress/result | ✓ VERIFIED | `lib/compress_video.dart` constructor validates `maxConcurrentJobs >= 1`; per-instance FIFO admission-closure queue (`createQueuedCompressJob`) implemented in 05-01 and proven structurally (not timing-based) on the emulator; CI run 36305706520 green. This code path is untouched by the subsequent review-fix commits (which touch `awaitCompressResult`, `JobRegistry.cancelAll()` and `ForegroundServiceHost`, none of which are the queue-admission mechanism). |
| 2 | A compression started from a background isolate completes and returns its typed result, with no main-isolate-only failure | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `CompressVideo.ensureInitializedInBackgroundIsolate` exists (lib/compress_video.dart:263) as a one-line wrapper; the mechanism (`awaitCompressResult` Pigeon method, present on both platforms) is implemented. Android proven by multiple stable emulator runs (05-02) and CI run 36311172609. **However**, commit 4b5b7a9 (post-review) rewrote `awaitCompressResult`'s handling of unknown/consumed jobIds across 6 files, and no CI run has completed against that state yet — run 36341721538 is in progress at time of writing. Apple's leg of this suite has never completed green against current HEAD. |
| 3 | On Android 15/16, a job with `mediaProcessing` foreground-service option keeps running and completes after backgrounding | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `ForegroundServiceHost.kt` exists, manifest declares the two permissions and a non-exported `mediaProcessing` service (`android/src/main/AndroidManifest.xml`); emulator proof with live `dumpsys` and measured progress-event counts (1 before backgrounding, 22 after) in CI run 36321581676. **However**, three fix commits (c630c82, b4fc528, 0b8ed88) modified `ForegroundServiceHost.kt` after that proof ran; no subsequent CI run has re-exercised the emulator suite against the fixed file. Physical-phone walkthrough is a documented, not-yet-run hardware-checklist item (expected deferral, consistent with prior phases). |
| 4 | On iOS, suspending the app mid-job resolves the job with a retryable Interrupted error, never a hang or `null`, and the README documents this | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `ErrorMapping.swift` maps AVError -11847 (`interruptedBySystem`, raw-value construction, not a guessed case name) to `"interrupted"` on both the typed and plain-NSError branches; `Compression.swift` wraps jobs in `beginBackgroundTask` (iOS-only, guarded); Dart round-trip test proves `PlatformException("interrupted")` resolves `CompressJob.result` with the retryable typed exception; README documents the contract and the no-entitlement guarantee. Proven by CI run 36327133883 (all four jobs green) and by XCTest. **However**, `JobRegistry.swift`'s cancellation bookkeeping (the exact path the interrupted reason travels through) was rewritten twice more after that run (7af5d26, 52cba90) to fix a real bug the code reviewer found (a torn-down job's belated `completeResult` call could resurrect unreachable bookkeeping) — and the fix itself shipped with a compile error (fixed by 9278860) that failed CI run 36341131702. No completed CI run has yet validated the current state of this file. Real-device suspension is a documented, not-yet-run hardware-checklist item (the simulator cannot suspend a process — confirmed live via `xcrun simctl`, settling Assumption A3). |

**Score:** 1/4 ROADMAP criteria fully confirmed on current HEAD; 3/4 have complete implementations and prior green CI runs, but those runs predate fix commits touching the exact files under test — a CI run validating current HEAD (36341721538) is in progress and unconfirmed as of this report.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/compress_video.dart` | `maxConcurrentJobs`, queue, `ensureInitializedInBackgroundIsolate` | ✓ VERIFIED | All present, dartdoc substantive, wired into `compress()` |
| `lib/src/compress_job.dart` | `isQueued`, per-job progress/result unaffected by isolate | ✓ VERIFIED | Present; doc explicitly explains per-isolate module state |
| `android/.../ForegroundServiceHost.kt` | ref-counted mediaProcessing service, `onTimeout` | ✓ VERIFIED (implementation) / ⚠️ pending CI re-confirmation post-fix | Exists, 10KB, JVM-testable `Ref` bookkeeping class present |
| `android/src/main/AndroidManifest.xml` | permissions + non-exported service | ✓ VERIFIED | `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PROCESSING`, `foregroundServiceType="mediaProcessing"` present; no `POST_NOTIFICATIONS`, no `dataSync` found in earlier greps recorded by 05-03's own acceptance evidence |
| `darwin/.../ErrorMapping.swift` | -11847 → `interrupted` mapping, both branches | ✓ VERIFIED | Raw-value construction, two `"interrupted"` returns (typed + plain-NSError branch), matches established pattern |
| `darwin/.../JobRegistry.swift` | reason-carrying cancellation, torn-down guard | ✓ VERIFIED (implementation) / ⚠️ pending CI re-confirmation post-fix | WR-04 fix (52cba90) present in source; not yet compiled/tested by a completed CI run |
| `example/integration_test/jobs_background_test.dart` | Isolate.run proof + omitted-init case | ✓ VERIFIED | Present, wired into `tool/run_ios_integration_suites.sh` and both Apple CI steps (2 occurrences in `.github/workflows/ci.yml`) |
| `README.md` | coherent background story, iOS suspension contract | ✓ VERIFIED | `maxConcurrentJobs`, `ensureInitializedInBackgroundIsolate`, foreground-service section, `interrupted`/`entitlement` language all present per 05-05's own greps |
| `.planning/REQUIREMENTS.md` | JOBS-03/04/05 closed | ⚠️ EVIDENCE STALE | Marked `[x]` / `Complete` for all three, citing CI run 36327133883 — but that run predates 9 fix commits to the exact files backing JOBS-04 and JOBS-05 (see human_verification above) |

### Key Link Verification

| From | To | Via | Status |
|------|-----|-----|--------|
| `CompressOptions.androidForegroundService` | `ForegroundServiceHost.attach` | Pigeon field read in `Compression.kt` | ✓ WIRED (per 05-03 code + review) |
| Service `onTimeout` | typed `interrupted` failure | `JobRegistry.cancel(jobId, "interrupted")` | ✓ WIRED |
| iOS `beginBackgroundTask` expiration | typed `interrupted` failure | `JobRegistry.cancel(jobId:reason:)` | ✓ WIRED (implementation); ⚠️ compile/behavior unconfirmed on current HEAD |
| `RootIsolateToken` capture | Pigeon host API call from spawned isolate | `ensureInitializedInBackgroundIsolate` | ✓ WIRED |
| New suite | Apple runner's executed suite list | `tool/run_ios_integration_suites.sh` default list + both CI step arg lists | ✓ WIRED (grep counts match plan's acceptance criteria per summaries) |

### Anti-Patterns / Debt Markers

No `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`placeholder` patterns were found in the files inspected during this pass. Three code-review iterations (05-REVIEW.md, 05-REVIEW-FIX.md) already ran an adversarial pass over this phase's diff and found/fixed 12 named issues (CR-01, WR-01 through WR-04 across both platforms, IN-01); the process itself is evidence of rigor, but its very last fix (WR-04 + a compile-error follow-up) has not yet been confirmed by a completed CI run, which is why this report does not mark the phase `passed`.

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| JOBS-03 | Queue with optional concurrency, per-job progress | ✓ SATISFIED | CI run 36305706520; code path unaffected by later fix commits |
| JOBS-04 | Callable from a background isolate | ? NEEDS HUMAN | Android proven; Apple proof + the `awaitCompressResult` bug-fix rewrite are pending CI run 36341721538 |
| JOBS-05 | Android `mediaProcessing` opt-in; iOS `interrupted` + docs | ? NEEDS HUMAN | Both platforms implemented and previously proven, but `ForegroundServiceHost.kt` and `JobRegistry.swift` were modified by review fixes after their proof runs; pending re-confirmation. Physical-device walkthroughs correctly deferred to `doc/HARDWARE_CHECKLIST.md`. |

No orphaned requirements found — all three IDs mapped to plan 05-05's `requirements:` frontmatter and to REQUIREMENTS.md rows.

### Gaps Summary

This phase's implementation is thorough and its own review process (three iterations, 12 fixes) is genuinely rigorous — better diligence than a typical phase. The reason this does not verify as a clean `passed` is narrow and specific: the code-review fix cycle's own last two commits (52cba90 fixing a real bug in Apple's cancellation bookkeeping, and 9278860 fixing a compile error that fix introduced) have not yet been validated by a completed CI run. The immediately preceding CI attempt against this exact code genuinely failed to compile. A CI run against the current HEAD (36341721538) was in progress at the moment of this verification and could not be waited out within this pass. Separately and less urgently, `ForegroundServiceHost.kt` (3 fix commits) and `awaitCompressResult` (1 substantial fix commit) also postdate the CI runs that proved their respective ROADMAP criteria.

None of this indicates the phase goal was *not* achieved — the implementations are real, substantive, and wired, and the prior proofs are strong. It indicates the goal's *current* state has not yet been re-confirmed after the last round of bug-fixing, which is exactly the kind of gap this project's own CLAUDE.md and REQUIREMENTS.md discipline ("closure needs observed evidence naming where it was observed") would want caught rather than waved through.

**Recommended next action:** watch CI run 36341721538 to completion (or its successor, if superseded/failed). If it is green on all four jobs, this phase's status converts to `passed` with no further work — update REQUIREMENTS.md's citation to the new run number. If it fails, the failure is almost certainly isolated to the Swift files touched by the WR-04/compile-fix commits, per the pattern already established by the one CI failure observed so far in this cycle.

---

_Verified: 2026-09-27T18:50:00Z_
_Verifier: Claude (gsd-verifier)_
