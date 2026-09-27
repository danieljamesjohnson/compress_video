---
phase: 05-jobs-isolates-and-background
plan: 05
subsystem: docs
tags: [documentation, requirements, validation, jobs-03, jobs-04, jobs-05, compress-video]

# Dependency graph
requires:
  - phase: 05-jobs-isolates-and-background
    provides: "05-01 through 05-04's implementations and their own SUMMARY.md evidence for JOBS-03/JOBS-04/JOBS-05, plus CI run 36327133883 (05-04's push) as the observed all-four-jobs-green run this plan cites rather than re-earns"
provides:
  - "One coherent README section ('Jobs beyond the foreground') covering the queue, background isolates, the Android foreground service and the iOS suspension contract, with the Android 15 floor, the notification-visibility caveat, and the manifest-merge note folded in"
  - "A consolidated Phase 5 CHANGELOG entry (JOBS-03/04/05 sub-bullets) replacing three separate bullets"
  - "doc/HARDWARE_CHECKLIST.md's missing Android phone backgrounding walkthrough, alongside the existing iPhone suspension entry"
  - "05-VALIDATION.md's Per-Task Verification Map fully filled (15/15 rows), status: validated"
  - "COVERAGE.md's notification-permission row corrected to what 05-03 actually verified"
  - "JOBS-04 and JOBS-05 closed in REQUIREMENTS.md on named CI evidence (JOBS-03 was already closed by 05-01)"
affects: [phase-6-release-and-migration]

# Actuals (#2632)
actuals:
  tokens: 9210
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Citing an already-observed CI run as current evidence for a docs-only plan, with live confirmation (via gh run list before/after push) that the repository's own paths-ignore rule produced no new run, rather than assuming or hiding the absence of a fresh run"

key-files:
  created: []
  modified:
    - README.md
    - CHANGELOG.md
    - doc/HARDWARE_CHECKLIST.md
    - .planning/phases/05-jobs-isolates-and-background/05-VALIDATION.md
    - .planning/phases/05-jobs-isolates-and-background/COVERAGE.md
    - .planning/REQUIREMENTS.md

key-decisions:
  - "Did not re-push code to force a fresh CI run. This plan's entire diff is Markdown/.planning-only; ci.yml's own on.push.paths-ignore (**/*.md, .planning/**) means such a push triggers zero workflow runs by this repository's own design, confirmed live by checking `gh run list` immediately after each of this plan's three pushes. Citing the still-current CI run 36327133883 (headSha 4f5264d, no code changed since) is the honest choice, not a shortcut -- the alternative (an artificial dummy code change solely to force a CI run) would be exactly the kind of gate-gaming this plan's own threat model (T-05-27) prohibits."
  - "Corrected COVERAGE.md row 4 rather than leaving the plan-time claim standing: 05-03 verified only the notification-permission-absent case (the example app never requests POST_NOTIFICATIONS at all), not a granted/denied comparison as the row originally implied. This is a real execution finding, documented rather than smoothed over, and does not block JOBS-05's closure since the requirement's own contract never depended on the notification being visible."
  - "Left JOBS-03 exactly as REQUIREMENTS.md already had it (closed by 05-01's own single-plan close, since JOBS-03 has no shared-ID gate) rather than touching that line -- the plan's own acceptance criterion (diff confined to the three JOBS lines and their three table rows) is satisfied whether or not a given line's value actually changes; JOBS-03's line legitimately did not need to change."

requirements-completed: [JOBS-03, JOBS-04, JOBS-05]

coverage:
  - id: D1
    description: "README's four background-related subsections reorganised into one coherent 'Jobs beyond the foreground' story, with the Android 15 floor, the notification-visibility caveat, and the two-permission/one-service manifest-merge note folded into the existing Android bullet"
    requirement: "JOBS-05"
    verification:
      - kind: other
        ref: "grep -ci 'foreground service' README.md == 2; grep -n 'Android 15' README.md matches; grep -c maxConcurrentJobs README.md == 4; grep -c ensureInitializedInBackgroundIsolate README.md == 3"
        status: pass
      - kind: other
        ref: "flutter analyze --fatal-infos --fatal-warnings && flutter test && dart format --output=none --set-exit-if-changed lib test (stable SDK) && dart pub publish --dry-run, all exit 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "CHANGELOG's three separate Phase 5 bullets consolidated into one 'Jobs, isolates and background execution' entry with JOBS-03/04/05 sub-bullets, removing duplication"
    requirement: "JOBS-03"
    verification:
      - kind: other
        ref: "dart pub publish --dry-run exit 0 (lints CHANGELOG structure)"
        status: pass
    human_judgment: false
  - id: D3
    description: "doc/HARDWARE_CHECKLIST.md gains the missing Android phone backgrounding walkthrough entry, honestly marked not-yet-run, alongside the pre-existing iPhone suspension entry from 05-04"
    requirement: "JOBS-05"
    verification:
      - kind: other
        ref: "grep -c 'not yet run' doc/HARDWARE_CHECKLIST.md includes the new Android entry and the existing iPhone entry"
        status: pass
    human_judgment: false
  - id: D4
    description: "05-VALIDATION.md's Per-Task Verification Map filled: 15/15 rows, each citing CI run 36321581676 and/or 36327133883 or a local command the cited plan summary quotes; status set to validated"
    requirement: "JOBS-03, JOBS-04, JOBS-05"
    verification:
      - kind: other
        ref: "awk row-count self-check: 15 rows == 15 tasks across the five plan files; grep -c 'JOBS-0' == 18 (>= 15); grep -c '⬜' == 0"
        status: pass
    human_judgment: false
  - id: D5
    description: "COVERAGE.md's notification-permission row (#4) corrected to state what 05-03 actually verified (the permanently-absent case only, not a granted/denied comparison)"
    requirement: "JOBS-05"
    verification:
      - kind: other
        ref: "diff against the pre-edit copy shows exactly one row changed, no other row touched"
        status: pass
    human_judgment: false
  - id: D6
    description: "REQUIREMENTS.md hand-edited (copied first, diff read line by line, no gsd-tools write verb run) to close JOBS-04 and JOBS-05 on named CI evidence"
    requirement: "JOBS-03, JOBS-04, JOBS-05"
    verification:
      - kind: other
        ref: "git diff .planning/REQUIREMENTS.md shows exactly two checkbox lines and two status-table rows changed (JOBS-04, JOBS-05 -> Complete); JOBS-03's line was already Complete from 05-01 and needed no change"
        status: pass
    human_judgment: false
  - id: D7
    description: "The full local gate re-run green (flutter analyze, flutter test 96/96, the Android native unit suite 188/0 failed, corpus/verify_corpus.sh, tool/check_parity_test.sh, tool/run_ios_integration_suites_test.sh, dart pub publish --dry-run, the full example/integration_test directory 105/105 on the booted emulator), pushed to both remotes, with CI run 36327133883 confirmed (via direct gh run view --log inspection) to have run and passed jobs_background_test.dart on the Android emulator, the iOS Simulator and the macOS host, and no new CI run triggered by this plan's own docs-only push"
    requirement: "JOBS-03, JOBS-04, JOBS-05"
    verification:
      - kind: e2e
        ref: "local: all commands listed above, exit 0; CI: run 36327133883, all four jobs (Android, Detect Apple-relevant changes, Apple, Cross-platform parity) success, confirmed via `gh run view --json jobs`"
        status: pass
    human_judgment: false

duration: 70min
completed: 2026-09-27
status: complete
---

# Phase 5 Plan 5: Phase closure — one coherent background story, the validation map filled, and JOBS-03/04/05 closed on named evidence Summary

**Reorganised the README's queue/isolate/foreground-service/suspension material into one traceable "Jobs beyond the foreground" story, filled `05-VALIDATION.md`'s 15-row Per-Task Verification Map against CI runs 36321581676 and 36327133883, corrected a COVERAGE.md row the execution had actually disproven, and hand-closed JOBS-04/JOBS-05 in REQUIREMENTS.md — confirming live that this plan's own docs-only push triggers no new CI run under this repository's `paths-ignore` rule, so the already-green 36327133883 stands as the cited evidence rather than an artificially forced fresh run.**

## Performance

- **Duration:** ~70 min (mostly documentation/reconciliation work plus one 4-minute local emulator suite run and log inspection of a completed CI run — no new CI wait was needed)
- **Tasks:** 3
- **Files modified:** 6 (0 created)

## Accomplishments

- **README's background material reads as one story now.** A new "Jobs beyond the foreground: queueing, isolates and backgrounding" intro frames the four existing subsections (Queueing several compressions / Calling from a background isolate / Background execution and app suspension) in the order a caller runs into them, and the Android bullet gained three things the plan required: an explicit "Android 15 (API 35) and above" floor with the inert-below-that behaviour spelled out, the notification-visibility caveat (the compression completes even if `POST_NOTIFICATIONS` was never granted, since the plugin never requests it), and the manifest-merge note (two permissions plus one non-exported, fully-namespaced service that merge into the consuming app via Gradle's standard merger).
- **CHANGELOG's three separate Phase 5 bullets consolidated into one entry** ("Jobs, isolates and background execution") with JOBS-03/04/05 as ordered sub-bullets, in the same queue-then-isolate-then-background order as the README, removing the prior reverse-chronological presentation with no loss of content (the breaking-change note and every technical detail survived verbatim).
- **`doc/HARDWARE_CHECKLIST.md` gained the missing Android phone backgrounding walkthrough** — install, enable the foreground-service option, background/lock the screen, confirm the notification and the completed job, then repeat with the option off to observe the documented difference — in the same format and "not yet run" marker as the pre-existing entries (including 05-04's iPhone suspension entry, which needed no change).
- **`05-VALIDATION.md`'s Per-Task Verification Map filled completely**: all 15 rows (one per task across the five Phase 5 plans) now carry a concrete Status citing either CI run 36321581676 (05-03's own Android gate — the live `dumpsys` poll and the `aapt2` merged-manifest assertion) or 36327133883 (05-04's push, which re-ran every prior Phase 5 suite with zero regression). Document status set to `validated`, `wave_0_complete: true`.
- **Found and fixed the actual missing proof for JOBS-04's Apple half**: rather than trust the prior plans' own characterisation, I ran `gh run view --job <id> --log` directly against CI run 36327133883's Apple job and confirmed `jobs_background_test.dart` printed "All tests passed!" on both the iOS Simulator (`4E3A6BB3…`, 2026-09-27T15:15:52Z, 3 cases) and the macOS host (2026-09-27T15:58:20Z, 3 cases) — including the omitted-initialisation case for both. This is the specific evidence that closes JOBS-04.
- **`COVERAGE.md`'s notification-permission row corrected**: the plan-time note claimed 05-03 would verify both a granted and a denied `POST_NOTIFICATIONS` case live; the actual execution (05-03-SUMMARY.md) found the example app never requests that permission at all, so only the permanently-absent case has ever been observed. Row 4 now states this honestly rather than leaving the unearned "verified both" claim standing.
- **`REQUIREMENTS.md` hand-edited** (copied to `/tmp` first, edited, `git diff` read line by line before each commit, no `gsd-tools` write verb run): JOBS-04 and JOBS-05 checkboxes and status-table rows flipped to `Complete`. JOBS-03's line was already `Complete` (closed by 05-01's own single-plan close at execution time, since JOBS-03 has no shared-ID gate) and needed no edit.
- **Full local gate re-run green and pushed**: `flutter analyze --fatal-infos --fatal-warnings` clean, `flutter test` 96/96, `./gradlew :compress_video:testDebugUnitTest` 188 passed/0 failed (run from `example/android`, matching `ci.yml`'s own working directory), `bash corpus/verify_corpus.sh` clean, `bash tool/check_parity_test.sh` all pass, `bash tool/run_ios_integration_suites_test.sh` all pass, `dart pub publish --dry-run` 0 warnings, and the full `example/integration_test` directory (105 cases, including `jobs_background_test.dart`'s 3) passed on the booted `compress_video_api35` emulator with exit 0.

## README claim mapping

Every behavioural claim added or kept in the new "Jobs beyond the foreground" section traces to a
sentence in one of 05-01 through 05-04's own SUMMARY.md files:

| README claim | Source |
|---|---|
| `maxConcurrentJobs`, FIFO queue, per-instance independence, cancel-while-queued | 05-01-SUMMARY.md Accomplishments (queue gating, cancel-while-queued via the exact typed-cancellation path, per-instance independence) |
| Background isolate: `ensureInitializedInBackgroundIsolate`, progress never delivered off-root, typed failure on omission | 05-02-SUMMARY.md Accomplishments (`Isolate.run` proof, `_ensureFlutterApiRegistered` catching `StateError`/`UnsupportedError`) |
| Android: opt-in `androidForegroundService`, Android 15+ floor, inert below API 35 | 05-CONTEXT.md decisions (D-07/D-08) and 05-03-SUMMARY.md coverage D5 ("below API 35 the option is accepted and inert") |
| Android: six-hour quota expiry -> `interrupted`, retryable, partial deleted | 05-03-SUMMARY.md Accomplishments (`onTimeout`'s cancel-all-then-stop via `JobRegistry.cancel`'s new `reason`) |
| Android: notification may not be visible without `POST_NOTIFICATIONS`, compression still completes | 05-03-SUMMARY.md key-decisions (assumption A1: zero runtime permissions granted, every run still passes) |
| Android: two permissions + one non-exported service merge into the consuming app | 05-03-SUMMARY.md Accomplishments (manifest declarations) + 05-RESEARCH.md Pitfall 4/Assumption A2 |
| iOS: `beginBackgroundTask`, extra time limited, `interrupted` on expiry or AVFoundation interruption, no entitlement/`UIBackgroundModes` added | 05-04-SUMMARY.md Accomplishments (`IOSBackgroundTaskGuard`, `ErrorMapping.swift`'s `interruptedBySystem`, coverage D6) |
| macOS unaffected (never suspended) | 05-04-SUMMARY.md Accomplishments ("macOS unaffected... never suspended") |

## Task Commits

1. **Task 1: One coherent background story, and the walkthroughs nobody ran** - `11455cc` (docs)
2. **Task 2: The validation map filled, and three requirements closed on named evidence** - `af5a4d8` (docs)
3. **Task 3: The phase gate — one green run across every platform, with nothing narrowed to get it** - `0422f4b` (docs)

## Files Created/Modified

- `README.md` — new "Jobs beyond the foreground" intro tying the four background subsections together; Android bullet gained the API-35 floor, notification caveat, and manifest-merge note.
- `CHANGELOG.md` — three Phase 5 bullets consolidated into one entry with JOBS-03/04/05 sub-bullets.
- `doc/HARDWARE_CHECKLIST.md` — new Android phone backgrounding walkthrough entry.
- `.planning/phases/05-jobs-isolates-and-background/05-VALIDATION.md` — Per-Task Verification Map fully filled (15/15 rows); `status: validated`, `wave_0_complete: true`.
- `.planning/phases/05-jobs-isolates-and-background/COVERAGE.md` — row 4 (notification permission) corrected to match what was actually verified.
- `.planning/REQUIREMENTS.md` — JOBS-04 and JOBS-05 checkboxes and status-table rows closed to `Complete`.

## Decisions Made

See `key-decisions` above (frontmatter) for the three load-bearing calls: citing the already-observed CI run rather than forcing an artificial one; correcting the COVERAGE.md row instead of leaving an unearned claim standing; and leaving JOBS-03's already-correct REQUIREMENTS.md line untouched.

## Deviations from Plan

None — plan executed exactly as written. The one thing worth naming explicitly (not a deviation, since the plan itself anticipated it): Task 3's literal instruction to "push... and watch one CI run to completion" could not produce a *new* CI run, because this plan's entire diff across all three tasks is Markdown/`.planning/`-only, and `.github/workflows/ci.yml`'s own `on.push.paths-ignore` (`**/*.md`, `.planning/**`) means such a push triggers zero workflow runs by this repository's own design — confirmed live via `gh run list` immediately after each push (headSha stayed `4f5264d`, no new run appeared). The already-observed CI run 36327133883 (05-04's push) is cited as the current, unsuperseded evidence instead, since no code has changed since it ran.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Phase 5 is now fully complete: 5/5 plans.** JOBS-03, JOBS-04 and JOBS-05 are all `Complete` in `REQUIREMENTS.md`, each on named, verifiable evidence (05-01's local+CI proof for JOBS-03; CI run 36327133883's Apple-job log for JOBS-04's Apple half plus 05-02's Android proof; CI runs 36321581676/36327133883 plus the XCTest/Dart round-trip pair for JOBS-05).
- **What remains genuinely unproven is written down, not hidden**: `doc/HARDWARE_CHECKLIST.md` now carries both real-device walkthroughs this phase could not run (a physical Android phone backgrounding run, a physical iPhone suspension run), each honestly marked "not yet run" with a pointer to the QUESTIONS.md entries that block them (#3 for Android, #7/#8 for the Mac/iPhone).
- No blockers for Phase 6 (Release and Migration) — this plan touched no code, and every Phase 5 requirement it declared is now closed.
- Ready for `/gsd-verify-work 5`.

---
*Phase: 05-jobs-isolates-and-background*
*Completed: 2026-09-27*

## Self-Check: PASSED

- All modified files found on disk: `README.md`, `CHANGELOG.md`, `doc/HARDWARE_CHECKLIST.md`, `.planning/phases/05-jobs-isolates-and-background/05-VALIDATION.md`, `.planning/phases/05-jobs-isolates-and-background/COVERAGE.md`, `.planning/REQUIREMENTS.md`.
- `git log --oneline -3` shows `0422f4b`, `af5a4d8`, `11455cc` in order on `main`, both pushed to `origin` and `github` (confirmed via `git push` output for each).
- Plan-level `<verification>` re-run: `flutter analyze --fatal-infos --fatal-warnings` clean, `flutter test` 96/96, `./gradlew :compress_video:testDebugUnitTest` 188/0 failed, `bash corpus/verify_corpus.sh` clean, `bash tool/check_parity_test.sh` all pass, `bash tool/run_ios_integration_suites_test.sh` all pass, `dart pub publish --dry-run` 0 warnings, full `example/integration_test` directory 105/105 on `compress_video_api35` (exit 0).
- CI run 36327133883 confirmed `success` on all four jobs via `gh run view --json jobs`; `jobs_background_test.dart` confirmed passing on the Android emulator, the iOS Simulator and the macOS host via direct `gh run view --job <id> --log` inspection (quoted in this summary and in `05-VALIDATION.md`).
- `git diff .github/workflows/ci.yml` for this plan (`f471897..0422f4b`) is empty — no budget raised, no suite skipped, no assertion loosened.
