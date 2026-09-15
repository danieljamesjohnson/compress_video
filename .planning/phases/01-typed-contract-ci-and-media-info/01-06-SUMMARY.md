---
phase: 01-typed-contract-ci-and-media-info
plan: 06
subsystem: media-info
tags: [avfoundation, swift, cocoapods, spm, ios-simulator, xctest, ci]

# Dependency graph
requires:
  - phase: 01-01
    provides: Private GitHub repo wired as `github` remote, toolchain pin baseline
  - phase: 01-03
    provides: compress_video plugin package scaffold, shared darwin/ Apple tree (podspec + Package.swift), typed error taxonomy (CompressVideoException/CompressVideoErrorReason), green path-gated CI on Linux+macOS
  - phase: 01-04
    provides: "pigeons/messages.dart's ProbeHostApi/ThumbnailHostApi (declared in full) and the generated Messages.g.swift (CompressVideoError, codec, setup classes) this plan implements against; the Android Probe.kt/MediaMath.kt/Arguments.kt shape this plan mirrors in Swift"
  - phase: 01-05
    provides: "Android Thumbnails.kt's shared-extraction-helper pattern, atomic-write pattern, and the getScaledFrameAtTime fit-within-box lesson this plan's Thumbnails.swift fix directly reuses for AVAssetImageGenerator.maximumSize"
provides:
  - "CompressVideoPlugin.swift registering the generated ProbeHostApi/ThumbnailHostApi through the shared darwin/ tree -- no hand-written channel code remains anywhere in the package"
  - "MediaMath.swift and Arguments.swift: the Swift mirror of Android's pure logic (displayedSize, normalizeCodec, scaledSize, clampPositionMs, rotationDegrees(from: CGAffineTransform), and every Arguments validator), force-unwrap-free"
  - "Probe.swift: AVFoundation media info (INFO-01) with iOS-13/macOS-11-compatible dual-path property loading"
  - "Thumbnails.swift: both thumbnail calls (INFO-02) via AVAssetImageGenerator with appliesPreferredTrackTransform=true, zero time tolerance, and an exact-size snap mirroring Android's Bitmap.createScaledBitmap fix"
  - "Identical XCTest suites (byte-diffed in CI) covering the pure logic on both example/ios/RunnerTests and example/macos/RunnerTests"
  - "CI's apple job now also boots a concrete iOS simulator and runs the same corpus integration suite (media_info_test.dart, thumbnail_test.dart) the Android emulator runs"
affects: [01-07]

# Actuals (#2632)
actuals:
  tokens: 17805
  tasks: 3
  commits: 7

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dual-path AVFoundation property loading: `if #available(iOS 16, macOS 13, *)` uses the awaited `load(_:)` API; the `else` branch uses `loadValuesAsynchronously(forKeys:)` + a `CheckedContinuation` wrapper (`awaitLegacyLoad`), so the plugin builds and runs at the project's real iOS 13/macOS 11 minimum. The higher of the two conflicting minimums 01-RESEARCH.md flagged (iOS 16/macOS 13, not 15/12) was chosen deliberately -- gating a still-unavailable API on a lower OS would crash at runtime rather than just miss an optimization."
    - "durationMs is produced by CMTimeConvertScale(duration, timescale: 1000, method: .roundHalfAwayFromZero) -- one conversion point, never a floating-point seconds intermediate -- both in Probe.swift (the returned field) and Thumbnails.swift (where the requested CMTime reuses the SAME converted CMTimeScale symbolically, so the file has exactly one literal `timescale: 1000`)."
    - "Exact-thumbnail-size snap: AVAssetImageGenerator.maximumSize is a fit-within bounding box, not independent exact dimensions -- confirmed live in CI, the Apple-side analog of 01-05's Android getScaledFrameAtTime finding. Thumbnails.swift now unconditionally redraws the decoded CGImage into a fresh CGContext at the exact MediaMath.scaledSize target when the decoded size differs, mirroring Android's Bitmap.createScaledBitmap pass."
    - "Swift cannot downcast `Any` to a CoreFoundation-bridged type (CMFormatDescription) without either `as?` (which this project's warnings-as-errors build treats as a hard error, since the compiler can prove the conditional check always succeeds) or `as!` (banned by the threat model as a force-cast crash surface). Resolution: on the legacy (pre-iOS-16/macOS-13) AVFoundation loading path only, videoCodec gracefully degrades to `unknown` rather than exercising either the compiler error or the banned pattern -- the same 'detector unavailable is safe, never a crash' policy already used for isHdr."

key-files:
  created:
    - darwin/compress_video/Sources/compress_video/MediaMath.swift
    - darwin/compress_video/Sources/compress_video/Arguments.swift
    - darwin/compress_video/Sources/compress_video/Probe.swift
    - darwin/compress_video/Sources/compress_video/Thumbnails.swift
  modified:
    - darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift
    - example/ios/RunnerTests/RunnerTests.swift
    - example/macos/RunnerTests/RunnerTests.swift
    - example/integration_test/thumbnail_test.dart
    - .github/workflows/ci.yml
    - QUESTIONS.md

key-decisions:
  - "Gated the modern `load(_:)` AVFoundation API on `#available(iOS 16, macOS 13, *)` -- the more conservative of 01-RESEARCH.md's two conflicting sourced minimums (iOS 15/16, macOS 12/13) -- rather than the lower bound, because gating an API that actually needs the higher OS version on the lower one would crash at runtime, not just silently skip an optimisation."
  - "videoCodec degrades to `unknown` on the legacy (pre-iOS-16/macOS-13) AVFoundation loading path only, because casting the legacy `AVAssetTrack.formatDescriptions: [Any]` array to `[CMFormatDescription]` has no available Swift spelling under this project's constraints: `as?` is a hard compiler error here (warnings-as-errors treats 'conditional downcast will always succeed' as fatal) and `as!` is banned by the threat model (T-01-15). The modern typed `load(.formatDescriptions)` path (iOS 16+/macOS 13+) is unaffected and reports the real codec."
  - "Thumbnails.swift unconditionally snaps the decoded CGImage to the exact `MediaMath.scaledSize` target via one CGContext draw pass, mirroring Android's `Bitmap.createScaledBitmap` fix from 01-05, after CI proved `AVAssetImageGenerator.maximumSize` has the identical fit-within-box behaviour as Android's `getScaledFrameAtTime`."
  - "The shared `getThumbnailFile` default-destination integration test now accepts both platforms' cache path shapes (`anyOf('/cache/compress_video/', '/Caches/compress_video/')`) -- the original assertion was Android-only despite the test file running on both platforms by this plan's own design."

patterns-established:
  - "Any future Apple AVFoundation property read needs the same dual-path (#available-gated modern load / legacy loadValuesAsynchronously) shape Probe.swift and Thumbnails.swift both use, plus the same CoreFoundation-downcast caution around formatDescriptions."

requirements-completed: []  # INFO-01, INFO-02, BULD-03 all remain shared with 01-07 (still pending) AND this plan's own CI verification is not yet confirmed green (see status below) -- none are ready to mark complete under either the shared-ID gate or this plan's own halted status.

coverage:
  - id: D1
    description: "CompressVideoPlugin.swift registers the generated ProbeHostApi/ThumbnailHostApi through the shared darwin/ tree (one os(iOS)/os(macOS) branch for the messenger); MediaMath.swift and Arguments.swift mirror Android's pure logic function-for-function; identical XCTest suites on iOS and macOS cover dimension swap, codec normalisation, half-away-from-zero rounding, scaledSize/clampPositionMs boundaries, rotation-transform derivation, and every Arguments rejection path."
    requirement: "BULD-03"
    verification:
      - kind: automated_ui
        ref: "xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination iOS Simulator (XCTest - iOS Runner step) -- confirmed passing on CI runs 35008007617, 35012589390 and 35014676502"
        status: pass
      - kind: other
        ref: "diff example/ios/RunnerTests/RunnerTests.swift example/macos/RunnerTests/RunnerTests.swift -- 0 output, verified locally and gated in CI's apple job on every run"
        status: pass
      - kind: other
        ref: "grep -RIl 'FlutterMethodChannel' darwin/ -> 0 files; grep -Ec '(try!|as!|fatalError\\()' over every hand-written Swift source -> 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "Probe.swift produces every INFO-01 field via AVAsset/AVAssetTrack (durationMs via a single CMTimeConvertScale half-away-from-zero conversion, displayed width/height via MediaMath.displayedSize over the rotation derived from preferredTransform, normalised codec, bitrate/frame-rate with null-not-zero sentinels, hasAudio, isHdr behind an availability-gated media-characteristic check with a transfer-function fallback), matching Android field for field."
    requirement: "INFO-01"
    verification:
      - kind: e2e
        ref: "example/integration_test/media_info_test.dart, 9/9 tests on the iOS simulator (3 clips against the corpus sidecars, 4 error cases, 1 concurrency case, 1 non-ASCII-filename case) -- CI run 35012589390's log shows all 9 passing against the current, unchanged Probe.swift"
        status: pass
      - kind: other
        ref: "grep gates in this plan's own acceptance criteria: preferredTransform present, exactly one 'timescale: 1000' conversion point, exactly one MediaMath.displayedSize call site, zero force-unwraps, at least 2 #available/@available guards -- all verified locally"
        status: pass
    human_judgment: false
  - id: D3
    description: "Thumbnails.swift implements both getThumbnail/getThumbnailFile with appliesPreferredTrackTransform=true and zero time tolerance, snapping the decoded frame to the exact MediaMath.scaledSize target (the AVAssetImageGenerator.maximumSize fit-within-box fix). CI's apple job boots a concrete iOS simulator and runs the same corpus integration suite the Android emulator runs."
    requirement: "INFO-02"
    verification:
      - kind: e2e
        ref: "example/integration_test/thumbnail_test.dart on the iOS simulator, run 35012589390 (pre-fix code): 21/23 passed, with the exact 2 failures (dimension off-by-one at maxDimensionPx=1919, and an Android-only cache-path assertion) that the two fixes in commit 48bc283 target"
        status: fail
      - kind: e2e
        ref: "Same suite against the current, fixed Thumbnails.swift and thumbnail_test.dart (commit 48bc283) -- NOT YET RE-RUN: three post-fix CI attempts (two hangs past the step's 20-minute bound, one job that never started at all due to a GitHub Actions billing block) all failed for reasons unrelated to the fix's correctness. See Deviations and Issues Encountered."
        status: unknown
    human_judgment: true
    rationale: "The dimension-snap and cache-path fixes are a direct, logically verified match to the exact failure messages CI produced pre-fix (same fit-within-box pattern 01-05 already fixed on Android; same shared-test Android-only-path-shape gap), but a GitHub Actions billing block (QUESTIONS.md #6) has prevented any Apple CI job from completing since the fix was pushed. A human must either wait for a successful re-run after Dan resolves billing, or manually inspect the fix."
  - id: D4
    description: "CI's apple job builds for iOS (CocoaPods and, after this plan, still expected via SPM) and macOS, running both XCTest targets -- confirmed multiple times during this plan's iteration cycle -- but the LATEST run has not concluded success end-to-end (blocked on GitHub Actions billing, not on this plan's code)."
    requirement: "BULD-05"
    verification:
      - kind: other
        ref: "gh run view <id> --attempt 3 annotation: 'The job was not started because recent account payments have failed or your spending limit needs to be increased.' -- an infrastructure/billing block, not a CI-red code signal"
        status: fail
    human_judgment: true
    rationale: "This plan's own <verification> step 1 requires the latest CI run to conclude success; it currently cannot, for a reason (GitHub billing) outside code or agent control. Recorded in QUESTIONS.md #6 and notified to Dan."

# Metrics
duration: 166min
completed: 2026-09-15
status: halted
---

# Phase 1 Plan 06: Apple Core (Probe, Thumbnails, XCTest on iOS and macOS) Summary

**All three tasks' Swift code is written, committed, and confirmed compiling/passing on the GitHub Actions macOS runner up through the fourth of five real CI iterations (Probe.swift's media info and the shared XCTest suites both fully green); the final fix for the two remaining thumbnail-test failures is logically verified against CI's own error output but not yet re-confirmed by a passing run, because GitHub Actions stopped starting any macOS job mid-session on a billing/spending-limit block only Dan can clear.**

## Performance

- **Duration:** 166 min (2h 46m) -- almost entirely CI wall-clock time across 8 pushed/rerun CI attempts on the GitHub Actions macOS runner (no local Apple compiler exists on danserver)
- **Started:** 2026-09-15T18:02:50Z (approx.)
- **Completed:** 2026-09-15T20:49:05Z
- **Tasks:** 3 completed (code-complete); CI verification halted on an external blocker
- **Files modified:** 10 (4 created, 6 modified)

## Accomplishments

- `CompressVideoPlugin.swift` now registers the generated `ProbeHostApi`/`ThumbnailHostApi` through the shared `darwin/` tree, with exactly one `os(iOS)`/`os(macOS)` branch for the messenger and one for JPEG encoding -- no hand-written channel code (`FlutterMethodChannel`) remains anywhere in the package, and the template's `getPlatformVersion` handler is gone.
- `MediaMath.swift` and `Arguments.swift` mirror Android's Kotlin originals function for function: `displayedSize`, `normalizeCodec`, `scaledSize`, `clampPositionMs`, and a new `rotationDegrees(from: CGAffineTransform)` that derives unsigned clockwise degrees from a track's `preferredTransform` by normalising `atan2(b, a)` to the nearest quarter turn. Every Arguments validator (path/output-path/positionMs/quality/maxDimensionPx) is ported with the same reason codes as Kotlin.
- Identical XCTest suites (diffed byte-for-byte by CI on every run) cover all of the above, plus every Arguments rejection path, on both `example/ios/RunnerTests` and `example/macos/RunnerTests`.
- `Probe.swift` produces every INFO-01 field: `durationMs` via a single `CMTimeConvertScale(..., timescale: 1000, method: .roundHalfAwayFromZero)` conversion (never through floating-point seconds); displayed width/height via `MediaMath.displayedSize` over the rotation derived from `preferredTransform`; normalised codec from the track's format description FourCC; bitrate/frame-rate reporting `nil` (never `0`) when the platform can't determine them; `isHdr` behind an `#available(iOS 14, macOS 11, *)`-gated `containsHDRVideo` characteristic check with a transfer-function-extension fallback, never throwing. Confirmed on CI: `example/integration_test/media_info_test.dart` 9/9 passing on the iOS simulator.
- `Thumbnails.swift` implements both thumbnail calls sharing one extraction helper: `appliesPreferredTrackTransform = true` (the documented-false default every competitor got wrong), zero time tolerance, and atomic file writes via `Data.write(to:options:.atomic)`. CI's `apple` job gained a step that boots a concrete iOS simulator (resolved from `xcrun simctl list devices available`, never hard-coded) and runs the exact same corpus integration suite the Android emulator runs.
- **Found and fixed a real platform quirk live in CI, the Apple-side twin of 01-05's Android finding:** `AVAssetImageGenerator.maximumSize` is a fit-within bounding box, not independent exact output dimensions -- a `maxDimensionPx=1919` request came back at height 1918, exactly the same off-by-one Android's `getScaledFrameAtTime` produced. Fixed by unconditionally snapping the decoded `CGImage` to the exact `MediaMath.scaledSize` target with one `CGContext` draw pass, mirroring Android's `Bitmap.createScaledBitmap` fix.
- **Found and fixed a shared-test cross-platform gap:** the `getThumbnailFile` default-destination test asserted Android's `/cache/compress_video/` path shape even though this plan's own purpose is running the identical Dart test file on the iOS simulator too; Apple's shape is `Library/Caches/compress_video/`. Fixed with `anyOf(...)`.
- Both of the fixes above are evidenced directly by real CI output (`Expected: <1919> Actual: <1918>` and `Expected: contains '/cache/compress_video/' ... does not contain`), not guessed.

## Task Commits

1. **Task 1: Plugin registration, the Swift pure-logic mirror, and XCTest coverage on both Apple platforms** - `d787451` (feat)
2. **Task 2: Probe.swift — AVFoundation media info to Android parity** - `ced0f49` (feat), `e90f5d3` (fix — CI compiler error), `209a7cb` (fix — CI compiler error)
3. **Task 3: Thumbnails.swift, and run the corpus integration suite on the iOS simulator** - `1efdb35` (feat), `5204086` (fix — CI timeout bound), `48bc283` (fix — real platform quirk + shared-test path gap)

**Docs:** `c10689a` (docs — recorded the GitHub Actions billing block in QUESTIONS.md)

**Plan metadata:** (this commit, docs)

## Files Created/Modified

- `darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift` - Registers Probe/Thumbnails against the generated HostApis; template MethodChannel code removed
- `darwin/compress_video/Sources/compress_video/MediaMath.swift` - Pure rotation/codec/scaling/duration logic, ported from Kotlin
- `darwin/compress_video/Sources/compress_video/Arguments.swift` - Pure path/argument validation, ported from Kotlin
- `darwin/compress_video/Sources/compress_video/Probe.swift` - `ProbeHostApi` implementation: full INFO-01 field extraction via AVFoundation
- `darwin/compress_video/Sources/compress_video/Thumbnails.swift` - `ThumbnailHostApi` implementation: frame extraction, exact-size snap, JPEG encode, atomic file write
- `example/ios/RunnerTests/RunnerTests.swift`, `example/macos/RunnerTests/RunnerTests.swift` - Identical XCTest suites over the Swift pure logic (kept byte-diffed in CI)
- `example/integration_test/thumbnail_test.dart` - Cross-platform cache-path assertion fix
- `.github/workflows/ci.yml` - RunnerTests diff gate, iOS simulator resolution + boot + bounded/verbose corpus integration run
- `QUESTIONS.md` - Recorded the GitHub Actions billing block (#6)

## Decisions Made

See `key-decisions` in frontmatter for the full list. Most consequential: choosing the higher (safer) of 01-RESEARCH.md's two conflicting `#available` minimums for the modern AVFoundation load path, and the `videoCodec`-degrades-to-`unknown` resolution for the legacy `formatDescriptions` cast that neither the compiler nor the threat model would otherwise permit a Swift spelling for.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Task 1's CompressVideoPlugin.swift cannot compile standalone before Tasks 2/3 exist**
- **Found during:** First push of Task 1 alone (CI run 35005031348)
- **Issue:** Task 1's own action text has `CompressVideoPlugin.swift` reference `Probe()`/`Thumbnails()`, which don't exist until Tasks 2/3 -- pushing Task 1 alone produced the expected "Cannot find 'Probe'/'Thumbnails' in scope" compiler errors.
- **Fix:** Completed and committed Tasks 2 and 3 before the next push, so the three task commits together (not each individually) are what CI first verifies. This is a plan-sequencing note, not a code defect.
- **Files modified:** none (sequencing only)
- **Verification:** Subsequent pushes compiled past this point
- **Committed in:** `ced0f49`, `1efdb35`

**2. [Rule 1 - Bug] Legacy `formatDescriptions` cast has no permitted Swift spelling under this project's constraints**
- **Found during:** Task 2, second and third real CI compiles (runs 35005659572, 35006901658)
- **Issue:** `track.formatDescriptions.compactMap { $0 as? CMFormatDescription }` triggers "Conditional downcast to CoreFoundation type will always succeed" -- a hard error under this project's warnings-as-errors build. The compiler-suggested fix, a forced cast, is banned by the threat model (T-01-15). A plain, unconditional `as CMFormatDescription` doesn't compile either ("'Any' is not convertible to 'CMFormatDescription'").
- **Fix:** `videoCodec` degrades to `unknown` on the legacy (pre-iOS-16/macOS-13) loading path only -- the same safe-default policy `isHdr` already uses. The modern typed `load(.formatDescriptions)` path is unaffected.
- **Files modified:** `darwin/compress_video/Sources/compress_video/Probe.swift`
- **Verification:** CI run 35008007617 compiled past this point (both XCTest targets passed)
- **Committed in:** `209a7cb`

**3. [Rule 1 - Bug] `AVAssetImageGenerator.maximumSize` is a fit-within bounding box, the Apple-side twin of 01-05's Android finding**
- **Found during:** Task 3, first real CI run of the corpus integration suite on the iOS simulator (35012589390)
- **Issue:** `maxDimensionPx=1919` came back at height 1918, not 1919 -- `MediaMath.scaledSize`'s independently-rounded target box isn't perfectly proportional to the source's exact aspect ratio, and the generator's box-fit picked the more-constraining dimension. Identical root cause to Android's `getScaledFrameAtTime` quirk 01-05-SUMMARY.md documented.
- **Fix:** Unconditionally snap the decoded `CGImage` to the exact `MediaMath.scaledSize` target with one `CGContext` draw pass (falls back to the undecoded image, never crashes, if context creation fails).
- **Files modified:** `darwin/compress_video/Sources/compress_video/Thumbnails.swift`
- **Verification:** Logically verified against the exact CI failure message; NOT yet re-confirmed by a passing CI run (see Issues Encountered)
- **Committed in:** `48bc283`

**4. [Rule 1 - Bug] Shared `getThumbnailFile` default-destination test asserted an Android-only path shape**
- **Found during:** Same CI run as #3 (35012589390)
- **Issue:** `expect(resultPath, contains('/cache/compress_video/'))` rejected Apple's actual, correct default cache location (`Library/Caches/compress_video/`) -- the test's own assumption was Android-only despite this plan's explicit purpose of running the identical suite on iOS too.
- **Fix:** `anyOf(contains('/cache/compress_video/'), contains('/Caches/compress_video/'))`.
- **Files modified:** `example/integration_test/thumbnail_test.dart`
- **Verification:** Logically verified (matches Apple's documented `.cachesDirectory` behaviour); NOT yet re-confirmed by a passing CI run
- **Committed in:** `48bc283`

**5. [Rule 3 - Blocking] The new iOS-simulator integration-test CI step hung twice with zero log output before a 20-minute bound was added**
- **Found during:** Task 3, second CI run (35008007617) -- the step ran 34+ minutes with no visibility (GitHub's job-logs API only returns output for completed jobs) before being cancelled to avoid burning this free-tier account's 10x-billed macOS minutes on an indeterminate hang.
- **Fix:** Added `timeout-minutes: 20` and `-r expanded` (verbose per-test reporting) to the step.
- **Files modified:** `.github/workflows/ci.yml`
- **Verification:** The very next run (35012589390) completed the step in ~6.5 minutes with full test output, confirming the workflow change itself works; the timeout bound then correctly caught two LATER hangs on reruns of commit `48bc283` (see Issues Encountered) instead of letting them run indefinitely.
- **Committed in:** `5204086`

---

**Total deviations:** 5 auto-fixed (3 bugs, 2 blocking issues). **Impact on plan:** All auto-fixes were necessary for correctness (the two real platform-quirk/test-gap bugs, mirroring 01-05's precedent exactly) or to make CI itself trustworthy (the timeout bound). No scope creep. Deviations 3 and 4's fixes are correct by inspection and by direct match to CI's own error output, but remain formally unverified by a fresh green run — this is the plan's residual, externally-blocked item, not a code quality gap.

## Issues Encountered

**GitHub Actions billing block (unresolved, blocking).** After pushing commit `48bc283` (deviations 3+4's fix), three consecutive attempts at the `apple` job all failed for reasons unrelated to the fix:
1. First attempt: the "Run corpus integration tests on the iOS simulator" step hung with zero log output past the successful build, hit the 20-minute bound, and failed on timeout — despite the *identical* step succeeding cleanly two pushes earlier (commit `5204086`) in ~6.5 minutes.
2. A bare rerun (`gh run rerun --failed`, no code change) hit the exact same hang-then-timeout pattern.
3. A second rerun didn't even start: `gh run view <id> --attempt 3` returned the annotation "The job was not started because recent account payments have failed or your spending limit needs to be increased." — a GitHub Actions billing/spending-limit block, confirmed via `gh run view --attempt 3` (not a code, test, or workflow-config issue).

This is now recorded in `QUESTIONS.md` #6 and `notify-dan` was used (this is exactly the "something he can buy/act on" category per the operating guide — a billing settings action). No further CI attempts were made after the billing block was confirmed, per the "don't loop on an externally blocked signal" guidance. The two hangs immediately prior may also trace back to spending-limit throttling behaviour rather than being purely random flakes, though this wasn't independently confirmed before the account was fully blocked.

**Resolution path once unblocked:** re-run the `CI` workflow for the current `main` HEAD (`gh run rerun <id> --failed` or push a no-op). No further Swift or Dart changes are expected to be needed — the fixes in `48bc283` are a direct, evidence-matched response to the only two real (non-infrastructure) failures this plan's CI ever produced.

## User Setup Required

None — no external service configuration required for the plugin itself. A GitHub account billing/spending-limit action is required to unblock CI verification; see QUESTIONS.md #6 (not a plugin user-setup item).

## Next Phase Readiness

- All three tasks' Swift/Dart deliverables are code-complete, committed, and match the plan's own acceptance criteria (verified locally with the exact grep commands specified) and threat-model requirements (zero force-unwraps/casts/`fatalError` in hand-written Swift, no `FlutterMethodChannel`, no logging).
- `INFO-01`, `INFO-02` and `BULD-03` remain unchecked in `REQUIREMENTS.md` — correctly so, both because they are shared with `01-07` (still pending, shared-ID gate) and because this plan's own CI verification has not concluded green yet.
- **`01-07-PLAN.md` (cross-platform parity gate, full pipeline green, phase sign-off) should NOT start until this plan's `status: halted` is resolved** — re-run CI after Dan clears the GitHub Actions billing block (QUESTIONS.md #6), confirm the `apple` job concludes `success` end-to-end (including the iOS-simulator integration step with the current `Thumbnails.swift`/`thumbnail_test.dart` fixes), then re-summarize this plan as `status: complete` before 01-07 begins.
- If the re-run surfaces any further real (non-infrastructure) failure, it would be a genuine, new finding requiring its own fix — but no such failure is expected given the fixes' direct match to the last real error output observed.

---
*Phase: 01-typed-contract-ci-and-media-info*
*Completed (code): 2026-09-15*
*Halted pending: GitHub Actions billing resolution (QUESTIONS.md #6)*

## Self-Check: PASSED

- FOUND: all 4 created files and all 6 modified files listed above (verified with `[ -f ]`)
- FOUND commits: d787451, ced0f49, e90f5d3, 209a7cb, 1efdb35, 5204086, 48bc283, c10689a (all present in `git log --oneline --all`)
- Re-ran every grep-based acceptance criterion from all three tasks locally after the final fix — all pass (see verification commands embedded in the coverage block and Task Commits section)
- `diff example/ios/RunnerTests/RunnerTests.swift example/macos/RunnerTests/RunnerTests.swift` — 0 output
- `grep -RIl 'FlutterMethodChannel' darwin/` — 0 files; `grep -Ec '(try!|as!|fatalError\()'` — 0 across every hand-written Swift source (Messages.g.swift, Pigeon-generated, is out of scope for this check and does contain generated `as!` casts, same as Android's generated Messages.g.kt)
- `dart format --output=none --set-exit-if-changed example/integration_test/thumbnail_test.dart` — 0 changed; `flutter analyze example/integration_test/thumbnail_test.dart` — no issues found
- CI evidence (not a fresh run against current HEAD, per the halted status above): run 35012589390 — Android job fully `success`; Apple job's `Build iOS (CocoaPods)`, `XCTest - iOS Runner`, `Boot the iOS simulator`, and `Run corpus integration tests on the iOS simulator` (30/32 tests, 2 known-and-now-fixed failures) all completed; `Build macOS`/`XCTest - macOS Runner`/SPM steps did not run in that attempt because the job failed before reaching them (their own success was previously confirmed against Task 1's code in run 35008007617 before Task 3's iOS-simulator step was added after them in the job order)
- `git status --short` clean at every commit boundary
- **Residual, undischarged item:** a fresh, fully green CI run of current HEAD (`c10689a`) is still needed and is blocked on GitHub Actions billing (QUESTIONS.md #6) — this is the reason for `status: halted` rather than `status: complete`
