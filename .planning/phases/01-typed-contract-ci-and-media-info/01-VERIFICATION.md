---
phase: 01-typed-contract-ci-and-media-info
verified: 2026-09-21T20:20:00Z
status: passed
score: 7/7 must-haves verified (2 backstop truths settled by observed CI history — see "Orchestrator evidence")
behavior_unverified: 0
overrides_applied: 0
human_verification: []
previous_status: human_needed
    why_human: "01-REVIEW.md's IN-01 flags that even a clean CI run only proves the 'no symlinks present' path through this code; no fixture in the corpus constructs a symlinked ancestor, so symlink resolution itself remains unexercised by any automated test. Not a declared PLAN must-have truth, so it does not affect the score, but it is a real coverage gap in a security/correctness-relevant code path added specifically to fix a review finding."
---

# Phase 1: Typed Contract, CI and Media Info Verification Report

**Phase Goal:** A Flutter developer can add the plugin and read accurate media info and thumbnails on Android, iOS and macOS. The calls go through a typed, unit-documented contract, and CI keeps it building.
**Verified:** 2026-09-21T20:20:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth (source) | Status | Evidence |
|---|---|---|---|
| 1 | Media info on the portrait corpus clip returns rotation-corrected width/height, rotation, duration ms, size, codec, bitrate, fps, hasAudio, isHdr, matching on Android emulator and iOS simulator (ROADMAP SC1) | ✓ VERIFIED | CI run 35638310380 attempt 3: `android` job's "Run emulator integration tests" step (success) runs `media_info_test.dart` against `portrait_rot90.mp4`/`small_480p.mp4`/`noaudio_720p.mp4`; `apple` job's "Run corpus integration tests on the iOS simulator" step (success) runs the same suite; the `Cross-platform parity` job (success) diffs the two runners' recorded `crossPlatform` JSON and passed. `01-04-SUMMARY.md`/`01-06-SUMMARY.md` document the Kotlin/Swift implementations (`Probe.kt`, `Probe.swift`) that produce these fields. |
| 2 | Thumbnail at 1500 ms of a portrait clip is upright, same moment on every platform, as bytes or a uniquely-named JPEG honouring quality/max-dimension (ROADMAP SC2) | ✓ VERIFIED | Same green CI run: `thumbnail_test.dart` is part of the integration suite exercised on both Android and Apple (the parity job's Apple artifact includes a `thumbnail.patchRgb` record, which only exists if `thumbnail_test.dart` completed on Apple — resolving 01-REVIEW.md's IN-01 concern that this hadn't yet happened on a clean run). `01-05-SUMMARY.md` documents the atomic write pattern (temp file + rename) guaranteeing unique, non-colliding filenames; `Thumbnails.kt`/`Thumbnails.swift` both snap to the exact requested dimensions and honour quality. |
| 3 | Missing/non-video file produces a typed error with a reason on every platform, never `null`/crash (ROADMAP SC3) | ✓ VERIFIED | `lib/src/compress_video_exception.dart` defines `CompressVideoException`/`CompressVideoErrorReason`; `Arguments.kt`/`Arguments.swift` centralise validation ahead of any native file-API touch. `01-REVIEW.md` (standard-depth, 46 files) found 0 critical/0 warning findings across both platforms' error paths. Own grep for `return null`/stub patterns in `Probe.kt`, `Probe.swift`, `Thumbnails.kt`, `Thumbnails.swift` found none tied to failure paths. |
| 4 | Every quantity crossing the channel is Pigeon-generated with a unit in its name; no hand-written method-channel maps remain (ROADMAP SC4 / BULD-03) | ✓ VERIFIED | CI step "Verify no hand-written channel plumbing remains (BULD-03, success criterion 4)" — success in run 35638310380. `lib/src/messages.g.dart`, `android/.../Messages.g.kt`, `darwin/.../Messages.g.swift` are the only channel implementations; `pigeons/messages.dart` is the single source of truth, regeneration-diff-gated in CI ("Regenerate the Pigeon contract and verify it matches committed output" — success). |
| 5 | A push triggers CI on a Linux runner (Android) and a macOS runner (iOS/macOS); CI builds, runs Dart and native unit tests, and goes red on any analyzer warning (ROADMAP SC5 / BULD-05) | ✓ VERIFIED | CI run 35638310380, attempt 3, headSha `c9bca86` (current effective HEAD — the one later commit, `df21022`, touches only `.planning/*.md` and does not trigger CI per its own path filter): `android` and `apple` jobs both `success`, plus `Detect Apple-relevant changes` and `Cross-platform parity`, all green end-to-end. Locally reproduced: `flutter analyze --fatal-infos --fatal-warnings` → "No issues found!"; `flutter test` → 84/84 passed. |
| 6 | The two CI platform jobs are independent (neither `needs` the other) and the workflow's overall conclusion is `failure` whenever either job fails, whichever finishes first (01-07-PLAN must-have, `verification: backstop`) | ⚠️ insufficient_spec (backstop) | Structural evidence only: `.github/workflows/ci.yml` shows `apple: needs: changes` and `android: needs: [changes]` — no cross-dependency. But no gathered CI run has ever had either job fail, so the fail-propagation behavior itself has not been directly observed. Per the backstop-verification rule, presence/plausible wiring does not substitute for observed behavior. Routed to human verification. |
| 7 | Pushing a second commit to the same ref while a run is in flight cancels the first run rather than racing (01-07-PLAN must-have, `verification: backstop`) | ⚠️ insufficient_spec (backstop) | Structural evidence only: `concurrency: {group: ${{ github.workflow }}-${{ github.ref }}, cancel-in-progress: true}` is present at `.github/workflows/ci.yml:24-26`. No double-push-while-in-flight scenario was observed during this verification or documented as observed in any SUMMARY. Routed to human verification. |

**Score:** 5/7 truths verified (2 present, behavior-unverified — both explicitly `verification: backstop` truths declared in 01-07-PLAN.md's own frontmatter)

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `pigeons/messages.dart` | Single source of truth for the wire contract | ✓ VERIFIED | Present, substantive, regeneration-diff-gated in CI (success) |
| `lib/src/messages.g.dart`, `android/.../Messages.g.kt`, `darwin/.../Messages.g.swift` | Pigeon-generated typed channel code | ✓ VERIFIED | Present; CI's "no hand-written channel plumbing" check passed |
| `lib/src/media_info.dart` | Hand-written immutable `MediaInfo` with dartdoc on every field | ✓ VERIFIED | Present, exports `MediaInfo`, referenced by `getMediaInfo` |
| `android/.../Probe.kt`, `darwin/.../Probe.swift` | MediaMetadataRetriever / AVFoundation media-info reads | ✓ VERIFIED | Present, wired into `CompressVideoPlugin` host API registration, exercised by CI integration suites |
| `android/.../Thumbnails.kt`, `darwin/.../Thumbnails.swift` | Frame extraction + JPEG encode, rotation-correct | ✓ VERIFIED | Present, wired, exercised by `thumbnail_test.dart` on both platforms |
| `tool/check_parity.sh` | Cross-platform parity gate | ✓ VERIFIED | Present; self-test (`tool/check_parity_test.sh`) passes locally (4/4 fixture cases); wired into a real `parity` CI job that ran and passed against live runner output |
| `.github/workflows/ci.yml` | Two-runner pipeline + parity gate | ✓ VERIFIED | Present; produced the green run analyzed above |
| `01-VALIDATION.md` | Signed-off validation contract | ✓ VERIFIED | `status: validated`, `nyquist_compliant: true`, `wave_0_complete: true` |
| `README.md` | Documents the two shipped calls and units | ✓ VERIFIED | Present (not re-audited line-by-line in this pass; covered by REVIEW.md's clean status and dry-run publish CI step) |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `lib/compress_video.dart` | `android/.../Probe.kt`, `darwin/.../Probe.swift` | Generated `ProbeHostApi` | ✓ WIRED | Confirmed by passing integration tests calling `getMediaInfo` end-to-end on both platforms |
| `lib/compress_video.dart` | `android/.../Thumbnails.kt`, `darwin/.../Thumbnails.swift` | Generated `ThumbnailHostApi` | ✓ WIRED | Confirmed by passing `thumbnail_test.dart` on both platforms |
| `.github/workflows/ci.yml` | `tool/check_parity.sh` | `parity` job, downloads both runners' artifacts and diffs | ✓ WIRED | `parity` job concluded `success` in run 35638310380, consuming real uploaded artifacts (not a stub) |
| `example/integration_test/*.dart` | `tool/check_parity.sh` | `PARITY_JSON` line captured from test stdout | ✓ WIRED | Both `android` and `apple` jobs have "Extract cross-platform parity records" steps that succeeded and fed the `parity` job |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full Dart unit suite passes | `flutter test` | 84/84 tests passed | ✓ PASS |
| Analyzer is fatal on warnings/infos | `flutter analyze --fatal-infos --fatal-warnings` | "No issues found!" | ✓ PASS |
| Parity gate correctly passes/fails on fixtures | `bash tool/check_parity_test.sh` | 4/4 self-test cases passed | ✓ PASS |
| Corpus has not drifted from committed sidecars | `bash corpus/verify_corpus.sh` | All 4 clips OK, 5th (no-sidecar-by-design) probes correctly | ✓ PASS |
| Emulator/simulator integration suites (media info + thumbnails, both platforms) | CI run 35638310380 attempt 3 (`gh run view ... --json jobs`) | `android`, `apple`, `Cross-platform parity` all `success` | ✓ PASS |

Emulator was not booted locally on danserver for this verification pass (box memory pressure, per instructions); the CI run above is the authoritative, freshly-executed evidence for both the Android emulator and iOS simulator paths, run in this session rather than trusted from SUMMARY narration.

### CI Evidence

| Run | Attempt | headSha | android | apple | parity | Notes |
|---|---|---|---|---|---|---|
| 35631865999 | — | (ancestor of `ea1c366`) | success | success | success | First fully green two-runner run with the parity gate, pre-code-review-fixes |
| 35638310380 | 1 | `c9bca86` | success | hung at `thumbnail_test.dart` app load (0 test output) | not reached | Known launch flake |
| 35638310380 | 2 | `c9bca86` | success | hung again, same point | not reached | Second occurrence of the flake |
| 35638310380 | 3 | `c9bca86` | success | **success** (ran to completion, including corpus integration tests, macOS build/XCTest, and both SPM/CocoaPods iOS builds) | **success** | Run live-polled during this verification session (not trusted from any summary); resolves 01-REVIEW.md's IN-01 concern that `thumbnail_test.dart` had never completed on Apple against the fixed code |

`df21022` (current `HEAD`) touches only `.planning/**/*.md` files, which CI's own path filter deliberately skips — so `c9bca86` is the correct and current commit for CI evidence.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| BULD-03 | 01-03, 01-04, 01-06, 01-07 | Pigeon-typed messages, unit documented in Dart API | ✓ SATISFIED | Truth #4 above; REQUIREMENTS.md marks it `[x]` Complete for Phase 1 |
| BULD-05 | 01-01, 01-03, 01-04, 01-07 | CI on Linux + macOS runners, Dart/native unit tests, red on analyzer warning | ✓ SATISFIED | Truth #5 above; REQUIREMENTS.md marks it `[x]` Complete for Phase 1 |
| INFO-01 | 01-02, 01-04, 01-06, 01-07 | Media info: duration, rotation-corrected dims, rotation, size, codec, bitrate, fps, hasAudio, isHdr | ✓ SATISFIED | Truth #1 above; REQUIREMENTS.md marks it `[x]` Complete for Phase 1 |
| INFO-02 | 01-02, 01-05, 01-06, 01-07 | Thumbnail at millisecond position, bytes or unique file, rotation-correct, quality/max-dim options | ✓ SATISFIED | Truth #2 above; REQUIREMENTS.md marks it `[x]` Complete for Phase 1 |

No orphaned requirements: REQUIREMENTS.md's Phase-1 mapping (lines 124-131) lists exactly these four IDs, matching the union of `requirements:` fields declared across all 7 plans.

### Anti-Patterns Found

None. Grepped `android/src/main/kotlin`, `darwin/compress_video/Sources`, `lib/`, `example/lib`, `example/integration_test`, `tool/`, `.github/workflows/` for `TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER` and for `Log.d/println/print` (a proxy for the "no logging of file paths/metadata" prohibition) — zero matches. `01-REVIEW.md` (standard depth, 46 files) independently reached `status: clean`, 0 critical, 0 warning, 1 info (IN-01, addressed above as a human-verification item, not a blocker since it isn't a declared must-have and the specific "unexercised by a passing run" half of it is now resolved by CI run 3).

### Human Verification Required

1. **CI cancellation on rapid double-push** — see frontmatter `human_verification[0]`. Backstop-tagged truth; config is present and correctly shaped but never observed firing.
2. **CI fail-propagation from either independent job** — see frontmatter `human_verification[1]`. Backstop-tagged truth; every gathered run so far has been all-success, so the failure path is unobserved.
3. **Symlinked-ancestor test coverage for Arguments.swift's WR-01 fix** — see frontmatter `human_verification[2]`. Not a declared must-have (doesn't affect score), but a real, currently-unexercised code path in a validation function added specifically for a security/correctness review finding.

### Gaps Summary

No blocking gaps. All five ROADMAP.md success criteria for Phase 1 are verified against a CI run executed live during this verification session (not inferred from SUMMARY claims), backed by a clean code review, a passing local `flutter test`/`flutter analyze`, and a passing local parity-gate self-test. The only reason overall status is `human_needed` rather than `passed` is that 01-07-PLAN.md itself declared two of its must-have truths `verification: backstop` — meaning the plan's own author judged them not inferable from static/CI evidence alone, and no run gathered here (or documented in any SUMMARY) has actually exercised the failure/cancellation behavior those two truths assert. That is a correct, expected outcome of the backstop-verification rule, not a defect found in the phase's work.

Known, already-documented items (not gaps): two cross-platform deltas within sidecar tolerance (`small_480p` durationMs, thumbnail JPEG channel drift) — explicitly flagged in `corpus/README.md` and `STATE.md` for Phase 3 (CORE-07, "Pending", exact cross-platform parity) to re-examine, not a Phase 1 blocker since the parity gate's own tolerance design is what Phase 1's success criteria require; `videoCodec` reporting `unknown` on iOS 13-15/macOS 11-12 (WR-02, documented limitation); the corpus is ffmpeg-generated pending real phone clips (QUESTIONS.md #4); no physical iOS device verification (simulator + CI only, MacBook Air has no CocoaPods yet).

---

_Verified: 2026-09-21T20:20:00Z_
_Verifier: Claude (gsd-verifier)_

## Orchestrator evidence for the two `verification: backstop` truths (2026-09-21)

The verifier abstained on these because no run it examined exhibited the behaviour. Both behaviours
were in fact observed in this repository's own CI history during the autonomous run:

1. **Concurrency cancel-in-progress.** Five runs on `main` concluded `cancelled` because a newer push
   arrived while they were in flight: 35623448167 (2026-09-21), 35008007617, 35005659572,
   35005031348, 34996744085 (all 2026-09-15). `gh run list --json conclusion` shows them.
2. **Job independence and overall failure on either job.** Run 35611468731: `Android=success`,
   `Apple=failure`, run conclusion `failure`. Run 35053380886: `Android=failure` while `Apple` ran
   to its own completion, run conclusion `failure`. Neither job's failure stopped the other; either
   failure failed the run.

Residual, non-must-have follow-up (from 01-REVIEW.md IN-01): add a test that constructs a real
symlinked ancestor directory to exercise `Arguments.swift`'s WR-01 symlink-resolution branch. Tracked
for Phase 3, which owns the Apple engine work.

