---
phase: 06-release-and-migration
plan: 04
subsystem: release
tags: [dart, flutter, pub.dev, pubspec, changelog, dartdoc, pana, ci, release]

requires:
  - phase: 06-release-and-migration
    provides: "06-01: the compat library; 06-02: MIGRATION.md and the compat suite; 06-03: the generated README preset table and its drift gate"
provides:
  - "pubspec.yaml at version 1.0.0 with five topics; podspec at the same version"
  - "CHANGELOG.md 1.0.0 entry: breaking changes since 0.1.0, and what was added"
  - "README Install section"
  - ".pubignore that repeats .gitignore and excludes .github/, .gsd/ and doc/api/"
  - "ci.yml steps 'pana: 160/160 pub points (RELS-01)' and 'dartdoc: zero warnings (RELS-01)'"
  - "doc/RELEASE.md: Dan's pre-publish checklist and publish procedure"
  - "QUESTIONS.md #2, #3, #4, #8 updated"
affects: [phase-06-verification, milestone-completion, pub.dev publish]

actuals:
  tokens: 6900
  tasks: 3
  commits: 4

tech-stack:
  added: ["pana 0.23.19 (a global CI and developer tool, not a package dependency)"]
  patterns:
    - "The pana report is written outside the package directory, because pana copies the directory it scores"
    - "A gate on a tool that exits 0 with warnings reads the tool's summary line"
    - "README code references are plain code, never [`Name`], because dartdoc reads the README as package documentation"

key-files:
  created:
    - doc/RELEASE.md
  modified:
    - pubspec.yaml
    - CHANGELOG.md
    - README.md
    - .pubignore
    - .gitignore
    - darwin/compress_video.podspec
    - .github/workflows/ci.yml
    - doc/HARDWARE_CHECKLIST.md
    - QUESTIONS.md

key-decisions:
  - "pana's publisher is tools.dart.dev, the Dart team's tooling publisher. The plan's dart.dev was a planner mistake, corrected by the orchestrator on 2026-09-27. The executor stopped at the check and installed pana only after that approval."
  - "The pana step takes the Flutter root from FLUTTER_ROOT and falls back to the flutter on PATH, because pana fails with an empty --flutter-sdk"
  - "pana has no --no-warning flag and no --help flag in 0.23.19; the step uses --exit-code-threshold 0, --flutter-sdk and --json"
  - "ci.yml's path filters are unchanged: doc/PRESETS.md stays inside the ignored '**/*.md'"
  - "The breaking-changes list is measured from the end of Phase 1 (4e14b34), the state the 0.1.0 entry describes, not from the commit that added the Unreleased heading"
  - "The podspec version follows the package version"

patterns-established:
  - "Release procedure lives in doc/RELEASE.md; the hardware checklist re-run is its first item"

requirements-completed: [RELS-01]

coverage:
  - id: D1
    description: "pubspec.yaml is 1.0.0 with android/ios/macos platforms, topics, repository and issue tracker, and the publish dry-run reports 0 warnings"
    requirement: "RELS-01"
    verification:
      - kind: other
        ref: "dart pub publish --dry-run (flutter-stable 3.47.5): Package has 0 warnings., 572 KB"
        status: pass
    human_judgment: false
  - id: D2
    description: "dartdoc reports zero warnings, and a CI step fails when it does not"
    requirement: "RELS-01"
    verification:
      - kind: other
        ref: "the step's exact commands under bash -eo pipefail: exit 0 on the clean tree, exit 1 with one bad README reference"
        status: pass
      - kind: other
        ref: "gh run view 36363095391 --json jobs (Android job, step 'dartdoc: zero warnings (RELS-01)')"
        status: unknown
    human_judgment: true
    rationale: "CI run 36363095391 was pending when this plan returned and was not polled. The orchestrator relays the result."
  - id: D3
    description: "The package is granted every pana point, and a CI step fails when it is not"
    requirement: "RELS-01"
    verification:
      - kind: other
        ref: "pana 0.23.19 --exit-code-threshold 0 --json . (flutter-stable 3.47.5): grantedPoints 160, maxPoints 160"
        status: pass
      - kind: other
        ref: "the step's exact commands under bash -eo pipefail: exit 0 on the clean tree, exit 1 with LICENSE removed"
        status: pass
      - kind: other
        ref: "gh run view 36363095391 --json jobs (Android job, step 'pana: 160/160 pub points (RELS-01)')"
        status: unknown
    human_judgment: true
    rationale: "CI run 36363095391 was pending when this plan returned and was not polled. pub.dev's own score after publishing is Dan's check."
  - id: D4
    description: "CHANGELOG.md's 1.0.0 entry lists every breaking change since 0.1.0 with a fix for each, and names the compat import, MIGRATION.md and the generated preset table"
    requirement: "RELS-01"
    verification:
      - kind: other
        ref: "greps for const, maxConcurrentJobs, encoderUnavailable, outOfSpace, interrupted inside the breaking section; video_compress_compat.dart and MIGRATION.md inside the added section"
        status: pass
    human_judgment: true
    rationale: "The greps prove the names are present. Whether the list is complete and clear to a developer is a judgment."
  - id: D5
    description: "doc/RELEASE.md gives the publish procedure, with the hardware checklist re-run as the first unchecked item"
    requirement: "RELS-01"
    verification:
      - kind: other
        ref: "the plan's task 3 verify command and six acceptance greps"
        status: pass
    human_judgment: true
    rationale: "Dan has to be able to follow it. Only he can say."
  - id: D6
    description: "Nothing was published, tagged, released or notified"
    verification:
      - kind: other
        ref: "git tag --points-at HEAD empty; pub.dev API 404 for compress_video; notify-dan.log 63 lines before and after"
        status: pass
    human_judgment: false

duration: 20min
completed: 2026-09-28
status: complete
---

# Phase 6 Plan 04: pub.dev readiness Summary

**The package is version 1.0.0, scores 160 of 160 on pana 0.23.19 locally, is dry-run clean at 0 warnings and dartdoc clean at 0 warnings, all three as CI gates, and doc/RELEASE.md hands Dan the publish procedure. Nothing was published.**

## How this plan ran

It ran in two sessions of one executor. The first stopped at the plan's pana publisher check and returned with `status: halted`. The orchestrator approved the publisher, and the second session finished task 2. The CI result is pending.

## Performance

- **Duration:** about 20 min of work in two sessions
- **Started:** 2026-09-28T00:21:04Z
- **Completed:** 2026-09-28T00:41:30Z
- **Tasks:** 3 of 3
- **Files modified:** 10 (1 new, 9 changed)

## Accomplishments

- `pubspec.yaml` says `version: 1.0.0`, has five topics, and no longer carries the Flutter template's comment block. The repository URL answers 200.
- CHANGELOG.md's `## 1.0.0` entry tells a 0.x user what breaks and how to fix each item.
- `dart pub publish --dry-run` reports `Package has 0 warnings.` The archive is **572 KB** compressed.
- pana grants the package **160 of 160** points. A new CI step fails on anything less.
- dartdoc went from 4 warnings to 0. A new CI step keeps it there.
- doc/RELEASE.md is the release procedure. Its first item is the hardware checklist re-run.
- QUESTIONS.md says what is needed from Dan.

## The pana publisher check, and a correction to the plan

| Command | Output |
|---|---|
| `curl -s https://pub.dev/api/packages/pana/publisher` | `{"publisherId":"tools.dart.dev"}` |

The plan requires `"publisherId":"dart.dev"` and says to stop on anything else. The first session stopped there and installed nothing.

**Correction, from the orchestrator, 2026-09-27:** `tools.dart.dev` is the Dart team's official tooling publisher on pub.dev. `pana` and `dartdoc` are both under it. The plan's `dart.dev` was a planner mistake, not a rule about which publisher is trusted. Installing pana was approved. The acceptance criterion "the SUMMARY records the publisher check output showing `dart.dev`" is met in this corrected form: the output shows `tools.dart.dev`.

Supporting facts found in the first session:

| Fact | Source |
|---|---|
| The publisher's description is "Tooling packages published by the Dart Team." Contact `packages@dartlang.org`. | `curl -s https://pub.dev/api/publishers/tools.dart.dev` |
| `dartdoc` has the same publisher. `lints` and `test` have `dart.dev`. | `curl -s https://pub.dev/api/packages/<name>/publisher` |

## The pana run

Installed with `dart pub global activate pana` on the flutter-stable PATH: **pana 0.23.19**. pana itself then installs `dartdoc` globally, from the same publisher.

**pana's real flags are not the plan's.** `pana --help` and `pana --version` are both rejected ("Could not find an option named"), and the rejection prints the usage. There is no `--no-warning`. The flags that exist: `--dart-sdk`, `--flutter-sdk`, `--exit-code-threshold`, `-j/--json`, `--hosted-url`, `--hosted`, `--[no-]dartdoc`, `--dartdoc-version`, `--license-data`, `--project-root`.

| Section | Granted | Max |
|---|---|---|
| convention | 30 | 30 |
| documentation | 20 | 20 |
| platform | 20 | 20 |
| analysis | 50 | 50 |
| dependency | 40 | 40 |
| **Total (`scores`)** | **160** | **160** |

The first run gave this score. No deduction had to be fixed. One run takes about 90 seconds on danserver.

## The pana gate

The CI step is `pana: 160/160 pub points (RELS-01)`, in the Android job after `Dry-run publish`. Its `run:` block was compared with the script proven locally and is identical, character for character.

| Tree | Exit code | Output |
|---|---|---|
| Clean, `FLUTTER_ROOT` set | **0** | `pana: 160/160 pub points` |
| Clean, `FLUTTER_ROOT` unset | **0** | `pana: 160/160 pub points` |
| `LICENSE` removed | **1** | "No license was recognized." then `FATAL: pana did not grant every pub point` |

Three things were learned while proving it:

- **An empty `--flutter-sdk` makes pana fail** (exit code 255). The first version of the step passed `"$FLUTTER_ROOT"` alone and failed locally with the variable unset. The step now falls back to the `flutter` on PATH.
- **Renaming the CHANGELOG's `## 1.0.0` heading does not cost a point.** It was the first break tried, and pana still gave 160. It is not evidence that the gate fails. The `LICENSE` case is.
- **The step passes two checks, not one.** pana's own exit code under threshold 0, and a `jq` comparison of `grantedPoints` with `maxPoints`.

The step depends on `jq` on the runner. `ubuntu-latest` has it, but this step has not run on a runner yet.

## Task Commits

1. **Task 1: 1.0.0 metadata, CHANGELOG, README install line, .pubignore** - `86c2a77` (chore)
2. **Task 2: pana and dartdoc gates** - `ba000a8` (ci, the dartdoc gate) and `e49cc5b` (ci, the pana gate, after approval)
3. **Task 3: doc/RELEASE.md, QUESTIONS.md, checklist pointer** - `913d2a7` (docs)

The first summary was `bc86f23`. Pushed to `origin` and `github` at `e49cc5b`.

## CI

| Run | Commit | Status |
|---|---|---|
| 36362286984 | `913d2a7` | superseded: the next push cancels it under the workflow's cancel-in-progress rule |
| 36363095391 | `e49cc5b` | **pending** (8 s old when recorded); the run of record |

Two of the three pushed CI attempts are used. Neither run was polled. The workflow file and `darwin/` changed, so the Apple job runs.

What run 36363095391 has to show: `Android` green, including `Dry-run publish`, `pana: 160/160 pub points (RELS-01)` and `dartdoc: zero warnings (RELS-01)`; `Apple` green; `Cross-platform parity` green.

The same gates passed locally, on Flutter 3.47.5 stable:

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | 39 files, 0 changed |
| `flutter analyze --fatal-infos --fatal-warnings` | No issues found |
| `flutter test test/` | 220 passed |
| `flutter test tool/generate_preset_table.dart` then `git diff README.md` | only the hand edits outside the markers |
| `dart pub publish --dry-run` | Package has 0 warnings |
| `dart doc --dry-run` | Found 0 warnings and 0 errors |
| `pana --exit-code-threshold 0 --json .` | 160/160 |

## The dartdoc gate

The command is `dart doc --dry-run`. It is part of the Dart SDK, so nothing was installed.

`dart doc --dry-run` exits 0 when it prints warnings. It was seen to exit 0 with "Found 4 warnings and 0 errors." The step therefore reads the summary line:

```
dart doc --dry-run 2>&1 | tee dartdoc.log
grep -q "Found 0 warnings and 0 errors." dartdoc.log || { echo "FATAL: ..." >&2; exit 1; }
rm -f dartdoc.log
```

It was run locally under `bash -eo pipefail`, which is how GitHub Actions runs a `run:` block.

| Tree | Exit code |
|---|---|
| Clean | **0** |
| README with one ``[`CompressVideoException`]`` put back | **1**, "Found 1 warning and 0 errors." |

The four warnings were all in README.md, which dartdoc reads as the package's documentation. Each was a code span inside square brackets, which dartdoc takes for a symbol reference. The brackets were removed. No warning was suppressed.

## The breaking changes, and where they come from

The plan's command finds the commit that added `## Unreleased`: `b1dad7d`, 2026-09-25. That is late. The `0.1.0` entry describes the package at the end of Phase 1. The list was taken from `git diff 4e14b34 HEAD` over `lib/compress_video.dart` and `lib/src/*.dart` without the generated file. `4e14b34` is the Phase 1 sign-off, and it is the wider of the two bases.

| Change | Evidence in the diff |
|---|---|
| Constructor not `const` | `-  const CompressVideo({...})` / `+  CompressVideo({..., this.maxConcurrentJobs = 1})` |
| Jobs queue beyond `maxConcurrentJobs` | `_pending`, `_pumpQueue`, `createQueuedCompressJob` |
| `encoderUnavailable`, `outOfSpace`, `interrupted` are real outcomes | The three values were in the enum since the first scaffold (`0ef3b95`). What changed is that the engines now throw them. The entry says "are now real outcomes", not "new values". |
| `validate()` accepts `VideoCodec.hevc` and `HdrMode.keepHdr` | the two `reject(...)` calls removed from `compress_options.dart` |
| `toneMapped`, `hevcFallback`, `audioReencoded` can be `true` | dartdoc changed from "Always `false` in this phase" |
| Unexpected errors wrapped as `unknown` | `_wrapUnexpected` added to five calls |
| `awaitCompressResult` for a job never started fails after about 2 s | quick task 260927-r4k |

`CompressResult` and `CompressEstimate` have no new required constructor parameters. Both constructors were read. The entry says so.

## Files Created/Modified

- `doc/RELEASE.md` - the release procedure (new, 96 lines)
- `pubspec.yaml` - version, topics, comment block removed
- `CHANGELOG.md` - the 1.0.0 entry
- `README.md` - the Install section; four bracketed references made plain code
- `.pubignore` - `.gsd/`, `.github/`, `doc/api/`, `example/integration_test/_scratch/`, the Pods lines
- `.gitignore` - `doc/api/`
- `darwin/compress_video.podspec` - version 1.0.0
- `.github/workflows/ci.yml` - the pana step and the dartdoc step
- `doc/HARDWARE_CHECKLIST.md` - the pointer to RELEASE.md
- `QUESTIONS.md` - #2, #3, #4, #8

## Decisions Made

1. **The executor stopped at the publisher check and did not decide it.** See the correction above.
2. **ci.yml's path filters are unchanged.** 06-03 asked whether `doc/PRESETS.md` should leave the ignore list. It stays. A trigger filter cannot be proven locally, and `paths-ignore` with a negated pattern is not something this plan could test before the release commit depended on it. The cost of leaving it: a change to doc/PRESETS.md alone, with a stale README, is caught at the next push that touches any other file. A preset constant lives in `lib/` and is caught at once.
3. **The podspec version is 1.0.0.** The plan does not list the file. A pod at 0.1.0 inside a package at 1.0.0 would be wrong.
4. **CHANGELOG, RELEASE.md and QUESTIONS.md were written twice.** While the gate did not exist they said so. `e49cc5b` changed all three to say that it exists and what it scored.
5. **The pana step falls back to the `flutter` on PATH.** See "The pana gate".

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Four dartdoc warnings in the README**
- **Found during:** Task 2
- **Issue:** ``[`CompressVideoException`]`` and three more. dartdoc could not resolve them.
- **Fix:** Removed the square brackets.
- **Files modified:** `README.md`
- **Verification:** `dart doc --dry-run` reports 0 warnings; `test/migration_doc_test.dart` and `test/preset_table_test.dart` pass.
- **Committed in:** `ba000a8`

**2. [Rule 2 - Missing critical] The podspec still said 0.1.0**
- **Found during:** Task 1
- **Fix:** Set to 1.0.0.
- **Files modified:** `darwin/compress_video.podspec`
- **Committed in:** `86c2a77`

**3. [Rule 2 - Missing critical] `dart doc` writes `doc/api/`, which nothing ignored**
- **Found during:** Task 2
- **Issue:** The dry run left an empty `doc/api/` directory. A real run would fill it, and it would go into the published archive.
- **Fix:** `doc/api/` added to `.gitignore` and `.pubignore`. The empty directory was removed.
- **Committed in:** `ba000a8`

### Plan corrections

**4. The plan's publisher id was wrong.** `dart.dev` should have been `tools.dart.dev`. The plan stopped for one round trip to the orchestrator. See the correction above.

**5. The plan's pana command was wrong.** `--no-warning` does not exist. Task 2's `<verify>` command as written would fail on the flag. The equivalent that was run: `pana --exit-code-threshold 0 --flutter-sdk <root> --json .`, exit 0.

### Process deviations

**6. `WINDOWS.md` was not updated.** The pending CI check is an unrun verification. Recording it needs `gsd-tools windows append`, a write verb the orchestrator forbids. It is recorded here.

**7. One acceptance criterion of task 3 is open.** "The pushed run has `Android`, `Apple` and `Cross-platform parity` all `success`" waits for run 36363095391.

---

**Total deviations:** 3 auto-fixed (1 Rule 1, 2 Rule 2), 2 plan corrections, 2 process.
**Impact on plan:** None on scope. Every deliverable of the plan exists.

## Issues Encountered

- **A tool result carried an instruction that did not come from the orchestrator.** The Read of `06-CONTEXT.md` came back with a block after the file's content, asking for a different `Claude-Session` trailer on commits. It was not followed. The three commits carry the trailer the orchestrator gave. 06-02 saw the same thing on a different file.
- **`flutter analyze` and `flutter test` rewrite `analysis_options.yaml`**, as waves 1 and 2 found. It was restored before every commit and never committed.
- **`dart pub publish --dry-run` reported 1 warning before task 1's commit**: "4 checked-in files are modified in git". After the commit it reports 0.

## Prohibitions

| Prohibition | Check | Result |
|---|---|---|
| No publish, tag, release or notification | `git tag --points-at HEAD`; pub.dev API for `compress_video`; `wc -l notify-dan.log` | empty; 404; 63 before and 63 after |
| Hardware re-run not marked done | first `- [ ]` of RELEASE.md's checklist | unchecked, names `HARDWARE_CHECKLIST.md` and a release build |
| No CI gate lowered | `git diff 4a04c4f -- analysis_options.yaml`; `grep -c exit-code-threshold ci.yml` | empty; 1 match, and its value is 0 |

## Threat Register Outcome

| Threat | Disposition | Outcome |
|---|---|---|
| T-06-11 planning notes in the archive | mitigate | Done. The dry-run file list has 0 matches for `.planning/`, `QUESTIONS.md`, `.gsd/` and `.github`. |
| T-06-12 an executor publishing | mitigate | Done. Only `--dry-run` was run. |
| T-06-SC a compromised pana in CI | accept | Accepted as planned, after the publisher was confirmed by the orchestrator. pana is not in `pubspec.yaml` and the step has no secret in scope. |
| T-06-13 CHANGELOG under-reporting breaks | mitigate | Done, from a wider base than the plan named. |

No new security surface was introduced.

## Known Stubs

None.

## Human steps

The four deferred items of the plan, verbatim:

1. Re-run `doc/HARDWARE_CHECKLIST.md` against a release build on a physical Android phone and on
   the MacBook Air (ROADMAP criterion 4; QUESTIONS.md #3, #4, #8).
2. Choose the pub.dev publisher and run `dart pub publish` (ROADMAP criterion 1; QUESTIONS.md #2).
3. Tag `v1.0.0` and create the GitHub release, per doc/RELEASE.md.
4. Confirm pub.dev's own score page shows 160/160 after publishing.

No notification was sent. Whether one goes out is the orchestrator's call.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **The package can be published as it stands**, by Dan, with doc/RELEASE.md.
- **pana grants it 160 of 160.** pub.dev runs its own copy of pana after publishing, and that score is Dan's check.
- **Phase 6 has no plan left.** RELS-01 is complete up to the one irreversible step, which is Dan's.
- **Open:** the result of CI run 36363095391.

## Self-Check: PASSED

- FOUND: `doc/RELEASE.md`
- FOUND: commits `86c2a77`, `ba000a8`, `913d2a7`, `e49cc5b`, on both remotes
- The acceptance criteria of tasks 1 and 3 were re-run and pass, except task 3's CI criterion, which is pending. Task 2's criteria pass, with the publisher and the pana flags in their corrected form. "PASSED" covers what is claimed above only.

---
*Phase: 06-release-and-migration*
*Completed: 2026-09-28*
