---
quick_id: 260927-r4k
slug: fix-apple-awaitcompressresult-registration-race
status: complete
date: 2026-09-27
commit: 404dff4, b8ee2f9, 74c7206
subsystem: apple-engine
tags: [swift, swift-concurrency, mainactor, pigeon, job-registry, kotlin, xctest]
key-files:
  created: []
  modified:
    - darwin/compress_video/Sources/compress_video/Compression.swift
    - android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt
    - example/ios/RunnerTests/RunnerTests.swift
    - example/macos/RunnerTests/RunnerTests.swift
key-decisions:
  - "startCompress and awaitCompressResult are @MainActor on Apple; registerJob is called with no await before the first suspension point"
  - "A request that fails validation is now a registered job whose typed failure completeResult records"
  - "No JVM test for Compression.kt's grace loop: the class needs a Context, the main Looper and a TransformerEngine"
actuals:
  tokens: 4200
  tasks: 4
  commits: 3
ci_run: 36351396397 (pending at time of writing)
duration: 4 min
completed: 2026-09-27
---

# Summary: Fix the Apple `awaitCompressResult` registration race

**`startCompress` now registers its jobId synchronously on the main actor before its first
suspension point, so a background isolate's immediately-following `awaitCompressResult` can no
longer overtake it; a bounded 2 s grace on both platforms backs that up.**

## Performance

- **Started:** 2026-09-27T21:18:08Z
- **Completed:** 2026-09-27T21:21:07Z (code pushed; CI pending)
- **Tasks:** 4 (Swift fix, Kotlin mirror, XCTest, verification + push)
- **Files modified:** 4

## What was done

- `Compression.swift`
  - `startCompress` is `@MainActor`. `requireValidJobId` stays first and outside the
    `do`/`catch` (an invalid id cannot be registered). `JobRegistry.registerJob(jobId: jobId)`
    follows immediately with **no `await`**, ahead of `Arguments.requireValidCompressRequest`,
    which moved inside the `do`/`catch` so a validation failure goes through `completeResult`
    like every other failure.
  - `completeResult` calls lost their `await` (same actor now). `runCompress` is unchanged and
    still nonisolated, so awaiting it hops off the main actor: no engine, probe or free-space
    work moved onto the main thread.
  - `awaitCompressResult` is `@MainActor`; `isConsumedJobId`/`isKnownJobId` are called without
    `await`. If the jobId is not yet known it polls up to 40 times, 50 ms apart
    (`try await Task.sleep(nanoseconds: 50_000_000)`, 2 s total), then throws the existing
    "unknown jobId" error with its text unchanged. `JobRegistry.awaitResult` stays awaited.
  - Class doc comment rewritten to explain why registration is synchronous on the main actor.
- `Compression.kt`: `awaitCompressResult` has the same 40 x `delay(50)` grace, with a comment
  that Android's main-Looper ordering makes it unreachable in practice. Pigeon launches the
  handler on `Dispatchers.Main`, so `delay` resumes on the main Looper and `JobRegistry` is
  still only touched from there.
- `RunnerTests.swift` (iOS and macOS, byte-identical): new
  `testAwaitCompressResultCalledBeforeRegistrationResolvesOnceTheJobRegisters`. It calls
  `awaitCompressResult` first, and a `Task { @MainActor in }` registers and completes the job
  ~100 ms later; the call must return the result rather than throw. A file-private
  `NoOpBinaryMessengerForCompressionTest` lets a `Compression` be built with no engine.

## Commits

- `404dff4` fix: register the Apple job synchronously on the main actor
- `b8ee2f9` fix: mirror the bounded known-jobId grace on Android
- `74c7206` test: XCTest for awaitCompressResult called before registration

## Verification

| Check | Result |
|---|---|
| Mac probe (`timeout 15 ssh ... dans-macbook-air true`), once | **Unreachable** — "Connection timed out", exit 255. Not retried. Nothing ran on the Mac. |
| Swift compiled anywhere | **No.** Not possible on danserver; the Mac was down. First compile is CI run 36351396397. |
| `./gradlew :compress_video:testDebugUnitTest` (from `example/android`) | Pass, exit 0 |
| `dart format --output=none --set-exit-if-changed .` (flutter-stable 3.47.5) | 37 files, 0 changed |
| `flutter analyze` (flutter-stable 3.47.5) | No issues found |
| `cmp` of the two `RunnerTests.swift` files | Identical |
| `pigeons/messages.dart`, `lib/`, generated `Messages.g.*` | Untouched |
| Pushed to `origin` and `github` | `951a418..74c7206` on both |
| CI | Run **36351396397**, `in_progress` when recorded. **Not polled; outcome unknown.** |

Push budget used: 1 of 3.

## Acceptance status

| Criterion | Status |
|---|---|
| `startCompress` `@MainActor`, `registerJob` with no `await` before `requireValidCompressRequest` | Met (by reading the code) |
| `awaitCompressResult` `@MainActor` with bounded (<= 2 s) wait | Met (by reading the code) |
| `Compression.kt` has the same bounded wait | Met; compiles and the JVM suite passes |
| `RunnerTests.swift` identical on both platforms with the new case | Met |
| No Pigeon contract change, no hand-written channels | Met |
| `jobs_background_test.dart` passes on the iOS simulator and macOS host in CI | **Unverified — pending run 36351396397** |

## Not verified / risks for whoever reads the CI result

- **The Swift has never been compiled.** Things most likely to fail the build if anything does:
  - the `@MainActor` methods satisfying `CompressHostApi`'s nonisolated `async` requirements
    (expected to be allowed; would surface as a conformance error in `Compression.swift`);
  - `NoOpBinaryMessengerForCompressionTest`'s four method signatures against
    `FlutterBinaryMessenger` on both Flutter and FlutterMacOS;
  - Sendable diagnostics from passing `flutterApi`/`engine` out of a `@MainActor` method, which
    would only be errors if the target builds in Swift 6 language mode.
- **The race itself is not reproduced by any test.** The new XCTest proves the grace period
  (the backstop), not the primary fix. The ordering fix is argued from the code and from
  Pigeon's `Task { @MainActor in }` wrapping; the original failure was intermittent (the same
  suite passed in runs 36327133883 and 36341721538), so one green CI run is consistent with
  the fix but does not by itself prove it.
- **Behaviour change:** an `awaitCompressResult` call for a jobId that was genuinely never
  started now takes ~2 s to fail instead of failing at once, on both platforms. No existing
  Dart test drives that path against a real engine (`test/await_compress_result_test.dart`
  uses a mock handler), so none was slowed.

## Deviations from Plan

**1. No JVM test for the Android grace loop (plan step 4 allowed this, with a reason).**
`Compression` takes a `Context`, a `Probe` and a `CompressVideoFlutterApi`, builds a
`TransformerEngine(context)` by default, and `awaitCompressResult` begins with
`requireMainLooper`, which calls `Looper.myLooper()`. The module's unit tests run against the
stub `android.jar` without `returnDefaultValues`, so that call throws before the loop is
reached; there is also no `kotlinx-coroutines-test` dependency to drive `delay`. Adding a
dependency and static-mocking `Looper` was judged out of scope for a loop that is unreachable
on Android. The Kotlin change is covered by compilation plus the unchanged JVM suite only.

Otherwise the plan was executed as written.

## Known Stubs

None.

## Next

Orchestrator relays the result of CI run 36351396397. If the Apple job fails to compile, the
three risk points above are where to look first; two pushes remain in the budget.

## Self-Check: PASSED

- All four modified files exist and are committed; `404dff4`, `b8ee2f9`, `74c7206` are in
  `git log` and on both remotes.
- "PASSED" covers what was claimed above only: the CI-dependent acceptance criterion is
  recorded as unverified, not as met.
