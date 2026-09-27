---
phase: 5
slug: jobs-isolates-and-background
# status lifecycle: draft (seeded by plan-phase) → validated (set by 05-05 task 2 / validate-phase §6)
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-09-27
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Dart `flutter_test` (root unit tests, run on danserver) + Gradle `testDebugUnitTest` (Android JVM unit) + XCTest via `xcodebuild test` on the CI macOS runner (one byte-identical source file per Apple platform) + `flutter test integration_test -d emulator-5554` (Android e2e, whole directory in one process) + `tool/run_ios_integration_suites.sh <udid\|macos>` (iOS simulator and macOS desktop e2e, one process per suite behind a launch watchdog) + `corpus/verify_corpus.sh`, `tool/check_parity_test.sh` and `tool/run_ios_integration_suites_test.sh` (shell gates) |
| **Config file** | `android/build.gradle.kts` for the Android JVM unit tests; the `Runner` scheme in `example/ios/Runner.xcworkspace` and `example/macos/Runner.xcworkspace` for XCTest; `.github/workflows/ci.yml` for every Apple execution, since the MacBook Air is usually asleep and has no CocoaPods (QUESTIONS.md #7, #8) and CI is this project's standing Apple verifier |
| **Quick run command** | `flutter analyze --fatal-infos --fatal-warnings && flutter test` (seconds on danserver), plus `cd android && ./gradlew :compress_video:testDebugUnitTest` whenever Kotlin changed |
| **Full suite command** | `cd example && flutter test integration_test -d emulator-5554` locally, plus an observed CI run whose `Android`, `Detect Apple-relevant changes`, `Apple` and `Cross-platform parity` jobs all conclude `success` |
| **Estimated runtime** | Quick: seconds. Android emulator directory: 8–15 minutes with the new suite. Apple: 90–150 minutes per pushed run across the split simulator and macOS steps — budget three pushed attempts per Apple-touching plan. |

---

## Sampling Rate

- **After every task commit:** `flutter analyze --fatal-infos --fatal-warnings && flutter test`, plus the Android native unit tests whenever Kotlin changed, plus `diff` between the two `RunnerTests.swift` copies whenever Swift tests changed.
- **After every plan:** the plan's own automated command from the map below, then the whole `flutter test integration_test -d emulator-5554` directory on the booted emulator.
- **Before `/gsd-verify-work 5`:** one CI run green on all four jobs with `jobs_background_test.dart` named in the Android, iOS-simulator and macOS logs; `bash tool/check_parity_test.sh`, `bash tool/run_ios_integration_suites_test.sh` and `bash corpus/verify_corpus.sh` all green; `doc/HARDWARE_CHECKLIST.md` carrying both real-device walkthroughs honestly marked not yet run.
- **Max feedback latency:** seconds for the Dart and JVM layers; 3–10 minutes for an Android emulator case that performs a real encode; 90–150 minutes for anything observable only on an Apple runner. A shorter Apple bound is not achievable and stating one would hide when feedback really is slow.

---

## Wave 0 Gaps (test scaffolding that must exist before the behaviour it covers)

- [ ] `test/compress_video_queue_test.dart` — FIFO ordering, concurrency limit 1 and 2, cancel-while-queued, per-instance independence (05-01 task 2).
- [ ] `example/integration_test/jobs_background_test.dart` — the phase's single new integration suite (05-02 task 1), extended by 05-03.
- [ ] The example app's `moveTaskToBack` channel in `MainActivity.kt` — required before the Android backgrounding proof can run at all (05-03 task 2).
- [ ] `android/src/test/kotlin/com/danjjohnson/compress_video/ForegroundServiceHostTest.kt` — the `onTimeout` override and ref-count proven on plain JVM, no six-hour wait (05-03 task 3).
- [ ] New XCTest cases in both byte-identical `RunnerTests.swift` copies — reason-carrying cancellation (05-04 task 1) and the interruption mapping (05-04 task 2).
- [ ] The new suite registered in `tool/run_ios_integration_suites.sh`'s default list and in one iOS and one macOS CI step (05-02 task 2).

---

## Per-Task Verification Map

Status is filled by 05-05 task 2 from the plan summaries; every cell must cite a CI run number or a
local command whose output the summary quotes.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 5-01-01 | 01 | 1 | JOBS-03 | T-05-01, T-05-03 | A queued job holds validated inputs and issues no platform call until admitted; each job's progress and output stay its own | unit+integration | `flutter analyze --fatal-infos --fatal-warnings && flutter test && cd example && flutter test integration_test/compress_jobs_test.dart -d emulator-5554` | ❌ | ⬜ |
| 5-01-02 | 01 | 1 | JOBS-03 | T-05-02, T-05-04, T-05-05 | The queue cannot starve, a queued cancellation is indistinguishable from a running one, and no failed future escapes unobserved | unit | `flutter test test/compress_video_queue_test.dart` | ❌ | ⬜ |
| 5-01-03 | 01 | 1 | JOBS-03 | T-05-01, T-05-03 | Observed concurrency matches the declared limit on real hardware; documentation states the real contract | integration+docs | `cd example && flutter test integration_test -d emulator-5554 && dart pub publish --dry-run` | ❌ | ⬜ |
| 5-02-01 | 02 | 2 | JOBS-04 | T-05-07, T-05-08 | The isolate helper adds no channel and no bridge; a background-isolate job is owned by that isolate alone | integration | `cd example && flutter test integration_test/jobs_background_test.dart -d emulator-5554` | ❌ | ⬜ |
| 5-02-02 | 02 | 2 | JOBS-04 | T-05-06, T-05-09, T-05-10 | Skipping initialisation fails typed within a bounded time rather than hanging; the suite really executes on both Apple runners | integration+ci | `bash tool/run_ios_integration_suites_test.sh && cd example && flutter test integration_test -d emulator-5554` + an observed CI run | ❌ | ⬜ |
| 5-02-03 | 02 | 2 | JOBS-04 | T-05-06 | The documented failure description matches the measured one | docs | `dart pub publish --dry-run` | ✅ | ⬜ |
| 5-03-01 | 03 | 3 | JOBS-05 | T-05-11, T-05-12, T-05-14, T-05-SC | A non-exported typed service, validated notification strings, no added dependency, no notification permission requested | integration+unit | `cd android && ./gradlew :compress_video:testDebugUnitTest && cd ../example && flutter test integration_test/jobs_background_test.dart -d emulator-5554` | ❌ | ⬜ |
| 5-03-02 | 03 | 3 | JOBS-05 | T-05-16, T-05-17 | The declaration really survives manifest merging into a consuming app, and a running service is really typed `mediaProcessing` | integration+ci | `cd example && flutter test integration_test -d emulator-5554` + an observed CI run with the merged-manifest assertion | ❌ | ⬜ |
| 5-03-03 | 03 | 3 | JOBS-05 | T-05-13, T-05-15 | The quota callback stops the service and cancels hosted jobs with a retryable reason, deleting partials through the existing path | unit | `cd android && ./gradlew :compress_video:testDebugUnitTest` | ❌ | ⬜ |
| 5-04-01 | 04 | 4 | JOBS-05 | T-05-20, T-05-22 | The background task is begun and ended exactly once per job, iOS only, with no entitlement or background mode added | native unit | `diff example/ios/RunnerTests/RunnerTests.swift example/macos/RunnerTests/RunnerTests.swift` + an observed CI run's two XCTest targets | ❌ | ⬜ |
| 5-04-02 | 04 | 4 | JOBS-05 | T-05-21 | The interruption code maps to the retryable reason on both branches, domain-scoped, with no guessed case name | native unit | an observed CI run's `XCTest - iOS Runner` and `XCTest - macOS Runner` steps | ❌ | ⬜ |
| 5-04-03 | 04 | 4 | JOBS-05 | T-05-18, T-05-19, T-05-23 | A platform interruption code resolves the caller's job with a typed retryable failure, never a hang or a null; unproven parts are named | unit+docs | `flutter test test/compress_video_exception_test.dart test/compress_job_test.dart` | ❌ | ⬜ |
| 5-05-01 | 05 | 5 | JOBS-03, JOBS-04, JOBS-05 | T-05-26 | No documented claim exceeds an observed summary sentence; both unproven walkthroughs are named in the hardware checklist | docs | `dart pub publish --dry-run` | ✅ | ⬜ |
| 5-05-02 | 05 | 5 | JOBS-03, JOBS-04, JOBS-05 | T-05-24, T-05-25 | Requirements close only on named evidence; planning markdown is hand-edited with a reviewed scoped diff | docs | `git diff --stat .planning/REQUIREMENTS.md` | ✅ | ⬜ |
| 5-05-03 | 05 | 5 | JOBS-03, JOBS-04, JOBS-05 | T-05-27 | The gate is green without any budget raised, suite skipped or assertion loosened | ci | full local gate command + one observed four-job-green CI run | ✅ | ⬜ |

---

## Requirement → Evidence

| Req ID | Closes on | Filled by |
|--------|-----------|-----------|
| JOBS-03 | The emulator queue cases (three jobs sequential, limit 2, queued cancel) plus `test/compress_video_queue_test.dart`, in one observed green run | 05-05 task 2 |
| JOBS-04 | `jobs_background_test.dart`'s `Isolate.run` case and omitted-initialisation case green on the Android emulator, the iOS simulator and the macOS host in one observed CI run | 05-05 task 2 |
| JOBS-05 | The Android backgrounding proof on the API 35 emulator + the merged-manifest CI assertion + `ForegroundServiceHostTest.kt` + the Apple XCTest mapping cases + the Dart round-trip cases. The real-device Android and iPhone walkthroughs remain `doc/HARDWARE_CHECKLIST.md` items and must be named as such in the closure note | 05-05 task 2 |
