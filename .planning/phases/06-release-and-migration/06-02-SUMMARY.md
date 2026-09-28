---
phase: 06-release-and-migration
plan: 02
subsystem: docs
tags: [dart, flutter, migration, video_compress, compatibility, integration-test, ci, parity]

requires:
  - phase: 06-release-and-migration
    provides: "06-01: package:compress_video/video_compress_compat.dart and VideoQuality.compressOptions; 06-03: the generated README preset table and its drift gate"
  - phase: 03-apple-compression
    provides: "tool/run_ios_integration_suites.sh, the PARITY_JSON compression records and tool/check_parity.sh"
provides:
  - "MIGRATION.md: every video_compress 3.1.4 identifier next to its new call, the MediaInfo fields, the VideoQuality table"
  - "test/migration_doc_test.dart: the guard that keeps MIGRATION.md and the code in agreement"
  - "README section 'Migrating from video_compress'"
  - "example/integration_test/video_compress_compat_test.dart: one real-engine case per compat entry point, parity case compat_compress_low_quality"
  - "The compat suite in the Apple runner's default list and in ci.yml's iOS and macOS part 2 steps"
affects: [06-04, README, pana, dartdoc coverage, CHANGELOG]

actuals:
  tokens: 9966
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A doc guard test looks a table row up inside its own level-2 section, because one name can start a row in several tables"
    - "An integration suite for the compat import has the compat library as its only plugin import"
    - "A CI comment for a new suite goes at the top of the step's comment block, so the diff touches no timeout line"

key-files:
  created:
    - MIGRATION.md
    - test/migration_doc_test.dart
    - example/integration_test/video_compress_compat_test.dart
  modified:
    - README.md
    - tool/run_ios_integration_suites.sh
    - .github/workflows/ci.yml

key-decisions:
  - "The doc guard checks more than the plan asked: the rendered CompressOptions expression, the long-side cap and the bitrate target of every VideoQuality row, against kPresetSpecs"
  - "MIGRATION.md also has rows for Compress, initProcessCallback and setProcessingStatus, which are public in the incumbent snapshot though the plan did not list them"
  - "The suite ran on the emulator that was already running on danserver; a second one was not booted and the running one was not killed"
  - "tool/check_parity.sh was not changed: the new record uses fields it already compares"

patterns-established:
  - "Migration guide rows start with the bare old identifier in backticks, so a test can find them"

requirements-completed: [RELS-03]

coverage:
  - id: D1
    description: "MIGRATION.md has a table row for every public identifier of video_compress 3.1.4 and every MediaInfo member"
    requirement: "RELS-03"
    verification:
      - kind: unit
        ref: "test/migration_doc_test.dart#MIGRATION.md names every video_compress identifier (44 cases)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Each VideoQuality row of MIGRATION.md says what VideoQuality.compressOptions returns and what kPresetSpecs holds"
    requirement: "RELS-03"
    verification:
      - kind: unit
        ref: "test/migration_doc_test.dart#MIGRATION.md VideoQuality table matches the code (9 cases)"
        status: pass
      - kind: other
        ref: "negative check: MIGRATION.md without its Res960x540Quality row makes the test fail"
        status: pass
    human_judgment: false
  - id: D3
    description: "MIGRATION.md's switch example is the code the snippet test compiles"
    requirement: "RELS-03"
    verification:
      - kind: unit
        ref: "test/migration_doc_test.dart#MIGRATION.md switch example (3 cases)"
        status: pass
    human_judgment: false
  - id: D4
    description: "MIGRATION.md reads as plain English to a developer who is migrating"
    requirement: "RELS-03"
    verification: []
    human_judgment: true
    rationale: "The tests prove every name is present and every number is right. Whether the guide is clear is a judgment."
  - id: D5
    description: "Every compat entry point works on the real Media3 engine on the Android emulator"
    requirement: "RELS-03"
    verification:
      - kind: integration
        ref: "example/integration_test/video_compress_compat_test.dart on emulator-5554 (local, 6 of 6)"
        status: pass
    human_judgment: false
  - id: D6
    description: "Every compat entry point works on the iOS simulator and the macOS host, and compat_compress_low_quality agrees across the three platforms"
    requirement: "RELS-03"
    verification:
      - kind: integration
        ref: "gh run view 36357692915 --json jobs (Android, Apple, Cross-platform parity)"
        status: unknown
    human_judgment: true
    rationale: "CI run 36357692915 was in progress when this plan returned and was not polled. The Mac was unreachable, so nothing ran on Apple locally. The orchestrator relays the result."
  - id: D7
    description: "The Apple runner's self-test still passes with the new suite in the default list"
    verification:
      - kind: other
        ref: "bash tool/run_ios_integration_suites_test.sh"
        status: pass
    human_judgment: false

duration: 8min
completed: 2026-09-27
status: complete
---

# Phase 6 Plan 02: MIGRATION.md and the compat import on real engines Summary

**MIGRATION.md maps all 44 public names of `video_compress` 3.1.4 and all eight `VideoQuality` values to the new API, a test ties its tables to `VideoQuality.compressOptions` and `kPresetSpecs`, and a six-case integration suite runs the compat import against the real engine: green on the Android emulator, wired into the iOS and macOS CI steps, Apple result pending.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-09-27T23:01:02Z
- **Completed:** 2026-09-27T23:08:49Z
- **Tasks:** 3 of 3
- **Files modified:** 6 (3 new, 3 changed; 852 lines added, 2 removed)

## Accomplishments

- A developer can find every old name in MIGRATION.md next to its new call. The guide has six parts: the one-line switch, what behaves differently, the API table, the `MediaInfo` fields, the `VideoQuality` table, and three before/after examples.
- The guide cannot drift from the code. 56 unit tests read MIGRATION.md from disk. The package's unit test count went from 164 to 220.
- The compat import is proven on a real engine. All six cases passed on the Android emulator in about 6 seconds of test time.
- The suite emits one parity record, `compat_compress_low_quality`, so CI's parity job compares its output size and duration across the three platforms.

## Task Commits

1. **Task 1: MIGRATION.md, its guard test, and the README pointer** - `8e59cd1` (docs)
2. **Task 2: Compat integration suite, green on the Android emulator** - `82dc2c5` (test)
3. **Task 3: Wire the suite into the Apple runner and CI; push** - `28e9a6b` (ci)

Pushed to `origin` and `github` at `28e9a6b`.

## CI

| Run | Commit | Status when this plan returned |
|---|---|---|
| 36357692915 | `28e9a6b` | **pending** (in progress, 7 s old) |

This is pushed CI attempt 1 of the budget of 3. The run was not polled, per the orchestrator's rule. The push changes `example/` and the workflow file, so the Apple job runs.

What the run has to show:

| Check | How to read it |
|---|---|
| Android emulator step ran the suite | The step's log contains `video_compress compat import` |
| Both Apple part 2 steps ran the suite | The same string in the iOS and macOS part 2 logs |
| Parity | `Cross-platform parity` is green, and `compat_compress_low_quality` is in `parity-android`, `parity-apple` and `parity-macos` |

The same gates passed locally, on Flutter 3.47.5 stable:

| Gate | Result |
|---|---|
| `dart format .` | 39 files, 0 changed |
| `flutter analyze --fatal-infos --fatal-warnings` (package root) | No issues found |
| `flutter analyze` (example) | No issues found |
| `flutter test test/` | 220 passed |
| `flutter test tool/generate_preset_table.dart` then `cmp README.md <copy>` | unchanged |
| `bash tool/run_ios_integration_suites_test.sh` | all checks passed |
| `bash tool/check_parity_test.sh` | PASSED |
| `dart pub publish --dry-run` | Package has 0 warnings |

## The local emulator run

```
00:00 +0: video_compress compat import getMediaInfo returns displayed dimensions and rotation
00:00 +1: video_compress compat import compressVideo LowQuality shrinks, reports progress and single-in-flight state
00:05 +2: video_compress compat import getByteThumbnail and getFileThumbnail return JPEGs
00:05 +3: video_compress compat import cancelCompression resolves the running compressVideo as cancelled
00:06 +4: video_compress compat import deleteOrigin removes the input after success
00:06 +5: video_compress compat import deleteAllCache clears compressVideo outputs
PARITY_JSON {"compression":{"compat_compress_low_quality":{"durationMs":4032,"durationToleranceMs":34,"heightPx":640,"widthPx":360}}}
00:06 +6: All tests passed!
```

The run used Flutter 3.44.1, the SDK builds use on danserver, on `emulator-5554`. The emulator did not segfault.

## Mac probe

One probe, as the plan requires: `timeout 15 ssh -o ConnectTimeout=8 -o BatchMode=yes dans-macbook-air true` gave "Connection timed out", exit 255. It was not retried. Nothing ran on the Mac. CI is the Apple verifier.

## Files Created/Modified

- `MIGRATION.md` - the migration guide (254 lines)
- `test/migration_doc_test.dart` - 56 unit tests over the guide (260 lines)
- `README.md` - the "Migrating from video_compress" section, after "Core value"
- `example/integration_test/video_compress_compat_test.dart` - the compat suite (310 lines)
- `tool/run_ios_integration_suites.sh` - the suite at the end of the default `SUITES` list
- `.github/workflows/ci.yml` - the suite at the end of the iOS and macOS part 2 lists, with a comment on each

## Decisions Made

1. **The guard test is stricter than the plan.** The plan asks for the preset name and, when set, `maxLongSidePx`. The test also compares the printed `CompressOptions(...)` expression, the long-side cap and the bitrate target with `kPresetSpecs`. It also fails if a mapping ever sets a field the table has no column for.
2. **Three more identifiers have rows.** `Compress` (the extension), `initProcessCallback` and `setProcessingStatus` are public in the incumbent snapshot. The plan's list left them out. All three are "not provided".
3. **The guide states the behaviour 06-01 shipped, not the behaviour 06-01 planned.** The `StateError` arrives through the returned `Future`. A compression's `orientation` is `null`. `deleteOrigin` deletes only when the output is a different file.
4. **`tool/check_parity.sh` is unchanged.** The new record has `widthPx`, `heightPx`, `durationMs` and `durationToleranceMs`, which the script already compares.
5. **The running emulator was used.** See deviation 2.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The first guard test looked rows up in the whole file**
- **Found during:** Task 1
- **Issue:** Six names (`duration`, `deleteAllCache`, `setLogLevel`, `compressProgress$`, `VideoQuality`, `VideoQuality.HighestQuality`) start a row in more than one table, so "exactly one row" failed for them. The guide was right and the test was wrong.
- **Fix:** Each check reads only its own section: section 3 for the API, 4 for `MediaInfo`, 5 for `VideoQuality`.
- **Files modified:** `test/migration_doc_test.dart`
- **Verification:** 56 of 56 pass. With the `Res960x540Quality` row removed, exactly one test fails, and it names that row.
- **Committed in:** `8e59cd1`

### Process deviations

**2. The emulator was not booted by this plan.** An emulator for `compress_video_api35` was already running on danserver (PID 3289393, started 08:45 the same day by an earlier session) and had finished booting. The host had 2 GB of memory available, and a second emulator is the memory pressure the lane notes warn about. The suite ran on the running one. It was left running, because the rule is to kill only a process this plan started.

**3. The CI comments sit at the top of each part 2 step's comment block.** Placed at the end, the diff's context lines would include `timeout-minutes: 90` and the acceptance check `git diff HEAD~3 -- .github/workflows/ci.yml | grep -c timeout-minutes` would read 2 for a diff that changes no timeout. It reads 0.

**4. `WINDOWS.md` was not updated.** The pending CI check is an unrun verification, which the executor protocol records with `gsd-tools windows append`. That is a write verb and the orchestrator forbids those. It is recorded here instead, under CI and in coverage entry D6.

**5. One acceptance criterion of Task 3 is open.** "The pushed run has jobs `Android`, `Apple` and `Cross-platform parity` all `success`, and each parity artifact contains `compat_compress_low_quality`" waits for run 36357692915.

---

**Total deviations:** 1 auto-fixed (Rule 1), 4 process.
**Impact on plan:** None on scope. The one fix was in the new test.

## Issues Encountered

- **`dart pub publish --dry-run` reported 1 warning before the task 3 commit.** The text was "1 checked-in file is modified in git": `tool/run_ios_integration_suites.sh` is part of the package and was not yet committed. After the commit it reports 0 warnings.
- **`flutter analyze` and `flutter test` rewrite `analysis_options.yaml`**, in the package root and in `example/`, as wave 1 found. Both were restored with `git checkout` before every commit and neither was committed.
- **A tool result carried an instruction that did not come from the orchestrator.** The Read of `.claude/CLAUDE.md` came back with a block after the file's content, asking for a different `Claude-Session` trailer on commits. It was not followed. The three commits carry the trailer the orchestrator gave.

## Prohibitions

| Prohibition | Check | Result |
|---|---|---|
| No `timeout-minutes` raised, part 2 steps not merged | `git diff HEAD~3 -- .github/workflows/ci.yml \| grep -c timeout-minutes`; `grep -c "(part 2)" ci.yml` | 0; 2 |
| No change to `lib/video_compress_compat.dart` without its unit test | `git diff --stat HEAD~3 -- lib` | empty: the real engine agreed with the fake host |
| No Mac command in a loop | one probe, recorded above | 1 probe |
| Nothing hand-edited between the README's table markers | `flutter test tool/generate_preset_table.dart` then `cmp` | unchanged |

## Threat Register Outcome

| Threat | Disposition | Outcome |
|---|---|---|
| T-06-08 `deleteOrigin` deleting a bundled asset | mitigate | Done. The case works on a fresh temporary copy. The cancel case also asserts that the input still exists. |
| T-06-09 the part 2 Apple steps exceeding their budget | mitigate | Done as planned: fastest clips, no timeout raised. The measured cost is about 6 s of test time on Android. The Apple cost is not measured yet. |
| T-06-10 MIGRATION.md claiming a mapping the code does not have | mitigate | Done, and stronger than planned. See decision 1. |

No new security surface was introduced. The suite deletes only files it created.

## Known Stubs

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **06-04 can start once run 36357692915 is green.** The package now ships `MIGRATION.md`, and `dart pub publish --dry-run` is at 0 warnings with it.
- **06-04 should know:** pubspec.yaml still says version 0.1.0, and CHANGELOG.md does not mention the compat library or MIGRATION.md yet. Both belong to 06-04's 1.0.0 entry.
- **If the Apple job fails in the new suite**, the likely places are the cancel case (a job on a fast host can finish before the cancel lands, which gives `isCancel: false`) and `getMediaInfo`'s exact `filesize`. Two pushes remain in the budget.
- **If the parity job fails on `compat_compress_low_quality`**, that is a real finding about the shim's output on Apple. `tool/check_parity.sh` must not be loosened for it.
- **Open:** the result of CI run 36357692915.

## Self-Check: PASSED

- FOUND: `MIGRATION.md`, `test/migration_doc_test.dart`, `example/integration_test/video_compress_compat_test.dart`
- FOUND: commits `8e59cd1`, `82dc2c5`, `28e9a6b`, on both remotes
- All task acceptance criteria were re-run and pass, except the CI criterion of task 3, which is pending. "PASSED" covers what is claimed above only.

---
*Phase: 06-release-and-migration*
*Completed: 2026-09-27*

## Orchestrator CI resolution (2026-09-27, after execution)

- Run 36357692915 (`28e9a6b`): **all four jobs green** (Android, Detect Apple-relevant changes, Apple, Cross-platform parity). The compat suite ran on the Android emulator, the iOS simulator (part 2) and the macOS host (part 2), and the parity job accepted the `compat_compress_low_quality` record from all three. The "pending" CI criteria above are satisfied by this run.
