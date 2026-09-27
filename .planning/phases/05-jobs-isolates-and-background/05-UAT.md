---
status: testing
phase: 05-jobs-isolates-and-background
source: [05-VERIFICATION.md]
started: 2026-09-27T20:17:14Z
updated: 2026-09-27T20:17:14Z
---

## Current Test
number: 1
name: Watch CI run 36341721538 (or its successor, if it fails/is superseded) to completion on GitHub Actions: `gh run watch 36341721538` (or `gh run list --limit 3` if it has since finished).
expected: |
  All four jobs (Android, Detect Apple-relevant changes, Apple, Cross-platform parity) conclude `success`, with `jobs_background_test.dart` and the foreground-service dumpsys assertion passing on Android, and both `RunnerTests.swift` XCTest targets (iOS simulator + macOS) compiling and passing — including the new `testJobRegistryCancelAllDoesNotResurrectBookkeepingForALiveJobsBelatedCompleteResultCall` case.
awaiting: user response

## Tests

### 1. Watch CI run 36341721538 (or its successor, if it fails/is superseded) to completion on GitHub Actions: `gh run watch 36341721538` (or `gh run list --limit 3` if it has since finished).
expected: All four jobs (Android, Detect Apple-relevant changes, Apple, Cross-platform parity) conclude `success`, with `jobs_background_test.dart` and the foreground-service dumpsys assertion passing on Android, and both `RunnerTests.swift` XCTest targets (iOS simulator + macOS) compiling and passing — including the new `testJobRegistryCancelAllDoesNotResurrectBookkeepingForALiveJobsBelatedCompleteResultCall` case.
why_human: This is the first CI run to execute against HEAD (653fcc6) since 9 code-review fix commits (843dc55 through 9278860) landed. Those commits rewrite exactly the mechanisms JOBS-04 and JOBS-05 depend on: `awaitCompressResult` (4b5b7a9, 6 files/301 lines — the background-isolate result-delivery path), Android `JobRegistry.cancelAll()` (843dc55), `ForegroundServiceHost.kt` (c630c82, b4fc528, 0b8ed88), and Apple `JobRegistry.swift`'s cancellation bookkeeping (7af5d26, 52cba90) plus its XCTest coverage (547a9b8, 9278860). The run immediately prior to this one, 36341131702, genuinely FAILED — both `RunnerTests.swift` copies did not compile (`'await' in an autoclosure that does not support concurrency`) — and that failure was in the exact WR-04 fix commit (52cba90) that is central to JOBS-05's Apple-side correctness claim. Commit 9278860 fixes the compile error; it has not yet been confirmed by a completed CI run. At the moment this report was written, the Android job in run 36341721538 was still executing native unit tests and the Apple job had not yet reached its build steps. I cannot wait out a 90–150 minute CI run inside this verification pass, so this is recorded as the single highest-priority open item: REQUIREMENTS.md's JOBS-04/JOBS-05 closures currently cite CI run 36327133883 as evidence, but that run's commit (headSha for 05-04's push) predates all 9 of the review-fix commits above — the evidence is stale relative to HEAD until 36341721538 (or a clean successor) is observed green.
result: resolved by CI run 36341721538 (all four jobs success) -- the pending-CI item is closed

### 2. Real Android phone: install the example app, start a compression with `androidForegroundService` set, press Home / lock the screen mid-encode, confirm the notification appears and the job completes with a typed result and a file on disk.
expected: Job survives backgrounding on real hardware exactly as the API 35 emulator already proved (05-03: 1 progress event before backgrounding, 22 after, reaching 100).
why_human: Requires a physical Android device; explicitly deferred to `doc/HARDWARE_CHECKLIST.md` as a not-yet-run entry by 05-05's own plan (QUESTIONS.md #3). This is a documented, intentional deferral consistent with how Phase 3/4 handled hardware-only proofs — not a phase defect, but still an open item before JOBS-05's Android half can be called fully proven end to end.
result: [pending]

### 3. Real iPhone (via the MacBook Air, once reachable): start a long compression, suspend the app, confirm the job resolves with the retryable `interrupted` error and no leftover partial file.
expected: Matches the XCTest-proven mapping and the Dart round-trip test (test/compress_job_test.dart) — a real device exercising the actual OS suspension rather than the injected/simulated proof.
why_human: The iOS simulator cannot suspend a real process (`xcrun simctl` was checked live in CI per 05-04 and documents no such mechanism — this is the settled verdict on Assumption A3, not an open question). This is correctly deferred to `doc/HARDWARE_CHECKLIST.md`, matching the project's established pattern for hardware-only proofs.
result: [pending]

## Summary
total: 3
passed: 1
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
