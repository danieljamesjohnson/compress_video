---
phase: 03-apple-compression-to-parity
plan: 09
subsystem: docs
tags: [readme, dartdoc, changelog, toolchain, requirements, validation, ci, parity]

# Dependency graph
requires:
  - phase: 03-apple-compression-to-parity
    provides: "03-08's widened apple job (macOS integration run) and two-comparison compression parity gate, both green on CI run 36202392709"
provides:
  - "A stated, testable definition of cross-platform sameness in README.md and CompressResult's dartdoc: dimensions/codec/flags/duration guaranteed, outputBytes/elapsedMs deliberately platform-dependent"
  - "CORE-01, CORE-07 and BULD-02 marked complete in REQUIREMENTS.md, each with named CI evidence"
  - "Every row of 03-VALIDATION.md's Per-Task Verification Map carries an observed status instead of the seeded 'pending'"
  - "A CHANGELOG entry and doc/TOOLCHAIN.md rows recording the Apple-side toolchain this phase established"
affects: [phase-4-ai-integration-if-any, gsd-verify-work-3, gsd-ship]

# Actuals (#2632)
actuals:
  tokens: 14300
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Parity is documented, not just gated: the README/dartdoc now say in prose what tool/check_parity.sh already enforces mechanically (exact/tolerant fields vs. deliberately-excluded fields)"

key-files:
  created: []
  modified:
    - README.md
    - lib/src/compress_result.dart
    - CHANGELOG.md
    - doc/TOOLCHAIN.md
    - .claude/CLAUDE.md
    - QUESTIONS.md
    - .planning/REQUIREMENTS.md
    - .planning/phases/03-apple-compression-to-parity/03-VALIDATION.md

key-decisions:
  - "Task 1 (the example app driven by hand on the iOS simulator and macOS host, with screenshots) was deferred entirely rather than attempted or faked -- the Mac was unreachable at the single probe this plan's own instructions allow, and no code, screenshot or 02-UAT.md edit was produced for it."
  - "BULD-04 was deliberately left Pending in REQUIREMENTS.md even though the plan's own acceptance criteria asked for all four requirements to close. Its Apple half needs the example app's own UI driven and observed live, which no CI integration_test proves (they call CompressVideo.compress() directly and never import example/lib/src/main_screen.dart) -- marking it complete would have violated the plan's own MUST NOT-mark-without-evidence prohibition."
  - "CORE-01, CORE-07 and BULD-02 were marked complete on existing CI evidence (the cross-platform parity gate and the Apple CocoaPods/SPM build steps) rather than waiting for BULD-02's fresh-app script (tool/verify_fresh_app.sh, 03-08 task 1) -- that script was extra rigor 03-08-PLAN.md itself flagged as going beyond BULD-02's literal requirement text, and BULD-02's actual claim (shared Swift core, installs through both CocoaPods and SPM) is already a green build in CI."
  - "03-VALIDATION.md's Per-Task Verification Map was filled in for ALL 27 rows, not just this plan's own 3, because the plan's own task 2 acceptance criterion demanded zero remaining 'pending' rows across the whole table. Twenty-one rows were resolved from each owning plan's own already-recorded SUMMARY.md/CI evidence (no re-verification needed, since nothing about those platforms changed); two rows (3-08-01, 3-09-01) were honestly marked deferred rather than invented green, since both are genuinely blocked on the same unreachable Mac."
  - "Discovered and fixed a false-positive in this row's own acceptance check: the table's legend line ('Status: [check] pending ...') always contains the literal substring the grep for a fully-updated table checks against, so the check could never read zero regardless of the table's real content. Reworded the legend, not the check, since the check's intent (no data row left unresolved) was correct."

requirements-completed: [CORE-01, CORE-07, BULD-02]

coverage:
  - id: D1
    description: "README and CompressResult's dartdoc state exactly what 'the same on every platform' means: dimensions, codec, transmuxed/usedOriginal/audioReencoded flags and duration are guaranteed within tolerance; outputBytes and elapsedMs are deliberately platform-dependent, pointed at doc/PRESETS.md's measured tables"
    requirement: CORE-01
    verification:
      - kind: other
        ref: "grep -ci 'elapsed' README.md (>=1 in the new section) and grep -c 'PRESETS' README.md (>=1)"
        status: pass
      - kind: other
        ref: "grep -c -i 'platform' lib/src/compress_result.dart (8, >=3 required)"
        status: pass
    human_judgment: false
  - id: D2
    description: "CORE-01, CORE-07 and BULD-02 marked complete in REQUIREMENTS.md, each with its evidence named in this summary; BULD-04 deliberately left Pending"
    requirement: CORE-01
    verification:
      - kind: e2e
        ref: "gh run view 36207227343 --json jobs (Detect Apple-relevant changes/Android/Apple/Cross-platform parity all success); gh run view 36202392709 --json jobs (same four, all success)"
        status: pass
      - kind: other
        ref: "git diff --name-only .planning/REQUIREMENTS.md (exactly 3 requirement rows + 3 traceability rows changed, reviewed by hand)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every row of 03-VALIDATION.md's Per-Task Verification Map carries an observed status (green, deferred, or otherwise resolved) instead of the seeded 'pending'"
    requirement: CORE-01
    verification:
      - kind: other
        ref: "grep -c '⬜ pending' .planning/phases/03-apple-compression-to-parity/03-VALIDATION.md (0, after the legend-line fix)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The example app run by hand through its whole flow on the iOS simulator and the macOS host, with committed screenshots of the compressing and done states, closing 02-UAT.md item 6"
    requirement: BULD-04
    verification: []
    human_judgment: true
    rationale: "Not attempted -- the Mac was unreachable at this plan's single allowed probe (QUESTIONS.md #8). No screenshot, no 02-UAT.md edit, no code exists for this deliverable; it is carried forward, not claimed."

duration: 110min
completed: 2026-09-26
status: partial
---

# Phase 3 Plan 09: Cross-Platform Sameness Documented, Three Requirements Closed on Named CI Evidence Summary

**README and `CompressResult` now say exactly what "the same on every platform" does and does not mean; CORE-01, CORE-07 and BULD-02 are closed on CI run 36207227343 (and the earlier 36202392709); every row of the phase's validation map carries an observed status; the example app's live Apple walkthrough (task 1, and with it BULD-04) stays open because the Mac never answered.**

## Performance

- **Duration:** ~110 min (dominated by an 82-minute CI wall-clock wait for run 36207227343)
- **Started:** 2026-09-26T00:40:00Z (approx.)
- **Completed:** 2026-09-26T02:32:43Z
- **Tasks:** 2 of 3 completed (task 1 deferred)
- **Files modified:** 8

## Accomplishments

- Added a "What 'the same on every platform' means" section to `README.md`, and matching dartdoc on `CompressResult`'s class comment plus its `outputBytes`/`elapsedMs` fields, stating precisely which fields are guaranteed equal across Android/iOS/macOS (dimensions, codec, the three shortcut flags, duration within tolerance) and which are deliberately not (`outputBytes`, `elapsedMs`), pointing at `doc/PRESETS.md`'s measured tables as the substantiation rather than an assertion.
- Marked **CORE-01**, **CORE-07** and **BULD-02** complete in `REQUIREMENTS.md` (hand-edited, `git diff` reviewed before each commit) on named CI evidence: run `36202392709` and this plan's own run `36207227343`, both showing the `Android`, `Apple` and `Cross-platform parity` jobs `success` — the parity gate diffs compression results (dimensions, codecs, flags, duration) between Android, iOS and macOS, and the `apple` job's CocoaPods and SPM build steps prove BULD-02's literal "shared Swift core, installs through both" claim. **BULD-04 deliberately left `Pending`** — its Apple half needs the example app driven by a human/agent eye on a live simulator and macOS host, which no automated `integration_test` suite exercises (they call the plugin API directly, never `example/lib/src/main_screen.dart`).
- Filled in the observed `Status` column of every one of `03-VALIDATION.md`'s 27 Per-Task Verification Map rows, using each plan's own already-recorded `SUMMARY.md`/CI evidence for 21 of them and honestly marking two (`3-08-01`, `3-09-01`) as deferred, both blocked on the same unreachable Mac. Also fixed the row's own acceptance check: the table's legend line always contained the literal string the check greps for, making a zero-pending result structurally impossible regardless of the table's real content — reworded the legend, not the check.
- Ran a full local verification sweep on danserver: `flutter analyze --fatal-infos --fatal-warnings`, `flutter test` (84/84), `bash corpus/verify_corpus.sh`, `bash tool/check_parity_test.sh`, `dart pub publish --dry-run`, `./gradlew :compress_video:testDebugUnitTest` (all `SizeGuardTest` cases and others, `BUILD SUCCESSFUL`), and the full Android emulator `integration_test` directory on `emulator-5554` (**80/80 cases passed** across `media_info`, `thumbnail`, `compress`, `compress_audio`, `compress_jobs`, `compress_output`).
- Added `CHANGELOG.md`'s phase entry (Apple engine, trim on all platforms, both install paths, the real example app, the widened compression parity gate) and `doc/TOOLCHAIN.md` rows recording the Apple-side toolchain this phase established (Mac's second Flutter SDK path/version, Xcode 26.2, iOS 26.2 simulator runtime, and which install path is proven where).
- Corrected a stale line in `.claude/CLAUDE.md` ("No CocoaPods and no Homebrew" — resolved 2026-09-25) and added the measured Apple-overshoots/Android-undershoots bitrate divergence and BULD-04's still-open status to the lane notes, so a future agent does not re-derive either.
- Deferred task 1 (the example app's live Apple walkthrough) with a single Mac-reachability probe as this plan's own instructions require, recording the exact resume command in `QUESTIONS.md` #8, `STATE.md`'s Deferred Items, and this summary.

## Task Commits

1. **Task 3: Say exactly what "the same on every platform" means, and close the requirements honestly** — `b1dad7d` (docs) — README/dartdoc/CHANGELOG/TOOLCHAIN/CLAUDE.md/QUESTIONS.md/REQUIREMENTS.md
2. **Task 2 (partial — Per-Task Verification Map accounting): One green run of the real pipeline, and a final sweep** — `e3d5b5f` (docs) — `03-VALIDATION.md`

**Task 1** (End-to-end "a person watches it work") — **not executed**; see Deviations and Next Phase Readiness. No commit exists for it (a precondition-unmet task is never partial-committed).

**Plan metadata:** committed separately below.

_Note: tasks were executed out of their written order (3 before finishing 2's CI-evidence recording) so the doc changes from task 3 — which touch `lib/src/compress_result.dart` and therefore trigger CI's `apple`/`parity` jobs — could be pushed once and used as task 2's own observed CI run, rather than pushing twice. This is a scheduling choice, not a scope change; every task's own acceptance criteria are still verified against real, current evidence._

## Files Created/Modified

- `README.md` — new "What 'the same on every platform' means" section
- `lib/src/compress_result.dart` — class dartdoc plus `outputBytes`/`elapsedMs` field dartdoc state the platform-dependence
- `CHANGELOG.md` — phase entry (Apple engine, trim, both install paths, example app, widened parity gate)
- `doc/TOOLCHAIN.md` — Apple-side toolchain rows (Mac SDK, Xcode, simulator runtime, install-path proofs)
- `.claude/CLAUDE.md` — corrected stale CocoaPods/Homebrew line; added bitrate-divergence and BULD-04 lane notes
- `QUESTIONS.md` — dated update to #8 recording this session's Mac-unreachable probe
- `.planning/REQUIREMENTS.md` — CORE-01/CORE-07/BULD-02 marked complete (checkbox + traceability rows); BULD-04 left Pending
- `.planning/phases/03-apple-compression-to-parity/03-VALIDATION.md` — every Per-Task Verification Map row given an observed status; legend line reworded

## Decisions Made

See `key-decisions` in the frontmatter for the full rationale on each. In short: defer task 1 honestly rather than fake or skip it silently; close three of four requirements on real evidence and leave the fourth open rather than force a complete-looking row set; backfill the whole validation map from history rather than only this plan's own three rows, since the plan's own acceptance criterion demanded it; fix the check's legend-line false positive rather than declare the check unsatisfiable.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `03-VALIDATION.md`'s own "zero pending rows" check was structurally unsatisfiable**
- **Found during:** Task 2, verifying `grep -c '⬜ pending' 03-VALIDATION.md` after filling in all 27 data rows
- **Issue:** The table's own legend line (`*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*`) always contains the literal substring `⬜ pending`, so the check could never return 0 regardless of how complete the table's real data rows were.
- **Fix:** Reworded the legend line to `*Legend: ⬜ = not yet run · ✅ = green · ❌ = red · ⚠️ = flaky/deferred*`, preserving its meaning without the literal collision.
- **Files modified:** `.planning/phases/03-apple-compression-to-parity/03-VALIDATION.md`
- **Verification:** `grep -c '⬜ pending' ...` now returns `0`.
- **Committed in:** `e3d5b5f`

### Scope Decisions (not bugs, documented for the verifier)

**2. [Task 3 acceptance criterion vs. honest evidence] BULD-04 left Pending, not marked complete**
- **Found during:** Task 3, closing the four requirement rows
- **Issue:** The task's own acceptance criteria list all four requirements (CORE-01, CORE-07, BULD-02, BULD-04) as "marked complete... evidence named in the summary," and "exactly four requirement rows change." Only three requirement rows actually changed (six lines total, including traceability) in this plan's commit.
- **Reasoning:** BULD-04's claim is specifically about the example app's own UI on all three platforms. No CI integration test drives `example/lib/src/main_screen.dart` — they call `CompressVideo.compress()`/etc. directly. The only evidence for BULD-04's Apple half is task 1's live walkthrough, which did not run (Mac unreachable). Marking BULD-04 complete without that evidence would have violated this same plan's own MUST NOT-mark-without-evidence prohibition and the T-03-39 threat mitigation. The plan's `<mac_dependent_tasks>` guidance and Dan's standing 2026-09-25 instruction to defer Mac-dependent work rather than force completion take precedence here.
- **Files modified:** `.planning/REQUIREMENTS.md` (3 rows changed, not 4)
- **Verification:** `git diff .planning/REQUIREMENTS.md` shows exactly CORE-01, CORE-07, BULD-02 (and their traceability rows) changed; BULD-04 unchanged, still `[ ]`/`Pending`.
- **Committed in:** `b1dad7d`

---

**Total deviations:** 1 auto-fixed (Rule 3, a broken self-check), 1 documented scope decision (an honest under-delivery against the plan's own literal acceptance criterion, in favor of the plan's own evidence-based prohibitions).
**Impact on plan:** Neither weakens the phase's actual claims — the fix makes the validation map's self-check meaningful again; the BULD-04 decision keeps `REQUIREMENTS.md` truthful rather than satisfying a checklist.

## Auth Gates

None encountered.

## Issues Encountered

- **The Mac (`dans-macbook-air`) was unreachable for the entire session.** Probed once at the start per this plan's own instructions (`timeout 15 ssh -o ConnectTimeout=8 -o BatchMode=yes dans-macbook-air true` → "Connection timed out"); the coordinator re-probed independently after the CI push completed and reported the same result. This blocked task 1 entirely (no code, no screenshots, no commit) and, downstream, kept BULD-04 from closing. See Next Phase Readiness for the exact resume path.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

**Ready:**
- CORE-01, CORE-07 and BULD-02 are closed with named CI evidence; the phase's documentation now states its actual cross-platform guarantee precisely.
- The validation map (`03-VALIDATION.md`) is a complete, honest record of what ran and what didn't across all nine plans — a future `/gsd-validate-phase` or `/gsd-verify-work 3` pass can read it directly instead of re-deriving history.
- CI is green on `main` for two consecutive runs (`36202392709`, `36207227343`) covering Android, Apple (iOS simulator + macOS desktop, both native XCTest runners, both SPM builds) and the two-comparison cross-platform parity gate.

**Blocked — everything below needs the Mac (`dans-macbook-air`), currently offline (QUESTIONS.md #8):**
- **Task 1 itself** (this plan): drive the example app by hand through pick → options → estimate → compress → live progress → cancel → result card → playback on the iOS simulator and the macOS host; capture and commit screenshots of the compressing and done states. Resume with `bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test/compress_test.dart` (the task's own precondition), then execute `03-09-PLAN.md` task 1 exactly as written.
- **02-UAT.md item 6** stays `[pending]` — it can only close with the screenshots task 1 produces.
- **BULD-04** stays `Pending` in `REQUIREMENTS.md` — it needs the same evidence.
- **03-08 task 1** (`tool/verify_fresh_app.sh`, BULD-02's fresh-app four-build proof) remains unwritten — carried forward from 03-08, not required for BULD-02's own closure in this plan (see key-decisions), but still open as extra rigor if a future session wants it. Resume with `bash tool/mac_sync.sh && bash tool/mac_run.sh build-macos`, then `03-08-PLAN.md` task 1 exactly as written.
- **03-01 task 1's own Mac build-proof half** (`tool/mac_run.sh build-ios`/`build-macos` exiting 0 on the Mac itself) also remains open — CI already proves the equivalent build success independently, but the literal Mac-side proof this row names has never completed.

**Also carried forward (from earlier plans, unrelated to the Mac):**
- The unresolved BULD-02 minimum-deployment-target question flagged in `03-08-PLAN.md`: whether "installs through CocoaPods and SPM" must also be proven at the *floor* OS versions (iOS 13 / macOS 11) rather than only the current toolchain. Explicitly out of scope for this phase per 03-08's own flagged-assumption note; still genuinely unresolved.
- Three forced-AAC-reencode audio bitrate/channel-count cases and the AUDO-01 non-AAC-source-fallback path have no dedicated real-fixture proof beyond what 03-05/02-05 already recorded (see those summaries).
- The free-space pre-check's non-APFS fallback branch remains unexercised by any fixture (no volume available to trigger it).
- The `truncated_mdat.mp4` Android-vs-Apple error-reason divergence (`io`/2000 vs `unsupportedInput`/-11880) is documented as an intentional, correct per-platform difference (`corpus/README.md`), not a bug — carried forward as a fact, not a defect.
- `videoBitrateBps` is deliberately excluded from the compression parity gate entirely (too wide a legitimate spread to catch a real regression) — the README/dartdoc changes in this plan make that exclusion's rationale explicit for the first time.
- The five 02-UAT.md items other than #6 (targetSizeMb/estimate() hardware accuracy, clearCache() symlink integration test, non-AAC audio fallback, decoder-failure error codes, out-of-space rejection) all still need a physical device or a fixture this phase does not add.
- Phase 2 still awaits `/gsd-verify-work 2`.

**For the phase verifier:** every requirement this phase could honestly close (CORE-01, CORE-07, BULD-02) is closed with a named, checkable run id. BULD-04 is the one requirement this phase set out to close and could not — not because the work doesn't exist (the plugin behaves correctly on Apple, proven exhaustively by CI), but because the specific "a person watched the example app work" evidence this requirement asks for needs a machine this project does not currently have live access to. That is a real gap, not a paperwork one, and it is the only thing standing between this phase and being fully done.

## Self-Check: PASSED

- `README.md` exists and contains the new section: FOUND (`grep -q "the same on every platform" README.md` → match)
- `lib/src/compress_result.dart` exists with platform-dependence dartdoc: FOUND (`grep -c -i platform` → 8)
- `.planning/REQUIREMENTS.md` shows exactly 3 requirement rows + 3 traceability rows changed: FOUND (`git diff` reviewed above)
- `.planning/phases/03-apple-compression-to-parity/03-VALIDATION.md` has zero `⬜ pending` data rows: FOUND (`grep -c` → 0)
- Commit `b1dad7d` exists: FOUND (`git log --oneline --all | grep b1dad7d`)
- Commit `e3d5b5f` exists: FOUND (`git log --oneline --all | grep e3d5b5f`)
- CI run `36207227343` shows all four jobs `success`: FOUND (`gh run view 36207227343 --json jobs`)

---
*Phase: 03-apple-compression-to-parity*
*Completed: 2026-09-26*
