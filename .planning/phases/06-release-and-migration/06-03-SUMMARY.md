---
phase: 06-release-and-migration
plan: 03
subsystem: docs
tags: [dart, flutter, readme, presets, generator, ci, drift-gate]

requires:
  - phase: 02-android-compression
    provides: kPresetSpecs, CompressOptions.maxFps, doc/PRESETS.md's Android measured table
  - phase: 03-apple-compression
    provides: doc/PRESETS.md's iOS Simulator and macOS host measured tables
provides:
  - "tool/preset_table.dart: parseMeasuredRows, renderPresetTable, replaceBetweenMarkers, presetTableStart, presetTableEnd"
  - "tool/generate_preset_table.dart: `flutter test tool/generate_preset_table.dart` rewrites README.md between the markers"
  - "README 'Presets at a glance' with the generated per-platform table"
  - "README 'What this plugin deliberately does not do' covering every D-06 non-goal"
  - "ci.yml step 'Verify README preset table matches the preset constants (RELS-02)'"
affects: [06-02, 06-04, README, pana, dartdoc coverage]

actuals:
  tokens: 8243
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A generated README block sits between two HTML comment markers; only the generator writes there"
    - "A tool script that needs the package's Dart API runs as a flutter_test test, because the package imports dart:ui"
    - "A generator fails loudly (StateError naming platform and preset) and never writes a partial table"

key-files:
  created:
    - tool/preset_table.dart
    - tool/generate_preset_table.dart
    - test/preset_table_test.dart
  modified:
    - README.md
    - .github/workflows/ci.yml

key-decisions:
  - "The README section is a level-3 heading (### Presets at a glance), not level-2, so the Usage subsections after it keep their parent"
  - "The first sentence under the table says an encoder lands near the target, not on it; 'ceiling' would contradict the Apple columns beside it"
  - "parseMeasuredRows finds columns by header name, not by position, and rejects a duplicate row"
  - "'(at 30 fps)' is PresetSpec's own nominal frame rate (presetNominalFps), kept separate from the maxFps cap"

patterns-established:
  - "Generated-doc drift gate: regenerate, then git diff --exit-code, placed before ci.yml's `git checkout -- .` reset"

requirements-completed: [RELS-02]

coverage:
  - id: D1
    description: "parseMeasuredRows reads the 1080p60 rows of doc/PRESETS.md's three measured tables and throws StateError on any missing heading, column, cell or row"
    requirement: "RELS-02"
    verification:
      - kind: unit
        ref: "test/preset_table_test.dart#parseMeasuredRows (8 cases)"
        status: pass
    human_judgment: false
  - id: D2
    description: "renderPresetTable renders the D-12 columns, one row per preset in declaration order, deterministically"
    requirement: "RELS-02"
    verification:
      - kind: unit
        ref: "test/preset_table_test.dart#renderPresetTable (10 cases)"
        status: pass
    human_judgment: false
  - id: D3
    description: "replaceBetweenMarkers changes only the text between the markers and throws when a marker is missing, repeated or out of order"
    requirement: "RELS-02"
    verification:
      - kind: unit
        ref: "test/preset_table_test.dart#replaceBetweenMarkers (7 cases)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The README table is generated and regenerating it changes nothing"
    requirement: "RELS-02"
    verification:
      - kind: other
        ref: "flutter test tool/generate_preset_table.dart (twice) && cmp README.md <copy> && git diff --exit-code README.md"
        status: pass
    human_judgment: false
  - id: D5
    description: "Changing a preset constant without regenerating the README makes the gate's two commands exit non-zero"
    requirement: "RELS-02"
    verification:
      - kind: other
        ref: "local drift self-check: p720 2500000 -> 2600000, gate exit 1; clean tree, gate exit 0"
        status: pass
    human_judgment: false
  - id: D6
    description: "The non-goals section names every D-06 item in plain English, with the nearest supported alternative"
    requirement: "RELS-02"
    verification:
      - kind: other
        ref: "8 case-insensitive greps over the section (web, FFmpeg, overlays, keepHdr, background isolate, Android 15, iOS, Upload), all >= 1"
        status: pass
    human_judgment: true
    rationale: "The greps prove every topic is named. Whether the wording reads as plain English to a developer is a judgment."
  - id: D7
    description: "The new CI step is green on the Android job of the pushed run"
    requirement: "RELS-02"
    verification:
      - kind: other
        ref: "gh run view 36349558026 --json jobs"
        status: unknown
    human_judgment: true
    rationale: "CI run 36349558026 was pending when this plan returned; the orchestrator relays its result. The step's exact commands passed locally."

duration: 5min
completed: 2026-09-27
status: complete
---

# Phase 6 Plan 03: Generated README preset table and non-goals Summary

**The README's per-platform preset table is now generated from `kPresetSpecs`, `CompressOptions().maxFps` and doc/PRESETS.md's measured rows by `flutter test tool/generate_preset_table.dart`, a CI step fails on any README diff after regenerating, and the non-goals section names all ten things the plugin will not do.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-09-27T20:46:49Z
- **Completed:** 2026-09-27T20:51:28Z
- **Tasks:** 3 of 3
- **Files modified:** 5 (3 new, 2 changed; 828 lines added, 2 removed)

## Accomplishments

- The README states each preset's longest side, bitrate target and frame rate cap, next to what that preset produced from the 1080p60 corpus clip on Android, iOS and macOS.
- Nobody types that table. The generator builds it, and a parse that is missing any of the 12 rows throws and writes nothing.
- A preset constant that changes without a regenerated README turns CI red. This was proven locally: exit 1 on a changed constant, exit 0 on a clean tree.
- The non-goals section grew from 3 bullets to 10 and covers every item in D-06.
- The package's unit test count went from 139 to 164.

## The generated table

| Preset | Longest side (px) | Video bitrate target | Frame rate cap | Android | iOS | macOS |
|---|---|---|---|---|---|---|
| p360 | 640 | 0.8 Mbps (at 30 fps) | 30 fps (never raised) | 360×640, 0.75 Mbps | 360×640, 0.86 Mbps | 360×640, 0.84 Mbps |
| p480 | 854 | 1.2 Mbps (at 30 fps) | 30 fps (never raised) | 480×854, 0.88 Mbps | 480×854, 1.32 Mbps | 480×854, 1.27 Mbps |
| p720 | 1280 | 2.5 Mbps (at 30 fps) | 30 fps (never raised) | 720×1280, 1.48 Mbps | 720×1280, 2.67 Mbps | 720×1280, 2.59 Mbps |
| p1080 | 1920 | 5 Mbps (at 30 fps) | 30 fps (never raised) | 1080×1920, 3.55 Mbps | 1080×1920, 5.26 Mbps | 1080×1920, 5.18 Mbps |

This copy is for the reader of this summary. README.md holds the real one.

## Task Commits

1. **Task 1: Preset table renderer and parser, unit-tested** - `86bb9ca` (feat)
2. **Task 2: Generator entry point, README table and non-goals section** - `4a2611c` (docs)
3. **Task 3: CI drift gate; commit and push** - `3ec3648` (ci)

Pushed to `origin` and `github` at `3ec3648`.

## CI

| Run | Commit | Status when this plan returned |
|---|---|---|
| 36349558026 | `3ec3648` | **pending** (6 s old) |

This is pushed CI attempt 1 of the plan's budget of 3. The run was not polled, per the orchestrator's rule. The push cancelled 06-01's run 36349144752 through the workflow's cancel-in-progress rule, as expected, and this run covers 06-01's commits too. The workflow file changed, so the Apple job runs as well.

The same gates passed locally, on Flutter 3.47.5 stable:

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | exit 0, 37 files, 0 changed |
| `flutter analyze --fatal-infos --fatal-warnings` | No issues found |
| `flutter test test/` | 164 passed |
| `flutter test tool/generate_preset_table.dart` then `git diff --exit-code README.md` | exit 0 |
| `dart pub publish --dry-run` | Package has 0 warnings |

## Drift self-check

Run locally before the push and not committed.

| Tree | Gate's two commands | Exit code |
|---|---|---|
| Clean | `flutter test tool/generate_preset_table.dart` then `git diff --exit-code README.md \|\| { ...; exit 1; }` | **0** |
| `kPresetSpecs` p720 changed from 2,500,000 to 2,600,000 | same | **1** |

On the changed tree the generator rewrote the p720 row to `2.6 Mbps` and the step printed `FATAL: README preset table is stale -- run: flutter test tool/generate_preset_table.dart`. Both files were then restored with `git checkout -- lib/src/presets.dart README.md`.

## Why the generator runs under `flutter test`

`dart run tool/generate_preset_table.dart` was run once and failed with exit code 254. Its first error line:

```
../../development/flutter-stable/packages/flutter_test/lib/src/_goldens_io.dart:11:8: Error: Dart library 'dart:ui' is not available on this platform.
```

The import path it reported was `generate_preset_table.dart => package:compress_video => package:flutter => dart:ui`. `flutter test` accepted the path `tool/generate_preset_table.dart` as it is, so the file did not need the `_test.dart` suffix and no rename was made.

## Files Created/Modified

- `tool/preset_table.dart` - pure parser, renderer and marker replacement (299 lines)
- `tool/generate_preset_table.dart` - the generator entry point (52 lines)
- `test/preset_table_test.dart` - 25 unit tests (425 lines)
- `README.md` - the "Presets at a glance" section and 7 more non-goal bullets
- `.github/workflows/ci.yml` - the drift gate step, at line 265

## Decisions Made

1. **The README heading is level 3.** The plan asks for `## Presets at a glance` between two `###` subsections of `## Usage`. A level-2 heading there would make "Jobs beyond the foreground" and the six subsections after it children of the preset section. The heading is `### Presets at a glance`. A grep for the plan's string still matches.
2. **The first sentence does not call the target a ceiling.** The iOS and macOS columns show 2.67 and 2.59 Mbps against a 2.5 Mbps target. The sentence says the target is what the encoder is asked for and that an encoder lands near it.
3. **Columns are found by header name.** A reordered doc/PRESETS.md table still parses, and a renamed column throws with the column's name.
4. **A duplicate row throws.** Two `portrait_hibitrate_1080p60` rows for one preset in one table would make the README depend on row order.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] A level-2 heading would have broken the README's outline**
- **Found during:** Task 2
- **Issue:** See decision 1.
- **Fix:** Used `###`.
- **Files modified:** `README.md`
- **Verification:** `grep -n "^## \|^### " README.md` shows the Usage subsections in one run.
- **Committed in:** `4a2611c`

**2. [Rule 1 - Bug] The first draft of the generated sentence contradicted the table**
- **Found during:** Task 2
- **Issue:** See decision 2. The draft said "The bitrate target is a ceiling".
- **Fix:** Reworded in `renderPresetTable`, then regenerated.
- **Files modified:** `tool/preset_table.dart`, `README.md`
- **Verification:** the generator is idempotent after the change; 25 unit tests pass.
- **Committed in:** `4a2611c`

### Process deviations

**3. One commit per task, not separate RED and GREEN commits.** Task 1 is marked `tdd="true"`, but Task 3 names exactly three commits and the orchestrator ran with TDD mode off. The test file was written before the library.

**4. `WINDOWS.md` was not updated.** The pending CI check is an unrun verification, which the executor protocol records with `gsd-tools windows append`. That is a write verb and the orchestrator forbids those. It is recorded here instead, under CI and in coverage entry D7.

**5. Two acceptance criteria of Task 3 are open.** "The pushed run's Android job shows the new step as `success`" waits for run 36349558026. "Both remotes equal `HEAD`" held at `3ec3648` and holds again after this summary's own push.

---

**Total deviations:** 2 auto-fixed (Rule 1), 3 process.
**Impact on plan:** Both fixes are about the README being true and readable, which is this plan's purpose. No scope was added.

## Issues Encountered

- **`flutter analyze` and `flutter test` on Flutter 3.47.5 rewrite `analysis_options.yaml`**, as 06-01 found. The generator run does it too. The file was restored with `git checkout -- analysis_options.yaml` before every commit and was never committed. The CI gate diffs only `README.md`, so this rewrite cannot trip it.
- **A push that changes only Markdown starts no CI run.** `ci.yml` ignores `**/*.md`. A change to doc/PRESETS.md alone, with a stale README, is caught at the next push that touches any other file, not at once. A preset constant lives in `lib/`, so that case is caught at once. The plan forbids touching the path gate, so it is unchanged. 06-04 may want to decide whether doc/PRESETS.md should be taken out of the ignore list.

## Prohibitions

| Prohibition | Check | Result |
|---|---|---|
| Nothing hand-edited between the markers | `flutter test tool/generate_preset_table.dart && git diff --exit-code README.md` | exit 0 |
| doc/PRESETS.md's measured rows untouched | `git diff HEAD~3 -- doc/PRESETS.md` | empty |
| No preset constant changed | `git diff HEAD~3 -- lib/src/presets.dart` | empty |
| No `timeout-minutes` touched | `git diff HEAD~3 -- .github/workflows/ci.yml \| grep -c timeout-minutes` | 0 |

## Threat Register Outcome

| Threat | Disposition | Outcome |
|---|---|---|
| T-06-05 README claims drifting from the constants | mitigate | Done. CI regenerates and diffs; the self-check saw exit 1. |
| T-06-06 a partial parse giving a table with missing platforms | mitigate | Done. `StateError` on any missing heading, column, cell or row; 8 tests. |
| T-06-07 the gate placed after the reset | mitigate | Done. Lines 262 (unit tests) < 265 (gate) < 277 (reset), also checked by parsing the YAML. |

No new security surface was introduced. The generator reads two files in the checkout and writes one.

## Known Stubs

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **06-02 can link to the table** as `README.md#presets-at-a-glance`.
- **06-04 should know** that `tool/` now holds two Dart files with public dartdoc, and that `flutter test` with no path still runs only `test/`.
- **To change a preset or a measurement:** edit the source, run `flutter test tool/generate_preset_table.dart`, and commit README.md in the same change.
- **Open:** the result of CI run 36349558026.

## Self-Check: PASSED

- FOUND: `tool/preset_table.dart`, `tool/generate_preset_table.dart`, `test/preset_table_test.dart`
- FOUND: commits `86bb9ca`, `4a2611c`, `3ec3648`
- All task acceptance criteria re-run and passing, except the CI criterion of task 3, which is pending.

---
*Phase: 06-release-and-migration*
*Completed: 2026-09-27*
