---
phase: 03-apple-compression-to-parity
plan: 06
subsystem: media-compression
tags: [swift, avfoundation, avassetreader, avassetwriter, jobregistry, errormapping, ci]

# Dependency graph
requires:
  - phase: 03-apple-compression-to-parity
    provides: "03-04's tracer engine (CompressionEngine.swift/Compression.swift/JobRegistry.swift) and 03-05's transmux/never-larger/audio-mode branches, both proven on the iOS simulator"
provides:
  - "Per-job progress derivation and per-sample cancellation with ordered partial-file deletion, both proven on Apple for the first time via the real compress_jobs_test.dart suite (they were built into 03-04's tracer commit b2e01b7 but never run there -- this plan is what actually exercises them)"
  - "CompressionEngine.resolvePlan(inputURL:inputInfo:request:) exposed (mirrors Android's TransformerEngine.resolvePlan) plus Compression.requireSufficientFreeSpace, the free-space pre-check with its non-APFS volumeAvailableCapacityKey fallback (D-10)"
  - "ErrorMapping.swift's AVError table widened to 13 entries (adds -11880 'Invalid sample cursor' -> unsupportedInput, matched by raw value) and CompressionEngine's AVError failure message reformatted to always carry a bare 'code N' phrase, closing a real gap where a recognised-but-newly-added reason's numeric code was unobservable from Dart"
  - "compress_jobs_test.dart's whole-file Android-only guard removed -- all 9 cases (progress ordering/range/terminal-100, two-job isolation, 4 cancel cases, 4 failure-typing cases) now run on Android, the iOS simulator and (natively, via XCTest only) macOS"
affects: [03-07, 03-08]

# Actuals (#2632)
actuals:
  tokens: 33000
  tasks: 3
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A raw-value-matched AVError.Code (ErrorMapping.invalidSampleCursor = AVError.Code(rawValue: -11880)!) checked with an `if code == ...` guard ahead of the main switch, rather than a `case .someGuessedName:` inside it -- Swift parses a bare lowercase identifier in a switch-case position as a NEW catch-all BINDING whenever it does not name a real declared case of the switched type, so a guessed AVFoundation case name that happens not to exist would silently swallow every code instead of failing to compile. Matching by the raw integer this SDK's own AVError.Code(rawValue:) already accepted (proven live by the failure reaching this function with a non-nil code at all) sidesteps the naming risk entirely."
    - "CompressVideoException.platformDetail (Dart) is reserved for an UNRECOGNISED platform reason NAME the installed package version doesn't know about yet (test/media_info_mapping_test.dart's own contract), not a general-purpose slot for a numeric platform error code -- the numeric code must always be folded into the message text instead, in a literal `code <positive digits>` phrase (no sign) so it survives compress_jobs_test.dart's `\\bcode \\d+\\b` observability check. A bare negative AVFoundation code formatted as `error -11880` does NOT satisfy that regex; `(code 11880)` does."
    - "CompressionEngine.resolvePlan(inputURL:inputInfo:request:) reads the input's own audio codec via the existing readAudioCodec(at:) helper (now non-private) before delegating to the original private resolvePlan(inputInfo:request:audioCodec:) -- mirrors Android's TransformerEngine.resolvePlan exactly, so Compression's pre-flight free-space check and the real compress() call can never resolve two different SizeGuard.Plan values for the same request."

key-files:
  created: []
  modified:
    - darwin/compress_video/Sources/compress_video/CompressionEngine.swift
    - darwin/compress_video/Sources/compress_video/Compression.swift
    - darwin/compress_video/Sources/compress_video/ErrorMapping.swift
    - example/ios/RunnerTests/RunnerTests.swift
    - example/macos/RunnerTests/RunnerTests.swift
    - example/integration_test/compress_jobs_test.dart
    - tool/run_ios_integration_suites.sh
    - .github/workflows/ci.yml

key-decisions:
  - "Tasks 1 and 2 (progress derivation, per-sample cancel with ordered deletion) were already implemented in 03-04's tracer commit (b2e01b7) -- the reader/writer copy loop needed correct semantics to exist as a tracer at all. This plan's own new work for those tasks was documentation (an explicit comment on the 99-clamp site) and, critically, actually RUNNING compress_jobs_test.dart on Apple for the first time via the whole-file guard removal -- proof, not re-implementation."
  - "The free-space pre-check (task 3) is wired via a NEW resolvePlan(inputURL:inputInfo:request:) overload on CompressionEngine rather than duplicating SizeGuard resolution logic inside Compression.swift, mirroring Android's own resolvePlan/requireSufficientFreeSpace split exactly so the pre-flight prediction and the real job can never disagree."
  - "Attempt 1 (commit 75b39e8, CI run 36151081384) surfaced a real gap: AVFoundation error -11880 ('Invalid sample cursor') reading the genuinely damaged truncated_mdat.mp4 fixture fell through ErrorMapping's default branch to reason 'unknown', and Dart's CompressVideoException.platformDetail is Dart-side reserved for an UNRECOGNISED reason NAME, not a numeric code -- so neither of the test's two accepted 'codeIsObservable' paths were satisfied. Fixed in attempt 2 (commit e3962b0) by mapping -11880 to 'unsupportedInput' (matched by raw value, not a guessed case name -- 03-RESEARCH.md Pitfall 6) and reformatting the AVError failure message to always carry a bare 'code N' phrase. This is a genuine, cross-platform-relevant bug fix (Rule 1), not scope creep: any future AVError code this table doesn't yet recognise would trip the exact same Dart-side gap."
  - "The Android job's compress_test.dart load failure in attempt 1 ('Failed to start Dart Development Service', 'adb: device offline') was a transient emulator/adb infrastructure flake unrelated to any file this plan touched -- confirmed by attempt 2's fully green Android run (79/79 tests) on identical Android-side code. Not investigated further; documented per the deviation-rules scope boundary (out-of-scope pre-existing flake, not a regression)."

requirements-completed: []  # CORE-01 stays unmarked here: also declared by 03-01/03-02/03-04/03-05/03-07/03-08/03-09 in this phase, several of which (03-07, 03-08, 03-09) have not executed yet, and 03-01's own Mac build proof is still deferred. This plan's OWN scope (per-job progress/cancel/errors, free-space pre-check) is fully proven on the iOS simulator and on Android; full cross-platform CORE-01 proof is a phase-close concern, not this plan's alone.

coverage:
  - id: D1
    description: "Per-job progress is derived from the writer loop's own appended-sample presentation time, clamped 0..99, throttled to at most one onProgress call every 250ms, with a single explicit 100 sent before the result reply on every successful path (real encode, transmux, never-larger)"
    requirement: CORE-01
    verification:
      - kind: integration
        ref: "CI run 36157289074, job Apple, step 'Run corpus integration tests on the iOS simulator': compress_jobs_test.dart 'a single job's progress values are all within 0-100, monotonically non-decreasing, and end with exactly one 100, closing before or as the result completes' -- passing (part of '00:34 +10: All tests passed!', all 10 cases)"
        status: pass
      - kind: integration
        ref: "Same run, same suite: 'two jobs started together each reach 100, complete independently, and produce two different, both-existing files, with no event from one job appearing on the other's stream' -- passing"
        status: pass
      - kind: integration
        ref: "CI run 36157289074, job Android, step 'Run emulator integration tests': the same two cases, both passing (part of '79 tests passed')"
        status: pass
    human_judgment: false
  - id: D2
    description: "Cancel sets a per-sample flag the copy loop (or export session) checks, deletes the partial file, marks the job terminal and removes it from the registry -- strictly before the job's result future resolves -- and is idempotent: a second cancel, a cancel after successful completion, and cancelling one of three concurrently-running jobs are all safe, isolated no-ops or partial no-ops"
    requirement: CORE-01
    verification:
      - kind: integration
        ref: "CI run 36157289074, job Apple: compress_jobs_test.dart's 4 Cancel-group cases ('cancelling mid-flight...', 'a second cancel()...', 'a cancel issued after successful completion...', 'cancelling one of three jobs...') all passing on the iOS simulator"
        status: pass
      - kind: integration
        ref: "CI run 36157289074, job Android: the same 4 cases passing on the real emulator"
        status: pass
      - kind: unit
        ref: "CI run 36157289074, job Apple, steps 'XCTest - iOS Runner' and 'XCTest - macOS Runner': JobRegistry's existing register/cancel-once/second-cancel-noop/terminal-noop cases (03-04) still pass on both Apple platforms, unaffected by this plan's changes"
        status: pass
    human_judgment: true
    rationale: "The plan's own acceptance criteria also name a macOS-HOST Dart-level run (bash tool/mac_run.sh macos integration_test/compress_jobs_test.dart --plain-name 'cancelling mid-flight'), which is unreachable this session: the Mac is offline (QUESTIONS.md #8) and CI's apple job has no macOS-host Flutter integration_test step at all (a pre-existing gap already carried forward from 03-04/03-05, not introduced here). The cancellation MECHANISM is proven cross-platform (Android + iOS simulator, both real devices/emulators) and the shared Swift code path is exercised on the macOS host via native XCTest, but the macOS-host Dart-level case specifically has never executed. Flagged for human/future-plan judgment rather than a false auto-pass."
  - id: D3
    description: "Every AVFoundation/NSError failure path resolves through ErrorMapping to a typed CompressVideoErrorReason with the platform's numeric code observable from Dart (via a 'code N' phrase in the message, or platformDetail for an unrecognised reason name), deletes the partial file and removes the job from the registry before replying, and never logs"
    requirement: CORE-01
    verification:
      - kind: integration
        ref: "CI run 36157289074, job Apple: all 4 Real-failures cases pass -- damaged truncated_mdat.mp4 (reason=unsupportedInput, message='AVFoundation error -11880 (code 11880): Invalid sample cursor'), nonexistent path (reason=fileNotFound), zero-byte file (reason=unsupportedInput), plain-text-renamed-.mp4 (typed CompressVideoException, non-cancelled) -- all leave no partial file"
        status: pass
      - kind: integration
        ref: "CI run 36157289074, job Android: the same 4 cases pass; the damaged-file fixture observes reason=io, platformDetail=null, message='Media3 export failed with code 2000: Asset loader error' -- a DIFFERENT reason bucket (io vs unsupportedInput) than Apple for the identical fixture, recorded per the plan's own instruction as a real cross-platform difference for 03-08's parity gate to arbitrate, not corrected to match"
        status: pass
      - kind: other
        ref: "grep -rh --include=*.swift -v '^[[:space:]]*//' darwin/compress_video/Sources/compress_video/ | grep -cE 'print\\(|NSLog\\(|os_log' == 0"
        status: pass
    human_judgment: false
  - id: D4
    description: "A pre-flight free-space check (1.2x SizeGuard's predicted output bytes vs the destination volume's available capacity) runs before any reader, writer or export session is built, with a fallback to the general volumeAvailableCapacityKey when the APFS-only volumeAvailableCapacityForImportantUsageKey reports zero for a directory that exists and is writable"
    requirement: CORE-01
    verification:
      - kind: other
        ref: "grep -c requireSufficientFreeSpace darwin/.../Compression.swift == 3; grep -c volumeAvailableCapacityForImportantUsageKey == 2; grep -c volumeAvailableCapacityKey == 2 (proving the non-APFS fallback exists)"
        status: pass
      - kind: integration
        ref: "CI run 36157289074: the check runs ahead of every startCompress call on both the iOS simulator and the real Android CI runner's ample free disk, introducing no regression across all 5 iOS-simulator suites (media_info 9/9, thumbnail 16/16, compress 22/22, compress_audio 7/7, compress_jobs 10/10) and the Android job's 79/79"
        status: pass
    human_judgment: true
    rationale: "No CI runner or fixture can genuinely exhaust destination free space (same limitation Android's own equivalent check carries, 02-06-SUMMARY.md's pending todo) or force volumeAvailableCapacityForImportantUsageKey to report zero on a real non-APFS volume -- the fallback's OWN trigger condition (Pitfall 5) has no automated proof, only the grep-verified presence of both keys and no observed regression. Consistent with 02-06's own accepted limitation for the Android equivalent."

duration: ~2h (dominated by CI wall-clock: 2 pushed attempts, ~50 min and ~70 min respectively)
completed: 2026-09-25
status: complete
---

# Phase 3 Plan 6: Per-Job Progress, Cancellation and the Typed Failure Surface Summary

**Ran compress_jobs_test.dart on Apple for the first time (progress/cancel logic built in 03-04's tracer, never exercised until now), wired the free-space pre-check via a new `CompressionEngine.resolvePlan` overload, and fixed a real Dart-observability gap where an AVFoundation error code this project's mapping table didn't yet recognise (-11880, "Invalid sample cursor") became unobservable from Dart entirely.**

## Performance

- **Duration:** ~2h, almost entirely CI wall-clock (2 pushed attempts)
- **Completed:** 2026-09-25
- **Tasks:** 3 (consolidated into 2 commits: the main implementation, then a targeted fix for what attempt 1's CI run surfaced)
- **Files modified:** 8

## Accomplishments

- Confirmed (rather than re-implemented) that `CompressionEngine.swift`'s copy loop already derives per-job progress correctly: clamped 0..99 from the last appended video sample's PTS over the trim-aware output duration, throttled to at most one call every 250ms (`progressThrottleSeconds = 0.25`), with a single explicit `onProgress(100.0)` sent before the result reply on every successful path (real encode, transmux, never-larger pre-check). Added an explicit comment at the clamp site naming why it never derives 100 itself.
- Confirmed the per-sample cancel flag (`CancelState`, checked once per `requestMediaDataWhenReady` iteration on both the video and audio inputs), the ordering (`quietDelete` before `JobRegistry.remove` before the job's result future resolves), and `JobRegistry.cancel`'s three-way idempotency guard (`!job.cancelled, !job.terminal`) were already correct from 03-04 -- this plan is what actually RUNS `compress_jobs_test.dart` against them for the first time on Apple.
- Added `CompressionEngine.resolvePlan(inputURL:inputInfo:request:)` (exposed, not `private`; mirrors Android's `TransformerEngine.resolvePlan`) and made `readAudioCodec(at:)` non-private so it can back the new overload.
- Added `Compression.requireSufficientFreeSpace` (1.2x safety margin, mirrors Android's `FREE_SPACE_SAFETY_FACTOR` exactly) and `Compression.availableCapacityBytes(forDirectory:)` with the non-APFS `volumeAvailableCapacityKey` fallback (03-RESEARCH.md Pitfall 5), wired into `startCompress` immediately after destination resolution and before `engine.compress` is ever called.
- Removed `compress_jobs_test.dart`'s whole-file `if (!Platform.isAndroid) { ...; return; }` guard. All 9 test cases now run on Android, the iOS simulator, and (the shared Swift core, via native XCTest) macOS.
- Widened `tool/run_ios_integration_suites.sh`'s default suite list and `.github/workflows/ci.yml`'s comment to include `compress_jobs_test.dart`.
- **Fixed a real bug surfaced by attempt 1's CI run:** `ErrorMapping.knownAVErrorCodes` widened to 13 entries, adding AVFoundation error -11880 ("Invalid sample cursor", matched by raw value rather than a guessed case name) mapped to `unsupportedInput`; `CompressionEngine.mapToCompressVideoError`'s AVError failure message reformatted to always include a literal `code N` (positive, no sign) phrase alongside the signed raw value, so a recognised reason's numeric code stays observable from Dart via `compress_jobs_test.dart`'s message-regex check even when `CompressVideoException.platformDetail` (reserved for an *unrecognised reason name*, not a numeric code) is `null`. Both `RunnerTests.swift` copies updated in lockstep (kept byte-identical) with a matching unit test.

## Task Commits

1. **Tasks 1-3 (consolidated): free-space pre-check, progress-clamp documentation, guard removal, CI suite widening** — `75b39e8`
2. **Fix: map AVError -11880 instead of falling through to unknown; fix the message-observability gap** — `e3962b0`

**Plan metadata:** this commit (docs)

## Files Created/Modified

- `darwin/compress_video/Sources/compress_video/CompressionEngine.swift` — clamp-site comment, `resolvePlan(inputURL:inputInfo:request:)` overload, non-private `readAudioCodec`, AVError message reformat
- `darwin/compress_video/Sources/compress_video/Compression.swift` — `requireSufficientFreeSpace`, `availableCapacityBytes(forDirectory:)`
- `darwin/compress_video/Sources/compress_video/ErrorMapping.swift` — `invalidSampleCursor` (-11880) mapped to `unsupportedInput`
- `example/ios/RunnerTests/RunnerTests.swift`, `example/macos/RunnerTests/RunnerTests.swift` — `AVFoundation` import, count bumped to 13, matching new test case (byte-identical)
- `example/integration_test/compress_jobs_test.dart` — whole-file Android-only guard removed
- `tool/run_ios_integration_suites.sh` — `compress_jobs_test.dart` added to the default suite list
- `.github/workflows/ci.yml` — step comment updated to name the newly-included suite

## Decisions Made

See `key-decisions` in frontmatter for the full accounting. In short: tasks 1-2's logic already existed (03-04); this plan's real contribution there was proof (running the suite) plus documentation. Task 3's free-space check mirrors Android's split exactly. Attempt 1's CI failure was a genuine, in-scope bug (an unrecognised AVError code becoming unobservable from Dart) fixed via Rule 1, not scope creep — any future unrecognised code would trip the identical gap.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] AVFoundation error -11880 ("Invalid sample cursor") fell through to reason "unknown", and its numeric code was unobservable from Dart**
- **Found during:** CI run 36151081384 (attempt 1), job Apple, `compress_jobs_test.dart`'s damaged-file case
- **Issue:** `ErrorMapping.reasonForAVError` had no case for AVFoundation's -11880 ("Invalid sample cursor" — a real, previously-unobserved code reading `truncated_mdat.mp4`'s truncated `mdat` box), so it fell through to `"unknown"`. `CompressVideoException.platformDetail` is Dart-side reserved for an UNRECOGNISED PLATFORM REASON NAME (see `test/media_info_mapping_test.dart`'s own contract), not a general numeric-code carrier — so it was populated with the literal string `"unknown"` (no digits), and the AVError failure message ("AVFoundation error -11880: Invalid sample cursor") contained no `code \d+` phrase either (the `-` between "error" and the digits, and the absence of the word "code" at all, meant neither of `compress_jobs_test.dart`'s two accepted `codeIsObservable` paths matched).
- **Fix:** Mapped -11880 to `"unsupportedInput"` (matched by raw value via `AVError.Code(rawValue: -11880)!`, not a guessed case name — 03-RESEARCH.md Pitfall 6 explicitly warns against plausible-sounding names that don't exist) and reformatted the AVError branch's message to `"AVFoundation error \(nsError.code) (code \(abs(nsError.code))): ..."`, guaranteeing a literal, sign-free `code N` phrase for every AVError-mapped failure, recognised or not.
- **Files modified:** `ErrorMapping.swift`, `CompressionEngine.swift`, both `RunnerTests.swift` copies
- **Verification:** CI run 36157289074, job Apple: `compress_jobs_test.dart` — "Observed failure for truncated_mdat.mp4: reason=CompressVideoErrorReason.unsupportedInput, platformDetail=null, message=AVFoundation error -11880 (code 11880): Invalid sample cursor" — case passes. Both `RunnerTests.swift` copies' new `testReasonForAVErrorInvalidSampleCursorMapsToUnsupportedInput` pass on the iOS simulator AND the macOS host.
- **Committed in:** `e3962b0`

### Scope Clarifications (not bugs)

**2. [Scope boundary, not a bug] Android's damaged-file fixture maps to a different reason bucket than Apple's**
- **Found during:** CI run 36157289074, comparing the Android and Apple jobs' printed observations for the same `truncated_mdat.mp4` fixture
- **What was seen:** Android: `reason=io, platformDetail=null, message=Media3 export failed with code 2000: Asset loader error` (Media3's `ExportException.ERROR_CODE_IO_UNSPECIFIED`). Apple: `reason=unsupportedInput, platformDetail=null, message=AVFoundation error -11880 (code 11880): Invalid sample cursor`.
- **Why this is not a bug:** The plan's own task 3 text is explicit: "Where an observed reason differs from the Android one for the same fixture, do not change the test to match: record it as a real cross-platform difference for the parity gate to arbitrate in 03-08." Both platforms genuinely disagree about WHICH failure category a truncated `mdat` box falls into (an I/O read failure on Android's demuxer vs. an invalid-sample-cursor decode-time error on AVFoundation's reader) — reconciling that classification (if it should be reconciled at all) is 03-08's parity-gate job, not this plan's.
- **Action taken:** None — recorded here and left for 03-08.

**3. [Infrastructure, not a bug] Android's `compress_test.dart` failed to load on attempt 1 with an unrelated adb/DDS flake**
- **Found during:** CI run 36151081384 (attempt 1), job Android
- **What was seen:** `Failed to load "compress_test.dart": Failed to start Dart Development Service`, immediately followed by `adb uninstall failed: ... adb: device offline`. `compress_test.dart` was not touched by this plan at all; every other Android suite (including the fully-rewritten `compress_jobs_test.dart`, 9/9) passed in the same run.
- **Action taken:** None — attempt 2 (commit `e3962b0`, pushed to fix the Apple issue above) re-ran the same Android suite on identical Android-side code and it passed cleanly (79/79 tests), confirming the flake was transient and unrelated to this plan's changes.

---

**Total deviations:** 1 auto-fixed bug (a real, cross-platform-relevant error-observability gap), 1 documented cross-platform difference (deferred to 03-08 by the plan's own instruction), 1 unrelated infrastructure flake (self-resolved on the next push). **Impact on plan:** The bug fix was necessary for `compress_jobs_test.dart`'s own stated correctness gate and generalizes beyond this one fixture (any future unrecognised AVError code would have hit the identical Dart-side observability gap); no scope creep beyond what CI evidence required.

## Issues Encountered

**CI attempt budget:** 2 of the 3 allowed attempts were used. Attempt 1 (`75b39e8`, CI run 36151081384) surfaced the -11880 mapping gap on Apple (a genuine bug) and an unrelated Android adb/DDS flake (self-resolving). Attempt 2 (`e3962b0`, CI run 36157289074) was fully green on every job (Android 79/79, Apple all 5 iOS-simulator suites + both native XCTest runners, Cross-platform parity).

**Known, pre-existing gap carried forward (not introduced by this plan):** CI's `apple` job has no macOS-HOST Flutter `integration_test` step at all — only native XCTest runs on macOS. This plan's task 2/3 acceptance criteria that name `bash tool/mac_run.sh macos integration_test/compress_jobs_test.dart --plain-name '...'` could not be run: the Mac is offline (`ssh -o ConnectTimeout=8 dans-macbook-air true` timed out at session start, QUESTIONS.md #8) and no CI substitute exists for the macOS-host Dart level specifically. This is the SAME gap 03-04-SUMMARY.md and 03-05-SUMMARY.md already documented and carried forward — not new, not a regression, and (per that established precedent) not a blocker for marking this plan `status: complete`. The shared Swift engine code IS exercised on the macOS host via native XCTest (both `RunnerTests.swift` copies, including the new -11880 case, pass there), so the underlying mechanism has some macOS-side proof; only the Dart-level `CompressJob` API surface on macOS specifically remains unverified.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **This plan's own scope (per-job progress, cancellation, the wired typed-failure surface, the free-space pre-check) is fully proven on Android and the iOS simulator**, and the shared Swift code is proven on the macOS host via native XCTest. `compress_jobs_test.dart` now runs unconditionally on all three platform CI paths that exist.
- **CORE-01 stays unmarked** in this plan's `requirements-completed` — see the frontmatter comment. 03-07/03-08/03-09 and 03-01's deferred Mac build proof all still need to land before the requirement can honestly close.
- **The Android-vs-Apple reason-bucket difference for `truncated_mdat.mp4`** (`io`/code 2000 vs `unsupportedInput`/code -11880) is recorded above for 03-08's parity gate to arbitrate — do not "fix" one platform to match the other without deciding, in 03-08, which classification is actually correct (or whether both are acceptable and the parity gate should just document the difference).
- **The macOS-host Dart-level `integration_test` gap** (no CI step; Mac still offline) remains open, exactly as 03-04/03-05 left it. Whoever next has a reachable Mac should run `bash tool/mac_sync.sh && bash tool/mac_run.sh macos integration_test/compress_jobs_test.dart` and `... compress_test.dart` to close it, or 03-08 (which explicitly owns widening the CI `apple` job) should add the missing step.
- **03-07 can proceed** with trim exactness, the shared-resolver `estimate()` (which can now reuse `CompressionEngine.resolvePlan(inputURL:inputInfo:request:)` directly, since this plan already added it for the free-space check), output placement and `clearCache()` — nothing in 03-07's declared scope depends on the open macOS-Dart-level gap above.

## Self-Check: PASSED

- `darwin/compress_video/Sources/compress_video/Compression.swift` — FOUND (`requireSufficientFreeSpace`, `availableCapacityBytes` present)
- `darwin/compress_video/Sources/compress_video/CompressionEngine.swift` — FOUND (`resolvePlan(inputURL:inputInfo:request:)`, clamp comment, reformatted AVError message present)
- `darwin/compress_video/Sources/compress_video/ErrorMapping.swift` — FOUND (`invalidSampleCursor`, 13-entry `knownAVErrorCodes`)
- `example/ios/RunnerTests/RunnerTests.swift` / `example/macos/RunnerTests/RunnerTests.swift` — FOUND, byte-identical (`diff` confirmed)
- `example/integration_test/compress_jobs_test.dart` — FOUND, whole-file guard removed, 0 remaining `Platform.isAndroid` references
- Commit `75b39e8` — FOUND in `git log --oneline`
- Commit `e3962b0` — FOUND in `git log --oneline`
- CI run 36157289074 — FOUND, conclusion `success` on all 4 jobs (`gh run view`)

---
*Phase: 03-apple-compression-to-parity*
*Completed: 2026-09-25*
