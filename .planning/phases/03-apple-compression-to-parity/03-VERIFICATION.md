---
phase: 03-apple-compression-to-parity
verified: 2026-09-26T03:02:08Z
status: gaps_found
score: 2/4 must-haves verified (2 partially verified — see gaps)
behavior_unverified: 0
overrides_applied: 0
gaps:
  - truth: "A fresh Flutter app adds the plugin and builds for iOS and macOS with CocoaPods and, separately, with Swift Package Manager (ROADMAP success criterion 3)."
    status: partial
    reason: "tool/verify_fresh_app.sh — the script 03-08-PLAN.md declared as the literal proof artifact for this criterion — was never written. 03-08 task 1's own plan-declared precondition (`bash tool/mac_sync.sh && bash tool/mac_run.sh build-macos` exits 0) has never been met because the MacBook Air has been unreachable on the tailnet throughout 03-01, 03-08 and 03-09 (QUESTIONS.md #8). Nothing was written or committed for this deliverable. REQUIREMENTS.md marks BULD-02 'Complete' anyway, on narrower substitute evidence (CI's own CocoaPods/SPM builds of the already-configured example app, not a throwaway app that newly adds the plugin as a dependency) — that substitution is explicitly disclosed in 03-09-SUMMARY.md's Deviations, so it is not a hidden gap, but it does not satisfy the roadmap criterion's literal wording."
    artifacts:
      - path: "tool/verify_fresh_app.sh"
        issue: "MISSING — file does not exist anywhere in the repository (confirmed by `find . -iname verify_fresh_app*` returning nothing)"
    missing:
      - "Write tool/verify_fresh_app.sh per 03-08-PLAN.md task 1's action/acceptance criteria (throwaway app in a temp dir, path dependency on this repo, four builds: iOS+macOS x CocoaPods+SPM, cleans up on every exit path, restores the global SPM setting, never writes inside this repo)."
      - "Prove its SPM half on the Mac via `bash tool/mac_sync.sh && bash tool/mac_run.sh build-ios && bash tool/mac_run.sh build-macos` (closes 03-01 task 1's last acceptance criterion first) then `bash tool/mac_run.sh shell 'bash tool/verify_fresh_app.sh --spm-only'` (03-08 task 1's own verify command)."
      - "Wire the CocoaPods half into CI (03-08 task 2 already scoped this) so the script runs on every push, then re-run CI once to observe it green."
  - truth: "The example app runs on Android, iOS and macOS — a user picks a video, sets options, watches live progress, can cancel, and plays the compressed result (ROADMAP success criterion 4 / BULD-04)."
    status: partial
    reason: "Verified on Android only: the app was driven live on the emulator with real screenshots committed (.planning/phases/03-apple-compression-to-parity/screenshots/{01_launch,03_compressing,04_result,05_playing}.png, confirmed by opening 03_compressing.png — it shows the real tracer UI mid-compress with a 39% progress bar and Cancel button). On iOS and macOS the underlying engine behaviors (progress, cancel, playback-producing output) are proven only through automated `integration_test` suites driving `CompressVideo.compress()` directly, never through the example app's own UI. 03-09 task 1 — the plan's own dedicated manual walkthrough — did not execute: no ios-simulator-result.png or macos-result.png exists (the two artifacts 03-09-PLAN.md's frontmatter declares), 02-UAT.md item 6 is still `[pending]`, not resolved. Blocked on the same Mac-unreachable condition as the item above (QUESTIONS.md #8, probed and timed out again specifically for this task on 2026-09-25)."
    artifacts:
      - path: ".planning/phases/03-apple-compression-to-parity/ios-simulator-result.png"
        issue: "MISSING — declared as a 03-09-PLAN.md artifact, never created"
      - path: ".planning/phases/03-apple-compression-to-parity/macos-result.png"
        issue: "MISSING — declared as a 03-09-PLAN.md artifact, never created"
    missing:
      - "Once the Mac is reachable: `bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test/compress_test.dart` (03-09 task 1's own stated precondition), then drive the example app by hand on the booted iOS simulator and on the macOS host through pick → options → estimate → compress → live progress → cancel → compress again → result card → playback, capture screenshots of the compressing and done states on each platform, commit them into this phase directory, and update 02-UAT.md item 6 to resolved with a reference to the committed files."
deferred: []
human_verification:
  - test: "Wake/attach the MacBook Air (open the lid, or plug it into power with 'Prevent automatic sleeping on power adapter' on) so `ssh dans-macbook-air` succeeds, then run `bash tool/mac_sync.sh && bash tool/mac_run.sh build-ios && bash tool/mac_run.sh build-macos` followed by writing and running `tool/verify_fresh_app.sh` per 03-08-PLAN.md task 1."
    expected: "Four builds (iOS+macOS x CocoaPods+SPM) of a throwaway app that only depends on this plugin by path all succeed, closing ROADMAP success criterion 3 and giving BULD-02 the literal fresh-app evidence its acceptance criteria call for."
    why_human: "Requires physical access to the MacBook Air (it is asleep/offline on the tailnet and has no remote wake mechanism) — an agent cannot restore its network reachability."
  - test: "With the Mac reachable, drive the example app by hand on the iOS simulator and on the macOS host through the full pick/options/estimate/compress/progress/cancel/result/playback flow, per 03-09-PLAN.md task 1."
    expected: "Two screenshots (compressing state, done state) committed per platform, 02-UAT.md item 6 marked resolved referencing them, closing BULD-04's Apple half."
    why_human: "Visual/interactive confirmation that the shared Dart UI actually renders and behaves correctly inside a real iOS/macOS window — no automated assertion substitutes for looking at the rendered screen, and it requires the same physical Mac access as the item above."
---

# Phase 3: Apple Compression to Parity Verification Report

**Phase Goal:** The same Dart call gives the same observable result on iOS and macOS as on Android, installs through CocoaPods or SPM, and trims exactly on every platform.
**Verified:** 2026-09-26T03:02:08Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | On iOS simulator and macOS, the portrait corpus clip compresses to a smaller, upright H.264/AAC MP4; presets, explicit targets, never-larger, transmux, audio options, typed errors, per-job progress and cancel behave as on Android; the same corpus integration tests pass on all three platforms | ✓ VERIFIED | CI run 36207227343 (2026-09-26, fully green): Android job success, Apple job success (iOS CocoaPods build, native XCTest iOS+macOS, iOS-simulator corpus integration suites, macOS-host corpus integration suites, both SPM builds), Cross-platform parity job success (Android-vs-iOS and macOS-vs-iOS both diffed real `PARITY_JSON` records, not stubs — confirmed by reading `tool/check_parity.sh`'s compression-record comparator and its 6-fixture self-test). Locally re-confirmed 2026-09-26: `flutter analyze --fatal-infos --fatal-warnings` clean, `flutter test` 84/84, `bash corpus/verify_corpus.sh` exit 0 (no drift across 5 sidecars), `bash tool/check_parity_test.sh` 10/10 self-test cases pass in both directions. |
| 2 | A trim from 2000 ms to 7000 ms produces an output 5 s long, within one frame, on Android, iOS and macOS | ✓ VERIFIED | `trim_source_10s.mp4`/`.expected.json` exist and verify clean (`corpus/verify_corpus.sh`). `compress_test.dart`'s trim case (lines 1050-1090) reads `startMs`/`endMs`/`expectedDurationMs`/`toleranceMs` from the sidecar with no hardcoded literals (confirmed by reading the case; no platform skip guard on it), and runs unmodified across all three platforms via the shared integration-test suite. iOS: CI run 36186455835 measured 13 ms delta against a 34 ms tolerance (03-07-SUMMARY.md). macOS: exercised by CI run 36207227343's "Run corpus integration tests on macOS" step (same suite, same case, job success). Android: covered by the same suite on `emulator-5554`, 80/80 cases passed per STATE.md's 2026-09-26 local sweep. |
| 3 | A fresh Flutter app adds the plugin and builds for iOS and macOS with CocoaPods and, separately, with Swift Package Manager. iOS and macOS use one shared Swift core | ✗ PARTIAL — see gap | Shared-core half is genuinely verified: `example/ios/RunnerTests/RunnerTests.swift` and `example/macos/RunnerTests/RunnerTests.swift` are byte-identical (`diff` exits 0), and the entire engine (`CompressionEngine.swift` 963 lines, `SizeGuard.swift`, `ErrorMapping.swift`, `PluginFiles.swift`, `Compression.swift`, `JobRegistry.swift`) lives once under `darwin/compress_video/Sources/compress_video/` shared by both platform targets. The "fresh app" half is not: `tool/verify_fresh_app.sh` (the plan's own declared proof artifact) does not exist in the repo. CocoaPods/SPM installability is instead evidenced only by CI building the pre-existing, already-configured example app (CI run 36207227343: `Build iOS (CocoaPods)`, `Build macOS`, `Build iOS via Swift Package Manager`, `Build macOS via Swift Package Manager`, all success) — real evidence that the podspec/Package.swift resolve correctly, but not the stronger "a fresh app that knows nothing about this repo" proof the roadmap criterion and 03-08-PLAN.md both specify. |
| 4 | The example app runs on Android, iOS and macOS: pick a video, set options, watch live progress, cancel, play the compressed result | ✗ PARTIAL — see gap | Android: fully verified — `screenshots/03_compressing.png` (read directly) shows the real tracer app mid-compress (39%, Cancel button, real filename/byte count/preset line), `screenshots/04_result.png` and `05_playing.png` exist alongside it, all from a live emulator run (03-03-SUMMARY.md, commit `9be3a86`). Widget suite (84/84 local) exercises the same screen logic on every platform's Dart code. iOS/macOS: the underlying compress/progress/cancel/playback-producing behaviors are proven only via headless `integration_test` suites calling `CompressVideo.compress()` directly (not through the example app UI) — CI run 36207227343. No manual walkthrough of the example app's own UI on iOS or macOS was ever performed: `ios-simulator-result.png`/`macos-result.png` (the artifacts 03-09-PLAN.md declares) do not exist, and `02-UAT.md` item 6 is still `[pending]`. |

**Score:** 2/4 roadmap success criteria fully verified; 2/4 partially verified with the remaining gap isolated to a single, already-tracked external blocker (see below).

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|---|---|---|---|---|
| CORE-01 | 03-04, 03-05, 03-06, 03-07, 03-08, 03-09 | Same Dart API, same observable behaviour, on Android/iOS/macOS | ✓ SATISFIED | REQUIREMENTS.md marks Complete; CI run 36207227343 (Android/Apple/parity all success) is the cited evidence and is confirmed current above. |
| CORE-07 | 03-01, 03-07, 03-08, 03-09 | Trim within one frame on every platform | ✓ SATISFIED | REQUIREMENTS.md marks Complete; trim truth #2 above independently verified. |
| BULD-02 | 03-01, 03-08, 03-09 | iOS/macOS share one Swift core; installs through CocoaPods and SPM | ⚠️ SATISFIED ON NARROWER EVIDENCE THAN ROADMAP SC3 | REQUIREMENTS.md marks Complete on CI's build of the existing example app under both install paths (real, not stubbed) — a legitimate but weaker proof than the "fresh app" script the phase's own plan and ROADMAP success criterion 3 call for. Not a hidden gap: 03-09-SUMMARY.md's Deviations section discloses exactly this substitution. Recommend leaving REQUIREMENTS.md as-is (the requirement's own text does not say "fresh app") but keeping ROADMAP SC3 open until `tool/verify_fresh_app.sh` exists and runs, per the gap above. |
| BULD-04 | 03-03, 03-09 | Example app: pick/options/progress/cancel/play, on all three platforms | ✗ CORRECTLY LEFT PENDING | REQUIREMENTS.md marks Pending — consistent with the truth-4 finding above (Android proven, Apple not). This is the one row where the project's own bookkeeping already matches this verification's finding exactly. |

No orphaned requirements: all four of this phase's declared IDs (CORE-01, CORE-07, BULD-02, BULD-04) are covered by at least one plan's `requirements:` frontmatter field, cross-checked against REQUIREMENTS.md's Phase 3 mapping.

### Required Artifacts (representative sample — full list is 03-VALIDATION.md's 27-row map)

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `darwin/compress_video/Sources/compress_video/CompressionEngine.swift` | AVAssetReader/Writer copy loop, transmux branch, never-larger, audio modes, progress, cancel, free-space check | ✓ VERIFIED | 963 lines; `moveIntoPlace`, `onProgress`, `ErrorMapping.reasonForAVError`, `audioReencoded`, `AVAssetExportSession`/`AVAssetExportPresetPassthrough` all present and wired (grepped directly); no `VideoComposition` construction (only a comment referencing the prohibition) |
| `darwin/compress_video/Sources/compress_video/SizeGuard.swift` | Pure plan resolver, no AVFoundation import | ✓ VERIFIED | 319 lines; `wouldTransmux` present |
| `darwin/compress_video/Sources/compress_video/ErrorMapping.swift` | AVError/NSError → typed reason table | ✓ VERIFIED | 115 lines; `decoderNotFound` present |
| `darwin/compress_video/Sources/compress_video/PluginFiles.swift` | Cache resolution, containment-checked sweep | ✓ VERIFIED | 154 lines; `sweep` present |
| `darwin/compress_video/Sources/compress_video/Compression.swift` | CompressHostApi impl: startCompress, estimate, clearCache, free-space pre-check | ✓ VERIFIED | 214 lines; `startCompress`, `clearCache` present |
| `darwin/compress_video/Sources/compress_video/JobRegistry.swift` | Main-queue-confined job map | ✓ VERIFIED | 101 lines |
| `tool/mac_sync.sh` / `tool/mac_run.sh` | Mac build-host workflow | ✓ VERIFIED | Both exist and are the mechanism every CI-substituted Apple verification in this phase's summaries points back to |
| `tool/verify_fresh_app.sh` | BULD-02's four-build fresh-app proof | ✗ MISSING | Does not exist anywhere in the repo — see gap above |
| `.planning/phases/03-apple-compression-to-parity/ios-simulator-result.png` | Visual proof, iOS done state | ✗ MISSING | See gap above |
| `.planning/phases/03-apple-compression-to-parity/macos-result.png` | Visual proof, macOS done state | ✗ MISSING | See gap above |
| `example/ios/RunnerTests/RunnerTests.swift` / `example/macos/.../RunnerTests.swift` | Byte-identical XCTest twins | ✓ VERIFIED | `diff` exits 0 |

### Key Link Verification

| From | To | Via | Status |
|---|---|---|---|
| `example/integration_test/compress_*_test.dart` (all 4 suites) | `tool/check_parity.sh` | `PARITY_JSON` compression records, real `jq`-driven comparison with documented tolerance envelopes | ✓ WIRED — confirmed by reading `tool/check_parity.sh`'s compression-record branch and its self-test (10/10 passing locally) |
| `CompressionEngine.swift` | `PluginFiles.swift` | `moveIntoPlace` on both the success path and the never-larger substitution path | ✓ WIRED |
| `CompressionEngine.swift` | `Messages.g.swift` | `onProgress` dispatched at lines 130/419/468, clamped 0-99 with a single terminal 100 | ✓ WIRED |
| `CompressionEngine.swift` | `ErrorMapping.swift` | `ErrorMapping.reasonForAVError`/`reasonForNSError`/`messageForNSError` at the failure-construction sites | ✓ WIRED |
| `example/lib` UI (options panel, progress section, result card) | `CompressVideo.compress()` | Direct call through the shared Dart widget tree (03-03) | ✓ WIRED on Android (live-driven); code-identical on iOS/macOS but never manually exercised there (see gap 4) |

### Behavioral Spot-Checks (run locally, 2026-09-26)

| Behavior | Command | Result | Status |
|---|---|---|---|
| Static analysis clean | `flutter analyze --fatal-infos --fatal-warnings` | "No issues found!" | ✓ PASS |
| Full Dart unit suite | `flutter test` | 84/84 passed | ✓ PASS |
| Corpus has not drifted (5 sidecars incl. new trim clip) | `bash corpus/verify_corpus.sh` | All 5 OK, exit 0 | ✓ PASS |
| Parity gate self-test (both directions, incl. compression fields) | `bash tool/check_parity_test.sh` | 10/10 PASS lines, "check_parity.sh self-test: PASSED" | ✓ PASS |
| No debt markers in phase-touched Swift/Dart/Kotlin source | `grep -rn -E "TBD\|FIXME\|XXX\|TODO\|HACK\|PLACEHOLDER"` over `darwin/`, `example/lib`, `example/integration_test`, `android/src/main` | No matches | ✓ PASS |
| CI run 36207227343 (cited in 03-09-SUMMARY.md as sign-off evidence) | `gh run view 36207227343 --json status,conclusion,jobs` | All 4 jobs `success` (Detect Apple-relevant changes, Android, Apple, Cross-platform parity) | ✓ PASS — independently re-confirmed, not taken on the summary's word |
| CI run 36212964031 (validates the 3 post-review-fix commits bb8968c/cf218ac/1def170) | `gh run view 36212964031 --json status,conclusion,jobs` | `in_progress` at verification time (Android emulator step and iOS XCTest step both mid-run) | ⧗ PENDING — not a failure, simply not yet concluded; record as outstanding evidence, do not block on it per the task brief |

### Anti-Patterns Found

None. No `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` markers, no stub returns (`return null`/`{}`/`[]` unbacked by real logic), no swallowed errors (`print`/`NSLog`/`os_log` count is 0 in the Swift engine, confirmed by the same grep the plan's own prohibition specifies) found in any file this phase touched.

### Deferred Items

None — both open items are this phase's own, not deferred to a later phase (BULD-04's Apple half and ROADMAP SC3's fresh-app proof are exclusively this phase's responsibility; no later phase in ROADMAP.md claims them).

### Human Verification Required

See frontmatter `human_verification`. Both items reduce to one root cause — the MacBook Air (`dans-macbook-air`) being asleep/unreachable on the tailnet — tracked at length in `QUESTIONS.md` #8 with exact resume commands recorded there by the executor at each of the three points it was blocked (03-01, 03-08, 03-09). This is not a new finding; it is this verification independently confirming that the STATE.md "Deferred Items" bookkeeping is accurate and that the two named artifacts genuinely do not exist.

### Gaps Summary

Phase 3's actual engine work is complete and well-verified: the Apple compression engine (transmux, never-larger, three audio modes, trim, progress, cancel, typed errors, free-space pre-check, estimate/clearCache) is implemented once in shared Swift, proven via real corpus integration tests on both the iOS simulator and the macOS host in CI, and cross-checked against Android through a real, non-stubbed parity gate (independently re-run locally, 10/10 self-test cases passing). Code review found 3 issues (CR-01, WR-01, WR-02) and all 3 are fixed and pushed; a validating CI run (36212964031) was in progress at verification time.

The two remaining gaps are narrow, well-isolated, and already known to the project: (1) `tool/verify_fresh_app.sh`, the literal proof artifact for ROADMAP success criterion 3, was never written because its own precondition (a proven Mac build-host round-trip) never became true; (2) the manual Apple example-app walkthrough (ROADMAP success criterion 4's Apple half, BULD-04) never ran for the same reason. Both are blocked purely on the MacBook Air being reachable — not on any code defect — and both have an exact, previously-recorded resume command. Neither should be mistaken for a hidden or newly-discovered gap: STATE.md, 03-VALIDATION.md and QUESTIONS.md #8 already document all of this candidly. This verification's job is to confirm that documentation is accurate rather than aspirational, which it is.

---

_Verified: 2026-09-26T03:02:08Z_
_Verifier: Claude (gsd-verifier)_
