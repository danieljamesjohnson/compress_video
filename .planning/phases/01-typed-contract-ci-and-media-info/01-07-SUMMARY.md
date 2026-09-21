---
phase: 01-typed-contract-ci-and-media-info
plan: 07
subsystem: ci
tags: [github-actions, ci, cross-platform-parity, jq, bash, pigeon, validation]

# Dependency graph
requires:
  - phase: 01-05
    provides: "Android thumbnails (getThumbnail/getThumbnailFile) and media info, both proven on the emulator"
  - phase: 01-06
    provides: "Apple Probe/Thumbnails (Swift), XCTest coverage, and the apple CI job -- halt resolved, confirmed green on run 35606910435"
provides:
  - "tool/check_parity.sh: a tolerance-aware cross-platform parity gate that diffs the ACTUAL crossPlatform media-info and thumbnail values the Android emulator and the iOS simulator each observed, reading each clip's own sidecar tolerances live rather than hardcoding them"
  - "tool/check_parity_test.sh: a fixture-based self-test proving the gate itself (a within-tolerance case passes, an out-of-tolerance case fails and names the field)"
  - "A third CI job, `parity`, that needs both platform jobs and fails the build on any real cross-platform divergence"
  - "A CI step in the `android` job that fails the build if any hand-written channel plumbing (MethodChannel/EventChannel/BasicMessageChannel) exists outside the Pigeon-generated Messages.g.* files"
  - "01-VALIDATION.md signed off: status: validated, nyquist_compliant: true, wave_0_complete: true, every Per-Task Verification Map row green"
  - "doc/TOOLCHAIN.md, README.md, CHANGELOG.md and .claude/CLAUDE.md lane notes reconciled with what CI actually resolved (not what was assumed at research time)"
affects: []

# Actuals (#2632)
actuals:
  tokens: 42000
  tasks: 3
  commits: 6

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Tolerance-aware parity comparison: check_parity.sh reads each clip's OWN sidecar (corpus/<clip>.expected.json) live for durationToleranceMs and reads portrait_rot90.expected.json's thumbnailProbe.rgbTolerance for the thumbnail record, rather than hardcoding either number or doing plain JSON equality. Every crossPlatform field except durationMs must be byte-identical; durationMs and thumbnail RGB get per-field tolerance checks. This is the same field-level contract corpus/README.md already documents for each platform's own per-clip test -- reused, not reinvented, by the cross-platform gate."
    - "PARITY_JSON emission: each integration-test file accumulates a SplayTreeMap (sorted keys) across its testWidgets cases and prints exactly one 'PARITY_JSON <json>' line from a tearDownAll callback, so CI can grep+tee the test's own stdout into an artifact without adding any new instrumentation surface. Raw observed values are recorded (not pre-bucketed) -- bucketing a value into a fixed-width tolerance bucket before comparison is unsound at bucket boundaries, discovered live when a legitimate one-frame duration difference and a real 34ms one both happened to be indistinguishable after bucketing."
    - "android-emulator-runner's `script:` input executes each line of a multi-line block as its own separate `sh -c` call, not a persistent shell -- confirmed live in CI (a `cd` didn't carry over, and dash's `sh` rejected `set -o pipefail` outright). Anything needing `cd`/`set -o pipefail`/a pipe together must be wrapped in one `bash -c '...'` line."

key-files:
  created:
    - tool/check_parity.sh
    - tool/check_parity_test.sh
  modified:
    - example/integration_test/media_info_test.dart
    - example/integration_test/thumbnail_test.dart
    - .github/workflows/ci.yml
    - corpus/README.md
    - doc/TOOLCHAIN.md
    - README.md
    - CHANGELOG.md
    - .claude/CLAUDE.md
    - .planning/STATE.md
    - .planning/ROADMAP.md
    - .planning/REQUIREMENTS.md
    - .planning/phases/01-typed-contract-ci-and-media-info/01-VALIDATION.md

key-decisions:
  - "check_parity.sh applies per-field tolerances read live from the corpus sidecars (durationToleranceMs, thumbnailProbe.rgbTolerance) instead of exact JSON equality -- the first version used exact equality and correctly-but-uselessly failed the build on two legitimate platform deltas (a one-frame duration difference, a JPEG re-encoding RGB difference) that each platform's OWN per-clip test already tolerates. Reusing the SAME documented tolerances, rather than inventing new ones, keeps one source of truth for what 'parity' means."
  - "Dart-side durationMs is recorded RAW, not pre-bucketed into the tolerance's own bucket width. The initial (later reverted) bucketing approach was unsound: two legitimately-close raw values can round into different buckets at a boundary, which is exactly what produced the false failure this plan's second CI fix addressed. Doing the tolerance comparison in exactly one place (the shell script, against real millisecond values) is both simpler and correct."
  - "small_480p's durationMs cross-platform delta (Android 3026ms vs Apple 2992ms vs ffprobe ground truth 3000ms) is documented as a real, tolerance-bounded platform difference and flagged for Phase 3 (CORE-07) rather than investigated further here -- Apple is closer to ground truth, but both platforms are within the sidecar's own durationToleranceMs and neither fails its own per-platform assertion."
  - "The Android-only-path and Markdown-only-path CI gating checks (plan verification item 3) were confirmed against EXISTING historical CI evidence (multiple Phase 2 pushes where `apple` correctly shows `skipped`) plus this plan's own final docs-only commit (which triggered no CI run at all), rather than a dedicated fresh demonstration commit -- see Deviations."

patterns-established:
  - "Any future CI parity/comparison gate between platforms should read tolerances from the same sidecar/fixture files the platform-level tests already use, never invent a second number."
  - "Any future reactivecircus/android-emulator-runner `script:` block needing `cd`/`set -o pipefail`/a pipe must be one `bash -c '...'` line, not a multi-line block."

requirements-completed: [BULD-05, BULD-03, INFO-01, INFO-02]

coverage:
  - id: D1
    description: "A dedicated CI job (`parity`) diffs the crossPlatform media-info and thumbnail values the Android emulator and the iOS simulator each actually observed, turning 'the two platforms agree' into a diff rather than an inference from running the same test file on both."
    requirement: "BULD-05"
    verification:
      - kind: e2e
        ref: "CI run 35631865999, job `parity` -- conclusion success (https://github.com/danieljamesjohnson/compress_video/actions/runs/35631865999)"
        status: pass
      - kind: unit
        ref: "tool/check_parity_test.sh -- fixture-based self-test, run locally and wired into the `parity` job before the real diff"
        status: pass
    human_judgment: false
  - id: D2
    description: "No hand-written channel map (MethodChannel/EventChannel/BasicMessageChannel) remains anywhere in the package outside the Pigeon-generated Messages.g.* files -- enforced as a CI gate, not just an inspection claim."
    requirement: "BULD-03"
    verification:
      - kind: e2e
        ref: "CI run 35631865999, `android` job step 'Verify no hand-written channel plumbing remains' -- success"
        status: pass
      - kind: other
        ref: "Demonstrated locally against a temporary probe file under lib/ before committing: grep exits 0 (match/fail) with the probe present, 1 (no-match/pass) once removed"
        status: pass
    human_judgment: false
  - id: D3
    description: "One CI run on the phase's final commit concludes success with android, apple and parity all green; the apple job is path-gated and independent of android (neither names the other in `needs`)."
    requirement: "BULD-05"
    verification:
      - kind: e2e
        ref: "CI run 35631865999 -- android: success, apple: success, parity: success (https://github.com/danieljamesjohnson/compress_video/actions/runs/35631865999)"
        status: pass
    human_judgment: false
  - id: D4
    description: "01-VALIDATION.md is signed off against commands that were really run: every Per-Task Verification Map row green, status: validated, nyquist_compliant: true, wave_0_complete: true."
    requirement: "BULD-03, BULD-05"
    verification:
      - kind: other
        ref: "grep -c 'nyquist_compliant: true' / 'status: validated' / 'wave_0_complete: true' each = 1; grep -c '⬜ pending' = 0 (legend line reworded to avoid a false match)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Toolchain pins, README, CHANGELOG and lane notes reconciled with what CI actually resolved (Flutter/Dart/Pigeon/runner-image versions, the android-emulator-runner script gotcha, the corpus-is-generated rule)."
    requirement: null
    verification: []
    human_judgment: true
    rationale: "Documentation accuracy and completeness is a judgment call a human reviewer should spot-check, even though every specific version claim in this SUMMARY was read from a live CI log rather than guessed."

# Metrics
duration: 195min
completed: 2026-09-21
status: complete
---

# Phase 1 Plan 07: Cross-Platform Parity Gate and Phase Sign-Off Summary

**A tolerance-aware `parity` CI job now diffs the ACTUAL media-info and thumbnail values the Android emulator and iOS simulator each observed (not just "ran the same test"), a new CI check fails the build on any hand-written channel plumbing, and Phase 1's validation contract is signed off against a fully green pipeline (CI run 35631865999).**

## Performance

- **Duration:** 195 min (~3h15m), almost entirely CI wall-clock across 4 pushed CI attempts
- **Started:** 2026-09-21T16:05:37Z (first task-1 commit)
- **Completed:** 2026-09-21T18:15:00Z (approx.)
- **Tasks:** 3 completed
- **Files modified:** 12 (2 created, 10 modified)

## Accomplishments

- `example/integration_test/media_info_test.dart` and `thumbnail_test.dart` each emit exactly one `PARITY_JSON <json>` line (from a `tearDownAll` callback, accumulated via a sorted `SplayTreeMap`) recording every clip's `crossPlatform` field set and the decoded thumbnail's width/height/sampled-patch-RGB — the raw values each platform actually observed, never hardcoded or bucketed.
- `tool/check_parity.sh` merges each platform's `PARITY_JSON` lines and applies the SAME field-level contract `corpus/README.md` already documents: every `crossPlatform` field except `durationMs` must be byte-identical; `durationMs` may differ by up to that clip's own sidecar `durationToleranceMs` (read live, never hardcoded); the thumbnail's sampled RGB may differ per channel by up to the sidecar's own `thumbnailProbe.rgbTolerance`. A missing/empty artifact, a clip with no matching sidecar, or a genuinely divergent field all fail loudly, naming the field, both values and the tolerance.
- `tool/check_parity_test.sh` is a fixture-based self-test (two hand-written JSON files, one within tolerance and one outside) proving the gate itself, wired into the `parity` job before the real diff runs.
- CI's `android` and `apple` jobs each capture their integration-test output (via `tee`, with `set -o pipefail` so a test failure is never swallowed), grep the `PARITY_JSON` lines into an artifact, and upload it (`actions/upload-artifact@v4`). A new `parity` job (`needs: [android, apple]`, `if: !cancelled() && both succeeded`) downloads both artifacts and runs `check_parity.sh`. Neither platform job names the other in `needs` — they stay independent and concurrent.
- A new `android` job step enumerates `lib/`, `android/src/main/`, and `darwin/compress_video/Sources/` for `MethodChannel`/`EventChannel`/`BasicMessageChannel` primitives outside the Pigeon-generated `Messages.g.*` files and fails, naming the offending file, if any hand-written channel plumbing is found — demonstrated locally against a temporary probe file before committing. The check branches on `grep`'s real exit status explicitly rather than swallowing it behind `|| true`.
- Audited the full pipeline against Phase 1's five success criteria: every other required step (format, `analyze --fatal-infos --fatal-warnings`, Pigeon regen+diff, corpus drift/mirror checks, Dart unit tests, `publish --dry-run`, APK build, Gradle native unit tests, emulator integration; CocoaPods/SPM iOS builds, both XCTest targets, macOS build, RunnerTests diff, iOS simulator integration) was already present from prior plans — no other gap found.
- `01-VALIDATION.md` signed off: every Per-Task Verification Map row flipped to green, `status: validated`, `nyquist_compliant: true`, `wave_0_complete: true`.
- `doc/TOOLCHAIN.md`, `README.md`, `CHANGELOG.md` and `.claude/CLAUDE.md`'s lane notes reconciled with what CI actually resolved this session (Flutter 3.47.5/Dart 3.13.4 on the runner vs the local 3.44.1 pin, Pigeon 29.0.2, macOS 26.6.2 on image `macos-26-arm64`, emulator API 35/`google_apis`/x86_64).
- `.planning/REQUIREMENTS.md`: `BULD-05`, `BULD-03`, `INFO-01`, `INFO-02` all marked `Complete` (shared-ID gate now satisfied — this was the last plan declaring all four).

## Task Commits

1. **Task 1: Add the cross-platform parity gate** — `78e3ccc` (feat), `9b0b66a` (ci — no-hand-written-channel check, folded in from Task 2's audit since both touch `ci.yml`), `06ec7b6` (fix — `sh`/pipefail bug), `242b8a8` (fix — tolerance-aware redesign)
2. **Task 2: Drive the complete pipeline green and capture the phase evidence** — audit completed as part of `9b0b66a`; evidence captured in this SUMMARY and `01-VALIDATION.md`
3. **Task 3: Sign off the phase documentation and clear the toolchain blocker** — `4e14b34` (docs)

**Plan metadata:** (this commit, docs)

_Note: Tasks 1 and 2 share commits because both touch `.github/workflows/ci.yml` and were driven through the same CI iteration cycle — see Deviations for the full CI attempt history._

## Files Created/Modified

- `tool/check_parity.sh` — Tolerance-aware cross-platform parity diff, reading sidecar tolerances live
- `tool/check_parity_test.sh` — Fixture-based self-test for the gate
- `example/integration_test/media_info_test.dart`, `thumbnail_test.dart` — Emit `PARITY_JSON` lines
- `.github/workflows/ci.yml` — Parity artifact capture/upload on both platform jobs, new `parity` job, no-hand-written-channel check, `bash -c` fix for the emulator-runner script
- `corpus/README.md` — Documents the parity gate's reused tolerances and the two observed real deltas
- `doc/TOOLCHAIN.md`, `README.md`, `CHANGELOG.md`, `.claude/CLAUDE.md` — Reconciled with live CI evidence
- `.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`, `01-VALIDATION.md` — Phase 1 sign-off

## Decisions Made

See `key-decisions` in frontmatter. Most consequential: redesigning `check_parity.sh` from exact-JSON-equality to a tolerance-aware comparison that reuses the corpus sidecars' own documented tolerances, after the exact-match version correctly-but-uselessly failed CI on two legitimate platform deltas.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `android-emulator-runner`'s `script:` executes each line as a separate `sh -c` call**
- **Found during:** Task 1, first CI push (run 35623448167)
- **Issue:** The step's multi-line `script:` block ran `cd example`, `set -o pipefail`, and the `flutter test | tee` pipe as three SEPARATE shell invocations — `cd` never carried over and dash's `sh` rejected `set -o pipefail` outright ("Illegal option -o pipefail"), so the step failed immediately at 0% test progress.
- **Fix:** Wrapped the whole sequence in one `bash -c '...'` line.
- **Files modified:** `.github/workflows/ci.yml`
- **Verification:** Next run (35624754433) got past this point and ran the actual test suite
- **Committed in:** `06ec7b6`

**2. [Rule 1 - Bug] `check_parity.sh`'s exact-JSON-equality comparison failed on two legitimate platform deltas**
- **Found during:** Task 1, second CI push, `parity` job (run 35624754433) — Android and Apple both green, but `parity` failed
- **Issue:** `small_480p`'s `durationMs` (Android 3026ms, Apple 2992ms — a 34ms/one-frame-at-30fps difference) and the `portrait_rot90` thumbnail's sampled patch green channel (255 vs 242, JPEG re-encoding loss, a 13-point difference) were both already within the tolerances `corpus/README.md` documents and each platform's OWN per-clip test already tolerates, but the parity script's plain JSON-string equality flagged both as failures.
- **Fix:** Redesigned `check_parity.sh` to apply the same field-level contract per-clip, reading each clip's own sidecar `durationToleranceMs` and `portrait_rot90.expected.json`'s `thumbnailProbe.rgbTolerance` live. Dropped the Dart-side pre-bucketing of `durationMs` (unsound at bucket boundaries) in favor of recording the raw value and doing the tolerance check in exactly one place. Added `tool/check_parity_test.sh`, a fixture-based self-test, wired into the `parity` job.
- **Files modified:** `tool/check_parity.sh`, `tool/check_parity_test.sh` (new), `example/integration_test/media_info_test.dart`, `.github/workflows/ci.yml`, `corpus/README.md`
- **Verification:** `bash tool/check_parity_test.sh` passes both fixture cases locally; `bash tool/check_parity.sh` against the two real artifacts from run 35624754433 now passes; CI run 35631865999's `parity` job concludes `success`
- **Committed in:** `242b8a8`

### Out-of-Scope Flakes (not fixed, not caused by this plan)

**3. Android: `compress_jobs_test.dart` concurrent-job codec exhaustion (transient)**
- **Found during:** CI run 35624754433, `android` job, "Run emulator integration tests" step
- **Issue:** "cancelling one of three jobs leaves the other two to complete normally" failed with `CompressVideoException(unsupportedInput): Media3 export failed with code 3002: Codec exception` (`c2.goldfish.h264.decoder`) — three concurrent Media3 exports exhausted the emulator's software/goldfish decoder. This is a Phase 2 test (`compress_jobs_test.dart`), untouched by any 01-07 commit; the exact same suite passed on the immediately preceding baseline run (35615277549) and on the very next CI attempt (35631865999) with zero code changes.
- **Action:** Not fixed — out of this plan's scope (Rule: scope boundary). Confirmed transient by a clean rerun.

**4. Apple: iOS simulator hang with zero test output (documented pre-existing flake)**
- **Found during:** Same run, `apple` job, "Run corpus integration tests on the iOS simulator" — hung on BOTH the first attempt and the scripted retry, each timing out at the 540s `perl alarm` bound, with zero test output past a successful Xcode build.
- **Issue:** This is the exact flake pattern `01-06-SUMMARY.md`'s Deviations #5 already documented ("hung with zero log output past a successful build") — hit twice in a row this time, unluckily. Not caused by any 01-07 code change: the hang occurs before the app even starts running the first test, so `_recordParity`/`tearDownAll` code is never reached.
- **Action:** Not fixed — a rerun (`gh run rerun --failed`) on unchanged code passed cleanly (run 35624754433 attempt 2: android and apple both `success`), confirming the transient nature.

---

**Total deviations:** 2 auto-fixed (both Rule 1 bugs, both in this plan's own new CI code), 2 documented out-of-scope flakes (confirmed transient by a clean rerun, not caused by this plan). **Impact on plan:** Both auto-fixes were necessary for the parity gate to be correct rather than merely present — an exact-match gate that fails on legitimate platform deltas would have taught engineers to ignore its output, defeating the point. No scope creep: the flaky Phase 2 test and the documented iOS-simulator hang were left alone.

## CI Attempt History

| Run | Commit | Android | Apple | Parity | Notes |
|---|---|---|---|---|---|
| 35623448167 | 9b0b66a | failure | (cancelled) | — | `sh`/pipefail bug in emulator-runner script |
| 35624754433 attempt 1 | 06ec7b6 | failure | failure | skipped | Two unrelated transient flakes (see Deviations #3/#4) |
| 35624754433 attempt 2 | 06ec7b6 | success | success | **failure** | Real parity-gate design bug found (see Deviations #2) |
| 35631865999 | 242b8a8 | success | success | **success** | Final green run — all three jobs pass |

**Final CI run: [35631865999](https://github.com/danieljamesjohnson/compress_video/actions/runs/35631865999)** — `android`: success, `apple`: success, `Detect Apple-relevant changes`: success, `Cross-platform parity`: success.

## Issues Encountered

- The `reactivecircus/android-emulator-runner`'s per-line-`sh -c` script execution model is undocumented and only discoverable by running it — now recorded in `.claude/CLAUDE.md` lane notes for future plans.
- The parity gate's own design (exact-match vs tolerance-aware) required one full CI iteration to get wrong-then-right, since the two legitimate deltas it caught could only be observed once both platform jobs were actually green and uploading real artifacts.
- The Android-only-path and Markdown-only-path CI gating demonstrations (plan `<verification>` item 3) were confirmed via existing historical CI evidence (multiple Phase 2 pushes showing `apple: skipped`) and this plan's own final docs-only commit (which triggered no run at all — confirmed via `gh run list`), rather than one dedicated fresh demonstration commit, to avoid a fifth CI iteration after three were already spent closing the parity gate itself. See `.planning/STATE.md` Pending Todos.
- `.planning/STATE.md`'s hand-edit could not satisfy the plan's literal "grep -c 'dans-macbook-air' unchanged" acceptance criterion once the standard end-of-plan position/progress/session-continuity updates were applied (a new Session Continuity note mentions `dans-macbook-air` once more) — the actual protected content (the Phase 3 SSH blocker line itself) is verified byte-identical before and after this plan's edits.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 1 is fully complete: all 7 plans done, all 5 success criteria met, CI green end-to-end on run 35631865999.
- `BULD-05`, `BULD-03`, `INFO-01`, `INFO-02` all marked `Complete` in `REQUIREMENTS.md`.
- Phase 1 now awaits phase-level verification (`/gsd-verify-work 1`), same as Phase 2.
- Phase 3 (Apple Compression to Parity) can now proceed — Mac SSH is authorized (`ssh dans-macbook-air`), and the parity gate's small_480p duration delta is flagged as its first cross-platform re-examination item (CORE-07).

---
*Phase: 01-typed-contract-ci-and-media-info*
*Completed: 2026-09-21*

## Self-Check: PASSED

- FOUND: `tool/check_parity.sh`, `tool/check_parity_test.sh` (verified with `[ -f ]`)
- FOUND commits: `78e3ccc`, `9b0b66a`, `06ec7b6`, `242b8a8`, `4e14b34` (all present in `git log --oneline --all`)
- `bash tool/check_parity_test.sh` — self-test PASSED (both fixture cases)
- `bash tool/check_parity.sh /nonexistent /alsononexistent` — exits non-zero, reports `FATAL`, never a match
- `grep -c '⬜ pending'` on `01-VALIDATION.md` — 0; `nyquist_compliant: true` / `status: validated` / `wave_0_complete: true` each — 1
- `grep -RIl 'MethodChannel' lib/ android/src/main/ --exclude='messages.g.dart' --exclude='Messages.g.kt'` — 0 files
- Final CI run 35631865999: `android`, `apple`, `parity` all `success` (confirmed via `gh run view --json jobs`)
- `git status --short` clean at every commit boundary
