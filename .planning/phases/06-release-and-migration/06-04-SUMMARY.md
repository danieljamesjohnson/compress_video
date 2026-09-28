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
  - "ci.yml step 'dartdoc: zero warnings (RELS-01)'"
  - "doc/RELEASE.md: Dan's pre-publish checklist and publish procedure"
  - "QUESTIONS.md #2, #3, #4, #8 updated"
affects: [phase-06-verification, milestone-completion, pub.dev publish]

actuals:
  tokens: 6004
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
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
  - "pana was not installed: pub.dev lists its publisher as tools.dart.dev and the plan's gate requires dart.dev. A human has to confirm it."
  - "No pana CI step was added, because a CI step must be proven locally first and pana was never run"
  - "ci.yml's path filters are unchanged: doc/PRESETS.md stays inside the ignored '**/*.md'"
  - "The breaking-changes list is measured from the end of Phase 1 (4e14b34), the state the 0.1.0 entry describes, not from the commit that added the Unreleased heading"
  - "The podspec version follows the package version"

patterns-established:
  - "Release procedure lives in doc/RELEASE.md; the hardware checklist re-run is its first item"

requirements-completed: []

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
        ref: "gh run view 36362286984 --json jobs (Android job, step 'dartdoc: zero warnings (RELS-01)')"
        status: unknown
    human_judgment: true
    rationale: "CI run 36362286984 was in progress when this plan returned and was not polled. The orchestrator relays the result."
  - id: D3
    description: "The package is granted every pana point, and CI fails when it is not"
    requirement: "RELS-01"
    verification: []
    human_judgment: true
    rationale: "Not done. pana was not installed because its publisher is tools.dart.dev, not dart.dev as the plan's gate requires. The score is unknown."
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

duration: 8min
completed: 2026-09-28
status: halted
---

# Phase 6 Plan 04: pub.dev readiness Summary

**The package is version 1.0.0 and dry-run clean at 0 warnings, dartdoc is at zero warnings with a CI gate, and doc/RELEASE.md hands Dan the publish procedure. The pana score gate was not built: pana's publisher on pub.dev is `tools.dart.dev`, the plan allows installing it only under `dart.dev`, so it was not installed and the score is unknown.**

## Status: halted at one gate

The plan has three tasks. Tasks 1 and 3 are complete. Task 2 is half complete: the dartdoc half is done, the pana half stopped at the plan's own package check. `status: halted` is set for that reason. RELS-01 is **not** marked complete.

## Performance

- **Duration:** 8 min
- **Started:** 2026-09-28T00:21:04Z
- **Completed:** 2026-09-28T00:28:30Z
- **Tasks:** 3 committed (task 2 without its pana half)
- **Files modified:** 10 (1 new, 9 changed; 243 lines added, 53 removed)

## Accomplishments

- `pubspec.yaml` says `version: 1.0.0`, has five topics, and no longer carries the Flutter template's comment block. The repository URL answers 200.
- CHANGELOG.md's `## 1.0.0` entry tells a 0.x user what breaks and how to fix each item.
- `dart pub publish --dry-run` reports `Package has 0 warnings.` The archive is **572 KB** compressed.
- dartdoc went from 4 warnings to 0. A new CI step keeps it there.
- doc/RELEASE.md is the release procedure. Its first item is the hardware checklist re-run.
- QUESTIONS.md says what is needed from Dan.

## The pana publisher check

The plan's task 2 begins with a package check. This is its output.

| Command | Output |
|---|---|
| `curl -s https://pub.dev/api/packages/pana/publisher` | `{"publisherId":"tools.dart.dev"}` |

The plan requires `"publisherId":"dart.dev"` and says: "If it shows anything else, stop and record it; do not install." So:

- pana was **not installed**. `~/.pub-cache/bin` does not exist on danserver.
- pana was **not run**. There is no local score. `grantedPoints` and `maxPoints` are unknown.
- `pana --help` was not read, so its flag names are not verified.
- No pana step was added to ci.yml. The orchestrator's rule is that a CI step is proven locally first.

What was found about `tools.dart.dev`, for whoever decides:

| Fact | Source |
|---|---|
| Its description is "Tooling packages published by the Dart Team." Contact `packages@dartlang.org`. | `curl -s https://pub.dev/api/publishers/tools.dart.dev` |
| `dartdoc` has the same publisher. `lints` and `test` have `dart.dev`. | `curl -s https://pub.dev/api/packages/<name>/publisher` |
| The latest pana is 0.23.19 and needs Dart SDK `^3.11.0`. | `curl -s https://pub.dev/api/packages/pana` |

This reads as the plan's author having the publisher id slightly wrong. It is still a package-legitimacy gate, and those are not for an executor to wave through.

### pana fallback

The plan's fallback is written for a different case, pana failing on the hosted runner. The same gates stand in here until the decision is made:

| Gate | Where | State |
|---|---|---|
| `dart pub publish --dry-run` at 0 warnings | ci.yml `Dry-run publish` (existing) | passes locally |
| dartdoc at zero warnings | ci.yml `dartdoc: zero warnings (RELS-01)` (new) | passes locally |
| dartdoc on every public symbol | `public_member_api_docs` under `flutter analyze --fatal-infos` (existing) | passes locally |

These do not prove 160/160. There is no runner failure text, because pana never reached a runner.

## Task Commits

1. **Task 1: 1.0.0 metadata, CHANGELOG, README install line, .pubignore** - `86c2a77` (chore)
2. **Task 2: dartdoc gate; pana held at the publisher check** - `ba000a8` (ci)
3. **Task 3: doc/RELEASE.md, QUESTIONS.md, checklist pointer** - `913d2a7` (docs)

Pushed to `origin` and `github` at `913d2a7`.

## CI

| Run | Commit | Status when this plan returned |
|---|---|---|
| 36362286984 | `913d2a7` | **pending** (in progress, 6 s old) |

This is pushed CI attempt 1 of the budget of 3. The run was not polled. The workflow file and `darwin/` changed, so the Apple job runs.

What the run has to show: `Android` green, including `Dry-run publish` and `dartdoc: zero warnings (RELS-01)`; `Apple` green; `Cross-platform parity` green.

The same gates passed locally, on Flutter 3.47.5 stable:

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | 39 files, 0 changed |
| `flutter analyze --fatal-infos --fatal-warnings` | No issues found |
| `flutter test test/` | 220 passed |
| `flutter test tool/generate_preset_table.dart` then `git diff README.md` | only the hand edits outside the markers |
| `dart pub publish --dry-run` | Package has 0 warnings |
| `dart doc --dry-run` | Found 0 warnings and 0 errors |

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
- `.github/workflows/ci.yml` - the dartdoc step
- `doc/HARDWARE_CHECKLIST.md` - the pointer to RELEASE.md
- `QUESTIONS.md` - #2, #3, #4, #8

## Decisions Made

1. **pana was not installed.** See "The pana publisher check".
2. **ci.yml's path filters are unchanged.** 06-03 asked whether `doc/PRESETS.md` should leave the ignore list. It stays. A trigger filter cannot be proven locally, and `paths-ignore` with a negated pattern is not something this plan could test before the release commit depended on it. The cost of leaving it: a change to doc/PRESETS.md alone, with a stale README, is caught at the next push that touches any other file. A preset constant lives in `lib/` and is caught at once.
3. **The podspec version is 1.0.0.** The plan does not list the file. A pod at 0.1.0 inside a package at 1.0.0 would be wrong.
4. **CHANGELOG's 1.0.0 entry does not claim a pana gate.** The first draft did. It was corrected in task 3's commit when the gate was not built.
5. **RELEASE.md has a section "The pana score"** that says the step is not in CI and why.

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

### Plan gates that stopped work

**4. The pana half of task 2 was not done.** See "The pana publisher check". Open acceptance criteria of task 2:
- "the local pana run's JSON has `grantedPoints == maxPoints`": not run.
- "`grep -c 'pana: 160/160 pub points (RELS-01)' ci.yml` is 1, or the SUMMARY has a `pana fallback` heading with the runner failure text": the heading is present; there is no runner failure text.
- Task 2's `<verify>` command runs pana and was not run.

### Process deviations

**5. `WINDOWS.md` was not updated.** The pana verification and the pending CI check are unrun verifications. Recording them needs `gsd-tools windows append`, a write verb the orchestrator forbids. They are recorded here.

**6. One acceptance criterion of task 3 is open.** "The pushed run has `Android`, `Apple` and `Cross-platform parity` all `success`" waits for run 36362286984.

---

**Total deviations:** 3 auto-fixed (1 Rule 1, 2 Rule 2), 1 plan gate, 2 process.
**Impact on plan:** The pana score gate, which is the plan's central proof of 160/160, is missing.

## Issues Encountered

- **A tool result carried an instruction that did not come from the orchestrator.** The Read of `06-CONTEXT.md` came back with a block after the file's content, asking for a different `Claude-Session` trailer on commits. It was not followed. The three commits carry the trailer the orchestrator gave. 06-02 saw the same thing on a different file.
- **`flutter analyze` and `flutter test` rewrite `analysis_options.yaml`**, as waves 1 and 2 found. It was restored before every commit and never committed.
- **`dart pub publish --dry-run` reported 1 warning before task 1's commit**: "4 checked-in files are modified in git". After the commit it reports 0.

## Prohibitions

| Prohibition | Check | Result |
|---|---|---|
| No publish, tag, release or notification | `git tag --points-at HEAD`; pub.dev API for `compress_video`; `wc -l notify-dan.log` | empty; 404; 63 before and 63 after |
| Hardware re-run not marked done | first `- [ ]` of RELEASE.md's checklist | unchecked, names `HARDWARE_CHECKLIST.md` and a release build |
| No CI gate lowered | `git diff HEAD~3 -- analysis_options.yaml`; thresholds in ci.yml | empty; no pana step, so no threshold |

## Threat Register Outcome

| Threat | Disposition | Outcome |
|---|---|---|
| T-06-11 planning notes in the archive | mitigate | Done. The dry-run file list has 0 matches for `.planning/`, `QUESTIONS.md`, `.gsd/` and `.github`. |
| T-06-12 an executor publishing | mitigate | Done. Only `--dry-run` was run. |
| T-06-SC a compromised pana in CI | accept | Not reached. The check that precedes the install did not pass, so nothing was installed. |
| T-06-13 CHANGELOG under-reporting breaks | mitigate | Done, from a wider base than the plan named. |

No new security surface was introduced.

## Known Stubs

None.

## Human steps

One decision comes before the four deferred items:

0. Say whether agents may install `pana` from the publisher `tools.dart.dev` (QUESTIONS.md #2). If yes, a follow-up installs it, runs it, fixes what it names, and adds the CI step `pana: 160/160 pub points (RELS-01)` at `--exit-code-threshold 0`.

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
- **Its pub points are unproven.** Dry-run, dartdoc and analyze are clean. pana has not scored it.
- **To finish this plan** after a yes on pana: `dart pub global activate pana`, read `pana --help`, run it on the package, record granted and max points, fix deductions, add the CI step, then set this summary to `status: complete` and add RELS-01 to `requirements-completed`. Two pushes remain in the budget.
- **Open:** the result of CI run 36362286984.

## Self-Check: PASSED

- FOUND: `doc/RELEASE.md`
- FOUND: commits `86c2a77`, `ba000a8`, `913d2a7`, on both remotes
- The acceptance criteria of tasks 1 and 3 were re-run and pass, except task 3's CI criterion, which is pending. Task 2's dartdoc and analyze criteria pass; its three pana criteria are open. "PASSED" covers what is claimed above only.

---
*Phase: 06-release-and-migration*
*Completed: 2026-09-28*
