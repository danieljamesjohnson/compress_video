---
phase: 03-apple-compression-to-parity
plan: 05
subsystem: media-compression
tags: [swift, avfoundation, avassetexportsession, avassetwriter, aac, ci]

# Dependency graph
requires:
  - phase: 03-apple-compression-to-parity
    provides: "03-04's real-encode-only AVAssetReader/AVAssetWriter engine (CompressionEngine.swift/Compression.swift/JobRegistry.swift), proven end-to-end on the iOS simulator"
provides:
  - "The AVAssetExportSession transmux fast path (D-05) and the unconditional never-larger post-check shared between it and the real-encode branch (finishJob), proven green on the iOS simulator across THREE separate CI runs (35809012150, 35812499597 attempt 2, 35821995638: compress_test.dart 22/22 every time)"
  - "Audio passthrough (AAC source) and audio strip, proven correct on the iOS simulator (35821995638)"
  - "A hardened CI simulator-suite step (launch watchdog + fresh-boot + 5-attempt hang retry) that finally let compress_audio_test.dart run to completion at all after five consecutive runs where it either never started or was killed by launch hangs"
affects: [03-06, 03-07, 03-08]

# Actuals (#2632)
actuals:
  tokens: 24500
  tasks: 3
  commits: 6

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CompressionEngine.finishJob: the ONE never-larger post-check site shared by the transmux branch (runTransmux) and the real-encode branch, so the >= comparison, the move-into-place/substitution and the re-probe result construction can never diverge between them"
    - "AVAssetExportSession version-gated between the deprecated exportAsynchronously/.status pair (primary, this project's iOS 13/macOS 11 floor) and the modern export(to:as:) async throws pair (#available(iOS 18, macOS 15, *)) -- outputURL/outputFileType (deprecated properties) are set only inside the legacy branch, never unconditionally"
    - "CI 'launch watchdog': background the suite process under its own process group (set -m; cmd &; kill -- -$pid), poll the attempt's own log file every 5s for a SECOND line beyond flutter test's own 'loading <suite>' line (an existence-only check falsely flips on that first line alone, defeating the fast path -- caught and fixed before pushing) -- no progress within 150s kills the whole tree and counts as a hang (up to 5 attempts); once progress appears the suite gets 600s to actually finish, then any failure is genuine and fails fast with no retry"

key-files:
  created: []
  modified:
    - darwin/compress_video/Sources/compress_video/CompressionEngine.swift
    - darwin/compress_video/Sources/compress_video/ErrorMapping.swift
    - example/ios/RunnerTests/RunnerTests.swift
    - example/macos/RunnerTests/RunnerTests.swift
    - example/integration_test/compress_test.dart
    - example/integration_test/compress_audio_test.dart
    - .github/workflows/ci.yml

key-decisions:
  - "The two 03-04 `skip: !Platform.isAndroid` cases (transmux report + remux-speed-ratio) are removed and now pass unconditionally on the iOS simulator -- CI run 35821995638 (and 35809012150, and 35812499597) all show compress_test.dart 22/22, including both transmux cases and the unconditional never-larger contract."
  - "The `noaudio_720p.mp4` transmux case and the `AudioStrip` case were both reworked to assert the platform-independent never-larger CONTRACT (outputBytes <= inputBytes, exactly one of {kept-and-correct, substituted-original-exactly}) rather than one platform's specific encoder-efficiency outcome as if it were a guarantee -- Android's Media3/CBR encoder happens to land these two fixtures under the never-larger threshold even with audio removed/absent; Apple's real H.264 encoder does not always, and CORE-05 is unconditional per D-06/TransformerEngine.finishSuccess's own documented reasoning. Verified correct via CI: both cases pass on the iOS simulator across all three runs that reached compress_test.dart."
  - "AAC re-encode output settings gained AVSampleRateKey (normalised to an AAC-legal rate), AVChannelLayoutKey (explicit mono/stereo layout, not just a channel count) and an ADDITIONAL Apple-specific 32,000bps-per-channel floor on top of SizeGuard's shared 8,000-960,000bps range -- this fixed the AVError -11861 (unsupportedOutputSettings, 'Cannot Encode Media') that was failing the 1000bps-clamped-up case outright. ErrorMapping.swift now maps `.unsupportedOutputSettings` to `encoderUnavailable` instead of falling through to `unknown`, with a matching XCTest case in both RunnerTests.swift copies."
  - "CI's iOS-simulator integration step was hardened three times in direct response to real, cited CI evidence: (1) the four-suite list widened to include compress_audio_test.dart once its whole-file guard was removed; (2) `bash -e`'s effect on GitHub Actions `run:` steps (confirmed live, run 35807149965) required every legitimately-failing command to be wrapped in `|| status=$?`/`|| true` rather than left bare, since a bare failure aborts the whole script before any retry bookkeeping runs; (3) a flat per-attempt alarm (600-900s) was replaced with a launch watchdog (150s to first real progress, then 600s to finish) after run 35812499597 showed two suites hanging twice each and burning the entire 60-minute step budget with zero suites completing."

requirements-completed: []  # CORE-01 stays unmarked here: the transmux/never-larger portion of this plan is fully proven, but the audio re-encode bitrate/channel bug below is a real, unresolved gap in the same requirement's Apple-side proof. Do not check off CORE-01 from this plan alone.

coverage:
  - id: D1
    description: "The AVAssetExportSession transmux fast path is attempted whenever SizeGuard.Plan.wouldTransmux is true, version-gated between the deprecated and modern export APIs, with shouldOptimizeForNetworkUse disabled so no moov-first rewrite can pad a short remux past its own input size"
    requirement: CORE-01
    verification:
      - kind: integration
        ref: "CI run 35821995638 (and 35809012150, 35812499597), job Apple, step 'Run corpus integration tests on the iOS simulator': compress_test.dart 'default options on small_480p.mp4 report transmuxed, not a re-encode' and 'a remux is measurably faster than a real encode' -- both passing, part of '+22: All tests passed!'"
        status: pass
    human_judgment: false
  - id: D2
    description: "The never-larger post-check is unconditional on every produced file (transmux or real encode), uses >= (equality counts as not smaller), and the substitution never returns the caller's own input path"
    requirement: CORE-01
    verification:
      - kind: integration
        ref: "CI run 35821995638, compress_test.dart's Never-larger and Transmux groups, all passing (part of the same 22/22 run)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Audio passthrough (AAC source) copies the track unchanged (audioReencoded false, audioCodec aac); a source with no audio track completes cleanly with a null audioCodec"
    requirement: CORE-01
    verification:
      - kind: integration
        ref: "CI run 35821995638, compress_audio_test.dart: 'default options (AudioPassthrough) on an AAC source...' and 'a source with no audio track at all...' -- both passing"
        status: pass
    human_judgment: false
  - id: D4
    description: "AudioStrip removes the audio track, or -- if the never-larger check substitutes the original wholesale -- returns exactly the original file, never a hybrid"
    requirement: CORE-01
    verification:
      - kind: integration
        ref: "CI run 35821995638, compress_audio_test.dart: 'AudioOptions.strip removes the audio track...' -- passing"
        status: pass
    human_judgment: false
  - id: D5
    description: "A forced AAC re-encode honours the requested bitrate (within 25%) and channel count exactly"
    requirement: CORE-01
    verification:
      - kind: integration
        ref: "CI run 35821995638, compress_audio_test.dart: three cases still fail -- '...64000bps/2 channels...' (measured 24,182bps vs 64,000bps requested, 62% deviation), 'the same reencode request at 1 channel...' (re-probed 2 channels, not 1), and '...64000bps and a 128000bps...' (same 24,182bps measurement). A fourth previously-failing case ('a reencode request at 1000bps succeeds with the bitrate clamped up...') now PASSES after the AVChannelLayoutKey/AVSampleRateKey/per-channel-floor fix -- the -11861 encoder-rejection is fixed, but the requested bitrate/channel count are still not reaching the real output."
        status: fail
    human_judgment: true
    rationale: "Unresolved engine bug, not a test-authoring issue: the measured bitrate is IDENTICAL (24,182bps) before and after the AAC-settings fix, and the channel-count mismatch is the same shape as before. The constancy of the measured value across different requested bitrates (64,000 and 128,000 both measure 24,182) is the strongest single clue and is recorded in Deviations below with next-step hypotheses -- but was not run to ground within this plan's attempt budget."

duration: ~11h across one long session (dominated by CI wall-clock across 10 pushed attempts plus 3 orchestrator reruns, iOS-simulator launch hangs, and three rounds of CI-infra hardening)
completed: 2026-09-25
status: complete
---

# Phase 3 Plan 05: Apple Transmux, Never-Larger, and Audio Modes Summary

**HALTED: AVAssetExportSession transmux and the unconditional never-larger contract are proven end-to-end on the iOS simulator (compress_test.dart 22/22 across THREE separate CI runs: 35809012150, 35812499597 attempt 2, 35821995638, and again 35826458554 attempt 2); audio passthrough/strip/the 1000bps-clamp case are proven too (35821995638); but the fix for the remaining forced-AAC-re-encode bitrate/channel bug (commit 8a44a04) has never actually executed on a simulator -- every CI run since has been consumed by hosted-simulator launch hangs exhausting the 60-minute step budget before `compress_audio_test.dart` could run. Halting per orchestrator direction; a Mac-backed session must close this out.**

## Performance

- **Duration:** ~9h, almost entirely CI wall-clock: 9 pushed attempts (60538b3, f9d76ad, 341b23c, d5664c6, 346a730, 03926c5 -- plus the plan-metadata commit to follow) plus 2 orchestrator-initiated reruns of the same commit, across launch-hang diagnosis, three rounds of CI-infra hardening, and one round of real AAC-settings/test fixes
- **Completed:** 2026-09-23 (halted, incomplete)
- **Tasks:** 3 planned; task 1 (transmux) and task 2 (never-larger) fully verified; task 3 (audio modes) partially verified -- passthrough/strip/no-audio-track proven, forced re-encode's bitrate/channel fidelity is not
- **Files modified:** 7 (0 created)

## Accomplishments

- `CompressionEngine.swift`: `runTransmux` (AVAssetExportSession, passthrough preset, `shouldOptimizeForNetworkUse = false`, version-gated between the deprecated `exportAsynchronously`/`.status` pair (primary, this project's iOS 13/macOS 11 floor) and the modern `export(to:as:)` async throws pair on `#available(iOS 18, macOS 15, *)`) and `finishJob` (the ONE never-larger post-check site, `>=`, shared by both the transmux and real-encode branches) -- both proven on the iOS simulator across three separate CI runs, each showing `compress_test.dart` at 22/22.
- Audio mode resolution: passthrough is attempted only for an AAC-compatible source, falling back to (or, for an explicit `reencode` request, always taking) a forced AAC re-encode; `audioReencoded` is reported from the branch that actually ran, never from the request. Passthrough, strip, and no-audio-track are all proven correct on the simulator.
- `ErrorMapping.swift` gained `.unsupportedOutputSettings` (-11861) -> `encoderUnavailable`, closing a real gap where this AVFoundation error fell through to `unknown`; matching XCTest case added to both `RunnerTests.swift` copies (kept byte-identical).
- Two test-contract fixes (both verified correct via CI, not weakenings): the `noaudio_720p.mp4` transmux case and the `AudioStrip` case now assert the platform-independent never-larger CONTRACT rather than one platform's specific encoder-efficiency coincidence as if it were a guarantee.
- CI's iOS-simulator integration step was hardened three times over the course of this plan, each time in direct response to real, cited evidence from a failed run: `bash -e`-safety for the retry loop, a launch watchdog replacing a flat per-attempt alarm, and widening the suite list to include `compress_audio_test.dart` now that its whole-file guard is gone. This is what finally got `compress_audio_test.dart` to run to completion at all, after five consecutive runs where it either never started or was killed mid-hang.

## Task Commits

1. **Tasks 1-3 (consolidated): transmux, never-larger, audio modes** -- `60538b3`
2. **Test fix: assert the never-larger contract on `noaudio_720p.mp4`, not Media3's exact-equality coincidence** -- `f9d76ad`
3. **CI: make the simulator suite step survive launch hangs (first hardening pass)** -- `341b23c`
4. **CI: don't let `bash -e` abort the suite loop on an alarm** -- `d5664c6`
5. **Fix: AAC re-encode output settings (-11861), `AudioStrip` test contract** -- `346a730`
6. **CI: prebuilt-app investigation (dropped, flag doesn't exist) + launch watchdog** -- `03926c5`

**Plan metadata:** this commit (docs)

## Files Created/Modified

- `darwin/compress_video/Sources/compress_video/CompressionEngine.swift` -- transmux branch, shared `finishJob`, audio-mode resolution, AAC output settings
- `darwin/compress_video/Sources/compress_video/ErrorMapping.swift` -- `.unsupportedOutputSettings` mapping
- `example/ios/RunnerTests/RunnerTests.swift`, `example/macos/RunnerTests/RunnerTests.swift` -- matching XCTest case (byte-identical)
- `example/integration_test/compress_test.dart` -- two `skip` lines removed; `noaudio_720p.mp4` case reworked to the contract
- `example/integration_test/compress_audio_test.dart` -- whole-file guard removed; `AudioStrip` case reworked to the contract
- `.github/workflows/ci.yml` -- suite list widened; `bash -e` safety; launch watchdog replacing the flat alarm

## Decisions Made

See `key-decisions` in frontmatter for the full accounting. In short: the shared never-larger contract is treated as authoritative over any one platform's encoder-efficiency coincidence (matching `TransformerEngine.finishSuccess`'s own documented reasoning), and CI's simulator-suite step was hardened incrementally against real, observed failure modes rather than guessed at up front.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `AVError.unsupportedOutputSettings` (-11861) fell through to `"unknown"` instead of a specific reason**
- **Found during:** Task 3, CI run 35809012150 (the first run to reach `compress_audio_test.dart` at all)
- **Fix:** Added the case to `ErrorMapping.reasonForAVError` (-> `encoderUnavailable`) and to `knownAVErrorCodes`, with a matching XCTest case in both `RunnerTests.swift` copies.
- **Committed in:** `346a730`

**2. [Rule 1 - Bug] AAC writer settings missing `AVSampleRateKey`/`AVChannelLayoutKey` and using SizeGuard's shared (Android-derived) bitrate floor, which is too low for Apple's real encoder**
- **Found during:** Task 3, CI run 35809012150
- **Fix:** Always set `AVSampleRateKey` (normalised to an AAC-legal rate) and `AVChannelLayoutKey` (explicit mono/stereo layout); apply an ADDITIONAL 32,000bps-per-channel floor on top of `plan.audioBitrateBps`, without changing the shared `SizeGuard.swift` port.
- **Verification:** The specific case this was sized to fix (`a reencode request at 1000bps succeeds with the bitrate clamped up...`) now passes (CI run 35821995638) -- the -11861 encoder rejection is gone.
- **Committed in:** `346a730`

### Test-contract corrections (not weakenings -- see key-decisions)

**3. [Rule 1, test-authoring] `noaudio_720p.mp4` transmux case and `AudioStrip` case both encoded one platform's encoder-efficiency coincidence as a contract guarantee**
- **Found during:** Task 1 (noaudio_720p) and Task 3 (AudioStrip)
- **Fix:** Both reworked to assert the platform-independent never-larger contract (never larger than input; exactly one of {kept-and-correct, substituted-original-exactly}), never a specific outcome one platform's encoder happens to produce.
- **Verification:** Both pass on the iOS simulator in every run that reached them (35809012150 onward).
- **Committed in:** `f9d76ad` (noaudio_720p), `346a730` (AudioStrip)

### CI infrastructure (three rounds, each responding to new evidence)

**4. [Rule 3 - Blocking] `bash -e` (GitHub Actions' default for `run:` steps) aborted the retry loop on the first alarm-killed attempt**
- **Found during:** CI run 35807149965 ("Process completed with exit code 142" immediately after the first alarm, retry loop never executing)
- **Fix:** Every legitimately-failing command in the loop wrapped in `|| status=$?` / `|| true`. Verified locally under `bash -e -o pipefail` with a stub `flutter`/`xcrun` across all three control-flow paths before pushing.
- **Committed in:** `d5664c6`

**5. [Rule 3 - Blocking] A flat 600-900s per-attempt alarm, plus a full Xcode rebuild on every retry, made a launch hang cost ~13 minutes and could exhaust the whole step budget on 1-2 unlucky suites**
- **Found during:** CI run 35812499597 (two suites hung twice each; `compress_audio_test.dart` never got a single completed attempt, the step's 60-minute timeout fired mid-build)
- **Fix:** Replaced the alarm with a launch watchdog -- 150s to first real progress (killing the whole process group via `set -m`/`kill -- -$pid` on timeout), then 600s to finish once progress appears; up to 5 attempts. `--use-application-binary` (prebuilt-binary reuse) was investigated and confirmed NOT to exist on `flutter test` (only `flutter drive`) on the CI Flutter SDK, so that specific avenue was dropped rather than attempted blind.
- **Caught before pushing:** the watchdog's own progress-detection had a bug (an existence-only grep matched `flutter test`'s own first "loading" line, permanently granting the long budget and defeating the fast path) -- found and fixed via local testing before this commit, not discovered live in CI.
- **Verification:** CI run 35821995638 -- `compress_test.dart` reached 22/22 for the third time, and `compress_audio_test.dart` ran to completion (4 passed, 3 failed) for the first time ever in this plan's history.
- **Committed in:** `03926c5`

---

**Total deviations:** 2 auto-fixed engine bugs, 2 test-contract corrections, 3 rounds of CI infrastructure hardening, and 1 unresolved engine bug (see below). No scope creep -- every change is either a cited bug fix or infrastructure that was blocking any verification signal at all.

## Resolution, 2026-09-25

The halt above is resolved by evidence. Quick task 260923-9lc replaced the simulator-suite step's
watchdog (`tool/run_ios_integration_suites.sh`) and `compress_audio_test.dart` then ran to
completion on CI twice on identical engine code: run **35857609478** and run **35869222604**,
**7/7 both times**, including the three cases this plan halted on --
`AudioOptions.reencode at 64000bps/2 channels reports audioReencoded true and re-probes as AAC
with exactly 2 channels, within 25 percent of the requested bitrate`, `the same reencode request
at 1 channel re-probes as exactly 1 channel`, and `a 64000bps and a 128000bps reencode of the
same clip produce measurably different audio bitrates in the expected direction`. So commit
`8a44a04`'s fix (`AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant` plus the
esds-authoritative channel count in the test) is proven on the simulator; task 3 is complete
and this plan's status is `complete`. The "Issues Encountered" section below is kept as the
record of how it got there.

## Issues Encountered

**HALTED, unresolved: a forced AAC re-encode's requested bitrate and channel count do not reach the real output on Apple, and the fix for it has never actually run.**

The measured state as of the last run that produced real `compress_audio_test.dart` output (CI run 35821995638, before commit `8a44a04`): three cases failed, all on `portrait_hibitrate_1080p60.mp4` (a fixture already established as safe from the never-larger post-check -- not a repeat of that interaction):

- `AudioOptions.reencode at 64000bps/2 channels...`: `Expected: <=0.25` deviation, `Actual: 0.62215625` -- measured 24,182bps vs a 64,000bps request.
- `the same reencode request at 1 channel re-probes as exactly 1 channel`: `Expected: <1>`, `Actual: <2>`.
- `a 64000bps and a 128000bps reencode...`: same 24,182bps measurement at the 64,000bps step (the 128,000bps step is never reached).

24,182bps was identical whether 64,000 or 128,000 was requested, and identical before and after the AVSampleRateKey/AVChannelLayoutKey/per-channel-floor fix in `346a730` (which only fixed the separate -11861 encoder-rejection failure -- the 1000bps-clamped-up case now passes). This constancy is the strongest clue that AVFoundation's AAC-LC encoder was silently ignoring `AVEncoderBitRateKey` and settling on its own default rather than honouring the request.

**A further fix was written and pushed (commit `8a44a04`) but has NEVER EXECUTED on a simulator:** `AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant` added to the AAC writer settings (the standard fix for exactly this "encoder ignores the requested rate without an explicit strategy" behaviour), plus a `compress_audio_test.dart` fix reading the AUTHORITATIVE channel count from the `esds` box's `AudioSpecificConfig` rather than the `mp4a` sample entry's `channelcount` field (which Apple's muxer hardcodes to 2 regardless of the real stream). The esds descriptor-parsing bit-math was verified against a synthetic buffer locally (both mono and stereo decode correctly) -- but the actual fix has not been proven against a real encode, because every CI run since (`35826458554` attempts 1 and 2) was consumed entirely by hosted-simulator launch hangs: `media_info_test.dart` and/or `thumbnail_test.dart` hung repeatedly (up to 3 times per suite), and by the time `compress_test.dart` finished (green, 22/22, a third consecutive clean run), the step's 60-minute budget was exhausted before `compress_audio_test.dart` could run even once.

**Why halting now rather than pushing again:** the orchestrator's CI-attempt budget for this plan is exhausted (10 pushed attempts, 3 orchestrator-initiated reruns), and the blocker is no longer engine correctness -- it is the hosted macOS runner's simulator reliability. Further pushes would not produce new signal without either a lighter suite ordering, a non-CI verification path, or luck. The 03-01 Mac (task 1, still blocked on QUESTIONS.md #8) is the correct next verification path once reachable.

**CI hardening caveat:** the launch watchdog (prebuilt-binary investigation + 150s/600s watchdog, commits `d5664c6`/`03926c5`) is a real, verified improvement (it is what got `compress_audio_test.dart` to run at all in `35821995638`), but the step still exceeded its 60-minute budget on both attempts of the LAST run (`35826458554`) via repeated hangs on the two lighter suites before audio ever got a turn. The watchdog's kill path (`set -m`; `kill -- -$pid`) was only verified locally against a stub `flutter`/`xcrun` (matching bash control flow, not real Xcode/simulator process trees) -- a killed `flutter test` process group may be leaving the simulator itself in a busy/unresponsive state that makes the NEXT suite's own launch more likely to hang too, compounding across a run. This needs checking on a real Mac, where `xcrun simctl` state can actually be inspected after a kill, not just inferred from CI logs.

**Carried forward, exact next step:** once the Mac is reachable (QUESTIONS.md #7/#8, CocoaPods still needed there) or the danserver Mac otherwise comes online, run `bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test/compress_audio_test.dart` (per 03-01's own scripts) against the code already on `main` (commit `8a44a04` or later) and confirm all three previously-failing cases now pass. If they still fail, `--plain-name` filters (e.g. `--plain-name 'reencode at 64000bps'`) keep each iteration cheap without CI's launch-hang tax at all.

## User Setup Required

None -- no external service configuration required. (The Mac's CocoaPods gap, QUESTIONS.md #7, remains a separate, already-tracked blocker for local Apple verification generally.)

## Next Phase Readiness

- **Transmux and never-larger (this plan's tasks 1-2) are fully proven** across four separate CI runs (35809012150, 35812499597 attempt 2, 35821995638, 35826458554 attempt 2, each showing `compress_test.dart` 22/22) and should not need revisiting.
- **Audio passthrough, strip, and the 1000bps-clamp case (part of task 3) are proven** (35821995638).
- **Audio forced re-encode bitrate/channel fidelity (the rest of task 3) is NOT proven.** A fix has been written and pushed but never executed against a real simulator. 03-06/03-07 must NOT assume audio re-encode works correctly on Apple until a Mac-backed run confirms commit `8a44a04`'s fix.
- **CI's simulator-suite step is materially more robust than at the start of this plan** (launch watchdog, 5 retries, `bash -e` safety, prebuilt-binary investigation) but is NOT yet reliable enough to guarantee all four suites complete within one 60-minute run -- see the CI hardening caveat above. A future plan may need to either split the step into two jobs, reduce the suite count per step, or accept that this specific runner/simulator combination needs occasional manual reruns.
- **03-01 task 1 remains blocked** (Mac second-SDK bring-up; Mac offline, QUESTIONS.md #8) -- this is now the ONLY practical path to closing out the remaining audio bug without further burning CI budget on launch-hang roulette.

---
*Phase: 03-apple-compression-to-parity*
*Completed: 2026-09-23 (incomplete -- see Issues Encountered)*
