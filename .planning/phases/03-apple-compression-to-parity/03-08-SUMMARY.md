---
phase: 03-apple-compression-to-parity
plan: 08
subsystem: testing
tags: [ci, parity-gate, macos, ios-simulator, github-actions, flutter-test, watchdog]

# Dependency graph
requires:
  - phase: 03-apple-compression-to-parity
    provides: "03-04 through 03-07's Apple compression engine (transmux, never-larger, audio modes, trim, estimate/clearCache) and 03-07's measured Apple preset tables (doc/PRESETS.md) -- the compression behaviour this plan's parity records diff across platforms"
provides:
  - "A 'compression' PARITY_JSON record family (case-name -> CompressResult-shaped fields) emitted by compress_test.dart, compress_audio_test.dart, compress_jobs_test.dart and compress_output_test.dart, diffed by an extended tool/check_parity.sh: exact match on dimensions/codecs/flags/channels/reason, sidecar-independent tolerance on durationMs, and a documented +/-50% envelope on outputBytes"
  - "tool/check_parity_test.sh proving every new field kind in both directions with hand-written fixtures, including a deliberately flipped transmuxed flag demonstrating the gate's teeth (T-03-36)"
  - "CI's apple job running a macOS desktop integration_test pass (not just native XCTest) through a per-suite watchdog runner, plus a macOS SPM build, plus a third parity-macos artifact"
  - "The parity job running TWO comparisons -- Android vs iOS, macOS vs iOS -- both green on CI run 36202392709"
  - "A fixed tool/run_ios_integration_suites.sh that also drives the macOS desktop target, working around a real upstream Flutter macOS-launch flake (leftover app instance re-activated by `open` instead of a fresh launch) discovered live on CI run 36195780910"
  - "Two explicit parity-gate arbitration decisions recorded in corpus/README.md: the truncated_mdat.mp4 error-reason divergence is documented, not gated; videoBitrateBps is deliberately not a gated field at all"
affects: [03-09]

# Actuals (#2632)
actuals:
  tokens: 15700
  tasks: 2
  commits: 4

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Nested 'compression' top-level PARITY_JSON key (case-name -> record), distinct from the flat per-clip media-info keys -- lets jq's `*` deep-merge combine four suites' own tearDownAll emissions into one map without a corpus-sidecar lookup per case"
    - "reset_device() device-branching in a shared watchdog script: simctl shutdown/boot/bootstatus for an iOS simulator UDID, pkill of the app executable/bundle for the literal device id `macos` -- because a process `open` hands off to launchd is never a member of the watchdog's own killed process group"

key-files:
  created: []
  modified:
    - example/integration_test/compress_test.dart
    - example/integration_test/compress_audio_test.dart
    - example/integration_test/compress_jobs_test.dart
    - example/integration_test/compress_output_test.dart
    - tool/check_parity.sh
    - tool/check_parity_test.sh
    - tool/run_ios_integration_suites.sh
    - tool/run_ios_integration_suites_test.sh
    - .github/workflows/ci.yml
    - corpus/README.md
    - QUESTIONS.md

key-decisions:
  - "Task 1 (tool/verify_fresh_app.sh, BULD-02's fresh-app CI/Mac proof) did NOT execute: its own <precondition> (`bash tool/mac_sync.sh && bash tool/mac_run.sh build-macos` exits 0) is unmet -- `ssh dans-macbook-air` times out, the same recurring blocker 03-01 task 1 never fully closed either. Per the executor precondition protocol this is never auto-approved or worked around; nothing was written or committed for it."
  - "truncated_mdat.mp4's error-reason divergence (Android io/2000, Apple unsupportedInput/-11880, 03-06-SUMMARY.md) is documented in corpus/README.md and deliberately NOT recorded in any PARITY_JSON line or gated -- both mappings are independently correct, verified readings of a genuinely different native diagnostic for the same damaged file, not a bug. Only the two error reasons already proven identical on every platform (fileNotFound, unsupportedInput-for-zero-byte) are gated."
  - "videoBitrateBps is deliberately NOT added to the compression PARITY_JSON schema at all: doc/PRESETS.md's measured Android undershoot (~71% at p1080) vs Apple overshoot (~103-110%) would need a tolerance too wide (a 30-40 percentage-point spread) to catch a real regression in either direction -- the measured numbers already live in doc/PRESETS.md, which is the right place for a comparison table, not a pass/fail gate."
  - "CI run 36195780910's single `flutter test integration_test -d macos` invocation (covering all six suites in one process) failed on a real upstream Flutter flake: once one suite's app instance is left running, macOS's `open` re-activates it instead of launching fresh for the next suite, so no new VM-service port opens. Fixed by extending tool/run_ios_integration_suites.sh to also drive the macOS device id -- one `flutter test <suite>` process per suite through the existing watchdog, with reset_device() killing any leftover app process before every macOS suite (not only after a failed attempt, since kill_tree cannot reach a process `open` already handed off to launchd)."
  - "Neither CORE-01, CORE-07 nor BULD-02 is marked complete in REQUIREMENTS.md: all three remain declared by 03-09 (and BULD-02 also by 03-01, itself still partial), so the shared-ID gate keeps them Pending regardless of this plan's own progress."

patterns-established:
  - "A per-device watchdog script (build-phase marker regex, dead-launch regex, device-specific reset) generalizes cleanly by branching on the device-id argument rather than forking a second script -- kept the iOS behavior provably unchanged (7 pre-existing self-test cases still pass verbatim) while adding 2 new macOS cases"

requirements-completed: []  # CORE-01/CORE-07/BULD-02 all still declared by 03-09 (BULD-02 also by 03-01); shared-ID gate keeps them Pending

coverage:
  - id: D1
    description: "CI's apple job runs the full integration_test suite (all six .dart files) on the iOS simulator, unchanged from before this plan (allowlist already removed by an earlier plan) -- confirmed green"
    requirement: CORE-01
    verification:
      - kind: integration
        ref: "CI run 36202392709, job Apple, step 'Run corpus integration tests on the iOS simulator': media_info 9/9, thumbnail 16/16, compress_test 23/23, compress_audio 7/7, compress_jobs 10/10, compress_output 15/15"
        status: pass
    human_judgment: false
  - id: D2
    description: "CI's apple job also runs the full integration_test suite on the macOS desktop target, through a per-suite watchdog runner that survives the real upstream 'leftover app instance' launch flake found live on CI run 36195780910"
    requirement: CORE-01
    verification:
      - kind: integration
        ref: "CI run 36195780910 (macOS step FAILED, diagnosed) then CI run 36202392709 (macOS step SUCCEEDED, all six suites); tool/run_ios_integration_suites_test.sh local self-test, 9/9 cases including the 2 new macOS-specific fixtures"
        status: pass
    human_judgment: false
  - id: D3
    description: "The four compression suites emit PARITY_JSON compression records for genuinely deterministic cases; tool/check_parity.sh compares them (exact fields, embedded-tolerance durationMs, +/-50%-envelope outputBytes) and the parity job runs both the Android-vs-iOS and the macOS-vs-iOS comparison, both green"
    requirement: CORE-01
    verification:
      - kind: integration
        ref: "CI run 36202392709, job 'Cross-platform parity', both 'Diff cross-platform parity values' steps succeeded; locally, tool/check_parity_test.sh 10/10 cases (6 new compression fixtures) and a full local Android-emulator run (80/80 tests) confirming real PARITY_JSON emission"
        status: pass
    human_judgment: false
  - id: D4
    description: "The gate has teeth, demonstrated once: a deliberately flipped transmuxed flag in a self-test fixture makes tool/check_parity_test.sh fail and name the field (T-03-36)"
    verification:
      - kind: unit
        ref: "tool/check_parity_test.sh, case 'flipped transmuxed flag correctly fails and names compression.transmux_bad.transmuxed'"
        status: pass
    human_judgment: false
  - id: D5
    description: "tool/verify_fresh_app.sh (the fresh-app four-build proof, BULD-02) was NOT written -- task 1's own <precondition> (a proven Mac toolchain) is unmet"
    requirement: BULD-02
    verification: []
    human_judgment: true
    rationale: "Task did not run -- ssh dans-macbook-air times out (offline, same recurring blocker as 03-01 task 1). Nothing was written or committed for this deliverable; it is fully outstanding, not partially proven. A human must wake the Mac (QUESTIONS.md #8) before this can be attempted."

# Metrics
duration: 135min
completed: 2026-09-26
status: partial  # task 1 (tool/verify_fresh_app.sh, BULD-02) did not execute -- Mac unreachable; tasks 2 (minus the fresh-app CI step) and 3 are complete and verified on CI run 36202392709
---

# Phase 3 Plan 08: Compression Parity Gate and macOS CI Watchdog Fix Summary

**Compression-result parity now diffed across Android, iOS and macOS (dimensions/codecs/flags/duration exact-or-tolerant, bytes within a documented +/-50% envelope), and the macOS desktop integration suite now survives a real upstream Flutter launch flake through the same per-suite watchdog the iOS simulator already used -- but the fresh-app CocoaPods/SPM build proof (BULD-02) is still blocked on the MacBook Air being offline.**

## Performance

- **Duration:** 135 min (mostly CI wall-clock across two pushed attempts)
- **Started:** 2026-09-25T22:14:49Z (first commit)
- **Completed:** 2026-09-26T00:29:53Z (second, green CI run)
- **Tasks:** 2 of 3 (task 1 blocked; task 2 delivered minus its Mac-dependent step; task 3 fully delivered)
- **Files modified:** 11

## Accomplishments

- Added `PARITY_JSON {"compression": {...}}` emission to all four compression suites (`compress_test.dart`: default re-encode, never-larger, transmux, trim; `compress_audio_test.dart`: passthrough, 2ch/1ch reencode, no-track; `compress_jobs_test.dart`: the two error reasons already proven identical cross-platform; `compress_output_test.dart`: the three estimate/result-agreement cases), for genuinely deterministic fields only.
- Extended `tool/check_parity.sh` with a `compression` case-name -> record comparator: exact match on `widthPx`/`heightPx`/`videoCodec`/`audioCodec`/`transmuxed`/`usedOriginal`/`audioReencoded`/`channels`/`reason`/`wouldTransmux`/`wouldUseOriginal`, an embedded-per-record tolerance check on `durationMs`, and a documented +/-50% envelope on `outputBytes`. `elapsedMs` is recorded for the log only.
- Extended `tool/check_parity_test.sh` with 6 new fixture pairs proving both directions, including a deliberately flipped `transmuxed` flag demonstrating the gate's teeth once (T-03-36) -- all 10 self-test cases pass.
- Widened CI's `apple` job: a macOS desktop `integration_test` pass (all six suites, D-22 -- the shared Swift core is now exercised end-to-end on macOS, not merely compiled), a third `parity-macos` artifact, and a macOS build under Swift Package Manager (D-20). The two-suite allowlist and its stale comment were already gone before this plan started (confirmed by grep).
- Widened the `parity` job to run two comparisons -- Android vs iOS (unchanged) and macOS vs iOS (new, held to the same strictness since both share one Swift core) -- both green.
- **Found and fixed a real bug live on CI (attempt 1, run 36195780910):** a single `flutter test integration_test -d macos` invocation covering all six suites failed after the first suite passed, because macOS's `open` re-activates a leftover app instance instead of launching fresh, so no new VM-service port ever opens for the remaining suites. Extended `tool/run_ios_integration_suites.sh` to also drive the macOS device id: one `flutter test <suite>` process per suite through the existing watchdog, a `reset_device()` that kills any leftover `compress_video_example` process/bundle before every macOS suite (not only after a failed attempt -- `kill_tree` cannot reach a process `open` already handed off to `launchd`), and build-done/dead-launch regexes widened to also match macOS's own message shapes. Proven locally first via 2 new self-test fixtures, then confirmed green on CI run 36202392709.
- Recorded two explicit parity-gate arbitration decisions in `corpus/README.md`, both requested by 03-06/03-07's carried-forward flagged assumptions: the `truncated_mdat.mp4` error-reason divergence is documented, not gated; `videoBitrateBps` is deliberately not a gated field at all.
- **Task 1 (`tool/verify_fresh_app.sh`, BULD-02) did not execute:** its `<precondition>` is unmet (Mac unreachable). Recorded in `QUESTIONS.md` #8.

## Task Commits

1. **Task 3: Emit and compare compression parity records** — `533f238` (feat)
2. **Task 2: Widen the CI apple job (minus the fresh-app step)** — `54b3402` (feat)
3. Blocker record for task 1 — `1974e0a` (docs)
4. **Fix: macOS integration-suite launch flake found on CI attempt 1** — `70becbf` (fix)

**Task 1 (`tool/verify_fresh_app.sh`) has no commit — nothing was written for it.**

_Executed out of the plan's own task order (3 before 2) since task 3's tool changes had no dependency on task 2's CI wiring, while getting real CI signal as early as possible mattered more than matching the written order; both were pushed together for the same CI run regardless._

## Files Created/Modified

- `example/integration_test/compress_test.dart` / `compress_audio_test.dart` / `compress_jobs_test.dart` / `compress_output_test.dart` — `PARITY_JSON` compression-record emission
- `tool/check_parity.sh` — compression-record comparator (exact/tolerant/±50%-envelope fields)
- `tool/check_parity_test.sh` — 6 new fixture pairs proving both directions
- `tool/run_ios_integration_suites.sh` — macOS device-id support, `reset_device()`, widened build-done/dead-launch regexes
- `tool/run_ios_integration_suites_test.sh` — 2 new macOS-specific fixture cases, fake `pkill`
- `.github/workflows/ci.yml` — macOS integration step (now via the watchdog script), `parity-macos` artifact, macOS SPM build, two-comparison `parity` job
- `corpus/README.md` — compression parity gate documentation, two arbitration decisions
- `QUESTIONS.md` — #8 updated with task 1's precondition-unmet record

## Decisions Made

See `key-decisions` in the frontmatter above for the full list with rationale (task 1 precondition-unmet halt; the two parity arbitration decisions; the macOS watchdog fix; no requirement marked complete).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed the macOS integration-suite launch flake found on CI attempt 1**
- **Found during:** Task 2 (widening the `apple` job's macOS integration step), on the first pushed CI attempt (run 36195780910)
- **Issue:** The plan's own text specified a single `flutter test integration_test -d macos` invocation for the macOS desktop run. On the hosted runner this failed after the first suite: `open` re-activates a leftover app instance for later suites instead of launching fresh, so `flutter_tools` never sees a new VM-service port and reports "Unable to start the app on the device."
- **Fix:** Extended `tool/run_ios_integration_suites.sh` (previously iOS-simulator-only) to also drive the macOS device id, one `flutter test <suite>` process per suite through its existing launch watchdog, with a device-aware `reset_device()` that kills any leftover app process before every macOS suite.
- **Files modified:** `tool/run_ios_integration_suites.sh`, `tool/run_ios_integration_suites_test.sh`, `.github/workflows/ci.yml`
- **Verification:** 2 new self-test fixtures locally (9/9 total self-test cases pass), then CI run 36202392709: macOS step green, all six suites.
- **Committed in:** `70becbf`

---

**Total deviations:** 1 auto-fixed (Rule 1 — real bug, not scope creep: the plan's own literal invocation was the thing that failed).
**Impact on plan:** Necessary to make Task 2's macOS integration run actually work; no scope creep beyond fixing the discovered bug.

## Issues Encountered

**Task 1 blocked, not an "issue solved" but a designed stop:** `tool/verify_fresh_app.sh`'s `<precondition>` (a proven Mac toolchain via `bash tool/mac_sync.sh && bash tool/mac_run.sh build-macos`) is unmet — `ssh dans-macbook-air` times out (`tailscale status`: offline, last seen 5h ago at the time of the check). This is the same recurring blocker 03-01 task 1 never fully closed either (its own `build-macos` proof was left "Outstanding" when the Mac slept mid-build). Per the executor precondition protocol this is never auto-approved or worked around, even in this project's unattended `mode: yolo` configuration. Recorded in `QUESTIONS.md` #8.

This plan is marked `status: partial`, not `halted`: per Dan's 2026-09-25 instruction to resume Phase 3 at 03-06 and run autonomously past Mac-dependent items (the same treatment 03-01's own deferred Mac proof received — see `03-01-SUMMARY.md` "Task 1 progress, 2026-09-25" and `STATE.md`'s "Deferred Items"), a `halted` status here would incorrectly block `03-09` through the dependency graph. `halted` is reserved for a designed stop that should gate downstream work; this is a known, tracked, externally-blocked item that does not.

## User Setup Required

None — no external service configuration required. The Mac being offline needs a physical action from Dan (open the lid / keep it awake), recorded in `QUESTIONS.md` #8, not a one-time setup step.

## Next Phase Readiness

- **CI run 36202392709 is the candidate "one green run covering every suite and the parity gate"** 03-09's own `must_haves` asks for: Android (all suites), Apple (iOS simulator six suites green, macOS desktop six suites green, both native XCTest runners green, both SPM builds green), and Cross-platform parity (both the Android-vs-iOS and the macOS-vs-iOS comparison green, over media-info, thumbnail AND compression records).
- **03-09 still needs, from the Mac specifically:** task 1's `tool/verify_fresh_app.sh` (BULD-02's fresh-app four-build proof) is entirely unwritten. Resume with `bash tool/mac_sync.sh && bash tool/mac_run.sh build-macos` once `timeout 15 ssh -o ConnectTimeout=8 -o BatchMode=yes dans-macbook-air true` succeeds, then execute 03-08-PLAN.md's task 1 exactly as written (write the script, prove the SPM half on the Mac, add the CI step referencing it -- both CocoaPods-path and SPM-path builds on the runner, since the runner has CocoaPods and the Mac does not). This is a small, self-contained follow-up; nothing else in this plan depends on it being done in a fresh session versus resumed mid-phase.
- **Not blocking 03-09's own work:** the two 03-05-era `skip: !Platform.isAndroid` lines noted in earlier summaries are already removed; the parity gate's compression coverage, the macOS integration run, and the two-comparison `parity` job are all real and proven on CI, independent of task 1.
- **CORE-01, CORE-07 and BULD-02 remain unchecked in `REQUIREMENTS.md`** — all three are also declared by 03-09 (BULD-02 additionally by 03-01, itself still partial), so the shared-ID gate correctly keeps them `Pending` until every declaring plan finishes.

## Self-Check: PASSED

- `[ -f tool/check_parity.sh ]`, `[ -f tool/check_parity_test.sh ]`, `[ -f tool/run_ios_integration_suites.sh ]`, `[ -f tool/run_ios_integration_suites_test.sh ]` → all FOUND
- `[ -f example/integration_test/compress_test.dart ]` (and the audio/jobs/output siblings) → all FOUND
- `git log --oneline --all --grep="03-08"` → FOUND (533f238, 54b3402, 1974e0a, 70becbf)
- `bash tool/check_parity_test.sh` → PASSED (10/10 cases)
- `bash tool/run_ios_integration_suites_test.sh` → PASSED (9/9 cases)
- CI run 36202392709 → `success` on every job (Android, Apple, Cross-platform parity)

---
*Phase: 03-apple-compression-to-parity*
*Completed: 2026-09-26*
