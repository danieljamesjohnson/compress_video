---
phase: 01-typed-contract-ci-and-media-info
plan: 01
subsystem: infra
tags: [android-sdk, emulator, github-actions, ci, toolchain, kvm]

# Dependency graph
requires: []
provides:
  - A working Android SDK + headless KVM-accelerated emulator on danserver (`~/Android/Sdk`, AVD `compress_video_api35`)
  - A private GitHub repository (`danieljamesjohnson/compress_video`) wired as the `github` remote, with a read-only default Actions workflow token, alongside the existing danserver `origin`
  - `docs/TOOLCHAIN.md` — quarterly toolchain-rot baseline with a verification date per pin
  - `.planning/phases/01-typed-contract-ci-and-media-info/COVERAGE.md` — API-coverage declaration (no external API)
  - A fully filled `01-VALIDATION.md` (Test Infrastructure, Sampling Rate, 20-row Per-Task Verification Map, Wave 0 Requirements, Manual-Only Verifications)
affects: [01-02, 01-03, 01-04, 01-05, 01-06, 01-07]

# Actuals (#2632)
actuals:
  tokens: 6000
  tasks: 3
  commits: 2

# Tech tracking
tech-stack:
  added: [openjdk-17-jdk-headless, android-cmdline-tools, android-emulator, gh-cli-repo-create]
  patterns: ["sg kvm -c wrapper for emulator/adb until next full re-login (mirrors sg docker pattern)"]

key-files:
  created:
    - docs/TOOLCHAIN.md
    - .planning/phases/01-typed-contract-ci-and-media-info/COVERAGE.md
  modified:
    - .claude/CLAUDE.md
    - .planning/phases/01-typed-contract-ci-and-media-info/01-VALIDATION.md

key-decisions:
  - "system-images;android-35;google_apis;x86_64 was available (the plan's primary choice); no fallback to android-36 system image was needed."
  - "GitHub repo created private per QUESTIONS.md #5 (Dan's call on when to flip public); default_workflow_permissions set to read via gh api."
  - "Killed a 47-day-hung apt.systemd.daily process holding the apt lock rather than waiting on it indefinitely (Rule 3 blocking-issue auto-fix)."

patterns-established:
  - "Android SDK env vars exported from both ~/.profile and ~/.bashrc (appended, not rewritten); flutter config --android-sdk run once."
  - "kvm group membership added but not yet live in this session — every adb/emulator command wrapped in sg kvm -c '<cmd>' until Dan's next full re-login."

requirements-completed: []  # BULD-05 is shared with sibling plans 01-03/01-04/01-07 still pending; shared-ID gate (#2388) blocks marking it Complete until all declaring plans finish.

coverage:
  - id: D1
    description: "Android SDK + JDK 17 installed and a headless KVM-accelerated emulator boots and is reachable via adb on danserver"
    requirement: "BULD-05"
    verification:
      - kind: other
        ref: "bash -lc 'flutter doctor -v' (exit 0, no ✗ in Android toolchain section)"
        status: pass
      - kind: other
        ref: "sg kvm -c 'adb devices' | grep -E '^emulator-[0-9]+\\s+device$'"
        status: pass
      - kind: other
        ref: "sg kvm -c 'adb shell getprop sys.boot_completed' -> 1 (booted in ~10s)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Private GitHub repository created and wired as a second remote (github) alongside origin, with a read-only default Actions workflow token"
    requirement: "BULD-05"
    verification:
      - kind: other
        ref: "gh repo view danieljamesjohnson/compress_video --json visibility,defaultBranchRef -> PRIVATE / main"
        status: pass
      - kind: other
        ref: "gh api repos/danieljamesjohnson/compress_video/actions/permissions/workflow -q .default_workflow_permissions -> read"
        status: pass
      - kind: other
        ref: "git rev-parse main github/main origin/main -> three identical shas"
        status: pass
    human_judgment: false
  - id: D3
    description: "Toolchain pin baseline (docs/TOOLCHAIN.md), API-coverage declaration (COVERAGE.md) and a fully filled 01-VALIDATION.md are committed with no template placeholders"
    verification:
      - kind: other
        ref: "grep -c 'Verified on' docs/TOOLCHAIN.md; grep -q '9.0.1'/'29.0.1'/'3.44.1' docs/TOOLCHAIN.md"
        status: pass
      - kind: other
        ref: "wc -l COVERAGE.md == 1; grep -c 'No external API integration' == 1"
        status: pass
      - kind: other
        ref: "grep -c 'REQ-{XX}' 01-VALIDATION.md == 0; grep -c '{quick command}' == 0"
        status: pass
    human_judgment: true
    rationale: "The plan's own acceptance criteria expects grep -c '^| 1-0' 01-VALIDATION.md == 21, but the plan's own verbatim table — and the actual total task count across all 7 phase-1 plans, independently verified — is 20. This is an off-by-one authoring bug in the plan text, not a missing row. Flagging for human awareness rather than silently declaring full pass on a criterion the plan itself cannot satisfy with real data."

# Metrics
duration: 35min
completed: 2026-09-15
status: complete
---

# Phase 1 Plan 01: Android Toolchain, GitHub Remote and Phase Declarations Summary

**Android SDK + headless KVM emulator installed on danserver, a private GitHub repo wired as a second remote with a read-only Actions token, and the phase's toolchain baseline, API-coverage declaration and validation contract all written.**

## Performance

- **Duration:** 35 min
- **Started:** 2026-09-15T14:26:00Z (approx.)
- **Completed:** 2026-09-15T14:42:12Z
- **Tasks:** 3 completed
- **Files modified:** 4 (1 created dir with 1 new file, 1 new file, 2 modified)

## Accomplishments
- Installed JDK 17, the Android command-line tools (fetched live from developer.android.com, sha256 recorded in the commit), platform-tools, platforms;android-36, build-tools;36.1.0 and the android-35 google_apis x86_64 system image under `~/Android/Sdk`
- Created and booted a headless AVD (`compress_video_api35`, pixel_6 profile) that reaches `sys.boot_completed=1` in ~10 s under KVM acceleration
- Created the private GitHub repository `danieljamesjohnson/compress_video`, added it as the `github` remote alongside the existing danserver `origin`, and locked its default Actions workflow token to read-only
- Wrote `docs/TOOLCHAIN.md`, the quarterly toolchain-rot baseline, with every pin's version, source of truth and verification date — several values (AGP, Kotlin, Gradle wrapper, compileSdk) confirmed live by generating a throwaway Flutter plugin and reading its generated build files directly, not from memory
- Wrote the one-line `COVERAGE.md` API-coverage declaration and fully replaced every placeholder in `01-VALIDATION.md`

## Task Commits

1. **Task 1: Install the Android toolchain and boot a headless emulator on danserver** - `06ae01a` (feat)
2. **Task 2: Create the private GitHub repository and wire it as a second remote** - no code commit (GitHub-side state + git remote configuration only, as specified by the plan's `<files>` field; verified via `gh` and `git` commands above)
3. **Task 3: Write the toolchain pin baseline, the API-coverage declaration and the phase validation contract** - `07cf773` (docs)

**Plan metadata:** (this commit, docs)

## Files Created/Modified
- `docs/TOOLCHAIN.md` - Quarterly toolchain-rot baseline, one row per pin with verification date
- `.planning/phases/01-typed-contract-ci-and-media-info/COVERAGE.md` - One-line API-coverage declaration
- `.planning/phases/01-typed-contract-ci-and-media-info/01-VALIDATION.md` - Filled Test Infrastructure, Sampling Rate, Per-Task Verification Map (20 rows), Wave 0 Requirements, Manual-Only Verifications
- `.claude/CLAUDE.md` - Lane notes updated with the full Android SDK install recipe (paths, package ids, AVD name, boot command, `sg kvm -c` requirement)

## Decisions Made
- Killed a 47-day-hung `apt.systemd.daily` process that was holding the apt lock (Jul 30 start date, only 9m15s of real CPU time — clearly stuck, not doing work) rather than waiting on it; this was a genuine blocker to Task 1's JDK install (Rule 3).
- Waited out a second, legitimate `unattended-upgrade --download-only` lock holder (3s old when discovered) instead of killing it, since it was actively running, not stuck.
- Used the `system-images;android-35;google_apis;x86_64` image as planned (no fallback to android-36 needed — it was available).
- GitHub repository created private per the locked decision in `01-CONTEXT.md`; QUESTIONS.md #5 already records that flipping it public is Dan's call.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Killed a hung apt.systemd.daily process holding the package manager lock**
- **Found during:** Task 1 (Install the Android toolchain)
- **Issue:** `sudo apt-get update` failed with `Could not get lock /var/lib/apt/lists/lock`, held by an `apt-get -qq -y update` process (PID 1101150) that had been running since **Jul 30** — 47 days — with only 9m15s of accumulated CPU time, i.e. genuinely stuck, not doing real work.
- **Fix:** `sudo kill -9` the stuck process tree, removed the stale lock files, ran `sudo dpkg --configure -a`, then retried `apt-get update`/`install` successfully. A second, legitimate lock holder (`unattended-upgrade --download-only`, 3s old) was waited out rather than killed.
- **Files modified:** none (system state only)
- **Verification:** `apt-get install openjdk-17-jdk-headless` completed cleanly on retry; `java -version` confirms 17.0.20
- **Committed in:** n/a (no repository files changed by this fix itself)

### Plan Text Issues (documented, not silently worked around)

**2. [Plan authoring bug] 01-VALIDATION.md acceptance criteria expects 21 Per-Task Verification Map rows; the plan's own verbatim data and the real task count are 20**
- **Found during:** Task 3 (Write the toolchain pin baseline, API-coverage declaration and validation contract)
- **Issue:** The task's `<acceptance_criteria>` and `<verify>` blocks assert `grep -c '^| 1-0' 01-VALIDATION.md` equals `21`. The plan's own "Validation strategy values" section — which the task instructs to transcribe verbatim — contains exactly 20 rows (one per task across plans 01-01 through 01-07). Independently counting `<task type="auto|tracer">` tags across all seven `01-*-PLAN.md` files also gives 20, matching the map. This is an off-by-one error in the plan's acceptance criteria, not a missing task or a data-entry mistake on my part.
- **Fix:** Transcribed the map verbatim as given (20 accurate rows, one per real task, all `⬜ pending` as specified — did not mark any row green ahead of schedule, correcting an earlier internal draft that had done so). Did not fabricate a fictitious 21st row to force the literal count check to pass, since doing so would violate the phase's own must-have truth ("one Per-Task Verification Map row for every task in plans 01-01 through 01-07") more severely than leaving the miscounted check unsatisfied.
- **Files modified:** `.planning/phases/01-typed-contract-ci-and-media-info/01-VALIDATION.md`
- **Verification:** `grep -c '^| 1-0' 01-VALIDATION.md` → 20 (documented as correct here); `grep -c 'REQ-{XX}'` → 0; `grep -c '{quick command}'` → 0; `wc -l COVERAGE.md` → 1
- **Committed in:** `07cf773`

---

**Total deviations:** 1 auto-fixed (1 blocking), 1 documented plan-text discrepancy (not auto-fixed, since fixing it would require fabricating data).
**Impact on plan:** No scope creep. The apt-lock kill was necessary to make any progress on Task 1. The row-count discrepancy has zero functional impact — the validation contract is complete and accurate against the real task set — but is called out so a future `/gsd-plan-phase` pass or plan reviewer can correct the "21" in `01-01-PLAN.md`'s acceptance criteria if desired.

## Issues Encountered
None beyond the deviations documented above.

## User Setup Required
None - no external service configuration required. (The GitHub repo, remote, and workflow-permission setting were all created via `gh`/`git`, not manual dashboard steps.)

## Next Phase Readiness
- Android code can now be compiled, tested and run on danserver without any further setup — `flutter doctor -v` is clean on the Android toolchain, and the emulator boots headless in ~10 s.
- The repository is on GitHub with both remotes (`origin`, `github`) in sync at the same commit, and a read-only default Actions workflow token, so plan 01-03's CI workflow can be added next without granting write access by accident.
- `docs/TOOLCHAIN.md`, `COVERAGE.md` and `01-VALIDATION.md` are in place for the rest of the phase to build against.
- Ready for 01-02-PLAN.md (generated corpus clips and sidecars), the other Wave 1 plan.
- Outstanding: `01-01-PLAN.md`'s Task 3 acceptance criteria should be corrected from 21 to 20 rows the next time this plan is touched (see Deviations above) — not blocking, informational only.

---
*Phase: 01-typed-contract-ci-and-media-info*
*Completed: 2026-09-15*
