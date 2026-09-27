---
phase: 05-jobs-isolates-and-background
plan: 03
subsystem: android-background-execution
tags: [android, foreground-service, media3, kotlin, pigeon, compress-video]

# Dependency graph
requires:
  - phase: 05-jobs-isolates-and-background
    provides: "05-01's per-instance FIFO queue (unchanged) and 05-02's JobRegistry result-deferred pattern, reused here for the reason-carrying cancellation path"
provides:
  - "CompressOptions.androidForegroundService / AndroidForegroundServiceOptions -- the opt-in for the mediaProcessing foreground service"
  - "ForegroundServiceHost -- a ref-counted, self-stopping Android foreground service with a framework-free Ref bookkeeping helper, tested on plain JVM"
  - "JobRegistry.cancel(jobId, reason) -- the retryable interrupted reason threaded through the existing cancellation path, reusable by 05-04's Apple work"
  - "CI evidence: a live dumpsys poll during the emulator suite, plus a deterministic aapt2-based merged-manifest assertion"
affects: [05-04-ios-suspension, 05-05-phase-signoff]

# Actuals (#2632)
actuals:
  tokens: 21000
  tasks: 3
  commits: 4

tech-stack:
  added: []
  patterns:
    - "A ref-counted foreground service (ForegroundServiceHost) whose entire framework-free bookkeeping (attach/detach/onTimeout) lives in a nested Ref class with no Android import, so its whole contract -- including the six-hour quota's onTimeout -- is provable on plain JVM with injected test doubles, no Robolectric, no real Service, no emulator."
    - "A cancellation reason threaded through an existing path (JobRegistry.cancel(jobId, reason = \"cancelled\")) rather than a new mechanism -- every existing call site keeps its behaviour with no edit, and the new caller (onTimeout) just supplies a different string."

key-files:
  created:
    - android/src/main/kotlin/com/danjjohnson/compress_video/ForegroundServiceHost.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/ForegroundServiceHostTest.kt
    - tool/verify_apk_foreground_service_manifest.sh
  modified:
    - pigeons/messages.dart
    - lib/src/messages.g.dart
    - android/src/main/kotlin/com/danjjohnson/compress_video/Messages.g.kt
    - darwin/compress_video/Sources/compress_video/Messages.g.swift
    - lib/src/compress_options.dart
    - lib/compress_video.dart
    - lib/src/compress_video_exception.dart
    - android/src/main/AndroidManifest.xml
    - android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/ArgumentsTest.kt
    - example/android/app/src/main/kotlin/com/danjjohnson/compress_video_example/MainActivity.kt
    - example/integration_test/jobs_background_test.dart
    - test/compress_options_test.dart
    - .github/workflows/ci.yml

key-decisions:
  - "Pulled JobRegistry.cancel's reason parameter and TransformerEngine's ExportOutcome.Cancelled(reason) forward from Task 3 into Task 1's commit, because ForegroundServiceHost.onTimeout (written in Task 1's new file, per the tracer's own end-to-end scope) needed JobRegistry.cancel(jobId, \"interrupted\") to compile. Task 3's own contribution is exercising that code with ForegroundServiceHostTest.kt and updating the interrupted dartdoc."
  - "No AndroidX Core notification-compatibility helper -- android/build.gradle.kts declares no direct dependency on it, so ForegroundServiceHost uses the platform's own Notification.Builder/NotificationChannel, unconditionally available at API 35+ (the only level this service ever runs at). Recorded per the plan's own research-override note."
  - "The framework-free Ref class inside ForegroundServiceHost is what makes onTimeout's whole contract (cancel every hosted job, then unconditionally stop) provable in a plain JVM Gradle test -- the real Service.onTimeout override is a two-line wrapper around Ref.onTimeout with injected cancel/stop closures, matching JobRegistry's own established test-without-a-real-Transformer pattern."
  - "Assumption A1 (notification permission does not gate the service starting) verified by observation rather than by toggling a runtime permission: this app declares no POST_NOTIFICATIONS permission at all (matching the plugin's own prohibition on requesting it), so dumpsys confirms zero runtime permissions granted on every run -- the suite has never once run with that permission present, and it passes every time. There is no meaningful \"granted\" comparison run since the app never requests it by design."
  - "05-RESEARCH.md Open Question 1 answered by direct measurement on the API 35 emulator: 1 progress event observed before the app was backgrounded, 22 after, reaching 100 -- the encode genuinely kept progressing inside the foreground service after losing the foreground, not merely finishing something already done."

requirements-completed: []

coverage:
  - id: D1
    description: "CompressOptions.androidForegroundService accepts a notification title/text/optional icon, defaults to absent, and validates non-blank title/text in both Dart and Kotlin"
    requirement: JOBS-05
    verification:
      - kind: unit
        ref: "test/compress_options_test.dart#CompressOptions.validate androidForegroundService cases (4 new)"
        status: pass
      - kind: unit
        ref: "android/src/test/kotlin/.../ArgumentsTest.kt#validateAndroidForegroundService and requireValidCompressRequest cases (5 new)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The plugin's own manifest declares FOREGROUND_SERVICE + FOREGROUND_SERVICE_MEDIA_PROCESSING and a non-exported mediaProcessing service, no intent filter, no dataSync, no POST_NOTIFICATIONS"
    requirement: JOBS-05
    verification:
      - kind: other
        ref: "grep assertions against android/src/main/AndroidManifest.xml (all pass, see task 1 acceptance criteria)"
        status: pass
      - kind: e2e
        ref: "tool/verify_apk_foreground_service_manifest.sh against the built example APK, wired into CI's android job -- CI run 36321581676, step 'Verify the debug APK's merged manifest carries the foreground-service declaration' passed"
        status: pass
    human_judgment: false
  - id: D3
    description: "A job with the option set runs inside a real mediaProcessing foreground service on the API 35 emulator, visible to dumpsys with the right type, and gone once the job ends"
    requirement: JOBS-05
    verification:
      - kind: integration
        ref: "example/integration_test/jobs_background_test.dart#Android foreground service opt-in (JOBS-05, D-07/D-08)"
        status: pass
      - kind: e2e
        ref: "live adb dumpsys capture (local) and CI's own polled dumpsys log, both showing isForeground=true types=0x00002000 -- CI run 36321581676 step 'Run emulator integration tests' printed 'dumpsys confirmed ForegroundServiceHost running with the mediaProcessing type during the suite'"
        status: pass
    human_judgment: false
  - id: D4
    description: "A job survives the example app being backgrounded mid-encode and completes with a typed result; progress observed after backgrounding is recorded"
    requirement: JOBS-05
    verification:
      - kind: integration
        ref: "example/integration_test/jobs_background_test.dart#Backgrounding mid-encode survives, honestly, on whatever API level runs this suite (JOBS-05, D-08/D-10)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Below API 35 the option is accepted and inert -- job unaffected, no service, no permission exercised"
    requirement: JOBS-05
    verification: []
    human_judgment: true
    rationale: "The only available emulator/CI image is API 35 -- the below-35 branch is written and covered by the same test case's conditional assertion, but has not executed on a real sub-35 device or image this session. Carried forward exactly like other cross-platform/hardware gaps in this project (see doc/HARDWARE_CHECKLIST.md convention)."
  - id: D6
    description: "Notification permission denial does not prevent the service starting or the job completing (assumption A1)"
    requirement: JOBS-05
    verification:
      - kind: e2e
        ref: "dumpsys package com.danjjohnson.compress_video_example showing zero runtime permissions granted, across every passing run of jobs_background_test.dart this session"
        status: pass
    human_judgment: false
  - id: D7
    description: "onTimeout cancels every hosted job with the interrupted reason, deletes partial files through the existing cancellation path, and stops the service -- proven on plain JVM"
    requirement: JOBS-05
    verification:
      - kind: unit
        ref: "android/src/test/kotlin/.../ForegroundServiceHostTest.kt (5 cases: ref-up, ref-down-to-stop, unknown-id detach, onTimeout with hosted jobs, onTimeout with none)"
        status: pass
    human_judgment: false
  - id: D8
    description: "Ordinary cancellation behaviour is unchanged by the reason-parameter plumbing; the existing cancellation group still passes"
    requirement: JOBS-05
    verification:
      - kind: integration
        ref: "example/integration_test/compress_jobs_test.dart 'Cancel: typed outcome, closed stream, deleted partial, idempotent' group, re-run within the full example/integration_test directory pass (local, exit 0) and CI run 36321581676"
        status: pass
    human_judgment: false

duration: ~50min
completed: 2026-09-27
status: complete
---

# Phase 5 Plan 3: Android `mediaProcessing` foreground service, live-verified end to end Summary

**A job opts into Android's `mediaProcessing` foreground service via `CompressOptions.androidForegroundService`; `ForegroundServiceHost` ref-counts hosted jobs, stops itself, and turns the system's six-hour quota expiry into a retryable `interrupted` failure -- proven with a live `dumpsys` capture (both locally and in CI) showing the real service type, a measured backgrounding proof (1 progress event before, 22 after), and five plain-JVM `onTimeout` tests with no emulator.**

## Performance

- **Duration:** ~50 min (three task commits plus a CI-round-trip fix for a stable-channel Dart formatting difference)
- **Tasks:** 3 (tracer + 2 auto)
- **Files modified:** 17 modified, 3 created

## Accomplishments

- **JOBS-05's Android half is demonstrably true, not merely code-complete.** A live `adb shell dumpsys activity services` capture, taken while a job was in flight on the `compress_video_api35` emulator, shows `isForeground=true foregroundId=4200 types=0x00002000` (`ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING`) and the correct notification channel -- and CI's own polled `dumpsys` log shows the identical evidence on a fresh hosted emulator (run 36321581676).
- **05-RESEARCH.md Open Question 1 answered by measurement:** backgrounding `portrait_hibitrate_1080p60.mp4`'s compression mid-encode showed 1 progress event before the app lost focus and 22 more after, reaching 100 -- the encode genuinely kept running inside the foreground service, not merely finishing something already done.
- **Assumption A1 confirmed empirically, not patched around:** this app declares no `POST_NOTIFICATIONS` permission at all (matching the plugin's own prohibition on requesting it) -- `dumpsys package` shows zero runtime permissions granted on every run, and every run of the suite still passes. There is no meaningful "granted" comparison to run, since the permission is never requested by design; the "denied" condition is this app's permanent state, and it never blocks the service.
- `ForegroundServiceHost` -- a started, ref-counted `mediaProcessing` service using the platform's own `Notification.Builder`/`NotificationChannel` (no AndroidX Core dependency, confirmed unchanged in `android/build.gradle.kts`). Its whole bookkeeping (attach/detach ref-count, `onTimeout`'s cancel-all-then-stop) lives in a framework-free nested `Ref` class, proven by 5 new plain-JVM cases in `ForegroundServiceHostTest.kt` with no Robolectric, no real `Service`, no emulator.
- `JobRegistry.cancel` gained a `reason` parameter (default `"cancelled"`, every existing call site unchanged) and `TransformerEngine`'s `ExportOutcome.Cancelled` now carries it, so `onTimeout` can resolve every hosted job as a typed, retryable `interrupted` failure through the exact same cancellation path that already deletes partial files -- no new deletion logic, no new guard, and `compress_jobs_test.dart`'s ordinary-cancellation group is unchanged (re-verified, full suite green).
- Pigeon contract gained `AndroidForegroundServiceOptionsMessage` and the `androidForegroundService` field on `CompressRequestMessage`, regenerated deterministically (re-running `dart run pigeon` a second time produces a byte-identical `messages.g.dart`) into Dart, Kotlin and Swift.
- `CompressOptions.androidForegroundService` / `AndroidForegroundServiceOptions` (Dart) mirrored by `Arguments.validateAndroidForegroundService` (Kotlin) -- both reject a blank title or text with `unsupportedInput`, both accepted by 9 new unit test cases total (4 Dart, 5 Kotlin).
- The plugin's own `AndroidManifest.xml` declares `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PROCESSING` and a non-exported `<service>`, no intent filter, no `dataSync`, no `POST_NOTIFICATIONS` -- and a new deterministic backstop, `tool/verify_apk_foreground_service_manifest.sh` (via `aapt2 dump xmltree`/`badging`), proves the built example APK's MERGED manifest really carries all of it (05-RESEARCH.md assumption A2), wired into CI as its own step.
- The example app's `MainActivity` gained a hand-written `MethodChannel` (`moveTaskToBack` + `apiLevel`) -- deliberately outside the plugin's own channel-plumbing scope (`lib/`, `android/src/main/`, `darwin/compress_video/Sources/`), confirmed by the existing CI grep step, which still finds nothing.
- CI's emulator-integration step now also polls a backgrounded `dumpsys activity services` loop for the whole run and fails the step if it never saw `ForegroundServiceHost` with the `mediaProcessing` type -- confirmed working live in CI run 36321581676.

## Task Commits

1. **Task 1 (tracer): a job opts into the foreground service, end to end** -- `edc1f92` (feat)
2. **Task 2: backgrounding proof, CI dumpsys + manifest evidence** -- `f817917` (feat)
3. **Task 3: the six-hour quota's `onTimeout`, proven on plain JVM** -- `557ee14` (test)
4. **CI-round-trip fix: stable-channel Dart formatting** -- `1c742f0` (style)

## Files Created/Modified

- `android/src/main/kotlin/com/danjjohnson/compress_video/ForegroundServiceHost.kt` -- the service, its notification, its ref-counted `Ref` bookkeeping, and `onTimeout`.
- `android/src/test/kotlin/com/danjjohnson/compress_video/ForegroundServiceHostTest.kt` -- 5 plain-JVM cases covering ref-counting and `onTimeout`.
- `tool/verify_apk_foreground_service_manifest.sh` -- deterministic `aapt2`-based merged-manifest assertion, wired into CI.
- `pigeons/messages.dart` / `lib/src/messages.g.dart` / `android/.../Messages.g.kt` / `darwin/.../Messages.g.swift` -- `AndroidForegroundServiceOptionsMessage` and the new request field, regenerated.
- `lib/src/compress_options.dart` -- `AndroidForegroundServiceOptions`, `CompressOptions.androidForegroundService`, validation.
- `lib/compress_video.dart` -- `_buildRequestMessage` populates the new wire field.
- `lib/src/compress_video_exception.dart` -- `interrupted`'s dartdoc now names both engines.
- `android/src/main/AndroidManifest.xml` -- the two permissions and the non-exported service.
- `android/.../Arguments.kt` / `ArgumentsTest.kt` -- `validateAndroidForegroundService`, wired into `requireValidCompressRequest`, 5 new cases.
- `android/.../Compression.kt` -- attach before the engine call, detach in a `finally` around it.
- `android/.../JobRegistry.kt` -- `cancel`'s new `reason` parameter.
- `android/.../TransformerEngine.kt` -- `ExportOutcome.Cancelled` carries the reason through to the thrown error.
- `example/android/app/src/main/kotlin/.../MainActivity.kt` -- the example-only `moveTaskToBack`/`apiLevel` channel.
- `example/integration_test/jobs_background_test.dart` -- the foreground-service case and the backgrounding/API-level case.
- `test/compress_options_test.dart` -- 4 new `androidForegroundService` validation cases.
- `.github/workflows/ci.yml` -- the `dumpsys` poll gate and the merged-manifest backstop step.

## Decisions Made

See `key-decisions` above (frontmatter) for the four load-bearing calls: pulling `JobRegistry.cancel`'s reason parameter forward into Task 1's commit for compile-order reasons; no AndroidX Core dependency; the framework-free `Ref` class as what makes `onTimeout` unit-testable at all; and how assumption A1 was verified by observing this app's permanent notification-permission-denied state rather than by toggling a permission the app never requests.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `onStartCommand` called `startForeground` before creating the notification channel**
- **Found during:** Task 1, first live emulator run
- **Issue:** The service crashed the whole app process with `CannotPostForegroundServiceNotificationException: Bad notification for startForeground` -- `startForeground` referenced a notification channel (`compress_video_media_processing`) that had never been created, because `ensureNotificationChannel()` was defined but never called from `onStartCommand`.
- **Fix:** `onStartCommand` now calls `ensureNotificationChannel()` before building the notification.
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/ForegroundServiceHost.kt`
- **Verification:** Re-ran `example/integration_test/jobs_background_test.dart` on the emulator; the foreground-service case passed and the app no longer crashed.
- **Committed in:** `edc1f92`

**2. [Rule 3 - Blocking] Two of Task 1's own acceptance-criteria greps initially failed because a doc comment contained the literal forbidden strings**
- **Found during:** Task 1, acceptance-criteria verification pass
- **Issue:** `grep -cE 'NotificationCompat|androidx\.core' ForegroundServiceHost.kt` returned 1 (a doc comment explaining that NO AndroidX Core dependency is used contained the literal string `androidx.core`); a similar doc-comment self-reference in the new unit test made `grep -c 'Robolectric' ForegroundServiceHostTest.kt` return 1 instead of the required 0.
- **Fix:** Reworded both comments to describe the absence without using the literal forbidden string.
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/ForegroundServiceHost.kt`, `android/src/test/kotlin/com/danjjohnson/compress_video/ForegroundServiceHostTest.kt`
- **Verification:** Both greps re-run, now 0.
- **Committed in:** `edc1f92`, `557ee14`

**3. [Rule 3 - Blocking] The plugin manifest's own XML comments broke the manifest merge**
- **Found during:** Task 1, first Gradle build after the manifest edit
- **Issue:** `./gradlew :compress_video:testDebugUnitTest` failed with `ManifestMerger2$MergeFailureException` -- two of the new comments contained a literal `--` inside the comment body, which is invalid XML (comments may not contain `--` except at the delimiters).
- **Fix:** Reworded both comments to avoid an embedded `--`.
- **Files modified:** `android/src/main/AndroidManifest.xml`
- **Verification:** The Gradle build succeeded afterward.
- **Committed in:** `edc1f92`

**4. [Rule 3 - Blocking] `dart format`'s stable-channel output differed from this box's default SDK, caught by CI's own format-check step**
- **Found during:** the first pushed CI attempt (run 36321395548), after all local verification had passed with the box's default (newer) Flutter SDK
- **Issue:** CI's `dart format --output=none --set-exit-if-changed .` (running the `stable` channel) reported `example/integration_test/jobs_background_test.dart` as needing reformatting -- the stable channel's formatter collapses a `group()`/`testWidgets()` call differently than the box's default SDK's newer "tall style" does. Locally I had run the stable-channel formatter over `lib` and `test` per this lane's own convention, but missed `example/`, which the repo-root `dart format .` check also covers.
- **Fix:** Ran `PATH=$HOME/development/flutter-stable/bin:$PATH dart format .` over the whole repo; only the one file changed, purely whitespace/layout, no logic change.
- **Files modified:** `example/integration_test/jobs_background_test.dart`
- **Verification:** `dart format --output=none --set-exit-if-changed .` now exits 0 with the stable SDK; the emulator re-run behaved identically; CI attempt 2 (run 36321581676) passed the format check.
- **Committed in:** `1c742f0`

---

**Total deviations:** 4 auto-fixed (2 Rule 1 bugs, 2 Rule 3 blockers). **Impact:** All four were necessary corrections found via genuine live verification (a real emulator crash, real acceptance-criteria grep failures, a real manifest-merge failure, and a real CI formatting mismatch) -- none were scope creep, and none required an architectural decision.

## Issues Encountered

- The first pushed CI attempt (run 36321395548) failed the Android job's format-check step for the reason described in Deviation 4 above; fixed and re-pushed as attempt 2 (run 36321581676), which passed the Android job in full, including both new CI gates (the live `dumpsys` poll and the merged-manifest backstop). This is attempt 2 of the plan's own 3-pushed-attempt budget.
- The Apple job in CI run 36321581676 was still running when this summary was first drafted; it has since finished. **Final result: CI run 36321581676 is fully green on all four jobs** -- Android, Detect Apple-relevant changes, Apple, and Cross-platform parity all `success`. The Apple job runs because `lib/`/`.github/workflows/ci.yml` were touched by the path-gate, not because this plan changed anything under `darwin/`; its own steps were unmodified by this plan's `.github/workflows/ci.yml` edit (which only touched steps inside the `android` job), so this green result confirms no regression, though it is not itself a gate for this plan's Android-only scope.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- **JOBS-05's Android half is proven** with live, in-flight evidence (dumpsys, both locally and in CI) and no known gaps beyond a real sub-API-35 device/image, which is a hardware-checklist item like the rest of this project's device-dependent gaps, never an executor precondition.
- **REQUIREMENTS.md's JOBS-05 row intentionally stays `Pending`** per this plan's own scope boundary -- it closes only once 05-04 lands the Apple (`beginBackgroundTask`/suspension) half. JOBS-04's own closure likewise belongs to 05-05, not this plan.
- `05-04` (iOS suspension) and `05-05` (phase sign-off) can proceed; no blocker from this plan. `JobRegistry.cancel`'s new reason parameter is reusable as-is by 05-04's Apple-side interruption mapping if a similar pattern is wanted there.
- Two pushed CI attempts used of the plan's 3-attempt budget; the Android job (this plan's own gate) is fully green on attempt 2. One attempt remains in budget, unused.

---
*Phase: 05-jobs-isolates-and-background*
*Completed: 2026-09-27*

## Self-Check: PASSED

- All created files found on disk: `android/src/main/kotlin/com/danjjohnson/compress_video/ForegroundServiceHost.kt`, `android/src/test/kotlin/com/danjjohnson/compress_video/ForegroundServiceHostTest.kt`, `tool/verify_apk_foreground_service_manifest.sh`.
- `git log --oneline` shows `edc1f92`, `f817917`, `557ee14`, `1c742f0` in order on `main`, all pushed to both `origin` and `github`.
- Plan-level verification re-run: `flutter analyze --fatal-infos --fatal-warnings` clean, `flutter test` 96/96, `./gradlew :compress_video:testDebugUnitTest` 188 passed / 0 failed, `dart format --output=none --set-exit-if-changed .` (stable SDK) clean, `dart pub publish --dry-run` 0 warnings, full `example/integration_test` directory green (0 exit) on the local emulator across two full runs.
- CI run 36321581676: **all four jobs `success`** (Android, Detect Apple-relevant changes, Apple, Cross-platform parity), confirmed via `gh run view --json jobs` after the run completed. Android includes the new `dumpsys` poll gate (`dumpsys confirmed ForegroundServiceHost running with the mediaProcessing type during the suite`) and the new merged-manifest backstop (`Merged manifest carries both foreground-service permissions and the typed service declaration.`).
