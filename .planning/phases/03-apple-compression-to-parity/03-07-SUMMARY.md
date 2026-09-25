---
phase: 03-apple-compression-to-parity
plan: 07
subsystem: media-compression
tags: [swift, avfoundation, avassetreader, avassetwriter, unicode, ci, doc-generation]

# Dependency graph
requires:
  - phase: 03-apple-compression-to-parity
    provides: "03-06's CompressionEngine.resolvePlan(inputURL:inputInfo:request:) overload (reused directly for estimate()) and the free-space pre-check; 03-01's trim_source_10s.mp4 fixture with its sidecar trim block; 03-04/03-05's real-encode/transmux/audio engine that trim, estimate and clearCache all sit on top of"
provides:
  - "The 2000-7000ms sidecar-driven trim case on trim_source_10s.mp4, proving CORE-07's trim mechanism (already implemented in CompressionEngine.swift by an earlier plan) end to end on Android, the iOS simulator and the macOS host, with measured first-sample-offset numbers printed for both trim cases (TRIM_MEASURED lines)"
  - "Compression.estimate(path:request:) and Compression.clearCache() implemented on Apple, both mirroring Compression.kt exactly (estimate resolves through the same CompressionEngine.resolvePlan the real job uses; clearCache sweeps PluginFiles.cacheSubDir() excluding live jobs' temp paths) -- compress_output_test.dart's whole-file Android-only guard removed, no assertion changed"
  - "Thumbnails.swift's cache subdirectory now shares PluginFiles.cacheSubDir() directly (was a coincidentally-identical private duplicate) so a thumbnail this plugin wrote is reclaimed by clearCache(), matching Android's Phase 2 behaviour"
  - "A real, previously-undetected Unicode-normalisation bug: Darwin's URL(fileURLWithPath:)/.path round trip silently decomposes an NFC (precomposed) filename to NFD, corrupting CompressResultMessage.outputPath for any caller-supplied non-ASCII outputPath -- found on CI, fixed at the two actual reporting choke points (CompressionEngine.buildResult, Thumbnails.writeJpegAtomically) with a regression XCTest that reproduces the round trip directly"
  - "doc/PRESETS.md's Apple section: two measured preset tables (iOS Simulator software encoder, macOS host real Video Toolbox hardware encode), a measured estimate()-accuracy table, and a recorded cross-platform bitrate-delivery divergence (Apple overshoots the nominal target 3-10%, Android's emulator undershoots to 71%) flagged for 03-08's parity gate"
  - "corpus/README.md's small_480p duration-delta finding (01-07 follow-up, D-17) resolved with direct mvhd/edit-list box-level evidence: the container's real intended duration is 3000ms, both platforms' readings (Android 3026ms, Apple 2992ms) are within the sidecar's own tolerance of it, and neither is fixed to match the other"
affects: [03-08, 03-09]

# Actuals (#2632)
actuals:
  tokens: 12200
  tasks: 3
  commits: 10

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Darwin's URL(fileURLWithPath:) constructor and .path getter round-trip a path through the POSIX file-system representation, which is NFD (decomposed Unicode) by long-standing Apple convention -- this happens on construction/access alone, with no real filesystem I/O required, so it affects even a not-yet-existing destination path. Normalising a path string to NFC at ONE point (e.g. inside a validation helper) does not survive being re-wrapped in a later `URL(fileURLWithPath:)` call -- the fix must sit at the actual boundary where the path is read back out via `.path` and handed to the caller (`.precomposedStringWithCanonicalMapping` applied there), not upstream where the string is merely validated."
    - "Swift's native `String ==` (and therefore XCTAssertEqual) compares by Unicode CANONICAL EQUIVALENCE -- it treats NFC and NFD forms of the same text as equal, which makes it unusable for testing exactly this class of bug. `NSString.isEqual(to:)` compares literal UTF-16 code units instead (matching Dart's own String equality, which is what originally observed this bug), and is the correct comparison for any XCTest proving byte-for-byte Unicode-form preservation."
    - "A CI integration-test step's `timeout-minutes` must scale with the number of suites it runs and the runner's own flake rate, not stay fixed as suites are added -- six suites absorbing hosted-simulator launch hangs exhausted a 60-minute budget sized for four."

key-files:
  created:
    - tool/measure_presets_ci.sh
  modified:
    - darwin/compress_video/Sources/compress_video/Arguments.swift
    - darwin/compress_video/Sources/compress_video/Compression.swift
    - darwin/compress_video/Sources/compress_video/CompressionEngine.swift
    - darwin/compress_video/Sources/compress_video/Thumbnails.swift
    - example/integration_test/compress_test.dart
    - example/integration_test/compress_output_test.dart
    - example/ios/RunnerTests/RunnerTests.swift
    - example/macos/RunnerTests/RunnerTests.swift
    - tool/run_ios_integration_suites.sh
    - .github/workflows/ci.yml
    - doc/PRESETS.md
    - corpus/README.md

key-decisions:
  - "Trim itself (AVAssetReader.timeRange + AVAssetWriter.startSession(atSourceTime:), trim-aware progress via SizeGuard's outputDurationMs) was already correctly implemented by an earlier plan before this one started -- task 1's real contribution was the new sidecar-driven 2000-7000ms case and the measured proof (TRIM_MEASURED lines: 500-3500ms delta 8ms, 2000-7000ms delta 13ms, both against a 34ms one-frame tolerance) that 03-RESEARCH.md's Pitfall 7/Open Question 1 asked for, not new production code."
  - "The 'trim end exceeds source duration should be rejected' adjacency case named in the plan's must_haves was NOT implemented: neither Android's Arguments.kt nor the pre-existing Apple Arguments.swift validates trimEndMs against the source's actual duration (both silently let AVFoundation/Media3 clamp), and this plan's files_modified list is Apple-only -- adding a NEW cross-platform validation rule affecting Android too is out of this plan's declared scope. Documented here rather than silently implemented asymmetrically."
  - "estimate()/clearCache() route through the exact resolvePlan overload 03-06 added for the free-space pre-check, so a prediction and a subsequent real job can never disagree -- no second computation was written."
  - "The Apple estimate()-accuracy tolerance stays a single, unconditional 75% constant (unchanged from Android's derivation) rather than gaining an Apple-specific branch: measured iOS Simulator accuracy (2.2-5.8% error) is far tighter than Android's worst case (67.0%), so a platform-specific carve-out would add a branch with no measured case to protect against. 03-RESEARCH.md's Open Question 2 is answered: yes, one tolerance covers both Apple devices, trivially."
  - "The small_480p duration delta (01-07/D-17) is resolved with evidence, not a code fix: direct mvhd/edit-list box parsing (mvhd timescale=1000/duration=3000, both tracks' edit lists agreeing) plus an edit-list-aware ffprobe read both independently confirm the container's real intended duration is exactly 3000ms. Neither platform's reading (Android 3026ms, Apple 2992ms) is 'demonstrably misreading' the file by the plan's own bar for changing platform code -- both are within the clip's 34ms tolerance, so neither reading was altered."
  - "The Unicode NFD bug fix went through two attempts because the first (normalising inside Arguments.standardizedAbsolutePath) was correct but insufficient: Compression.swift re-wraps that already-NFC string in a fresh URL(fileURLWithPath:), and CompressionEngine.buildResult's later `.path` access on that URL re-introduces NFD regardless of the upstream fix. The second attempt moved the fix to the actual reporting boundary (buildResult, plus Thumbnails.writeJpegAtomically defensively) and added a targeted XCTest that reproduces the bare round-trip loss directly, so a future refactor cannot silently reopen it."
  - "CI's iOS-simulator integration step's timeout-minutes was raised from 60 to 90 (not the watchdog script's own per-suite/per-phase budgets) after compress_output_test.dart's addition as a sixth suite let 12 hosted-simulator launch hangs exhaust the old budget before two suites got a turn -- an outer-backstop-only change, confirmed sufficient by the same run at 90 minutes reaching every suite with only two hangs."

requirements-completed: [CORE-07, CORE-01]  # NOT marked complete in REQUIREMENTS.md -- see Next Phase Readiness. Both are also declared by 03-08/03-09, neither of which has a SUMMARY.md yet; the shared-ID gate (03-06's own precedent) means neither requirement is honestly closeable until every declaring plan finishes.

coverage:
  - id: D1
    description: "A 2000-7000ms trim on trim_source_10s.mp4 produces a five-second output within one frame, on Android, the iOS simulator and the macOS host, with the expected duration and tolerance read from the fixture's own sidecar"
    requirement: "CORE-07"
    verification:
      - kind: integration
        ref: "example/integration_test/compress_test.dart#a trim from 2000ms to 7000ms on trim_source_10s ... (CORE-07)"
        status: pass
      - kind: integration
        ref: "example/integration_test/compress_test.dart#a trim from 500ms to 3500ms ... (existing case, re-verified)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Compression.estimate()/clearCache()/output placement work on Apple exactly as on Android, proven by the same shared Dart suite with the platform guard removed"
    requirement: "CORE-01"
    verification:
      - kind: integration
        ref: "example/integration_test/compress_output_test.dart (all groups: estimate accuracy, estimate/result prediction agreement, output placement, clearCache) -- CI run 36186455835, Apple job"
        status: pass
      - kind: integration
        ref: "example/integration_test/thumbnail_test.dart (Android + iOS simulator, confirming the cache-subdirectory refactor did not regress Phase 1)"
        status: pass
    human_judgment: false
  - id: D3
    description: "A real, previously-undetected Unicode NFC/NFD outputPath corruption bug found and fixed, with a regression test proving the mechanism directly"
    requirement: "CORE-09"
    verification:
      - kind: integration
        ref: "example/integration_test/compress_output_test.dart#an explicit outputPath with non-ASCII characters ... -- CI run 36186455835, Apple job (failed on runs 36176323945 and 36181752118 before the fix)"
        status: pass
      - kind: unit
        ref: "example/ios/RunnerTests/RunnerTests.swift#testFileURLPathRoundTripLosesNfcAndPrecomposedStringRestoresIt, #testRequireWritableOutputParentPreservesNfcForNonAsciiFilename"
        status: pass
    human_judgment: false
  - id: D4
    description: "Apple preset behaviour published from two real devices' own measurements (iOS Simulator software encoder, macOS host hardware encoder), with the software-vs-hardware caveat stated and a real cross-platform bitrate-delivery divergence flagged for 03-08"
    verification:
      - kind: other
        ref: "tool/measure_presets_ci.sh output, CI run 36186455835 artifacts measure-ios-simulator/measure-macos-host, transcribed verbatim into doc/PRESETS.md"
        status: pass
    human_judgment: true
    rationale: "Every number is measured and traceable to a CI artifact, but the DECISION of whether one tolerance covers both Apple devices, and how to characterise the Apple-vs-Android bitrate divergence for 03-08, is an interpretive judgment a human should be able to review, not something a test asserts pass/fail on."
  - id: D5
    description: "small_480p's year-old cross-platform duration delta (01-07 follow-up) resolved with direct container-format evidence rather than a platform code change"
    verification:
      - kind: other
        ref: "corpus/README.md 'small_480p's duration delta, resolved (D-17...)' section; underlying evidence is a direct mvhd/edit-list box parse performed this session (not committed as a script) plus an edit-list-aware ffprobe -show_format read"
        status: pass
    human_judgment: true
    rationale: "This is a documentation finding closing a standing question, not an assertion a test enforces -- the judgment that neither platform is 'demonstrably misreading' the file (the plan's own bar for changing platform code) is exactly the kind of call this field exists to flag for human review."

# Metrics
duration: ~4h10m, almost entirely CI wall-clock across 4 pushed attempts
completed: 2026-09-25
status: complete
---

# Phase 3 Plan 07: Trim exactness, estimate/clearCache parity, and measured Apple presets Summary

**Closed CORE-07's trim exactness with a measured 2000-7000ms case, implemented `estimate()`/`clearCache()` on Apple mirroring Android exactly, found and fixed a real Unicode NFC/NFD `outputPath` corruption bug along the way, and published `doc/PRESETS.md`'s Apple section from two real devices' measurements.**

## Performance

- **Duration:** ~4h10m, almost entirely CI wall-clock across 4 pushed CI attempts
- **Started:** 2026-09-25T17:20:00Z (approx.)
- **Completed:** 2026-09-25T21:35:00Z (approx.)
- **Tasks:** 3 of 3 completed
- **Files modified:** 13 (12 modified, 1 created) across 10 commits

## Accomplishments

- Added the sidecar-driven 2000ms-7000ms trim case on `trim_source_10s.mp4` to `compress_test.dart`, alongside the existing 500-3500ms case, both now printing `TRIM_MEASURED` lines with the real observed offset. Trim itself (`AVAssetReader.timeRange` + `AVAssetWriter.startSession(atSourceTime:)`, trim-aware progress derivation) was already implemented by an earlier plan; this plan's contribution was the new test case and the measured proof 03-RESEARCH.md's Pitfall 7/Open Question 1 required.
- Implemented `Compression.estimate(path:request:)` (resolves through the same `CompressionEngine.resolvePlan` the real job uses, no reader/writer/export session built) and `Compression.clearCache()` (sweeps `PluginFiles.cacheSubDir()` excluding live jobs' temp paths) on Apple, mirroring `Compression.kt`. Removed `compress_output_test.dart`'s whole-file `Platform.isAndroid` guard with no assertion changed.
- Relocated `Thumbnails.swift`'s cache directory computation onto the shared `PluginFiles.cacheSubDir()` helper (was a private, coincidentally-identical duplicate), so a thumbnail this plugin wrote is reclaimed by `clearCache()`.
- Found and fixed a real bug: Darwin's `URL(fileURLWithPath:)`/`.path` round trip silently decomposes a caller-supplied NFC (precomposed) `outputPath` filename to NFD, corrupting `CompressResultMessage.outputPath`. Took two attempts to land at the correct fix location (the actual reporting boundary in `CompressionEngine.buildResult`, not the upstream `Arguments.swift` validation helper) — see Deviations.
- Wired CI to automatically run `tool/measure_presets.dart`'s own documented reproduction procedure on both the iOS Simulator and the macOS host (`tool/measure_presets_ci.sh`), and published the resulting two measured tables plus a measured `estimate()`-accuracy table in `doc/PRESETS.md`'s new Apple section.
- Resolved the year-old `small_480p` duration-delta finding (01-07/D-17) with direct `mvhd`/edit-list box-level evidence: the container's real intended duration is exactly 3000ms; neither platform's reading is fixed, since both are within tolerance and neither is demonstrably wrong.
- Raised the iOS-simulator integration step's CI budget from 60 to 90 minutes after `compress_output_test.dart`'s addition (a sixth suite) exhausted the old budget on hosted-simulator launch hangs before it got a turn.

## Task Commits

Each task was committed atomically (10 commits total across 4 pushed CI attempts):

1. **Task 1: Sidecar-driven 2000-7000ms trim case** — `ac661bb` (test), `c431d50` (fix: lint)
2. **Task 2: estimate()/clearCache()/thumbnail relocation** — `d66e2a1` (feat)
3. **Task 3: CI measurement wiring, doc/PRESETS.md, corpus/README.md** — `3f047c5` (feat: CI wiring), `497dbbe` (docs: D-17), `3a6dc75` (docs: stale comment), `c77edba` (docs: Apple preset tables)
4. **Cross-cutting fixes discovered via CI** — `9c5c315` (ci: 90-minute budget), `2009019` (fix: NFC attempt 1), `d3582aa` (fix: NFC attempt 2, correct location)

**Plan metadata:** this commit (docs)

## Files Created/Modified

- `tool/measure_presets_ci.sh` — automates `tool/measure_presets.dart`'s copy-run-remove reproduction procedure against one flutter device (new)
- `darwin/compress_video/Sources/compress_video/Arguments.swift` — `standardizedAbsolutePath` normalises its own return value to NFC
- `darwin/compress_video/Sources/compress_video/Compression.swift` — `estimate()`, `clearCache()` implemented
- `darwin/compress_video/Sources/compress_video/CompressionEngine.swift` — `buildResult` normalises `outputPath` to NFC at the actual reporting boundary
- `darwin/compress_video/Sources/compress_video/Thumbnails.swift` — shares `PluginFiles.cacheSubDir()`, defensive NFC normalisation on its own returned path
- `example/integration_test/compress_test.dart` — new trim case, updated stale Apple-parity comment
- `example/integration_test/compress_output_test.dart` — platform guard removed, `ESTIMATE_ACCURACY` print added
- `example/ios/RunnerTests/RunnerTests.swift` / `example/macos/RunnerTests/RunnerTests.swift` — two new Unicode-regression XCTest cases (byte-identical)
- `tool/run_ios_integration_suites.sh` — `compress_output_test.dart` added to the default suite list
- `.github/workflows/ci.yml` — measure-presets steps added, iOS suite step timeout raised to 90 minutes
- `doc/PRESETS.md` — Apple section (two measured tables, estimate-accuracy table, bitrate-divergence finding)
- `corpus/README.md` — small_480p duration-delta resolution (D-17)

## Decisions Made

See `key-decisions` in frontmatter for the full accounting. In short: trim's mechanism pre-existed and only needed proof; estimate/clearCache route through the existing shared resolver; the Apple tolerance stays unified with Android's (measured, not assumed); the duration delta is resolved with evidence, not a code change; the Unicode fix required finding the true reporting boundary, not the first plausible-looking location.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Darwin `URL(fileURLWithPath:)`/`.path` round trip silently decomposes NFC to NFD in `CompressResultMessage.outputPath`**
- **Found during:** Task 2's CI verification (CI run 36176323945), re-surfaced identically on the next attempt (CI run 36181752118) after an insufficient first fix
- **Issue:** A caller-supplied `outputPath` with a precomposed Unicode filename (e.g. `vidéo_日本語_output.mp4`) came back from `compress()` with the "é" decomposed into "e" + combining acute accent — visually and when printed identical, byte-different, failing `compress_output_test.dart`'s non-ASCII outputPath case.
- **Fix (attempt 1, insufficient):** Normalised `Arguments.standardizedAbsolutePath`'s return value to NFC via `.precomposedStringWithCanonicalMapping`. Correct for that function's own contract, but `Compression.swift` re-wraps the result in a fresh `URL(fileURLWithPath:)`, and `CompressionEngine.buildResult`'s later `.path` access on that URL re-introduces NFD regardless — the fix did not survive the round trip.
- **Fix (attempt 2, correct):** Moved the normalisation to the actual reporting boundary: `CompressionEngine.buildResult` now returns `destinationURL.path.precomposedStringWithCanonicalMapping` for `CompressResultMessage.outputPath` — the one function every caller-visible path (real encode, transmux, both never-larger branches) funnels through. Applied the same defensively in `Thumbnails.writeJpegAtomically`.
- **Files modified:** `Arguments.swift` (kept, still correct for its own scope), `CompressionEngine.swift`, `Thumbnails.swift`, both `RunnerTests.swift` copies (two new regression cases)
- **Verification:** CI run 36186455835, Apple job: `compress_output_test.dart`'s non-ASCII outputPath case passes; both new XCTest cases pass on the iOS simulator and macOS host.
- **Committed in:** `2009019` (attempt 1), `d3582aa` (attempt 2, the actual fix)

**2. [Rule 3 - Blocking] CI's iOS-simulator integration step's 60-minute timeout was sized for four suites, not six**
- **Found during:** Task 3's first CI push (CI run 36168698223)
- **Issue:** `compress_output_test.dart`'s addition as this step's sixth suite meant 12 hosted-simulator launch hangs (a well-documented, pre-existing flake — `flutter/flutter#116248`/`#77992`) exhausted the old 60-minute budget before `compress_audio_test.dart` or `compress_output_test.dart` got a turn, even though every suite that DID run was green.
- **Fix:** Raised the step's `timeout-minutes` from 60 to 90 — the outer backstop only, not the watchdog script's own per-suite/per-phase budgets (unchanged in `tool/run_ios_integration_suites.sh`).
- **Files modified:** `.github/workflows/ci.yml`
- **Verification:** The next run (36176323945) at 90 minutes absorbed only 2 launch hangs and every suite got a turn.
- **Committed in:** `9c5c315`

---

**Total deviations:** 2 auto-fixed (1 bug requiring two attempts to locate correctly, 1 CI infrastructure budget). **Impact on plan:** Both fixes were necessary for the plan's own acceptance criteria (compress_output_test.dart passing on Apple; the iOS suite step completing at all) and neither is scope creep — the Unicode bug is a genuine, previously-undetected correctness issue in the Apple engine's `outputPath` field, and the CI budget was a direct, measured consequence of this plan's own suite addition.

## Issues Encountered

**CI attempt budget:** this plan used 4 pushed attempts total (the plan's own nominal 3-attempt guidance plus one authorised retry from the phase-level orchestrator after the first 3 were exhausted by a mix of infrastructure timeout and two real find-the-actual-bug-location iterations): attempt 1 (`3f047c5`, CI run 36168698223) timed out on CI infrastructure (12 silent simulator launch hangs against the old 60-minute budget) with zero code failures — Android green, no Apple suite failures observed, just incomplete coverage; attempt 2 (`9c5c315`, CI run 36176323945) raised the budget and surfaced the real Unicode NFD bug for the first time; attempt 3 (`2009019`, CI run 36181752118) applied an insufficient fix at the wrong location, reproducing the identical failure; attempt 4 (`d3582aa`, CI run 36186455835) applied the correct fix at the actual reporting boundary and reached fully green on every job (Detect Apple-relevant changes, Android, Apple, Cross-platform parity).

**No other issues.** The Android job's one intermittent `compress_jobs_test.dart` concurrent-cancel/`adb: device offline` flake (seen on run 36176323945) is the exact, previously-documented infrastructure flake named in this project's own lane notes — cleared on the very next push with no code change.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **CORE-07's trim mechanism is proven end to end** on Android, the iOS simulator and the macOS host, with the fixture's own sidecar driving the expectation. **CORE-01's estimate()/clearCache()/output-placement work is proven identically on Apple and Android** via the same shared Dart suite.
- **Neither CORE-01 nor CORE-07 is marked complete in `REQUIREMENTS.md`** by this plan — both are also declared by `03-08-PLAN.md` and `03-09-PLAN.md`, neither of which has a `SUMMARY.md` yet, so the shared-ID gate (the same rule 03-06-SUMMARY.md applied to CORE-01) keeps both `Pending` until every declaring plan finishes. 03-09 (or whichever plan finishes last) should re-check `requirements.ready-ids` and close both then.
- **A real, measured cross-platform bitrate-delivery divergence is flagged for 03-08's parity gate**: Apple overshoots the nominal preset bitrate target by 3-10% at every measured preset (both the iOS Simulator and the macOS host), while Android's emulator undershoots (down to 71% at `p1080`) — any future `videoBitrateBps` parity tolerance needs to span both directions, not just Android's documented undershoot. See `doc/PRESETS.md`'s Apple section for the full numbers.
- **The `truncated_mdat.mp4` Android/Apple reason-bucket difference 03-06 left for 03-08 to arbitrate is unchanged by this plan** (`io`/code 2000 on Android vs `unsupportedInput`/code -11880 on Apple) — not touched here, still open for 03-08.
- **The macOS-host Dart-level `integration_test` CI gap** (documented since 03-04/03-05/03-06, QUESTIONS.md #8) narrowed slightly but did not close: `tool/measure_presets.dart` now runs on the macOS host via native `flutter test -d macos` (no general-purpose Dart integration_test step needed for that specific harness), but `compress_output_test.dart`'s `estimate()`-accuracy suite still only runs on the iOS Simulator in CI, so Apple's real-hardware `estimate()` accuracy is unmeasured from CI specifically (though the preset-level MEASURE table IS measured on real hardware). Whoever next has a reachable Mac, or 03-08 (which owns widening the CI `apple` job), should close this if it matters before shipping.
- **03-08 can proceed** with no unresolved blocker from this plan's own declared scope.

## Self-Check: PASSED

- `darwin/compress_video/Sources/compress_video/Compression.swift` — FOUND (`estimate`, `clearCache` implemented, no `throw ... "not yet implemented"` remains)
- `darwin/compress_video/Sources/compress_video/CompressionEngine.swift` — FOUND (`precomposedStringWithCanonicalMapping` at the `buildResult` reporting site)
- `darwin/compress_video/Sources/compress_video/Thumbnails.swift` — FOUND (`PluginFiles.cacheSubDir()`, `precomposedStringWithCanonicalMapping`)
- `example/integration_test/compress_test.dart` — FOUND (2000-7000ms trim case present, reads `startMs`/`endMs`/`expectedDurationMs`/`toleranceMs` from the sidecar)
- `example/integration_test/compress_output_test.dart` — FOUND (`Platform.isAndroid` guard removed, `ESTIMATE_ACCURACY` print present)
- `doc/PRESETS.md` — FOUND (Apple section with two measured tables, `simulator` and `macOS` both present)
- `corpus/README.md` — FOUND (`small_480p`'s duration delta resolved section, `2992`/`3026` both present)
- `tool/measure_presets_ci.sh` — FOUND, executable
- Commits `ac661bb`, `c431d50`, `d66e2a1`, `3f047c5`, `497dbbe`, `3a6dc75`, `9c5c315`, `2009019`, `d3582aa`, `c77edba` — all FOUND in `git log --oneline`
- CI run 36186455835 — FOUND, conclusion `success` on every job (`gh run view`)

---
*Phase: 03-apple-compression-to-parity*
*Completed: 2026-09-25*
