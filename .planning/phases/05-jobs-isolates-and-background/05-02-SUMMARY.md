---
phase: 05-jobs-isolates-and-background
plan: 02
subsystem: api
tags: [dart, isolates, background-isolate, compress-video, flutter-engine-limitation]

# Dependency graph
requires:
  - phase: 05-jobs-isolates-and-background
    provides: "05-01's per-instance FIFO queue and CompressJob contract, unchanged by this plan"
provides:
  - "CompressVideo.ensureInitializedInBackgroundIsolate(RootIsolateToken), the one new public member this plan's discretion section authorized"
  - "_ensureFlutterApiRegistered resilience: compress() no longer crashes synchronously off-root"
  - "Empirically confirmed, documented boundary of what works from a background isolate today (getMediaInfo/getThumbnail/estimate/clearCache: yes; compress(): no, confirmed Flutter engine limitation)"
affects: [05-03-android-foreground-service, 05-04-ios-suspension, 05-05-phase-signoff]

# Actuals (#2632)
actuals:
  tokens: 14300
  tasks: 1
  commits: 1

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Catch-and-continue for a hard SDK boundary: _ensureFlutterApiRegistered treats BackgroundIsolateBinaryMessenger.setMessageHandler's UnsupportedError as an expected, permanent condition off-root (not an error to propagate), letting the rest of a call proceed rather than crashing synchronously."

key-files:
  created:
    - example/integration_test/jobs_background_test.dart
  modified:
    - lib/compress_video.dart
    - lib/src/compress_job.dart

key-decisions:
  - "Did not build a SendPort/ReceivePort bridge to route progress or the compress() reply across the isolate boundary, even though that would 'fix' the symptom -- explicitly prohibited by this plan's own threat model and 05-RESEARCH.md's Don't-Hand-Roll table, and exactly the anti-pattern BackgroundIsolateBinaryMessenger exists to replace."
  - "Rewrote the suite to prove what is empirically true (getMediaInfo et al. work off-root) rather than write a compress()-based test that cannot pass, or a permissive one that would pass without checking anything -- a skip: true case documents the hang instead of hiding it."
  - "Halted the plan after Task 1 rather than proceeding to Task 2 (CI wiring) and Task 3 (README claims), both of which are premised on compress() working off-root -- wiring an incomplete/misleading suite into CI or documenting a false capability would misrepresent JOBS-04 (see threat model T-05-09, repudiation)."
  - "Filed QUESTIONS.md #9 and sent a notify-dan push: this changes a customer-facing capability claim (how much of the incumbent's issue #242 this closes), which is a decision for the project owner, not something to resolve unilaterally by quietly softening the plan's own success criteria."

requirements-completed: []

coverage:
  - id: D1
    description: "CompressVideo.ensureInitializedInBackgroundIsolate added as documented, one-line wrapper over BackgroundIsolateBinaryMessenger.ensureInitialized"
    requirement: JOBS-04
    verification:
      - kind: unit
        ref: "flutter analyze --fatal-infos --fatal-warnings (clean); grep -c ensureInitializedInBackgroundIsolate lib/compress_video.dart >= 1"
        status: pass
    human_judgment: false
  - id: D2
    description: "_ensureFlutterApiRegistered no longer crashes compress() synchronously off-root (catches the confirmed-permanent UnsupportedError from BackgroundIsolateBinaryMessenger.setMessageHandler)"
    requirement: JOBS-04
    verification:
      - kind: integration
        ref: "example/integration_test/jobs_background_test.dart#getMediaInfo returns correctly from inside Isolate.run"
        status: pass
    human_judgment: false
  - id: D3
    description: "A background-isolate-started compression completes and returns a typed CompressResult, with progress delivered to that isolate's own job"
    requirement: JOBS-04
    verification: []
    human_judgment: true
    rationale: "NOT achieved. Empirically confirmed during this plan's execution: compress()'s own startCompress call never resolves when issued from a background isolate (native completes per logcat; the Dart await hangs). This is a genuine Flutter engine limitation (see Deviations), not something this plan closes. Requires a project-owner decision (QUESTIONS.md #9) on how to scope JOBS-04 before further work proceeds."
  - id: D4
    description: "The suite is wired into tool/run_ios_integration_suites.sh and both Apple CI steps"
    requirement: JOBS-04
    verification: []
    human_judgment: true
    rationale: "NOT done. Task 2 (CI wiring) was not executed because it is premised on a working compress()-from-background-isolate proof, which D3 shows does not exist. Wiring an incomplete/misleading suite into a 90-150-minute-per-push CI budget was judged worse than pausing for a scope decision."
  - id: D5
    description: "README documents the background-isolate recipe"
    requirement: JOBS-04
    verification: []
    human_judgment: true
    rationale: "NOT done (Task 3 not executed) -- premised on the same D3 gap. Writing README claims about compress() working off-root would be false."

duration: 75min
completed: 2026-09-27
status: halted
---

# Phase 5 Plan 2: Background-isolate initialiser -- what actually works, and what a Flutter engine limit blocks Summary

**`CompressVideo.ensureInitializedInBackgroundIsolate` ships and makes `getMediaInfo`/`getThumbnail`/`estimate`/`clearCache` genuinely usable from inside `Isolate.run`, but `compress()` itself is empirically confirmed to hang off-root due to a Flutter engine limitation this plan's own no-bridge prohibition cannot route around -- halted pending a scope decision (QUESTIONS.md #9).**

## Performance

- **Duration:** ~75 min (includes extensive empirical diagnosis: SDK source reading, `adb logcat` correlation, three isolated reproduction probes)
- **Tasks:** 1 of 3 completed (in a revised form); Tasks 2 and 3 not executed
- **Commits:** 1 (`87d1a28`)
- **Files modified:** 3 (1 created)

## Accomplishments

- `CompressVideo.ensureInitializedInBackgroundIsolate(RootIsolateToken)` shipped exactly as
  the plan specified: a one-line wrapper over `BackgroundIsolateBinaryMessenger.ensureInitialized`,
  with a dartdoc recipe. This is the plan's only intended new public surface, and it's real —
  no channel, no isolate ownership, no token storage.
- `lib/src/compress_job.dart`'s `_ensureFlutterApiRegistered` now catches the confirmed-permanent
  `UnsupportedError` `BackgroundIsolateBinaryMessenger.setMessageHandler` throws off-root, instead
  of letting it crash `compress()` synchronously before the call even starts. Without this fix,
  `compress()` failed immediately and untyped on every background isolate, regardless of whether
  `ensureInitializedInBackgroundIsolate` had been called.
- `example/integration_test/jobs_background_test.dart` proves, on the Android emulator, that
  `getMediaInfo` (and by the identical outgoing-call mechanism, `getThumbnail`/`estimate`/
  `clearCache`) genuinely work from inside `Isolate.run` once initialised — real progress
  towards JOBS-04 and the incumbent's issue #242.
- The suite also carries a `skip: true` case that documents, rather than hides, the confirmed
  `compress()` hang, with a header explaining exactly what was found and why it can't be routed
  around without violating this plan's own prohibitions.
- Filed `QUESTIONS.md #9` (a decision only the project owner can make: how to scope JOBS-04
  given the confirmed engine limitation) and sent a `notify-dan` push, since this changes a
  customer-facing capability claim.

## Task Commits

1. **Task 1 (revised): initialiser + resilience fix + honest test suite** — `87d1a28` (feat)

Task 2 (Apple/CI wiring) and Task 3 (README recipe) were not started — both are premised on
`compress()` working from a background isolate, which Task 1's own empirical findings disprove.

## Files Created/Modified

- `lib/compress_video.dart` — `ensureInitializedInBackgroundIsolate`, dartdoc recipe.
- `lib/src/compress_job.dart` — `_ensureFlutterApiRegistered` now catches `UnsupportedError` from
  a background isolate's failed FlutterApi registration attempt instead of propagating it.
- `example/integration_test/jobs_background_test.dart` — new. One passing group proving
  `getMediaInfo` works off-root; one `skip: true` group documenting the confirmed `compress()`
  hang with a detailed header.

## Decisions Made

- Did not build a `SendPort`/`ReceivePort` bridge to work around the confirmed engine limitation,
  even though it would technically "fix" the symptom — this plan's own threat model (T-05-08) and
  05-RESEARCH.md's "Don't Hand-Roll" table explicitly prohibit exactly this pattern, for good
  reason (it's the anti-pattern `BackgroundIsolateBinaryMessenger` exists to replace).
- Rewrote the test suite around what's empirically true rather than either (a) shipping a test
  that can't pass, or (b) softening assertions until something passes without proving anything —
  chose (c): prove the real, working half, and mark the broken half `skip: true` with a full
  written explanation, so CI stays green without hiding the gap.
- Halted after Task 1 instead of proceeding to Task 2/3, which are both premised on the broken
  half working. Wiring an incomplete suite into a 90–150-minute Apple CI budget, or writing README
  claims that `compress()` works off-root, would both misrepresent JOBS-04's actual state.
- Filed `QUESTIONS.md #9` and sent `notify-dan` rather than unilaterally deciding how to scope
  JOBS-04 — this is a customer-facing capability claim (how much of incumbent issue #242 this
  closes) that the project owner should ratify, not something an autonomous run should quietly
  redefine.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `compress()` crashed synchronously on any background isolate, even before calling `ensureInitializedInBackgroundIsolate`'s target purpose**
- **Found during:** Task 1, first emulator run of the planned `Isolate.run` compression case
- **Issue:** `_ensureFlutterApiRegistered(binaryMessenger)` unconditionally calls
  `messages.CompressVideoFlutterApi.setUp(impl, binaryMessenger: binaryMessenger)`, which
  internally calls `BasicMessageChannel.setMessageHandler` — and
  `BackgroundIsolateBinaryMessenger.setMessageHandler` throws `UnsupportedError`
  unconditionally ("Messages from the host platform always go to the root isolate"), confirmed
  by reading the Flutter SDK source (`_background_isolate_binary_messenger_io.dart`). This meant
  `compress()` threw synchronously and untyped from ANY background isolate call, regardless of
  whether the caller remembered `ensureInitializedInBackgroundIsolate`.
- **Fix:** Wrapped the `setUp` call in a `try`/`on UnsupportedError` that continues (marking the
  messenger as "attempted" in the registry) rather than propagating. `compress()`'s actual
  platform call — an outgoing, `send()`-based request/reply that DOES work off-root — can then
  proceed. The job started this way never receives progress events (a separate, structural
  finding — see below), but no longer crashes before it even starts.
- **Files modified:** `lib/src/compress_job.dart`
- **Verification:** `flutter analyze --fatal-infos --fatal-warnings` clean; confirmed via a
  throwaway diagnostic probe (`getMediaInfo`/`estimate` from `Isolate.run`) that the catch fires
  and the isolate proceeds normally for calls that don't hang for the separate reason below.
- **Committed in:** `87d1a28`

### Escalated — Rule 4 (architectural), resolved by scope reduction rather than a bridge

**2. `compress()` never resolves when issued from a background isolate — confirmed Flutter engine limitation, not fixable in-package**
- **Found during:** Task 1, after fix #1 above, running the plan's own `Isolate.run` compression
  case on the Android emulator: the test hung and timed out (`TimeoutException after 2 minutes`)
  even with a correct `ensureInitializedInBackgroundIsolate` call.
- **Diagnosis (empirical, not assumed):**
  1. Isolated the hang to `compress()` specifically by writing three throwaway probes on the same
     emulator: `getMediaInfo` from `Isolate.run` succeeded instantly; `estimate` (same
     `CompressHostApi` class, same outgoing-call mechanism, no `_ensureFlutterApiRegistered`
     dependency) also succeeded instantly; `compress` hung every time.
  2. Added temporary debug `print`s inside `lib/src/compress_job.dart`'s `_run` (removed before
     committing) and confirmed via `adb logcat` that `startCompress` is called but never returns
     — no exception thrown, genuinely never resolves.
  3. Cross-checked against `adb logcat`: native's `TransformerInternal: Init` is followed by
     `Release` ~200-300ms later, consistent with the corpus's cheapest clip (`small_480p.mp4`)
     genuinely completing a real compression natively. The native side is not the problem — the
     Dart-side reply-delivery mechanism is.
  4. This matches the shape of `flutter/flutter#144342`, already cited (lower-confidence) in
     05-RESEARCH.md's Pitfall 2: a null-check exception during a platform message response
     callback, caught internally by `BackgroundIsolateBinaryMessenger`'s own receive-port
     listener and reported via `FlutterError.reportError` rather than surfaced to the pending
     completer — leaving that completer, and therefore the awaiting `Future`, unresolved forever.
     Pitfall 2's original text framed this as a risk specific to the OMITTED-initialisation case;
     the empirical finding here is that it also reproduces on the plain, correctly-initialised
     happy path, which is a materially worse outcome than "MEDIUM confidence, untested" implied.
- **Why not fixed:** the only mechanism available to relay a result or progress across the
  isolate boundary in this situation is a hand-rolled `SendPort`/`ReceivePort` bridge — exactly
  what this plan's own threat model (T-05-08) and 05-RESEARCH.md's "Don't Hand-Roll" table
  explicitly rule out, and for good reason (it's precisely the anti-pattern
  `BackgroundIsolateBinaryMessenger` exists to replace). Building one to route around a
  confirmed engine limitation would be exactly the mistake the prohibition exists to prevent.
- **Resolution applied:** rewrote the suite to assert what's empirically true rather than what
  the plan assumed. Task 2 (CI wiring for both Apple steps) and Task 3 (README recipe) were not
  executed, since both depend on the compress()-off-root proof this finding disproves.
  `QUESTIONS.md #9` filed with three options for the project owner (ship the partial capability
  as-is and document the limit; file an upstream Flutter bug and wait; or ask for further
  in-package investigation in case this analysis is wrong). `notify-dan` push sent.
- **Files modified:** `example/integration_test/jobs_background_test.dart` (rewritten around the
  confirmed boundary); `lib/src/compress_job.dart` (fix #1, which is necessary but not
  sufficient — it stops the crash but does not stop the hang).
- **Verification:** `example/integration_test/jobs_background_test.dart` passes on the emulator
  (`+1 ~1`: one test passed, one skipped) — `flutter test integration_test/jobs_background_test.dart -d emulator-5554`.
- **Committed in:** `87d1a28`

---

**Total deviations:** 1 auto-fixed (Rule 1 bug), 1 escalated (Rule 4 architectural, resolved by
documented scope reduction rather than a prohibited bridge).
**Impact on plan:** The auto-fix is a genuine, unconditional improvement (compress() no longer
crashes off-root). The escalation means JOBS-04 is NOT closed by this plan as originally scoped —
see QUESTIONS.md #9 for the pending decision. Tasks 2 and 3 are deferred, not abandoned: once the
project owner decides how JOBS-04 should be scoped, they (or a corrected 05-02 continuation) can
proceed with CI wiring and README documentation matching whatever is actually true.

## Issues Encountered

The core issue IS the escalated deviation above — no additional unrelated issues.

## User Setup Required

None — no external service configuration required. This is a decision, not a setup task; see
QUESTIONS.md #9.

## Next Phase Readiness

- **Blocked:** JOBS-04 is not closed. `05-03`/`05-04`/`05-05` (Android foreground service, iOS
  suspension, phase sign-off) should be checked against QUESTIONS.md #9 before executing, in
  case any of them assume `compress()` works from a background isolate (for example, a
  foreground-service worker isolate pattern).
- What IS solid and reusable regardless of the JOBS-04 decision: `ensureInitializedInBackgroundIsolate`
  itself, the `_ensureFlutterApiRegistered` resilience fix, and the empirically-confirmed fact
  that every non-`compress()` call in this package already works correctly from a background
  isolate once initialised.
- Recommend reading `QUESTIONS.md #9` and this SUMMARY's Deviations section in full before
  deciding how to continue Phase 5.

---
*Phase: 05-jobs-isolates-and-background*
*Completed: 2026-09-27*

## Self-Check: PASSED

- `lib/compress_video.dart`, `lib/src/compress_job.dart`,
  `example/integration_test/jobs_background_test.dart` all found on disk.
- Commit `87d1a28` present in git log (`git log --oneline -1` at HEAD).
- Plan-level verification re-run: `flutter analyze --fatal-infos --fatal-warnings` clean (root
  package); `flutter test` 92/92 (root package); `flutter test integration_test/jobs_background_test.dart -d emulator-5554`
  green with 1 pass + 1 documented skip.
- `grep -crE 'ReceivePort|SendPort' lib/` shows exactly one hit, in a dartdoc comment in
  `lib/src/compress_job.dart` explaining why a bridge was NOT built (the plan's prohibition
  verification greps compiled/executable code, not prose; no `ReceivePort`/`SendPort` construct
  appears anywhere in this package's actual code).
