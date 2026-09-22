---
phase: 03-apple-compression-to-parity
plan: 04
subsystem: media-compression
tags: [swift, avfoundation, avassetreader, avassetwriter, sizeguard, jobregistry, ci]

# Dependency graph
requires:
  - phase: 03-apple-compression-to-parity
    provides: "03-02's SizeGuard.swift/ErrorMapping.swift/PluginFiles.swift ports; 03-01/03-02's Messages.g.swift/Probe.swift/Arguments.swift Swift surface"
provides:
  - "CompressionEngine.swift: a real AVAssetReader/AVAssetWriter copy loop, compiled and building cleanly on a real Xcode toolchain via CI (run 35765529347's iOS build + XCTest steps both green) -- NOT YET proven end-to-end on a real encode this session (see Deviations)"
  - "Compression.swift: CompressHostApi conformance (startCompress, cancel); estimate()/clearCache() intentionally throw until 03-07"
  - "JobRegistry.swift: main-queue-confined registry, 8 new XCTest cases proven green on the iOS simulator via CI"
  - "CompressVideoPlugin.swift: CompressHostApi registered; the two teardown paths (iOS detachFromEngine, macOS handleWillTerminate) exist by name -- NOT exercised by any test this session"
  - "Arguments.requireValidCompressRequest, ported from Arguments.kt"
affects: [03-05, 03-06, 03-07]

# Actuals (#2632)
actuals:
  tokens: 15200
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "AVAssetReader/AVAssetWriter copy loop driven entirely on a job-scoped serial DispatchQueue via requestMediaDataWhenReady, bridged into async/await with withCheckedThrowingContinuation and a single settle()/maybeFinish()/failAndCancel() state machine confined to that one queue -- no lock needed for the loop's own state, only for the cross-queue CancelState flag JobRegistry's cancel closure flips from the main queue"
    - "Coded/displayed dimension swap for 90/270-degree rotation lives at exactly one call site in CompressionEngine.compress, immediately after SizeGuard.resolve, with a comment recording why (SizeGuard speaks displayed, AVFoundation's reader/writer surfaces speak coded)"
    - "JobRegistry.swift mirrors JobRegistry.kt's shape but drops the Handler/progressRunnable polling apparatus entirely -- Apple's progress is derived inline from the copy loop's own appended-sample PTS, not polled, so there is nothing analogous to stopPolling to hold onto beyond markTerminal's race-window closing"

key-files:
  created:
    - darwin/compress_video/Sources/compress_video/CompressionEngine.swift
    - darwin/compress_video/Sources/compress_video/Compression.swift
    - darwin/compress_video/Sources/compress_video/JobRegistry.swift
  modified:
    - darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift
    - darwin/compress_video/Sources/compress_video/Arguments.swift
    - example/ios/RunnerTests/RunnerTests.swift
    - example/macos/RunnerTests/RunnerTests.swift
    - example/integration_test/compress_test.dart
    - .github/workflows/ci.yml

key-decisions:
  - "Consolidated all three tasks into one implementation commit (mirrors 03-02's precedent) since CompressionEngine.swift is the tight coupling point for all of them and each CI round-trip costs 20-45 minutes against an unreachable Mac"
  - "Transmux (AVAssetExportSession) and audio re-encode are explicitly out of this plan's scope, per the plan's own task-1 action text (\"only the real-encode branch\"); a wouldTransmux-eligible file falls through to a real encode instead of the (not-yet-built) fast path -- functionally correct, just not the fastest path Android already has"
  - "The plan's own <precondition> (tool/mac_sync.sh && tool/mac_run.sh xctest-ios) could not be evaluated literally -- neither script exists (03-01 task 1 still blocked, Mac still offline) -- per this session's explicit orchestrator override, GitHub Actions substituted as the verifier of record, bounded at 3 pushed CI attempts"

requirements-completed: []  # CORE-01 NOT marked complete -- see Next Phase Readiness. The plan declares CORE-01; it is not satisfied by unverified code.

coverage:
  - id: D1
    description: "CompressionEngine.swift/Compression.swift/JobRegistry.swift/CompressVideoPlugin.swift compile cleanly against a real Xcode toolchain (iOS simulator target, CocoaPods integration)"
    requirement: CORE-01
    verification:
      - kind: integration
        ref: "CI run 35765529347, job Apple, step 'Build iOS (CocoaPods)'"
        status: pass
    human_judgment: false
  - id: D2
    description: "The 8 new JobRegistry XCTest cases (register/find, cancel-once, second-cancel-noop, unknown-id-noop, terminal-noop, cancel-all-empties-registry, live-temp-paths) pass on the iOS simulator, and RunnerTests.swift stays byte-identical between iOS and macOS"
    requirement: null
    verification:
      - kind: unit
        ref: "CI run 35765529347, job Apple, step 'XCTest - iOS Runner'"
        status: pass
      - kind: other
        ref: "CI run 35765529347, job Apple, step 'Verify RunnerTests.swift is identical on iOS and macOS'"
        status: pass
    human_judgment: false
  - id: D3
    description: "A real Dart compress call produces a smaller, upright, re-encoded H.264+AAC MP4 on the iOS simulator (the tracer's own <verify>), and the SizeGuard-driven geometry/frame-rate-cap/never-upscale/target-size cases in compress_test.dart pass"
    requirement: CORE-01
    verification: []
    human_judgment: true
    rationale: "compress_test.dart never executed this session -- CI's iOS-simulator integration step ran media_info_test.dart FIRST in its suite list, which hung twice (900s alarm, once plus the one automatic retry) on a documented pre-existing flake unrelated to this plan's code (same failure signature the existing CI comment already recorded on 2026-09-15 and 2026-09-21), consuming the step's entire budget before compress_test.dart ever got its turn. Zero assertions in compress_test.dart were observed pass or fail. This is the plan's actual acceptance bar and it is UNPROVEN, not merely unlucky -- a human/next session must re-run CI (no code change anticipated) to observe it."
  - id: D4
    description: "Both teardown paths (iOS detachFromEngine, macOS handleWillTerminate) fire and cancel every live job"
    requirement: null
    verification: []
    human_judgment: true
    rationale: "The methods exist and are named correctly (grep-verified), and their shared cancelAll() path is exercised transitively by the JobRegistry XCTest cases, but no test invokes plugin detach/terminate directly this session."

duration: ~2h (dominated by CI wall-clock: 3 pushed attempts across ~90 minutes)
completed: 2026-09-22
status: halted
---

# Phase 3 Plan 04: Apple Compression Engine (tracer) Summary

**Real AVAssetReader/AVAssetWriter engine, JobRegistry and SizeGuard-driven geometry written and proven to COMPILE and pass its own new unit tests on a real Xcode toolchain via CI — but the plan's actual acceptance bar (a real compress call producing a real file on the simulator) was never executed this session, blocked by an unrelated, pre-existing CI simulator-hang flake that struck ahead of it in the suite queue.**

## Performance

- **Duration:** ~2h, almost entirely CI wall-clock across 3 pushed attempts (the bound this session's explicit instructions set)
- **Completed:** 2026-09-22 (halted, not complete — see below)
- **Tasks:** 3 (consolidated into 1 implementation commit + 2 fix commits)
- **Files modified:** 9 (3 created, 6 modified)

## Accomplishments

- `CompressionEngine.swift` (677 lines): one `AVAssetReader`/`AVAssetWriter` pipeline per job on a job-scoped serial `DispatchQueue`, never the `MainActor` Pigeon delivers `startCompress` on. Reader `outputSettings` request BGRA plus the CODED target size only when a resize is actually needed (no `AVMutableVideoComposition` anywhere — `grep -c VideoComposition` is 0 outside comments). `AVAssetWriterInput.transform` carries `preferredTransform`; the writer encodes at the CODED size with the plan's displayed target swapped back to coded orientation for a 90/270-degree source. Frame-rate cap is PTS-based decimation in the copy loop itself (the writer's `AVVideoExpectedSourceFrameRateKey` is a hint only). Every geometry/bitrate number comes from one `SizeGuard.resolve` call. `writer.canApply` gates the settings before any input is added. The never-larger pre- and post-checks are both unconditional. The result is built from a `Probe` re-probe of the finished file, never the writer's own settings.
- `Compression.swift`: `CompressHostApi` conformance (`startCompress`, `cancel`); `estimate()`/`clearCache()` intentionally throw a typed "not yet implemented" error, deferred to 03-07 per the plan's own task-1 scope note.
- `JobRegistry.swift`: main-queue-confined `jobId -> {cancel closure, tempFile}` registry holding no AVFoundation reference — 8 new XCTest cases (register/find, cancel-invokes-once, second-cancel-noop, unknown-id-noop, cancel-after-terminal-noop, cancel-all-empties-registry, live-temp-paths-set) added to both `RunnerTests.swift` copies (kept byte-identical) and **proven green on the iOS simulator via CI**.
- `CompressVideoPlugin.swift`: registers `CompressHostApi`; adds the two platform-divergent teardown paths (`detachFromEngine(for:)` on iOS, `handleWillTerminate(_:)` on macOS), both calling `JobRegistry.cancelAll()`, with a code comment recording that they are NOT equivalent events.
- `Arguments.requireValidCompressRequest`, ported field-for-field from `Arguments.kt`.
- `compress_test.dart`'s Android-only platform guard removed; the file is otherwise byte-for-byte unchanged (verified via `git diff --stat`, only the guard block and its comment touched).
- `.github/workflows/ci.yml`'s `apple` job now runs `compress_test.dart` in the iOS-simulator integration step (alarm raised 540s → 900s for its heavier real-encode groups); `compress_audio_test.dart`/`compress_jobs_test.dart`/`compress_output_test.dart` stay excluded, with a comment explaining why (03-05/03-07 own audio re-encode, cancel/progress edge cases, and estimate/clearCache).

## Task Commits

1. **Tasks 1-3 (consolidated): the engine, JobRegistry/teardown, and SizeGuard-driven geometry** — `b2e01b7`
2. **Fix: missing `path:` argument label on two `Probe.getMediaInfo` call sites** (found live by CI run 35761811458, the first of the 3 pushed attempts) — `e7a9eed` (this commit also introduced a second, incorrect "fix" to `AVError.Code` handling that itself needed reverting — see Deviations)
3. **Fix: revert the `AVError.Code` handling** to the original `if let` form after CI run 35764281991 (attempt 2) proved it was in fact failable, contradicting commit 2's own in-code claim — `a1748d2`

**Plan metadata:** this commit (docs)

## Files Created/Modified

- `darwin/compress_video/Sources/compress_video/CompressionEngine.swift` — the reader/writer copy loop
- `darwin/compress_video/Sources/compress_video/Compression.swift` — `CompressHostApi` conformance
- `darwin/compress_video/Sources/compress_video/JobRegistry.swift` — the job registry
- `darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift` — registration + teardown
- `darwin/compress_video/Sources/compress_video/Arguments.swift` — `requireValidCompressRequest`
- `example/ios/RunnerTests/RunnerTests.swift`, `example/macos/RunnerTests/RunnerTests.swift` — 8 new `JobRegistry` cases (byte-identical)
- `example/integration_test/compress_test.dart` — platform guard removed
- `.github/workflows/ci.yml` — `apple` job's iOS-simulator step now includes `compress_test.dart`

## Decisions Made

- Consolidated all three tasks into one implementation commit (mirrors 03-02's precedent) since `CompressionEngine.swift` is the coupling point for all of them and each CI round-trip against the (currently unreachable) Mac costs 20-45 minutes.
- Transmux and audio re-encode are out of this plan's scope exactly as its own task-1 action text specifies ("only the real-encode branch"); a file that would qualify for transmux on Android instead falls through to a real encode here — correct output, just not yet the fast path.
- The plan's `<precondition>` (`tool/mac_sync.sh && tool/mac_run.sh xctest-ios`) could not be evaluated literally since neither script exists (03-01 task 1 is still blocked, Mac still offline — QUESTIONS.md #8). Per this session's explicit orchestrator instructions, GitHub Actions was the verifier of record instead, bounded at 3 pushed attempts.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Missing `path:` argument label on `Probe.getMediaInfo` calls**
- **Found during:** CI run 35761811458 (pushed attempt 1 of 3)
- **Issue:** `Probe().getMediaInfo(standardizedPath)`/`Probe().getMediaInfo(destinationURL.path)` omitted the required `path:` external label, a genuine Swift compile error ("Missing argument label 'path:' in call") at two call sites (`Compression.swift:33`, `CompressionEngine.swift:382`).
- **Fix:** Added the `path:` label at both call sites.
- **Files modified:** `Compression.swift`, `CompressionEngine.swift`
- **Verification:** Neither error reappeared in the next CI attempt's diagnostics.
- **Committed in:** `e7a9eed`

**2. [Rule 1 - Bug, self-inflicted] Incorrect "fix" to `AVError.Code(rawValue:)` handling, then reverted**
- **Found during:** Same commit as deviation 1 (an over-correction made without re-verifying), then caught by CI run 35764281991 (pushed attempt 2 of 3)
- **Issue:** While fixing deviation 1, `mapToCompressVideoError`'s `if let code = AVError.Code(rawValue: nsError.code)` was rewritten to a plain (non-optional) `let code = AVError.Code(rawValue: nsError.code)` on the (wrong) theory that `AVError.Code`'s `rawValue:` initializer is non-failable because it is an `NS_ERROR_ENUM`-bridged type. CI's compiler disagreed: "Value of optional type 'AVError.Code?' must be unwrapped to a value of type 'AVError.Code'" at the exact rewritten line.
- **Fix:** Reverted to the original `if let` form (which drew no complaint in attempt 1's diagnostics, the strongest available evidence it was correct all along).
- **Files modified:** `CompressionEngine.swift`
- **Verification:** CI run 35765529347 (attempt 3) shows the `Build iOS (CocoaPods)` step green — no further diagnostic at this line or anywhere else in the module.
- **Committed in:** `a1748d2`

---

**Total deviations:** 2 auto-fixed (both Rule 1, both in the same small error-mapping/probe-call surface). **Impact on plan:** Both were necessary compile-correctness fixes with no scope creep; the second was a self-inflicted regression from the first fix, caught and reverted within the session's own attempt budget.

## Issues Encountered

**The plan's actual acceptance bar (a real Dart compress call producing a real, smaller, upright file on the iOS simulator) was never executed this session.** CI run 35765529347 (the 3rd and final pushed attempt this session's instructions bounded me to) shows:

- `Build iOS (CocoaPods)`: **success** — the entire new Swift surface (`CompressionEngine.swift`, `Compression.swift`, `JobRegistry.swift`, the `CompressVideoPlugin.swift` registration/teardown additions, `Arguments.requireValidCompressRequest`) compiles cleanly against a real Xcode toolchain.
- `XCTest - iOS Runner`: **success** — every existing XCTest case plus all 8 new `JobRegistry` cases pass on the iOS simulator.
- `Run corpus integration tests on the iOS simulator`: **failure** — `media_info_test.dart` (the FIRST suite in the list, completely unrelated to this plan — it is a Phase 1 suite this plan did not touch) hung for the full 900-second alarm bound, was retried once after a simulator reset (per the step's own documented, pre-existing recovery logic), and hung again for the full 900 seconds a second time. `compress_test.dart` — the suite this plan actually needed to prove — never got its turn; the step failed with exit code 142 (`SIGALRM`) before reaching it. This is the exact, previously-documented flake the step's own comment already named ("occasionally hangs at app launch with zero output on the hosted simulator (seen 2026-09-15 and 2026-09-21 on suites that pass on the very next run)") — not a regression this plan introduced.

**No code fix is indicated by this failure.** The next session should re-run CI (or re-run just the iOS-simulator integration step) with no code changes; if `media_info_test.dart` boots cleanly, `compress_test.dart` should get its turn and this plan's actual verification can proceed. If a second re-run also hangs on the same suite, that graduates from "known flake" to "worth its own investigation" — but that has not happened yet.

**A second, independent failure in the same CI run: the `Android` job also failed** (`compress_test.dart`'s `p1080` case timed out after 20s — `TimeoutException after 0:00:20.000000`, cascading into a `SemanticsHandle` leak assertion on the very next test in the same run). This plan touched no Android/Kotlin code and no Android CI configuration; `TransformerEngine.kt`/`SizeGuard.kt` are unmodified. The corroborating evidence in the same job's log (`Unable to connect to adb daemon on port: 5037` during emulator startup) points to the same class of hosted-runner emulator flakiness this project's own `STATE.md` has recorded before, not a regression. Out of this plan's scope to fix (Rule scope boundary — this plan touches no Android code); recorded here and in `STATE.md`/`QUESTIONS.md` for whoever next runs CI against Android to be aware a rerun may simply pass.

**The `Cross-platform parity` job was skipped** — an expected consequence of both the `Android` and `Apple` jobs it depends on failing to produce parity artifacts this run, not an independent failure.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **CORE-01 is NOT marked complete.** The plan's own success criteria require the tracer's `<verify>` to actually pass on the simulator; it has not run. `requirements-completed` above is deliberately empty.
- **What IS proven, durably, for the next session to build on:** the entire Apple compression engine compiles against a real Xcode toolchain, and its own new unit-testable surface (`JobRegistry`) is fully green. This is strong positive signal that the plan's actual work is very likely correct — what remains is observing it run, not writing more code.
- **Immediate next step:** re-run CI on this same commit (`a1748d2`) with no code changes anticipated. If `compress_test.dart` gets its turn this time, read its output against this plan's task 1/2/3 acceptance criteria (which named-passing/failing cases) and either close this plan out with a fresh `SUMMARY.md` update or open a real, narrower bug if something in `compress_test.dart` itself fails (as opposed to the suite simply not running).
- **03-01 task 1 remains blocked** (Mac second-SDK bring-up; Mac offline, QUESTIONS.md #8) — unrelated to this plan's own blocker, but still open.
- Plans 03-05/03-06/03-07 (audio re-encode/strip proof, transmux, estimate/clearCache) all depend on this plan's engine existing, which it now does (pending the above re-verification) — do not start them assuming CORE-01 is proven; re-run CI first.

---
*Phase: 03-apple-compression-to-parity*
*Completed: 2026-09-22 (halted)*
