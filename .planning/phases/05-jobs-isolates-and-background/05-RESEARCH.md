# Phase 5: Jobs, Isolates and Background - Research

**Researched:** 2026-09-27
**Domain:** Flutter plugin job queueing, background isolates, Android foreground services (mediaProcessing), iOS background task suspension
**Confidence:** MEDIUM (Android FGS timeout mechanics and BackgroundIsolateBinaryMessenger/EventChannel interplay are CITED from official docs; iOS suspension-to-AVError mapping and the emulator's actual FGS-survival behavior are ASSUMED/untested pending execution — see Open Questions)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Job queue and concurrency (JOBS-03)**
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

**Background isolate (JOBS-04)**
- Pigeon channels need `BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken)`
  in a background isolate. The plugin exposes nothing new for this beyond documentation and a
  static `CompressVideo.ensureInitializedInBackgroundIsolate(RootIsolateToken)` convenience
  that calls it (thin wrapper, no hand-written channels — the CI plumbing grep must stay
  clean).
- Proof: an integration test that runs a real compression inside `Isolate.run` (root token
  passed in) on all three platforms, asserting the typed result and progress delivery, plus
  a case proving a clear typed error (not a hang) when initialisation was skipped.

**Android foreground service (JOBS-05)**
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

**iOS suspension (JOBS-05)**
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

### Deferred Ideas (OUT OF SCOPE)
- Real-device backgrounding walkthroughs (Android phone: QUESTIONS.md #3; iPhone via the
  Mac) join the hardware checklist.
- A `dataSync`-typed fallback service for Android 14 and below (explicitly not done).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| JOBS-03 | Caller can submit several jobs; sequential by default with optional concurrency limit; each reports its own progress | Dart-side queue design (§Architecture Patterns Pattern 1); reuses existing per-job `CompressJob`/progress-stream/`JobRegistry` machinery unchanged (§Existing Code Insights) |
| JOBS-04 | The API can be called from a background isolate | `BackgroundIsolateBinaryMessenger.ensureInitialized` + Pigeon HostApi/EventChannel behavior (§Core Technology, §Common Pitfalls Pitfall 2) |
| JOBS-05 | Android `mediaProcessing` foreground service opt-in; iOS documents suspension as retryable Interrupted | Android FGS lifecycle/manifest/`onTimeout` contract (§Core Technology, §Common Pitfalls 3-5); iOS `beginBackgroundTask`/AVError mapping (§Core Technology, §Common Pitfalls 6) |
</phase_requirements>

## Summary

This phase adds three independent capabilities on top of code that is already stable: a
Dart-side FIFO job queue with a concurrency limit, a documented recipe (plus one static
convenience method) for calling the existing Pigeon API from a background isolate, and an
opt-in Android foreground service paired with an honest iOS suspension story. None of the
three require new native engines or new dependencies — `TransformerEngine.kt` and
`CompressionEngine.swift` already run one job at a time per call and already have
start/finish hooks; the queue sits entirely above them in Dart, the foreground service wraps
the existing per-job Android call, and the iOS background task wraps the existing per-job
Apple call. The `interrupted` error reason is already reserved in the shared taxonomy
(`lib/src/compress_video_exception.dart`) and unused — this phase is what finally throws it.

The riskiest unknowns are less about API shape (CONTEXT.md has already locked that) and more
about runtime behavior this project cannot fully observe before executing the phase: whether
Android 15/16's `Service.onTimeout(int, int)` callback and the 6 h/24 h FGS quota behave as
documented on the API 35 emulator image already provisioned on danserver; whether a
`POST_NOTIFICATIONS`-less app can still start a `mediaProcessing` foreground service (it can
start — the runtime permission gates whether the notification is *visible*, not whether
`startForeground()` succeeds); and whether the iOS simulator can be made to simulate app
suspension well enough to exercise the `interrupted` mapping in CI (it plausibly cannot, and
CONTEXT.md already anticipates this by deferring the real walkthrough to a hardware
checklist).

**Primary recommendation:** Build the Dart queue as a small in-memory state machine wrapping
the existing `CompressJob`/`_jobRegistry` machinery with zero native changes for JOBS-03; add
one static isolate-initialisation convenience plus documentation for JOBS-04; and for JOBS-05
implement the Android foreground service as a single `Service` component owned by the plugin
(not `ActivityAware`, since `CompressVideoPlugin` only needs `applicationContext` to start a
service and post a notification) with its own `onTimeout` override that force-cancels every
hosted job with `interrupted`, while the iOS side wraps each job in
`beginBackgroundTask(expirationHandler:)` and maps both task expiration and the writer's
`.failed`/`AVError.operationInterrupted` outcome to the same reason.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Job queueing / concurrency limit | Dart (plugin's Flutter-facing layer) | — | CONTEXT.md locks this in `CompressVideo`; native engines stay per-job, no native queue |
| Background-isolate channel init | Dart (plugin's Flutter-facing layer) | Android/iOS platform channel plumbing (unchanged) | `BackgroundIsolateBinaryMessenger` is a Dart/engine-embedder concern; native Pigeon codegen needs no change |
| Android foreground service lifecycle | Android platform layer (`android/src/main/kotlin`) | — | `Service`, manifest, notification, `onTimeout` are all Android-API-level, owned by the plugin's own AAR |
| iOS background task / suspension mapping | Apple platform layer (`darwin/.../Sources`) | — | `UIApplication.beginBackgroundTask`, `AVError` mapping are AVFoundation/UIKit-level, owned by the Swift core shared between iOS and macOS (macOS branch is a no-op) |
| Error taxonomy (`interrupted`) | Dart (shared contract) | Android + Apple (both throw it) | Already defined in `lib/src/compress_video_exception.dart`; this phase is the first to throw it from both platforms |

## Standard Stack

No new third-party dependency is added by this phase. Every capability is implemented with
platform-owned APIs already available at the project's pinned toolchain versions
(`android/build.gradle.kts`: compileSdk 36, minSdk 23, Kotlin 2.3.20, JVM 17; `kotlinx-coroutines-android:1.10.2` already a dependency) or Dart/Flutter SDK APIs (`BackgroundIsolateBinaryMessenger` has shipped since Flutter 3.7, well below this project's stable floor).

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `android.app.Service` + `androidx.core.app.NotificationCompat` | AGP/compileSdk 36 (platform API, no version pin) | Foreground service host + its required notification | Standard Android mechanism for `mediaProcessing`-typed FGS; no alternative library needed [CITED: developer.android.com/develop/background-work/services/fgs/service-types] |
| `flutter/services.dart` `BackgroundIsolateBinaryMessenger` | Flutter SDK (stable since 3.7) | Registers a background isolate's `BinaryMessenger` so Pigeon-generated Host/FlutterApi calls work off the root isolate | Flutter's own documented mechanism; the alternative (hand-rolled isolate-to-isolate `SendPort` plumbing) is explicitly the thing "Don't Hand-Roll" flags below [CITED: docs.flutter.dev/platform-integration/platform-channels, medium.com/flutter/introducing-background-isolate-channels] |
| `UIApplication.beginBackgroundTask(expirationHandler:)` | iOS 13+ (platform API) | Requests extra background execution time for an in-flight `AVAssetWriter` job | Standard iOS mechanism; no entitlement or third-party dependency needed, matches CONTEXT.md's "no background-processing entitlement" decision |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `kotlinx-coroutines-android` | 1.10.2 (already a dependency, confirmed via `android/build.gradle.kts`) | Coordinating the service's per-job bookkeeping (job count, stop-when-empty) | Only if the queue/service bookkeeping benefits from a coroutine scope tied to the service lifecycle; a plain `MutableMap`/counter is also sufficient and may be simpler |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| One shared foreground service hosting all opted-in jobs | One service instance per job | Rejected by CONTEXT.md explicitly ("One service instance hosts all opted-in jobs"); per-job services would multiply notifications and complicate the 6h/24h quota accounting, which is tracked per FGS type, not per instance |
| `dataSync` FGS type as a pre-Android-15 fallback | None (explicitly deferred) | CONTEXT.md and REQUIREMENTS.md both defer this; `dataSync` would add a permission to every consuming app for a codepath most callers won't hit |
| A Dart `Isolate`-based worker pool for concurrency | The existing native per-job engines plus a Dart FIFO queue | The native engines already run correctly per-job; adding a Dart isolate pool would duplicate the isolate-plumbing work JOBS-04 already requires and gains nothing, since the actual encode work happens natively either way |

**Installation:** No new packages. No `pubspec.yaml`, `build.gradle.kts`, or `Package.swift`/podspec dependency changes are needed for this phase.

## Package Legitimacy Audit

Not applicable — this phase installs no new external packages (npm/pub/CocoaPods/SPM). All
new code uses platform SDK APIs (`android.app.Service`, `UIApplication`, Flutter's own
`BackgroundIsolateBinaryMessenger`) already available in the toolchain this project already
depends on. **Skip the Package Legitimacy Gate for this phase.**

## Architecture Patterns

### System Architecture Diagram

```
Dart caller
   |
   | compress(path, options)              [JOBS-03: queue]
   v
CompressVideo (Dart) ---- maxConcurrentJobs=N ----> internal FIFO queue
   |                                                     |
   | (job slot available)                                | (job waits, state=queued)
   v                                                     v
CompressJob.start() ---- Pigeon CompressHostApi.startCompress() ---- per job, unchanged
   |
   |-- binaryMessenger from BackgroundIsolateBinaryMessenger.ensureInitialized()
   |   when called from a background isolate                          [JOBS-04]
   v
Native platform channel
   |
   +-- Android: TransformerEngine.kt (existing, per-job)
   |      |
   |      +-- CompressOptions.androidForegroundService set?          [JOBS-05]
   |      |      yes -> ForegroundServiceHost.start()/attach(jobId)
   |      |             (one Service instance, ref-counts hosted jobs,
   |      |              stops itself when count reaches 0)
   |      |      onTimeout(startId, fgsType) fires (6h/24h quota) ->
   |      |             cancel every hosted job with reason=interrupted,
   |      |             delete partial output, stopSelf()
   |      +-- job completes/fails/cancels -> detach from service,
   |             stop service if it was the last hosted job
   |
   +-- Apple: CompressionEngine.swift (existing, per-job)
          |
          +-- iOS only: wrap job in UIApplication.beginBackgroundTask(
          |      expirationHandler: { cancel this job, reason=interrupted })
          +-- AVAssetWriter/.Reader reports operationInterrupted (-11847)
                 or writer.status == .failed after resignation ->
                 map to reason=interrupted (ErrorMapping.swift)
          +-- macOS: no wrapping, no suspension, unchanged
```

### Recommended Project Structure

No new top-level directories. New files fit the existing per-platform layout:

```
lib/
├── src/
│   ├── compress_video.dart          # queue lives here (CompressVideo.compress)
│   ├── compress_job.dart            # CompressJob gains a `queued` state; unchanged wire format
│   └── compress_video_isolate.dart  # NEW: static ensureInitializedInBackgroundIsolate() + doc
android/src/main/kotlin/com/danjjohnson/compress_video/
├── ForegroundServiceHost.kt         # NEW: the Service + notification + onTimeout
├── TransformerEngine.kt            # gains start/finish hooks into ForegroundServiceHost
├── ErrorMapping.kt                 # gains `interrupted` mapping (onTimeout path)
darwin/compress_video/Sources/compress_video/
├── CompressionEngine.swift          # gains beginBackgroundTask wrap (#if os(iOS))
├── ErrorMapping.swift               # gains `interrupted` mapping (-11847 / .failed)
android/src/main/AndroidManifest.xml # + FOREGROUND_SERVICE / FOREGROUND_SERVICE_MEDIA_PROCESSING
                                      #   permissions + <service> declaration
```

### Pattern 1: Dart FIFO queue with a concurrency gate

**What:** `CompressVideo` holds a private `Queue<_PendingJob>` and an active-count integer
bounded by `maxConcurrentJobs`. `compress()` always returns a `CompressJob` synchronously
(matching the existing `CompressJob.start()` contract, which is also synchronous-return); if
a slot is free, it starts the native call immediately; otherwise the job is created in a
`queued` state and its native call is deferred until a running job's `result` future
completes (success, failure, or cancel), at which point the queue pulls the next entry in
submission order.

**When to use:** Exactly this phase's JOBS-03 requirement — nothing native changes; this is
pure Dart scheduling above the existing one-job-per-native-call contract that Phases 2-4
already built and verified (`compress_jobs_test.dart` covers progress ordering, cancel, and
typed failures for the *unqueued* per-job behavior that this phase must not regress).

**Example (illustrative shape, not a verified code listing):**
```dart
// Illustrative only -- exact structure is Claude's Discretion per CONTEXT.md.
class CompressVideo {
  CompressVideo({this.maxConcurrentJobs = 1})
    : assert(maxConcurrentJobs >= 1);
  final int maxConcurrentJobs;
  final Queue<_PendingJob> _queue = Queue<_PendingJob>();
  int _activeCount = 0;

  CompressJob compress(String path, CompressOptions options) {
    final job = CompressJob._queued(generateJobId());
    _queue.add(_PendingJob(job, path, options));
    _pump();
    return job;
  }

  void _pump() {
    while (_activeCount < maxConcurrentJobs && _queue.isNotEmpty) {
      final pending = _queue.removeFirst();
      _activeCount++;
      pending.job._start(...).whenComplete(() {
        _activeCount--;
        _pump();
      });
    }
  }
}
```

### Pattern 2: Background isolate initialisation convenience

**What:** A static method that is a one-line wrapper:
```dart
// Source: Flutter SDK docs pattern (docs.flutter.dev/platform-integration/platform-channels,
// medium.com/flutter/introducing-background-isolate-channels), adapted to this plugin's shape.
static void ensureInitializedInBackgroundIsolate(RootIsolateToken token) {
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
}
```
**When to use:** Documented as the required first call inside any `Isolate.run`/`compute`
callback that will call `CompressVideo` methods. The caller obtains the token on the root
isolate with `RootIsolateToken.instance` (non-null only on the root isolate) and passes it
into the spawned isolate's closure.

### Anti-Patterns to Avoid
- **Hand-rolling a `SendPort`/`ReceivePort` bridge to funnel calls back to the root isolate:**
  unnecessary — `BackgroundIsolateBinaryMessenger` makes Pigeon-generated Host and Flutter
  APIs (including EventChannel-backed ones, per the `EventChannel.binaryMessenger` docs)
  usable directly from the background isolate without any bridge.
- **Starting a new foreground service per job:** rejected by CONTEXT.md; also multiplies
  notifications and complicates 6h/24h quota accounting, which Android tracks per
  service *type* system-wide, not per component instance.
- **Swallowing `onTimeout` without calling `stopSelf()`:** the documented consequence is an
  ANR ("A foreground service of <fgs_type> did not stop within its timeout")
  [CITED: developer.android.com/develop/background-work/services/fgs/timeout].

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Calling platform channels from a non-root isolate | A custom isolate-to-isolate message bridge that proxies calls back to the root isolate | `BackgroundIsolateBinaryMessenger.ensureInitialized(RootIsolateToken)` | This is exactly the API Flutter shipped in 3.7 to solve this; it registers the isolate's own direct platform-channel path, no proxying needed [CITED: medium.com/flutter/introducing-background-isolate-channels] |
| Detecting Android FGS quota exhaustion | Polling `dumpsys` or tracking elapsed wall-clock time in the plugin itself | `Service.onTimeout(int startId, int fgsType)` (Android 15+) | The system already tracks the 6h/24h budget per FGS type and calls this override; duplicating that accounting in app code would drift from the real quota [CITED: developer.android.com/develop/background-work/services/fgs/timeout] |
| Detecting an interrupted AVFoundation export | Wrapping every writer call in a custom timeout/heartbeat | `AVError.operationInterrupted` (-11847) and `AVAssetWriter.status == .failed` after resignation | This is the documented, system-reported signal for exactly this condition [CITED per VIDEO_COMPRESS_BRIEF.md §5, quoting an Apple engineer's forum reply: developer.apple.com/forums/thread/672056] |

**Key insight:** every piece of "background survival" logic in this phase has a first-party
system callback or API designed for it (`onTimeout`, `beginBackgroundTask`'s
`expirationHandler`, `AVError` codes). The implementation risk is in wiring these correctly
to the existing per-job engines and error taxonomy, not in inventing new mechanisms.

## Common Pitfalls

### Pitfall 1: Queue starvation on cancel-while-queued
**What goes wrong:** Cancelling a queued job (never reached native) must still call `_pump()`
to consider the next queue entry, or a slot that should be immediately free will be perceived
as never freed if the queue-removal path doesn't share code with the completion path.
**Why it happens:** Cancel-while-queued resolves the job's `result` synchronously in Dart
without ever incrementing `_activeCount`, so it must NOT decrement it either — a mismatched
count is an easy off-by-one.
**How to avoid:** Route "remove from queue, resolve `cancelled`" through a path that does not
touch `_activeCount`, and give the running-job completion path (which does touch it) its own
single `_pump()` call site.
**Warning signs:** A concurrency-limit-2 test where cancelling a queued job never lets a later
job start.

### Pitfall 2: Background isolate omission produces a hang, not a clean error
**What goes wrong:** If `BackgroundIsolateBinaryMessenger.ensureInitialized` is skipped, the
exact failure mode reported in `flutter/flutter#144342` is a null-check exception raised
*during a platform message response callback* — i.e., it can surface asynchronously and not
at the call site, which risks looking like a hang if the exception is dropped by an
unhandled-async-error path rather than being caught and rethrown as `CompressVideoException`.
**Why it happens:** Pigeon-generated Host API calls use the ambient default messenger; on a
background isolate before initialisation, that default messenger is `null`/unset and the
Flutter engine's platform-message plumbing null-checks it.
**How to avoid:** CONTEXT.md's own proof step ("a case proving a clear typed error, not a
hang, when initialisation was skipped") should assert this surfaces as a normal Dart
exception on the call (or the returned `Future`), not an unhandled zone error; verify this
empirically during execution rather than assuming Pigeon's generated code already wraps it.
**Warning signs:** An integration test for the omitted-initialisation case that passes only
because it never actually awaits the failing call.
[CITED: github.com/flutter/flutter/issues/144342]

### Pitfall 3: `startForeground()` without a visible notification channel silently degrades
**What goes wrong:** On API 33+, `POST_NOTIFICATIONS` is a runtime permission; if it is
denied, `startForegroundService`/`startForeground()` still succeeds (the service still runs
and gets FGS protections), but the user sees no notification, which can look like "the
foreground service didn't start" during manual testing.
**Why it happens:** `POST_NOTIFICATIONS` gates whether a notification is *shown*, not whether
a foreground service is legally allowed to start — these are separate Android mechanisms and
are commonly conflated.
**How to avoid:** Document this explicitly (the notification may not display without the
runtime permission, but the service — and the compression — still runs); do not make the
plugin request `POST_NOTIFICATIONS` itself (that's an app-level decision, not obviously
appropriate for a library to force). [ASSUMED — based on general Android permission-model
training knowledge; not verified against a live device/emulator this session. Flag for
verification during execution: start the service on the emulator with the notification
permission both granted and denied, and confirm compression still completes in the denied
case.]

### Pitfall 4: Manifest merging silently drops the plugin's `<service>` if the host app declares one at the same name
**What goes wrong:** A Flutter plugin AAR's manifest is merged into the consuming app's
merged manifest by Gradle's manifest merger; a conflicting `<service>` element (same fully
qualified name, different attributes) declared by the app itself can cause a merge failure or
require `tools:node="merge"` annotations.
**Why it happens:** Standard Gradle manifest-merging behavior, not specific to this plugin.
**How to avoid:** Use a service class name fully namespaced under
`com.danjjohnson.compress_video` (already this project's package) so a collision with
app-level code is implausible; document the requirement in the README regardless, per the
pattern of other plugins that ship a `<service>` (e.g., WorkManager-based plugins).
[ASSUMED — general Gradle manifest-merger behavior, not verified against this specific
manifest this session.]

### Pitfall 5: `onTimeout(startId, fgsType)` runs on the main thread with only "a few seconds" before ANR
**What goes wrong:** The system's window to call `stopSelf()` after `onTimeout` fires is
short; any blocking work in the `onTimeout` override (e.g., synchronous disk I/O to delete
every hosted job's partial file) risks the ANR the mechanism is meant to have you avoid.
**Why it happens:** `onTimeout` documentation describes it as time-boxed by design (it exists
specifically so the system can enforce the FGS type's time limit without waiting indefinitely
for the app to clean up).
**How to avoid:** In `onTimeout`, immediately cancel all hosted jobs (a cheap, already-existing
Kotlin operation via `JobRegistry`/`Compression`'s existing cancel path) and call
`stopSelf()`; defer any slower partial-file deletion to the same cancellation path the
existing per-job cancel already uses (which CONTEXT.md says is unchanged), rather than doing
extra synchronous work inside `onTimeout` itself.
**Warning signs:** A CI/emulator test that cannot practically trigger real 6h-quota
exhaustion — this is one of Phase 5's genuine untestable-in-CI edges; the `onTimeout` code
path itself can still be unit-tested by invoking the override directly with a fake
`Service`/context, without waiting for a real 6-hour window.
[CITED: developer.android.com/develop/background-work/services/fgs/timeout]

### Pitfall 6: iOS simulator cannot genuinely suspend an app to trigger the interruption
**What goes wrong:** `xcrun simctl` has no documented command to suspend a specific running
app process the way a real device backgrounding + memory-pressure eviction would; a test that
tries to prove the `interrupted` mapping by actually suspending the simulator app is likely to
be unreliable or impossible in CI.
**Why it happens:** The simulator models foreground/background app state transitions
differently from a physical device's process-suspension and OS-level task-completion timers.
**How to avoid:** CONTEXT.md already anticipates this — plan the integration-test proof as an
*injected* interruption (a test-only hook that synthesizes the `AVError.operationInterrupted`
condition or forces the writer into `.failed` status) rather than a real backgrounding
transition, and defer the real hardware/Mac walkthrough to the hardware checklist, matching
the pattern already used for the HDR/HEVC hardware-only items in Phase 4's
`doc/HARDWARE_CHECKLIST.md`.
**Warning signs:** A plan task that requires `simctl` to background the app as its *only*
proof of the mapping, with no injected-fault fallback — this would make the task's own
`<precondition>` unmeetable in CI, the same shape as the Phase 3/4 Mac-blocked tasks already
logged in STATE.md.
[ASSUMED — based on general knowledge of `simctl`'s documented capabilities; not verified via
a fresh `xcrun simctl help` this session due to no reachable Mac this session per lane notes.]

## Runtime State Inventory

Not applicable — this is a greenfield feature phase (new queue, new isolate helper, new
foreground service, new error mapping), not a rename/refactor/migration phase. No existing
stored data, service config, OS-registered state, secrets, or build artifacts reference names
that this phase changes.

## Code Examples

### Android: minimal `onTimeout` override shape
```kotlin
// Illustrative pattern per Android's documented Service.onTimeout(int, int) contract.
// Source: developer.android.com/develop/background-work/services/fgs/timeout
override fun onTimeout(startId: Int, fgsType: Int) {
    // Cancel every job this service instance is hosting, reason = interrupted,
    // reusing the existing per-job cancel path (JobRegistry / Compression).
    hostedJobIds.toList().forEach { jobId -> compression.cancelWithReason(jobId, "interrupted") }
    stopSelf(startId)
}
```

### Dart: obtaining the root isolate token before spawning
```dart
// Source: Flutter SDK background-isolate pattern
// (medium.com/flutter/introducing-background-isolate-channels)
final RootIsolateToken token = RootIsolateToken.instance!;
await Isolate.run(() async {
  CompressVideo.ensureInitializedInBackgroundIsolate(token);
  final result = await const CompressVideo().compress(path, options).result;
  return result;
});
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| Untyped `MethodChannel`, no injectable messenger (video_compress's own limitation — GitHub issue #242 "cannot run in a background isolate") | Pigeon-generated typed APIs + `BackgroundIsolateBinaryMessenger` | Flutter 3.7 (`BackgroundIsolateBinaryMessenger` shipped) | This phase directly closes the incumbent's #242 gap (7-reaction wish), one of the differentiators named in the project brief |
| `dataSync` FGS type used generically for any long-running background work pre-Android-14 | `mediaProcessing`-typed FGS, introduced for exactly "converting media to different formats" | Android 14 (API 34) added the type; Android 15 added `onTimeout`/6h quota enforcement | This project's minSdk is 23 but the FGS opt-in is explicitly Android-15+-only per CONTEXT.md, so the newer, better-fitting type is used without needing an older fallback |

**Deprecated/outdated:**
- iOS `AVAssetExportSession.progress`: deprecated in iOS 27 in favor of `states(updateInterval:)` — not directly relevant to JOBS-05 (the Apple engine here uses `AVAssetWriter`, not `AVAssetExportSession`, per Phase 3/4's already-locked architecture) but worth keeping in mind if any export-session code path is touched during this phase.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A denied `POST_NOTIFICATIONS` permission does not block `startForeground()` from succeeding on API 33+, only the notification's visibility | Common Pitfalls 3 | If wrong, the plugin might need to guard the FGS start behind a permission check, changing the opt-in contract; must be verified live on the emulator during execution |
| A2 | Gradle manifest merging will not silently drop the plugin's `<service>` given a namespaced class name | Common Pitfalls 4 | If wrong, the FGS could fail to register in a consuming app's merged manifest without a build error, a hard-to-diagnose failure; low risk given the namespacing, but unverified |
| A3 | `xcrun simctl` cannot genuinely suspend a running app process to trigger `AVError.operationInterrupted` naturally | Common Pitfalls 6 | If wrong (i.e., if some `simctl`/`launchctl` invocation *can* do this), the integration-test proof could rely on a real suspension rather than an injected fault, which CONTEXT.md's plan already treats as likely infeasible — being wrong here would only mean a *simpler* proof is available, low downside |
| A4 | iOS `beginBackgroundTask`'s effective wall-clock budget on the pinned iOS 26 target is short enough (commonly cited as tens of seconds) that most non-trivial compressions will hit the interruption path rather than complete within it | Summary; Architecture Patterns | If the real budget is materially longer, "short jobs finish after backgrounding" (CONTEXT.md's own framing) may cover more real-world cases than expected, changing how often `interrupted` is actually observed in practice — does not change the required mapping code, only its exercise frequency |

## Open Questions

1. **Does Media3 Transformer's export actually keep progressing on the danserver emulator
   after `moveTaskToBack`, independent of the foreground service wrapping it?**
   - What we know: Media3 Transformer runs its own internal processing (not tied to Activity
     lifecycle) once started; a foreground service is what keeps the *process* alive long
     enough for that processing to finish once the Activity is gone, and Android's process
     ramping-down/OOM-killer behavior (not Activity destruction alone) is the actual risk
     without one.
   - What's unclear: whether the specific `compress_video_api35` software-GL emulator profile
     (already documented in STATE.md as slow/limited for some HDR paths) shows any additional
     throttling of background CPU work that would confound a plan's proof step.
   - Recommendation: the plan should verify this empirically as its own task (start a job with
     the FGS option on, `moveTaskToBack`, poll for completion) rather than assume it from
     documentation; if the emulator throttles unexpectedly, the existing HARDWARE_CHECKLIST.md
     pattern (documented known-limitation, not a code bug) is the fallback, matching how
     Phase 4 handled the emulator's software-GL HDR tone-map exhaustion.

2. **Exact wording/availability of `Manifest.permission.POST_NOTIFICATIONS`'s interaction with
   `startForeground()` for a `mediaProcessing`-typed service specifically** (as opposed to FGS
   types generally) was not independently re-verified against Android's dedicated
   `mediaProcessing` service-types page this session, beyond the general FGS timeout page
   already searched.
   - What we know: general Android runtime-notification-permission behavior (§Pitfall 3).
   - What's unclear: whether `mediaProcessing` has any type-specific notification requirement
     beyond the general FGS notification requirement (all FGS need *a* notification within a
     short window of `startForeground()`, regardless of type).
   - Recommendation: re-check `developer.android.com/develop/background-work/services/fgs/service-types#media-processing` directly during planning/execution before writing the manifest and service code, and confirm empirically on the emulator.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Android SDK + headless emulator (danserver) | JOBS-05 Android proof | Yes | API 35 `compress_video_api35`, per CLAUDE.md lane notes | — |
| Physical Android phone | Real backgrounding walkthrough (deferred) | No (per QUESTIONS.md #3) | — | Emulator proof + hardware checklist item, per CONTEXT.md |
| macOS host / iOS simulator (MacBook Air over SSH) | JOBS-04/05 Apple-side proof, XCTest | Uncertain this session — probe once, do not loop (per required_reading instruction); GitHub Actions `apple` job is the standing Apple verifier regardless | 3.47.5 Flutter stable on Mac; CI runner is macOS-latest | GitHub Actions macOS runner (CI) |
| GitHub Actions | CI verification for both platforms | Yes — repo is public, prior billing block cleared per lane notes | — | — |

**Missing dependencies with no fallback:**
- Physical Android phone and physical iPhone real-suspension walkthroughs — both explicitly
  deferred to the hardware checklist by CONTEXT.md; not a blocker for this phase's plan.

**Missing dependencies with fallback:**
- Mac reachability for local iteration — CI (`github` remote, macOS runner) is the standing
  fallback verifier, as established in prior phases and reiterated in this project's CLAUDE.md.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `flutter test` (Dart unit) + `example/integration_test` (Android emulator via `flutter test integration_test`, iOS simulator via `tool/run_ios_integration_suites.sh`) |
| Config file | `example/integration_test/` suite files; suite list in `tool/run_ios_integration_suites.sh` |
| Quick run command | `flutter test` (Dart-only unit tests, fast) |
| Full suite command | Android: `flutter test integration_test` on the booted emulator; Apple: `tool/run_ios_integration_suites.sh` (or CI's `apple` job) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| JOBS-03 | 3 jobs queue sequentially by default; limit=2 runs 2 at once; each job's own progress | unit + integration | `flutter test` (queue unit tests) + `flutter test integration_test` (real concurrent compressions) | ❌ Wave 0 — new test file needed, alongside existing `compress_jobs_test.dart` pattern |
| JOBS-04 | Background isolate compress completes with typed result; omitted-init case yields typed error not a hang | integration (all 3 platforms) | `flutter test integration_test` (Android/iOS/macOS) | ❌ Wave 0 — new suite, must be added to `tool/run_ios_integration_suites.sh`'s list per CONTEXT.md |
| JOBS-05 (Android) | FGS-opted job survives `moveTaskToBack`; `dumpsys activity services` shows `mediaProcessing` type; `onTimeout` cancels with `interrupted` | integration (emulator) + unit (`onTimeout` override invoked directly) | `flutter test integration_test` + Android native unit test (Kotlin JVM test of the `onTimeout` handler) | ❌ Wave 0 — needs the example app's `moveTaskToBack` MethodChannel (example-only, CONTEXT.md) plus the new native unit test |
| JOBS-05 (iOS) | Suspension maps to retryable `interrupted`, never hang/null | XCTest (error-mapping unit test) + iOS simulator integration test (injected interruption) | XCTest via `RunnerTests.swift`-adjacent new test file; `tool/run_ios_integration_suites.sh` | ❌ Wave 0 — new XCTest cases for `ErrorMapping.swift`'s new `interrupted` branch |

### Sampling Rate
- **Per task commit:** `flutter test` (Dart unit, fast feedback on queue logic and error taxonomy)
- **Per wave merge:** full emulator + simulator/CI integration suites, matching existing phase practice
- **Phase gate:** Full suite green (Android emulator locally, Apple via CI's `apple` job) before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] A new Dart unit test file (e.g. `test/compress_video_queue_test.dart`) covering FIFO ordering, concurrency-limit-2 behavior, and cancel-while-queued (Pitfall 1) — covers JOBS-03
- [ ] A new integration test exercising `Isolate.run` + `ensureInitializedInBackgroundIsolate`, plus the omitted-initialisation typed-error case — covers JOBS-04
- [ ] Example app's `moveTaskToBack` MethodChannel (example-only, outside plugin channel-grep scope per CONTEXT.md) — needed before the Android FGS integration proof can run
- [ ] A Kotlin JVM unit test directly invoking the new `onTimeout(startId, fgsType)` override (no real 6h wait needed) — covers the untestable-in-CI edge of Pitfall 5
- [ ] New XCTest cases in the Apple test target for `ErrorMapping.swift`'s `interrupted` case (RunnerTests.swift itself stays byte-identical per CONTEXT.md, so this is a new adjacent file) — covers JOBS-05 (iOS)
- [ ] Any new suite added to both `tool/run_ios_integration_suites.sh`'s list and the CI parity gate, per CONTEXT.md's explicit reminder

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Plugin has no auth surface |
| V3 Session Management | No | N/A |
| V4 Access Control | Marginal | Android: only the plugin's own code starts/stops its foreground service; no external Intent surface is exposed (no exported `<service>`) |
| V5 Input Validation | Yes | `maxConcurrentJobs >= 1` assertion (already specified in CONTEXT.md); `RootIsolateToken` is an opaque Flutter-engine-issued token, not user input, so no additional validation surface there |
| V6 Cryptography | No | N/A |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Exported `<service>` reachable by other apps on the device | Elevation of Privilege | Declare the new `<service>` `android:exported="false"` (it is only ever started from within the same process by the plugin's own Kotlin code, never via an external Intent) |
| A malicious host app could theoretically abuse an unbounded `maxConcurrentJobs` to exhaust device resources | Denial of Service | Out of this plugin's threat model (the host app is the trusted caller, not an adversary); no additional mitigation beyond the existing `>= 1` validation is warranted |
| Partial output files left behind after an `interrupted` cancellation | Information Disclosure (stale sensitive video content) | CONTEXT.md already specifies "partial output deleted" for both the Android `onTimeout` path and the iOS interruption path — reuses the existing per-job cleanup, not new work |

## Sources

### Primary (HIGH confidence)
- Read this session: `lib/src/compress_job.dart`, `lib/compress_video.dart`, `lib/src/compress_video_exception.dart` (lines ~6-46, `CompressVideoErrorReason` enum including the reserved `interrupted` value), `android/src/main/kotlin/com/danjjohnson/compress_video/CompressVideoPlugin.kt` (confirms `FlutterPlugin`-only, `applicationContext` available, no `ActivityAware`), `android/src/main/AndroidManifest.xml` (currently empty of permissions/services), `android/build.gradle.kts` (compileSdk 36, minSdk 23, Kotlin 2.3.20, JVM 17, `kotlinx-coroutines-android:1.10.2`), `pubspec.yaml` (pigeon 29.0.2)
- `.planning/phases/05-jobs-isolates-and-background/05-CONTEXT.md` — locked decisions, verbatim above
- `.planning/REQUIREMENTS.md` — JOBS-03/04/05 text
- `.planning/research/sources/VIDEO_COMPRESS_BRIEF.md` — §5 "Background" (Apple engineer's -11847 quote, Android 6h/24h quota, sourced to developer.apple.com/forums/thread/672056 and developer.android.com/develop/background-work/services/fgs/service-types)

### Secondary (MEDIUM confidence)
- [developer.android.com/develop/background-work/services/fgs/timeout](https://developer.android.com/develop/background-work/services/fgs/timeout) — `Service.onTimeout(int,int)`, 6h/24h quota tracked per FGS type, ANR consequence of not calling `stopSelf()`
- [medium.com/flutter/introducing-background-isolate-channels](https://medium.com/flutter/introducing-background-isolate-channels-7a299609cad8) — `BackgroundIsolateBinaryMessenger` mechanism and pattern
- `EventChannel.binaryMessenger` API docs (main-api.flutter.dev) — confirms EventChannel resolves to `BackgroundIsolateBinaryMessenger` automatically off the root isolate, supporting the JOBS-04 assumption that Pigeon's `@EventChannelApi`-generated code (if any is added later) would work the same way as HostApi

### Tertiary (LOW confidence)
- General Android `POST_NOTIFICATIONS`/FGS-start interaction (Pitfall 3, Assumption A1) — training knowledge, not independently re-verified against a dedicated doc page this session
- Gradle manifest-merger behavior for a plugin AAR `<service>` (Pitfall 4, Assumption A2) — training knowledge
- `xcrun simctl` suspension capability (Pitfall 6, Assumption A3) — training knowledge, no live `simctl help` run this session (no reachable Mac)
- iOS `beginBackgroundTask` typical budget (Assumption A4) — training knowledge; not re-verified against current Apple docs this session

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all APIs are already-pinned platform SDKs
- Architecture: MEDIUM — the Dart queue and isolate-init patterns are well-established; the Android FGS/`onTimeout` and iOS suspension mapping are correctly sourced but unverified against this project's actual emulator/simulator behavior
- Pitfalls: MEDIUM — Pitfalls 1, 2, 5 are grounded in read code or a cited GitHub issue; Pitfalls 3, 4, 6 are flagged `[ASSUMED]` and listed in the Assumptions Log for confirmation during planning/execution

**Research date:** 2026-09-27
**Valid until:** 30 days (stable platform APIs; re-check if Android or iOS ships a new OS version in that window, per this project's own "verify at Phase 1, don't trust training data" pattern)

## RESEARCH COMPLETE
