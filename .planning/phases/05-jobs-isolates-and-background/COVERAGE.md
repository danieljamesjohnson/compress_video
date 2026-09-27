# Phase 5 — API Coverage Declaration

**No external API integration:** this phase integrates *platform lifecycle* surfaces — Android's
foreground-service framework, iOS's background-task API and Flutter's background-isolate messenger
— behind the existing Pigeon contract. No third-party service, network endpoint, hosted SDK or
registry package is consumed, and no new pub.dev / CocoaPods / SPM / Gradle dependency is added
(05-RESEARCH.md → "Package Legitimacy Audit": not applicable; "Installation": no new packages).
There is therefore no API key, no auth flow, no rate limit and no versioned remote contract to
declare.

The surface that *is* worth an explicit matrix is the **platform lifecycle surface** this phase
newly depends on: OS-owned mechanisms whose behaviour decides whether a job survives, fails
honestly, or hangs. Each is declared INTEGRATE (wired and asserted this phase) or OPT-OUT
(deliberately not wired, with the reason). INTEGRATE is the default.

## Platform lifecycle matrix

| # | Mechanism | Platform | Disposition | Plan | Note |
|---|-----------|----------|-------------|------|------|
| 1 | `BackgroundIsolateBinaryMessenger.ensureInitialized(RootIsolateToken)` | Flutter (all) | **INTEGRATE** | 05-02 | The whole of JOBS-04. Exposed as one static wrapper; the failure mode when it is skipped is asserted, not assumed (05-RESEARCH.md Pitfall 2). |
| 2 | A `mediaProcessing`-typed started `Service` with `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PROCESSING` | Android 15+ | **INTEGRATE** | 05-03 | Opt-in per job (D-07). Non-exported, ref-counted, stops itself. Proven on the API 35 emulator with a live `dumpsys` capture and a merged-manifest CI assertion. |
| 3 | `Service.onTimeout(startId, fgsType)` — the 6 h / 24 h quota callback | Android 15+ | **INTEGRATE** | 05-03 | Cancels hosted jobs with the retryable `interrupted` reason and stops the service. Exercised by invoking the override directly in a JVM unit test; a real six-hour expiry is not reachable in any environment this project has. |
| 4 | `POST_NOTIFICATIONS` runtime permission | Android 13+ | **OPT-OUT** | 05-03 | The plugin never requests it: whether to prompt a user is the host app's decision. The service and the compression run regardless; only the notification's visibility depends on it. 05-03 verifies that live, both granted and denied (assumption A1). |
| 5 | `dataSync`-typed foreground service as a pre-Android-15 fallback | Android 14 and below | **OPT-OUT** | — | Explicitly deferred by 05-CONTEXT.md and REQUIREMENTS.md. It would land an extra permission in every consuming app for a path most callers never take. Below API 35 the option is accepted and inert, and the documentation says so. |
| 6 | `UIApplication.beginBackgroundTask(expirationHandler:)` | iOS | **INTEGRATE** | 05-04 | Buys short jobs enough time to finish after backgrounding; its expiration handler is what makes `interrupted` real on Apple. No entitlement required. |
| 7 | `UIBackgroundModes` / a background-processing entitlement | iOS | **OPT-OUT** | — | The plugin imposes no background mode on the host app (D-12). `beginBackgroundTask` needs none, and a library that silently adds one is imposing an App Store review surface on its callers. |
| 8 | `BGProcessingTask` / `BGTaskScheduler` | iOS 13+ | **OPT-OUT** | — | Schedules opportunistic work at a system-chosen time; it cannot continue an in-flight `AVAssetWriter` export, which is what JOBS-05 asks about. Out of scope for v1 and not named by any requirement. |
| 9 | AVFoundation error -11847 (interruption), via `AVError` and via a plain `NSError` in AVFoundation's domain | iOS + macOS | **INTEGRATE** | 05-04 | The documented system signal for an interrupted export. Both branches mapped, domain-scoped, with XCTest on both Apple platforms. |
| 10 | `xcrun simctl`-driven real app suspension | iOS simulator | **OPT-OUT** | 05-04 | No documented mechanism suspends a running simulator app process the way a device does (05-RESEARCH.md Pitfall 6, assumption A3). 05-04 records an explicit verdict; the real walkthrough is a `doc/HARDWARE_CHECKLIST.md` item, never an executor precondition. |
| 11 | A Dart isolate worker pool as the concurrency mechanism | Flutter (all) | **OPT-OUT** | — | The encode already happens natively and the native engines are already correctly per-job; a worker pool would duplicate JOBS-04's plumbing and buy nothing (05-RESEARCH.md, Alternatives Considered). The queue is a plain Dart FIFO with a counter. |
| 12 | A native-side job queue | Android + Apple | **OPT-OUT** | — | D-01 keeps the queue entirely in Dart. A second queue underneath it would be two schedulers disagreeing about one device. |

**Callers never see the lifecycle surface directly.** The public API additions this phase makes
are exactly four: one constructor parameter (`maxConcurrentJobs`), one options object
(`CompressOptions.androidForegroundService`), one static initialiser
(`CompressVideo.ensureInitializedInBackgroundIsolate`) and one error reason that was already in the
taxonomy and now actually gets thrown (`CompressVideoErrorReason.interrupted`). No capability-query
API, no service handle and no isolate handle is exposed — 05-CONTEXT.md's "keep the public API
additions minimal" line is the constraint, and everything else is behaviour.

## Package legitimacy

Skipped for this phase, per 05-RESEARCH.md § "Package Legitimacy Audit": no npm, pip, cargo, pub,
CocoaPods, SPM or Gradle package is installed. `android/build.gradle.kts`, `pubspec.yaml`,
`darwin/compress_video/Package.swift` and the podspec are all asserted unchanged by the plans that
could plausibly have touched them.
