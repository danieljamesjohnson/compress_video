---
phase: 03-apple-compression-to-parity
plan: 01
subsystem: testing
tags: [corpus, ffmpeg, validation, ci, mac-build-host]

# Dependency graph
requires:
  - phase: 02-android-compression-on-media3
    provides: Android reference engine and corpus conventions (crossPlatform/tolerant sidecar fields, verify_corpus.sh derivation pattern)
provides:
  - "corpus/trim_source_10s.mp4 and its derived `trim` sidecar block — the fixture every Phase 3 trim assertion (CORE-07) reads its numbers from"
  - "Phase 3's validation contract (03-VALIDATION.md) confirmed against the real plan files, and COVERAGE.md confirmed present"
affects: [03-02, 03-03, 03-04, 03-05, 03-06, 03-07, 03-08, 03-09]

# Actuals (#2632)
actuals:
  tokens: 9800
  tasks: 2
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "trim sidecar block: startMs/endMs literal, expectedDurationMs derived (endMs - startMs), toleranceMs derived as one frame at the clip's own measured fps, rounded UP to the next whole ms (ceiling) — never hardcoded in a test"

key-files:
  created:
    - corpus/trim_source_10s.mp4
    - corpus/trim_source_10s.expected.json
    - example/assets/corpus/trim_source_10s.mp4
    - example/assets/corpus/trim_source_10s.expected.json
  modified:
    - corpus/generate_corpus.sh
    - corpus/verify_corpus.sh
    - corpus/sync_to_example.sh
    - corpus/README.md
    - example/pubspec.yaml
    - .planning/phases/03-apple-compression-to-parity/03-VALIDATION.md
    - QUESTIONS.md

key-decisions:
  - "toleranceMs is derived as ceiling(1000/measured_fps), not nearest-rounding — nearest-rounding gives 33 at 30fps, but the phase's own must_have requires exactly 34, matching every existing 30fps clip's hardcoded durationToleranceMs convention"
  - "Task 1 (Mac second-SDK bring-up, tool/mac_sync.sh, tool/mac_run.sh) did not execute: its precondition (`ssh dans-macbook-air true` exits 0) was unmet because the Mac is offline on the tailnet, confirmed twice ~15 minutes apart. Per the executor precondition protocol this is never auto-approved and the task was not partial-committed."

patterns-established:
  - "Corpus fixture self-assertion for a new clip (stream counts, coded dims, frame rate, duration window, size cap) mirrors the existing Clip A-E pattern in generate_corpus.sh exactly, keeping the six-clip file byte-reproducible across two runs"

requirements-completed: []  # CORE-07/BULD-02 remain open; this plan only lands the shared fixture + validation infra, no compress behavior

coverage:
  - id: D1
    description: "trim_source_10s.mp4 (10s, 30fps, 1280x720, H.264+AAC, no rotation matrix) generated, self-asserted and byte-reproducible across two runs"
    requirement: CORE-07
    verification:
      - kind: other
        ref: "bash corpus/generate_corpus.sh (twice) + sha256sum diff"
        status: pass
    human_judgment: false
  - id: D2
    description: "trim sidecar block (startMs 2000, endMs 7000, expectedDurationMs 5000, toleranceMs 34) machine-derived by verify_corpus.sh --write, matches on default-mode diff"
    requirement: CORE-07
    verification:
      - kind: other
        ref: "bash corpus/verify_corpus.sh; jq -e assertions against corpus/trim_source_10s.expected.json"
        status: pass
    human_judgment: false
  - id: D3
    description: "New clip + sidecar mirrored into example/assets/corpus/ with sha256 verification, declared in example/pubspec.yaml assets, flutter pub get succeeds"
    verification:
      - kind: other
        ref: "bash corpus/sync_to_example.sh; cd example && flutter pub get"
        status: pass
    human_judgment: false
  - id: D4
    description: "No pre-existing corpus clip or sidecar changed as a side effect of this plan"
    verification:
      - kind: other
        ref: "git diff --exit-code -- corpus/portrait_rot90.expected.json corpus/small_480p.expected.json corpus/noaudio_720p.expected.json corpus/portrait_hibitrate_1080p60.expected.json"
        status: pass
    human_judgment: false
  - id: D5
    description: "03-VALIDATION.md's Per-Task Verification Map row count (27) matches the real task count counted from the nine 03-0*-PLAN.md files (27); every CORE-01/CORE-07/BULD-02/BULD-04 requirement and every T-03-* reference resolves; COVERAGE.md exists"
    verification:
      - kind: other
        ref: "for f in 03-0*-PLAN.md; do grep -cE '<name>Task '; done | sum, compared against the table's own row count"
        status: pass
    human_judgment: false
  - id: D6
    description: "Mac build-host bring-up (second Flutter SDK, tool/mac_sync.sh, tool/mac_run.sh, SPM build proof) — task 1, requirement BULD-02"
    requirement: BULD-02
    verification: []
    human_judgment: true
    rationale: "Task did not run — its precondition (ssh dans-macbook-air true exits 0) is unmet because the Mac is offline on the tailnet. Nothing was written or committed for this deliverable; it is fully outstanding, not partially proven. A human must wake the Mac (QUESTIONS.md #8) before this can be attempted."

# Metrics
duration: 9min
completed: 2026-09-22
status: partial  # task 1 executed 2026-09-25 except the Mac build proof -- see "Task 1 progress"
---

# Phase 3 Plan 01: Mac Build Host, Trim Fixture and Validation Reconciliation Summary

**Generated the 10-second `trim_source_10s.mp4` corpus fixture with a machine-derived `trim` sidecar block, and confirmed Phase 3's validation contract against the real plan files — but the Mac build-host bring-up (task 1) could not run because the MacBook Air is offline on the tailnet.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-09-22T14:24:00Z
- **Completed:** 2026-09-22T14:33:26Z
- **Tasks:** 2 of 3 completed (task 1 blocked, precondition unmet)
- **Files modified:** 11 (across 2 commits, plus 1 blocker-recording commit to QUESTIONS.md)

## Accomplishments

- `corpus/generate_corpus.sh` extended with Clip F, `trim_source_10s.mp4` (10s, 30fps, 1280x720 coded, H.264 + AAC stereo at 128kbps/48kHz, no rotation matrix, ~1Mbps, explicit 30-frame GOP), self-asserting stream counts, coded dimensions, frame rate, duration window and size cap; proven byte-reproducible across two full regeneration runs
- `corpus/verify_corpus.sh` extended to derive a `trim` sidecar block for this one clip (`startMs: 2000, endMs: 7000, expectedDurationMs: 5000, toleranceMs: 34`), refusing to derive it if the range is inverted or lands within 500ms of the clip's own measured duration
- Clip and sidecar mirrored into `example/assets/corpus/` (sha256-verified) and declared in `example/pubspec.yaml`'s assets list; `flutter pub get` confirmed clean
- No existing corpus clip or sidecar changed as a side effect (independently verified via `git diff`)
- `03-VALIDATION.md`'s Per-Task Verification Map row count (27, seeded at plan time) confirmed to exactly match the real task count counted from the nine `03-0*-PLAN.md` files (3 tasks × 9 plans = 27) — no off-by-one this time, unlike Phase 1 and Phase 2. Every `CORE-01`/`CORE-07`/`BULD-02`/`BULD-04` requirement and every `T-03-*` threat reference independently confirmed to resolve against the real plan files. `COVERAGE.md` confirmed present and correctly declares no external API integration.

## Task Commits

Each completed task was committed atomically:

1. **Task 2: Generate the 10-second trim fixture and derive its sidecar trim block** - `3be485c` (feat)
2. **Task 3: Reconcile the phase validation contract against the real plan files and write the coverage declaration** - `c31f8b0` (docs)

Additionally, `eb7bfa4` (docs) records the task 1 blocker in `QUESTIONS.md` #8.

**Task 1 (Mac build host bring-up) did not execute — no commit exists for it.** See Deviations below.

_Note: this plan's `<tasks>` block has 3 tasks; only 2 completed this session._

## Files Created/Modified

- `corpus/trim_source_10s.mp4` - the 10s trim fixture
- `corpus/trim_source_10s.expected.json` - its ground-truth sidecar, including the new `trim` block
- `example/assets/corpus/trim_source_10s.mp4` / `.expected.json` - mirrored copies for the example app's asset bundle
- `corpus/generate_corpus.sh` - Clip F generation + self-assertion
- `corpus/verify_corpus.sh` - `trim` block derivation, added to `CLIPS`
- `corpus/sync_to_example.sh` - added to the clip mirror list
- `corpus/README.md` - documents the new clip and the `trim` sidecar block's fields
- `example/pubspec.yaml` - declares the two new asset paths
- `.planning/phases/03-apple-compression-to-parity/03-VALIDATION.md` - row-count note updated to record the confirmation
- `QUESTIONS.md` - new #8, recording the Mac-offline blocker

## Decisions Made

- `toleranceMs` in the `trim` sidecar block is derived as `ceiling(1000 / measured_fps)`, not nearest-rounding — nearest-rounding of `1000/30 = 33.33` gives `33`, but the plan's own `must_haves` requires exactly `34`, matching the fixed `34ms` `durationToleranceMs` convention every existing 30fps clip in this corpus already hardcodes. This is documented in both `verify_corpus.sh`'s inline comment and `corpus/README.md`.
- Task 1 was not attempted beyond its precondition check: per the executor's precondition protocol, an unmet `<precondition>` is never auto-approved and the task is never partial-committed, even in this unattended run. No `tool/mac_sync.sh`/`tool/mac_run.sh` file was created; no Mac SDK install was attempted.

## Deviations from Plan

### Task 1 not executed — precondition unmet (not an auto-fixable deviation)

**Task 1's `<precondition>`** — `ssh dans-macbook-air true exits 0 from danserver without a password prompt, and ssh dans-macbook-air 'xcodebuild -version' prints Xcode 26.x` — **was checked and found unmet.**

- **Found during:** Task 1, before any file was written (precondition check runs before task work per the executor protocol)
- **Evidence:** `timeout 20 ssh -o ConnectTimeout=10 -o BatchMode=yes dans-macbook-air 'echo CONNECTED'` → `ssh: connect to host dans-macbook-air port 22: Connection timed out`, reproduced twice ~15 minutes apart (a background attempt at plan start, and a foreground retry near the end of this session, after tasks 2 and 3 completed). `tailscale status` independently confirms: `dans-macbook-air ... macOS active; relay "dfw"; offline, last seen 5m ago`.
- **Not the previously-resolved QUESTIONS.md #1 permission issue** (that was "Permission denied" at the SSH layer; this is a network-layer timeout — the machine itself is unreachable, most likely asleep).
- **Action taken:** Did NOT proceed with task 1. Did NOT write `tool/mac_sync.sh` or `tool/mac_run.sh`. Did NOT attempt the Mac SDK install. Recorded the blocker as `QUESTIONS.md` #8 with exact reproduction evidence and the unblock action (wake the Mac). Did NOT send a `notify-dan` push — waking the Mac requires Dan's physical presence, which he cannot do in response to a notification if he isn't near it right now; this is recorded, not pushed, per the danserver push/record policy.
- **Proceeded with tasks 2 and 3**, which have no dependency on the Mac and were fully completable, verified and committed independently.
- **This is a `gate="blocking-human"`-class stop**, not Rules 1-3 (bug/missing-critical/blocker) — no amount of auto-fixing on danserver can make a remote machine reachable, and per the precondition protocol an unmet precondition is never auto-approved even under this project's `mode: yolo` / unattended configuration.

---

**Total deviations:** 1 (precondition-unmet task stop, not auto-fixed, not architectural).
**Impact on plan:** Task 1's deliverables (second Flutter SDK on the Mac, `tool/mac_sync.sh`, `tool/mac_run.sh`, SPM build proof against the current example) remain entirely outstanding. Every later plan in Phase 3 that assumes a working Mac build-host workflow (03-02 onward, all of which use `tool/mac_run.sh`) is blocked until task 1 completes. Tasks 2 and 3 have no such dependency and are fully done.

## Issues Encountered

None beyond the Task 1 precondition block documented above.

## User Setup Required

None - no external service configuration required. The Mac being asleep/offline needs a physical action from Dan (open the lid / wake it), not a service configuration step; recorded in `QUESTIONS.md` #8, not this section, since it is not a one-time setup task but a per-session availability check.

## Next Phase Readiness

- **Not ready to proceed to 03-02 through 03-09** in the normal sense — every subsequent plan in this phase depends on `tool/mac_sync.sh`/`tool/mac_run.sh` existing and a working Mac SDK, neither of which exists yet.
- **The trim fixture and validation contract are ready** — 03-07 (which owns the CORE-07 trim assertion) can proceed once the Mac workflow exists, reading `corpus/trim_source_10s.expected.json`'s `trim` block rather than any hardcoded number.
- **Resume path:** re-check `ssh dans-macbook-air true` (or re-run `/gsd-execute-phase 3`, which will re-attempt task 1's precondition). Once the Mac answers, execute task 1 exactly as `03-01-PLAN.md` specifies — nothing about task 1 has changed, and no work has been lost or needs to be redone for tasks 2/3.
- **Per the atomic close-out invariant:** this plan intentionally has no `03-01-SUMMARY.md` claiming full completion — `status: halted` above reflects that task 1 is outstanding, not that the plan finished. A future execution should re-summarize as `status: complete` once task 1 lands, or this halted summary should be read alongside a task-1-only follow-up commit.

## Task 1 progress, 2026-09-25 (continued under the `/gsd-autonomous` resume from 03-06)

The Mac was reachable again on 2026-09-25 (~09:15-09:40 CDT) and Dan had installed Homebrew 5.1.15
and CocoaPods 1.17.0 on it since QUESTIONS.md #7 was written, so task 1 was executed directly:

- **Second SDK:** already present at `~/development/flutter-stable` -- `flutter --version` prints
  `Flutter 3.47.5 • channel stable` (>= 3.44.0). `flutter config` shows
  `enable-swift-package-manager: true`. Dan's `~/flutter` HEAD before:
  `90673a4eef275d1a6692c26ac80d6d746d41a73a`; nothing ran from it, and the "after" read could not be
  taken because the Mac slept (see below) -- re-read it on the next Mac session.
- **`tool/mac_sync.sh`** written and proven (commit `ba3c15e`): 26 then 17 files transferred;
  `ls -a ~/CodeProjects/compress-video` on the Mac shows `pubspec.yaml` and `darwin` and no
  `.git`, `.planning`, `build` or `.dart_tool`.
- **`tool/mac_run.sh`** written and proven: `MAC_RUN_TIMEOUT=2 mac_run.sh shell 'sleep 30'` exits
  142 in 19 s and leaves no `sleep` on the Mac (the alarm kills the whole remote process group;
  CI's exec-only alarm would not); `shell true` exits 0, `shell false` exits 1. First version had a
  real bug (`exec </dev/null` at the top of a `bash -s` script ends the script) -- fixed by reading
  the script with `bash -c "$(cat)"`.
- **`build-ios` ran and FAILED on a real code defect:** `Arguments.swift:254` -- a ten-term `??`
  chain over `String?` -- hit "The compiler is unable to type-check this expression in reasonable
  time" on the Mac's Xcode 26.2, which CI's faster runner never tripped. Fixed in `fac7f69`
  (same checks, same order, walked as a `[() -> String?]`).
- **Outstanding:** `build-ios` after that fix and `build-macos` (it reached "Building macOS
  application..." and then the Mac went to sleep; SSH timed out from ~09:40). CI's `apple` job
  builds iOS via CocoaPods, iOS via SPM and macOS on every push, so the fix is validated there
  meanwhile; the Mac-side proof is the only acceptance criterion still open. Resume with
  `bash tool/mac_sync.sh && bash tool/mac_run.sh build-ios && bash tool/mac_run.sh build-macos`
  next time `timeout 15 ssh -o ConnectTimeout=8 -o BatchMode=yes dans-macbook-air true` succeeds.
- The `.claude/CLAUDE.md` lane note for the Mac workflow is recorded (same commit as this summary).

Status is `partial`, not `halted`: with Dan's 2026-09-25 instruction to resume Phase 3 at 03-06 and
run autonomously, the Mac build proof is a deferred item (STATE.md "Deferred Items"), not a
designed stop that should keep 03-06..03-09 blocked.

## Self-Check: PASSED

- `[ -f corpus/trim_source_10s.mp4 ]` → FOUND
- `[ -f corpus/trim_source_10s.expected.json ]` → FOUND
- `[ -f example/assets/corpus/trim_source_10s.mp4 ]` → FOUND
- `[ -f example/assets/corpus/trim_source_10s.expected.json ]` → FOUND
- `git log --oneline --all --grep="03-01"` → FOUND (3be485c, c31f8b0)
- Task 2 full `<verify><automated>` block re-run post-commit → PASSED (see task commit)
- Task 3 full `<verify><automated>` block re-run → PASSED (see task commit)

---
*Phase: 03-apple-compression-to-parity*
*Completed: 2026-09-22 (tasks 2-3); task 1 executed 2026-09-25 except the Mac build proof*
