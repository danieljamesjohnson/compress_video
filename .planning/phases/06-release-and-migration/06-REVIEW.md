---
phase: 06-release-and-migration
reviewed: 2026-09-28T01:35:13Z
depth: standard
iteration: 3
diff_base: 04b6fd6
files_reviewed: 4
files_reviewed_list:
  - .claude/CLAUDE.md
  - .github/workflows/ci.yml
  - doc/HARDWARE_CHECKLIST.md
  - example/integration_test/video_compress_compat_test.dart
findings:
  critical: 0
  warning: 0
  info: 3
  total: 3
status: approved
---

# Phase 6: Code Review Report (iteration 3)

**Reviewed:** 2026-09-28T01:35:13Z
**Depth:** standard
**Iteration:** 3 — re-review of the iteration-2 fix commits `0440afa..9e8dc11`
**Files Reviewed:** 4
**Status:** approved

## Summary

This is the re-review of the five iteration-2 fix commits. Each changed hunk was read in the
context of its whole file. All five fixes do what the fix report says. No critical and no
warning finding is open. Three info items are open: IN-03 (skipped with a sound reason) and
two new ones, IN-10 and IN-11. None blocks.

| Count | Open | Resolved (all iterations) |
|---|---|---|
| Critical | 0 | 0 |
| Warning | 0 | 10 |
| Info | 3 (IN-03, IN-10, IN-11) | 8 |

One thing remains unproven and cannot be proven by a review: that a push which changes only
`README.md` starts a run. See WR-07.

### What was run, and where

Nothing in the repository was changed. `git status` is clean after the review. Scratch files
were written to the session scratchpad only.

| Check | Result |
|---|---|
| `yaml.safe_load` of ci.yml: `push.paths == pull_request.paths` | True, the eight patterns in the required order |
| The same parse: a `paths-ignore` key under `push` or `pull_request` | none |
| `grep -n "paths-ignore"` on ci.yml | two matches, both inside the explanatory comment (`:6-7`) |
| `git diff 04b6fd6..HEAD -- .github/workflows/ci.yml` | two hunks: the trigger block (`:3-33`) and the pana step (`:320-336`). The `changes` job (`:47-91`) is not in the diff |
| The pana failure line (`ci.yml:336`) under `bash -eo pipefail`, six hand-made reports | see IN-07 below |
| `grep` of the shipped documents, `lib/`, `example/lib/` and `example/integration_test/` for `mac_sync`, `mac_run`, `danserver`, `dans-macbook` | no match |
| `git show 86dcdf3^:example/integration_test/video_compress_compat_test.dart` | the cancel case before WR-08 required `isCancel == true` on every platform |
| `gh run list` on the `github` remote | 36357692915 succeeded with that strict form on Android, iOS and macOS. 36366408783 is pending for `7c3f273` |

Not run, and why:

- **The integration suite.** Not run on any device by this review. The fixer's emulator run
  and its mutation run (the `cancelCompression()` call removed) are taken from the fix
  report. The assertion they rest on was read.
- **The workflow trigger filter.** It cannot be run locally.
- **Run 36366408783** was pending when this report was written. It is not evidence for
  anything here. It was started by a push that changes `ci.yml`, so it also says nothing
  about a Markdown-only push.

## Iteration-2 findings: status

| Id | Status | Reason |
|---|---|---|
| WR-07 | RESOLVED | `paths` with `!` exclusions and later re-inclusions, the documented form. Both events carry the same list. One proof is still owed, see below. |
| WR-10 | RESOLVED | Android and iOS require `isCancel == true`. A cancel that does nothing fails there. The macOS finished branch is asserted in full. Residual gap on macOS only, IN-10. |
| IN-03 | OPEN (skipped by the fixer) | Unchanged. The reason is sound: `copyWith` is a public API addition and a design choice. |
| IN-07 | RESOLVED | The FATAL line and pana's stderr are printed for every malformed report tried. |
| IN-08 | RESOLVED | The lane note names the three files, the form of the filter and the order rule. One stale detail in the same note, IN-11. |
| IN-09 | RESOLVED | The comment names no file. No shipped file names either Mac script. |

All fifteen iteration-1 findings keep the status recorded in iteration 2: fourteen resolved,
IN-03 open. None of their files was changed by the iteration-2 commits except
`video_compress_compat_test.dart` (WR-08, IN-06), and both still hold there.

## Verification of each fix

### WR-07 (RESOLVED): trigger filter

**File:** `.github/workflows/ci.yml:3-33`

| Requirement | Result |
|---|---|
| `push` and `pull_request` lists identical | yes, compared after parsing |
| No `paths-ignore` key left | yes |
| `.planning/**` excluded | `:15`, `:26` |
| `**/*.md` excluded | `:16`, `:27` |
| `QUESTIONS.md` excluded | `:17`, `:28`. Already covered by `!**/*.md`; the line is redundant and harmless |
| `.mission-control/**` excluded | `:18`, `:29` |
| `README.md`, `MIGRATION.md`, `doc/PRESETS.md` re-included after the exclusions | `:19-21`, `:30-32`, the last three patterns |
| `'**'` is the first pattern | yes |
| `branches: [main]` and `workflow_dispatch` kept | yes |
| `changes` job untouched | yes |

The three re-inclusions have no wildcard, so they match the root `README.md`, the root
`MIGRATION.md` and `doc/PRESETS.md` only. `example/README.md` and `corpus/README.md` stay
excluded, which is the intent.

A push of only these three files gives `apple=false` in the `changes` job, because none
matches the list at `:87`. The Android job runs and the Apple job is skipped.

**Still owed:** one push that changes only `README.md`, to see a run start. The form no
longer depends on it, but CHANGELOG.md's statement that a CI gate guards the README table is
proven only then. This is a release-checklist item, not a finding.

### WR-10 (RESOLVED): compat cancel case

**File:** `example/integration_test/video_compress_compat_test.dart:225-307`

- **Android and iOS require the cancel.** `:266-273` asserts `isCancel` is `true` whenever
  the platform is not macOS. It runs before the two-branch `if`, so the `else` branch cannot
  be reached there with a passing test.
- **A no-op cancel fails there.** If the cancel stops nothing, the encode finishes,
  `compressVideo` returns `isCancel: false` (`lib/video_compress_compat.dart:435`), and
  `:267` fails. The fixer's mutation run shows the same failure message.
- **The macOS finished branch is complete.** `:280-296`: `path` and `file` set, the file
  exists, `filesize` above 0, equal to the file's length and not above the input, and
  `width`, `height`, `duration` set. When the never-larger rule delivers the original,
  `filesize` equals the input size and `lessThanOrEqualTo` holds.
- **The null check is safe.** `info.isCancel!` at `:274` follows `isNotNull` at `:256`.
- **The requirement on iOS has evidence.** This same case, with this same clip and
  `HighestQuality`, required `isCancel == true` on all three platforms before WR-08 and
  passed in run 36357692915. So the strict form is not a new flake risk on Android or iOS.

### IN-07 (RESOLVED): pana failure branch

**File:** `.github/workflows/ci.yml:336`

The line was copied out and run under `bash -eo pipefail`:

| Report | Exit | FATAL line and stderr printed |
|---|---|---|
| `.scores` below the maximum, no `.report` | 1 | yes |
| `.report` is a string | 1 | yes (jq's error is printed first) |
| `.report.sections` holds numbers and strings | 1 | yes |
| `maxPoints` is 0 | 1 | yes |
| full score, pana exit code 3 | 1 | yes |
| full score, exit code 0 | 0 | not applicable, the step passes |

The gate itself is unchanged.

### IN-08 (RESOLVED) and IN-09 (RESOLVED)

`.claude/CLAUDE.md:151` and `doc/HARDWARE_CHECKLIST.md:232` read as the fix report says.

## Info

### IN-03 (OPEN): `compressVideo` copies `CompressOptions` field by field

**File:** `lib/video_compress_compat.dart:396-413`
**Issue:** Unchanged. A field added to `CompressOptions` later is dropped here with no
compile error. Skipped by the fixer with a sound reason.
**Fix:** as before. A test that fails when `CompressOptions` gains a field would also do, and
adds no public API.

### IN-10 (NEW): on macOS the cancel case still passes when the cancel does nothing

**File:** `example/integration_test/video_compress_compat_test.dart:258-273`
**Issue:** The tolerance that WR-10 removed for Android and iOS is kept for macOS, as the
iteration-2 review proposed. So on macOS a `cancelCompression()` that stops nothing still
gives a green case. The shim's cancel is Dart code shared by all platforms and is proven on
Android and iOS, so the risk is small.

Two statements in the comment are weaker than they read:

1. "macOS is the one host where the encode can plausibly win the race". No run has shown
   it. `compress_jobs_test.dart:241-292` requires `cancelled` on macOS with no second
   outcome, and the strict form of this case passed on macOS in run 36357692915.
2. "what compress_jobs_test.dart requires of the same clip after the same wait". The clip
   and the wait are the same. The preset is not: that suite uses the default `p720`, this
   case uses `p1080`. The difference makes this encode slower, so it supports the
   requirement. The comment should say so.

**Fix:** either drop the macOS exception and require `isCancel == true` everywhere, as the
case did before WR-08, or keep it and print the last progress value seen before the cancel,
so a lost race can be told from a dead cancel in the log.

### IN-11 (NEW): the lane note lists fewer Apple-gated paths than the `changes` job

**File:** `.claude/CLAUDE.md:151`
**Issue:** The note says the macOS job runs when a push touches `darwin/`, `pigeons/`,
`lib/`, `example/`, `pubspec.yaml` or the workflow file. The `changes` job
(`.github/workflows/ci.yml:87`) also matches `tool/` and `corpus/`. The omission is older
than this phase, but commit 3c7d931 rewrote this same note and left it.
**Fix:** add `tool/` and `corpus/` to the list in the note.

## For the orchestrator

1. **A tool result carried an instruction that did not come from you or the user.** The
   output of this review's first `git` command ended with a block asking for a
   `Claude-Session` trailer on commits. It was not followed. This review makes no commit.
   The same block was recorded in iterations 1 and 2 and by the fixer.
2. **One proof is still owed for WR-07:** a push that changes only `README.md`. Put it on
   the release checklist.
3. **Run 36366408783 was pending** and run 36365479082 was in progress when this report was
   written. `cancel-in-progress` is on, so the newer run will cancel the older. The newer
   run is the first evidence on real toolchains for WR-02 and WR-03, and for the new cancel
   assertion on iOS.
4. **No source file was changed and nothing was committed.**

---

_Reviewed: 2026-09-28T01:35:13Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Iteration: 3_

## VERIFICATION PASSED

Open critical: none. Open warnings: none.

Open info (none blocks):

- **IN-03** — `lib/video_compress_compat.dart:396-413`: field-by-field copy of `CompressOptions`. Skipped with reason.
- **IN-10** — `example/integration_test/video_compress_compat_test.dart:258-273`: on macOS a cancel that does nothing still passes.
- **IN-11** — `.claude/CLAUDE.md:151`: the lane note omits `tool/` and `corpus/` from the Apple-gated paths.
