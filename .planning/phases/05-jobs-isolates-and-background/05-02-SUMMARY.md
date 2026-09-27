---
phase: 05-jobs-isolates-and-background
plan: 02
subsystem: api
tags: [dart, isolates, background-isolate, compress-video, kotlin, swift]

# Dependency graph
requires:
  - phase: 05-jobs-isolates-and-background
    provides: "05-01's per-instance FIFO queue and CompressJob contract, unchanged by this plan"
provides:
  - "CompressVideo.ensureInitializedInBackgroundIsolate(RootIsolateToken), the one new public Dart member"
  - "CompressHostApi.awaitCompressResult(jobId), a new Pigeon async method backing compress()-from-background-isolate on both platforms"
  - "JOBS-04 proven end-to-end on Android (emulator, multiple stable runs); Apple implementation written, CI-pending"
affects: [05-03-android-foreground-service, 05-04-ios-suspension, 05-05-phase-signoff]

# Actuals (#2632)
actuals:
  tokens: 42000
  tasks: 3
  commits: 4

tech-stack:
  added: []
  patterns:
    - "Pre-registered CompletableDeferred/continuation, keyed by job id, completed the instant an outcome is known and read by a SEPARATE async host call (awaitCompressResult) -- decouples a result from a reply path that a background isolate cannot use, without a SendPort/ReceivePort bridge."
    - "Bounded native acknowledgement wait (withTimeoutOrNull) instead of fire-and-forget: preserves an existing ordering guarantee for the common (root-isolate) case while still bounding the uncommon (background-isolate, unacknowledgeable) case."

key-files:
  created: []
  modified:
    - pigeons/messages.dart
    - lib/src/messages.g.dart
    - lib/compress_video.dart
    - lib/src/compress_job.dart
    - android/src/main/kotlin/com/danjjohnson/compress_video/Messages.g.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt
    - darwin/compress_video/Sources/compress_video/Messages.g.swift
    - darwin/compress_video/Sources/compress_video/JobRegistry.swift
    - darwin/compress_video/Sources/compress_video/Compression.swift
    - example/integration_test/jobs_background_test.dart
    - tool/run_ios_integration_suites.sh
    - .github/workflows/ci.yml
    - README.md
    - CHANGELOG.md

key-decisions:
  - "Diagnosed the ACTUAL root cause (empirically, via adb logcat + reading the Flutter engine source and generated Pigeon code) rather than accepting the plan's own halted-state theory at face value: Android's startCompress blocks on CompressVideoFlutterApi.onProgress's ack before returning, not a generic 'no isolate can register a handler' hang. This distinction is what made a bridge-free fix possible."
  - "Kept startCompress's own success-path onProgress(100.0) call DIRECT and AWAITED (not fire-and-forget), after empirically finding fire-and-forget broke 02-06's root-isolate progress-ordering guarantee. Used a bounded withTimeoutOrNull (3s) instead -- invisible to the fast root-isolate case, bounds the background-isolate case."
  - "CompressJob._run on a background isolate explicitly (bounded) waits for the abandoned startCompress reply to settle before returning, in addition to reading the real result from awaitCompressResult -- confirmed empirically that letting the isolate exit first crashes the whole process natively (engine-level did_send CHECK failure, not a catchable Dart exception)."
  - "Apple's fix mirrors the Pigeon-level contract only, not the Android bug: Compression.swift's onProgress was already fire-and-forget via an AsyncStream, so awaitCompressResult there is the documented symmetric escape hatch, not a crash fix. Verified only by reading the source -- Mac unreachable, CI's apple job is the real verifier."
  - "Did not add new native XCTest coverage for JobRegistry.swift's continuation-based result store (time-boxed decision) -- example/integration_test/jobs_background_test.dart on the macOS CI leg is the coverage for this plan; a future plan could add unit coverage if warranted."

requirements-completed: [JOBS-04]

coverage:
  - id: D1
    description: "CompressVideo.ensureInitializedInBackgroundIsolate ships and is the only new public Dart member"
    requirement: JOBS-04
    verification:
      - kind: unit
        ref: "flutter analyze --fatal-infos --fatal-warnings (clean)"
        status: pass
    human_judgment: false
  - id: D2
    description: "A compression started from Isolate.run completes and returns its typed, never-larger CompressResult on Android"
    requirement: JOBS-04
    verification:
      - kind: integration
        ref: "example/integration_test/jobs_background_test.dart#Isolate.run: a real compression completes entirely off the root isolate"
        status: pass
    human_judgment: false
  - id: D3
    description: "The omitted-initialisation case fails typed and bounded for both compress() and getMediaInfo(), never a hang"
    requirement: JOBS-04
    verification:
      - kind: integration
        ref: "example/integration_test/jobs_background_test.dart#the omitted-initialisation case fails typed, never hangs"
        status: pass
    human_judgment: false
  - id: D4
    description: "No regression to the existing per-job progress/result ordering guarantee on the root isolate"
    requirement: JOBS-04
    verification:
      - kind: integration
        ref: "example/integration_test/compress_jobs_test.dart (all 13 cases, including the progress-ordering and queue cases)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The suite is wired into tool/run_ios_integration_suites.sh and both Apple CI steps, budgets unchanged"
    requirement: JOBS-04
    verification:
      - kind: other
        ref: "grep -c jobs_background_test.dart tool/run_ios_integration_suites.sh (>=1) and .github/workflows/ci.yml (==2); tool/run_ios_integration_suites_test.sh all-pass"
        status: pass
    human_judgment: false
  - id: D6
    description: "Apple's implementation compiles and the suite passes on the iOS simulator and macOS host"
    requirement: JOBS-04
    verification: []
    human_judgment: true
    rationale: "Not locally verifiable -- the MacBook Air is unreachable this session (recurring QUESTIONS.md blocker) and Xcode/Swift cannot be compiled on danserver. Written by mirroring Android's public contract and reading Compression.swift's existing (already fire-and-forget) onProgress design; CI's apple job is the sanctioned verifier and is the pending step after this SUMMARY is committed."
  - id: D7
    description: "README documents the background-isolate recipe and the measured failure/limitation shape"
    requirement: JOBS-04
    verification:
      - kind: other
        ref: "grep -c ensureInitializedInBackgroundIsolate README.md (>=2), grep -c RootIsolateToken README.md (>=1)"
        status: pass
    human_judgment: false

duration: 165min
completed: 2026-09-27
status: complete
---

# Phase 5 Plan 2: Background-isolate compression, fixed end to end on Android, Apple pending CI Summary

**`CompressVideo.ensureInitializedInBackgroundIsolate` plus a new Pigeon `awaitCompressResult` escape hatch make `compress()` genuinely work from `Isolate.run` on Android (verified: real compression, typed omitted-init failure, no root-isolate regression, multiple stable emulator runs) — the earlier halt's root cause was Android's own `onProgress` acknowledgement blocking `startCompress`'s reply, not a structural dead end, and it was fixed without the SendPort/ReceivePort bridge the plan's own threat model prohibits.**

## Performance

- **Duration:** ~165 min across two sessions — the initial halt (Task 1, ~75 min, see git history for the superseded first cut of this SUMMARY) plus this orchestrator-directed fix-and-retry (~90 min): root-causing the native block, three failed intermediate designs (native fire-and-forget → root-isolate regression; unbounded Dart wait → 30s+ non-resolution; bounded-but-too-short wait → still crashed once), the working bounded-timeout design, then CI wiring and docs.
- **Tasks:** 3 (revised Task 1 fix, Task 2 CI wiring, Task 3 docs)
- **Commits:** 4 total across both sessions (`87d1a28` initial initialiser + resilience fix, `0c91246` first halt's docs, `2637b7d` the awaitCompressResult fix, `c54eda9` CI wiring + README/CHANGELOG)

## Accomplishments

- `CompressHostApi.awaitCompressResult(jobId)` — a new `@async` Pigeon method, regenerated cleanly (`dart run pigeon`, deterministic on a second run) into Dart, Kotlin and Swift. Resolves a job's terminal outcome from a per-job registry entry completed the instant it is known, independent of any Dart-side acknowledgement.
- **Root-caused the ACTUAL blocker** (not assumed): Android's `Compression.kt#startCompress` calls `engine.compress(...)`, which calls `onProgress(100.0)` — a direct `suspend` call to `CompressVideoFlutterApi.onProgress` — and AWAITS it before returning. A background isolate can never send that acknowledgement (`BackgroundIsolateBinaryMessenger.setMessageHandler` throws unconditionally off-root), so `startCompress`'s own coroutine, and therefore its reply, was genuinely stuck — confirmed via `adb logcat` (native's Media3 Transformer completing in ~220ms while the Dart-side await sat for 30+ seconds unresolved) and by reading the generated `Messages.g.kt`.
- **Fixed with `JobRegistry.completeResult`** (Android) / a continuation-based store (Apple `JobRegistry.swift`): the result is recorded BEFORE the blocking/fire-and-forget progress push, so `awaitCompressResult` never depends on it.
- **Found and fixed a real regression along the way**: making the terminal `onProgress(100.0)` fire-and-forget (the first attempted fix) broke `compress_jobs_test.dart`'s root-isolate progress-ordering guarantee (`Expected: <100.0> Actual: <99.0>`). Reverted to a direct awaited call, now bounded by `PROGRESS_ACK_TIMEOUT_MS` (3s) via `withTimeoutOrNull` — invisible to the root isolate (real acks arrive in well under a second), bounding the background-isolate case instead.
- **Found and fixed a genuine native process crash**: abandoning `startCompress`'s own reply Future entirely (fire-and-forget from Dart) and letting the spawning isolate exit crashed the WHOLE process — `[FATAL:flutter/lib/ui/window/platform_message_response_dart_port.cc] Check failed: did_send.` — an uncatchable engine-level `CHECK`, not a JVM/Dart exception. Fixed by having `CompressJob._run` explicitly wait (bounded, 15s, comfortably longer than native's 3s bound) for that abandoned reply to settle before returning, with its error attached-and-observed immediately so it is never separately reported as an unhandled Future error either.
- **Hardened the omitted-initialisation path further**: `_ensureFlutterApiRegistered` now also catches `StateError` (from `BackgroundIsolateBinaryMessenger.instance` itself when `ensureInitializedInBackgroundIsolate` was never called at all) — previously only `UnsupportedError` (the initialised-but-restricted case) was caught, so the never-initialised case crashed synchronously and untyped. Every future-returning public call (`getMediaInfo`/`getThumbnail`/`getThumbnailFile`/`estimate`/`clearCache`) gained the matching `WR-03`-style last-resort catch `CompressJob._run` already carried.
- `example/integration_test/jobs_background_test.dart` rewritten: the `compress()`-from-`Isolate.run` case is un-skipped and proves a real, never-larger, typed result; the omitted-initialisation case now covers both `compress()` and `getMediaInfo()`. All three cases pass on **multiple consecutive clean emulator runs**. The full pre-existing suite (`compress_jobs_test.dart`'s 13 cases, `compress_test.dart`'s 32, `compress_audio_test.dart`'s 7, `thumbnail_test.dart`'s 16, `compress_output_test.dart`'s 17, `hard_inputs_test.dart`'s 16, `media_info_test.dart`'s 9) re-verified green — **no regressions**.
- Wired into `tool/run_ios_integration_suites.sh`'s default list and the lighter of each Apple CI step pair (no `timeout-minutes` changed, both split steps intact, `tool/run_ios_integration_suites_test.sh` still passes). README gained a "Calling from a background isolate" section; CHANGELOG records the addition and its closure of `video_compress` issue #242.

## Task Commits

1. **Task 1 (first session, halted): initialiser + resilience fix + honest partial test suite** — `87d1a28` (feat)
2. **Task 1 (first session) close-out docs** — `0c91246` (docs)
3. **Task 1 (this session, resumed): `awaitCompressResult` fix, both platforms, un-skipped test** — `2637b7d` (feat)
4. **Tasks 2+3 (this session): CI wiring, README, CHANGELOG** — `c54eda9` (docs)

## Files Created/Modified

- `pigeons/messages.dart` / `lib/src/messages.g.dart` / `android/.../Messages.g.kt` / `darwin/.../Messages.g.swift` — new `awaitCompressResult` method, regenerated deterministically.
- `android/.../JobRegistry.kt` — `resultDeferredFor`/`completeResult`/`forgetResult`, a `CompletableDeferred<Result<CompressResultMessage>>` per job.
- `android/.../Compression.kt` — `startCompress` pre-registers the deferred and wraps its body in an outer catch-all; new `awaitCompressResult` override.
- `android/.../TransformerEngine.kt` — both success branches record the result via `JobRegistry.completeResult` BEFORE the (now bounded, `PROGRESS_ACK_TIMEOUT_MS`) `onProgress(100.0)` call.
- `darwin/.../JobRegistry.swift` — `@MainActor`-isolated `completeResult`/`awaitResult` via `CheckedContinuation`.
- `darwin/.../Compression.swift` — `startCompress` wrapped in do/catch calling `JobRegistry.completeResult`; new `awaitCompressResult`; `requireSufficientFreeSpace` made `static` to support the refactor.
- `lib/compress_video.dart` — `_wrapUnexpected` helper, wired into every future-returning public call.
- `lib/src/compress_job.dart` — `_ensureFlutterApiRegistered` catches `StateError` too; `_run` branches on `RootIsolateToken.instance == null` to use `awaitCompressResult` off-root, with the bounded abandoned-reply wait.
- `example/integration_test/jobs_background_test.dart` — rewritten, 3 passing cases, no skips.
- `tool/run_ios_integration_suites.sh`, `.github/workflows/ci.yml`, `README.md`, `CHANGELOG.md` — wiring and docs.

## Decisions Made

See `key-decisions` above (frontmatter) for the four load-bearing calls: root-causing empirically rather than accepting the halted-state theory; keeping the root-isolate `onProgress` path awaited-and-bounded rather than fire-and-forget; explicitly waiting for the abandoned `startCompress` reply on a background isolate rather than abandoning it; and mirroring only Apple's public contract, not a bug it doesn't have.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `_ensureFlutterApiRegistered` did not catch `StateError`, only `UnsupportedError`**
- **Found during:** re-running the omitted-initialisation case after the `awaitCompressResult` fix landed
- **Issue:** A background isolate that never calls `ensureInitializedInBackgroundIsolate` at all hits `BackgroundIsolateBinaryMessenger.instance`'s own `StateError` guard before ever reaching `setMessageHandler`'s `UnsupportedError` — this exception was uncaught, crashing `compress()` synchronously and untyped.
- **Fix:** Added `on StateError` alongside the existing `on UnsupportedError` catch.
- **Files modified:** `lib/src/compress_job.dart`
- **Verification:** `example/integration_test/jobs_background_test.dart`'s omitted-init case passes for both `compress()` and `getMediaInfo()`.
- **Committed in:** `2637b7d`

**2. [Rule 1 - Bug] Fire-and-forget `onProgress(100.0)` broke root-isolate progress ordering**
- **Found during:** running the full `example/integration_test` suite after the first fire-and-forget attempt
- **Issue:** `compress_jobs_test.dart`'s progress-ordering assertions failed (`Expected: <100.0> Actual: <99.0>`) — the terminal progress event could now arrive at Dart AFTER `job.result` had already resolved.
- **Fix:** Reverted to a direct, awaited `onProgress(100.0)` call, now wrapped in `withTimeoutOrNull(PROGRESS_ACK_TIMEOUT_MS)` (3s) so a background isolate's unacknowledgeable call still bounds, without changing the fast root-isolate path's behaviour at all.
- **Files modified:** `android/.../TransformerEngine.kt`
- **Verification:** Full `example/integration_test` suite re-run green, including all 13 `compress_jobs_test.dart` cases.
- **Committed in:** `2637b7d`

**3. [Rule 1 - Bug] Abandoning `startCompress`'s reply crashed the whole process natively**
- **Found during:** running `jobs_background_test.dart` after the `awaitCompressResult` fix, before the bounded-wait fix
- **Issue:** `CompressJob._run` fired `startCompress` without awaiting it, got the real result via `awaitCompressResult`, and returned — tearing the spawning isolate down while native's own delayed `startCompress` reply was still in flight. Native's attempt to deliver that reply to the now-dead isolate hit `[FATAL:flutter/lib/ui/window/platform_message_response_dart_port.cc] Check failed: did_send.`, an uncatchable engine-level abort (`SIGABRT`).
- **Fix:** `_run` now also explicitly (bounded, 15s) awaits the abandoned `startCompressFuture` before returning, with an immediate `.then(_, onError:)` attached first so its error is never separately reported as unhandled either.
- **Files modified:** `lib/src/compress_job.dart`
- **Verification:** `jobs_background_test.dart` passed on three consecutive clean emulator runs after this fix (zero crashes), versus reproducing on every attempt before it.
- **Committed in:** `2637b7d`

---

**Total deviations:** 3 auto-fixed (all Rule 1 bugs, all found and fixed via genuine empirical diagnosis — logcat, native stack traces, and re-running the full existing suite after each candidate fix).
**Impact on plan:** All three were necessary for correctness; none were scope creep. The second and third deviations in particular reflect the kind of finding this plan's own "verify empirically" methodology exists to catch — a plausible-looking fix (fire-and-forget; abandon the Future) that looked correct in isolation but broke a different, previously-passing guarantee or crashed the process, caught only by re-running the FULL existing suite after each change rather than just the new one.

## Issues Encountered

- The local Android emulator crashed/died twice during this session under sustained rapid app install/uninstall/crash cycling (a documented recurring danserver resource-pressure pattern, not a code issue) — rebooted both times with the standard recipe (`sg kvm -c '...emulator...'`, poll `sys.boot_completed`). The final full-suite verification pass completed cleanly before the second death; subsequent doc-only changes (README/CHANGELOG/CI YAML) did not require re-verification.
- Two test-infrastructure findings, fixed in the test file itself (not the plugin): `Directory.systemTemp` can resolve to a different-but-equivalent Android path alias (`/data/user/0/...` vs `/data/data/...`, a well-known per-user bind-mount) than what native reports back — fixed by asserting file existence at both aliases rather than string equality.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **JOBS-04 is proven on Android** (real device-class evidence: emulator, multiple stable runs, no regressions to the existing 05-01/02-06 guarantees). **Apple's implementation is written but CI-pending** — this SUMMARY intentionally does NOT close JOBS-04 in `REQUIREMENTS.md` yet; that happens once the pushed CI run's `apple` job confirms `jobs_background_test.dart` green on both the iOS simulator and the macOS host (or a documented follow-up if it is not, per the plan's own 3-pushed-attempt budget — this is attempt 1).
- `05-03`/`05-04`/`05-05` (Android foreground service, iOS suspension, phase sign-off) can proceed once CI confirms — no known blocker beyond that confirmation.
- QUESTIONS.md #9 is superseded by this fix (the JOBS-04 scope question no longer applies — the capability now exists in full) and has been updated to record that.

---
*Phase: 05-jobs-isolates-and-background*
*Completed: 2026-09-27*

## Self-Check: PASSED

- All modified files found on disk; `git log --oneline -4` shows `c54eda9`, `2637b7d`, `0c91246`, `87d1a28` in order.
- Plan-level verification re-run: `flutter analyze --fatal-infos --fatal-warnings` clean, `flutter test` 92/92, `dart format --set-exit-if-changed` clean (stable SDK), `dart pub publish --dry-run` (1 warning, uncommitted-changes notice only, expected pre-commit).
- Full `example/integration_test` directory re-run green on the Android emulator across multiple sessions (media_info 9/9, compress 32/32, compress_audio 7/7, compress_jobs 13/13, thumbnail 16/16, compress_output 17/17, hard_inputs 16/16, jobs_background 3/3) with zero regressions and zero crashes on the final clean pass.
- `grep -cE 'ReceivePort|SendPort' android/src/main/kotlin/com/danjjohnson/compress_video/` and the Dart/Swift equivalents show no bridge construct anywhere in the package's own sources (only continuation/deferred-based synchronization, which is not a channel bridge).
- Apple's Swift changes are NOT locally compiled (Mac unreachable) — CI's `apple` job is the pending, authoritative verification for that half; this is disclosed above (coverage D6) rather than assumed passing.
