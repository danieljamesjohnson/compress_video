# Phase 5: Jobs, Isolates and Background - Context

**Gathered:** 2026-09-27
**Status:** Ready for planning
**Mode:** Smart discuss, recommended answers AUTO-ACCEPTED (Dan's 2026-09-25 "go full auto"
instruction; he was not available). Every decision below is the orchestrator's recommendation
and can be overridden by editing this file before or during planning.

<domain>
## Phase Boundary

Apps can queue several compressions, run them off the main isolate, and keep an Android job
alive in the background, with honest behaviour when iOS suspends the app. Requirements:
JOBS-03 (queue with optional concurrency limit, per-job progress), JOBS-04 (callable from a
background isolate), JOBS-05 (Android `mediaProcessing` foreground service opt-in; iOS
suspension surfaces a retryable `interrupted` error and is documented).

Out of scope: web, release packaging and the `video_compress` compat shim (Phase 6), any
change to the codec/HDR behaviour landed in Phase 4.

</domain>

<decisions>
## Implementation Decisions

### Job queue and concurrency (JOBS-03)
- The queue lives in Dart, inside `CompressVideo`: `compress()` enqueues and returns the
  `CompressJob` immediately; the job carries a `queued` state until it starts. The native
  engines stay strictly per-job (they already are) and gain no queue of their own.
- Concurrency is a constructor parameter, `CompressVideo({int maxConcurrentJobs = 1})`,
  validated to be >= 1; jobs run in submission order; a limit of 2 runs two at once.
- Cancelling a queued job removes it from the queue and resolves it with the existing typed
  `cancelled` outcome without ever reaching the native side; cancelling a running job is
  unchanged. Each job's progress stream is unchanged (emits only once the job starts).
- Two `CompressVideo` instances have independent queues (documented); the default instance
  is the common case.

### Background isolate (JOBS-04)
- Pigeon channels need `BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken)`
  in a background isolate. The plugin exposes nothing new for this beyond documentation and a
  static `CompressVideo.ensureInitializedInBackgroundIsolate(RootIsolateToken)` convenience
  that calls it (thin wrapper, no hand-written channels — the CI plumbing grep must stay
  clean).
- Proof: an integration test that runs a real compression inside `Isolate.run` (root token
  passed in) on all three platforms, asserting the typed result and progress delivery, plus
  a case proving a clear typed error (not a hang) when initialisation was skipped.

### Android foreground service (JOBS-05)
- Opt-in per job via `CompressOptions.androidForegroundService` (a small options object:
  notification title, text, optional icon resource name); default off.
- The plugin declares the `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MEDIA_PROCESSING`
  permissions and a `Service` with `foregroundServiceType="mediaProcessing"` in its own
  manifest (merged into the app). Android 15+ only: on API < 35 the option is accepted but
  no service is started and the result/documentation says so (the ROADMAP criterion names
  Android 15/16); no `dataSync` fallback, so no extra permission lands in every app.
- One service instance hosts all opted-in jobs: started with the first, stopped when the
  last finishes or is cancelled; the notification shows the count of running jobs. The
  system's `onTimeout` (the 6 h per 24 h quota) cancels the hosted jobs with the retryable
  `interrupted` reason and deletes their partial files (never-larger and cleanup rules
  unchanged).
- Emulator proof: the example app (example-only code, outside the plugin's channel-grep
  scope) exposes a `moveTaskToBack` MethodChannel; the integration test starts a job with
  the option on, backgrounds the app mid-job, and asserts the job completes with a typed
  result. `adb shell dumpsys activity services` in CI confirms the service type.

### iOS suspension (JOBS-05)
- The Apple engine wraps each running job in `UIApplication.beginBackgroundTask` (iOS only)
  so short jobs finish after the app goes to the background; when the task expires or
  AVFoundation reports the interruption (AVError -11847 `operationInterrupted`, and the
  writer's `.failed` status after resignation), the job resolves with reason `interrupted`
  (retryable), partial output deleted — never a hang, never `null`. macOS has no suspension;
  nothing changes there.
- README documents: iOS exports are interrupted on suspension; catch `interrupted` and
  resubmit; no background-processing entitlement is requested by the plugin.
- Proof: XCTest for the error mapping on both platforms (RunnerTests.swift stays byte
  identical), integration test on the iOS simulator for the mapping via an injected
  interruption where feasible; the real backgrounding walkthrough is a hardware/Mac
  checklist item (deferred like the Phase 3/4 items), never an executor precondition.

### Claude's Discretion
- Internal queue data structure and how `queued` is represented on `CompressJob`.
- Exact notification channel id/name and default strings.
- Whether the foreground service is a bound or started service, as long as it stops itself.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CompressJob` (lib/src/compress_job.dart) with per-job progress stream, cancel, typed
  result; `JobRegistry` on Android and Apple; typed `CompressVideoError` reasons incl.
  `cancelled` (an `interrupted` reason was reserved in Phase 3 and is not yet thrown).
- Pigeon contract (pigeons/messages.dart); regenerate with `dart run pigeon --input
  pigeons/messages.dart && dart format lib/src/messages.g.dart` and commit all outputs.
- compress_jobs_test.dart (progress ordering, cancel, typed failures) is the analog suite;
  tool/run_ios_integration_suites.sh suite list and the parity gate must include any new
  suite.

### Established Patterns
- Never-larger unconditional; every failure typed and mapped on both platforms; result flags
  gated by `!usedOriginal`; no hand-written channels inside lib/, android/src/main, darwin/.
- CI is the Apple verifier; Mac work probed once, never looped; hardware-only proofs are
  documented deferred steps.

### Integration Points
- `CompressVideo.compress()` (lib/src/compress_video.dart) is where the queue hooks in.
- `TransformerEngine.kt` job start/finish is where the foreground service is attached;
  `CompressionEngine.swift` job start/finish is where the background task and interruption
  mapping attach; `ErrorMapping.kt` / `ErrorMapping.swift` gain the `interrupted` mapping.
- Plugin AndroidManifest.xml (android/src/main/AndroidManifest.xml) for permissions/service.

</code_context>

<specifics>
## Specific Ideas

- Keep the public API additions minimal: one constructor parameter, one options object, one
  static initialiser, one new error reason surfaced. Everything else is behaviour.
- Research must confirm on the pinned Media3 1.11 that Transformer keeps running inside a
  foreground service after `moveTaskToBack`, the exact `onTimeout` contract on API 35/36,
  and whether `BackgroundIsolateBinaryMessenger` works with Pigeon's event channels.

</specifics>

<deferred>
## Deferred Ideas

- Real-device backgrounding walkthroughs (Android phone: QUESTIONS.md #3; iPhone via the
  Mac) join the hardware checklist.
- A `dataSync`-typed fallback service for Android 14 and below (explicitly not done).

</deferred>
