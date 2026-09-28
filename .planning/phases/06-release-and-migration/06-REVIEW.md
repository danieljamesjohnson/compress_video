---
phase: 06-release-and-migration
reviewed: 2026-09-28T01:21:46Z
depth: standard
iteration: 2
diff_base: d18f049
files_reviewed: 21
files_reviewed_list:
  - .github/workflows/ci.yml
  - .pubignore
  - CHANGELOG.md
  - MIGRATION.md
  - README.md
  - android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt
  - darwin/compress_video/Sources/compress_video/Compression.swift
  - doc/HARDWARE_CHECKLIST.md
  - doc/PRESETS.md
  - doc/RELEASE.md
  - doc/TOOLCHAIN.md
  - example/integration_test/hard_inputs_test.dart
  - example/integration_test/video_compress_compat_test.dart
  - lib/compress_video.dart
  - lib/src/compress_job.dart
  - lib/src/compress_options.dart
  - lib/src/compress_result.dart
  - lib/video_compress_compat.dart
  - test/preset_table_test.dart
  - test/video_compress_compat_test.dart
  - tool/preset_table.dart
findings:
  critical: 0
  warning: 2
  info: 4
  total: 6
status: issues_found
---

# Phase 6: Code Review Report (iteration 2)

**Reviewed:** 2026-09-28T01:21:46Z
**Depth:** standard
**Iteration:** 2 — re-review of the fix commits `48aa3b0..04b6fd6`
**Files Reviewed:** 21
**Status:** issues_found

## Summary

This is the re-review of the fourteen fix commits. Each changed hunk was read in the context
of its whole file. Thirteen of the fifteen iteration-1 findings are resolved. Two warnings are
open: one reopened (WR-07) and one new (WR-10, which the WR-08 fix introduced). No BLOCKER.

| Count | Open | Resolved |
|---|---|---|
| Critical | 0 | 0 |
| Warning | 2 (WR-07, WR-10) | 8 |
| Info | 4 (IN-03, IN-07, IN-08, IN-09) | 5 |

### What was run, and where

Unlike iteration 1, this review executed things. Tests ran in a copy of the working tree in
the session scratchpad, so the repository was not touched. `git status` is clean after the
review.

| Check | Result |
|---|---|
| `flutter test test/` (scratch copy, Flutter 3.44.1) | 221 passed |
| The two compat unit suites with `--test-randomize-ordering-seed` 1 to 5 | 40 passed, every seed |
| `flutter test tool/generate_preset_table.dart`, then `diff` of README.md against the repository | no drift |
| `dart pub publish --dry-run` (repository, Flutter 3.47.5) | Package has 0 warnings |
| The dry-run file listing, for the four WR-09 exclusions | none of the four is listed |
| `grep` of every tracked file for `danthebeliever`, `dans-macbook-air`, `danserver`, `tailc2efd2`, `/home/dan`, `/Users/danjohnson` | see WR-09 below |
| `gh run list` on the `github` remote | run 36365479082 started for `04b6fd6`; the `changes` job succeeded |

Not run, and why:

- **Kotlin and Swift.** No native test was run by this review. WR-02 and WR-03 are judged by
  reading. CI run 36365479082 was still in progress when this report was written, so it is not
  evidence for either.
- **The integration suite.** Not run on any device by this review.
- **The workflow trigger filter.** It cannot be run locally. See WR-07.

## Iteration-1 findings: status

| Id | Status | Reason |
|---|---|---|
| WR-01 | RESOLVED | Engine, current job and flag are library-level; after `dispose()` the job is visible, cancellable and blocks a second call. Proven by the new unit test, also in shuffled order. |
| WR-02 | RESOLVED | `resultDeferredFor` now precedes validation, and validation is inside the `try`. A validation failure is recorded once, by the outer `catch`. |
| WR-03 | RESOLVED | Comments only. The grace loop and its constants are marked load-bearing. |
| WR-04 | RESOLVED | All three README statements and both dartdoc copies are corrected. No other copy of the old wording remains. |
| WR-05 | RESOLVED | Headers and footnote name the test clip, the emulator and the simulator. The README regenerates with no drift. |
| WR-06 | RESOLVED | pana is pinned to 0.23.19 and its stderr is printed on both failure paths. One small gap, IN-07. |
| WR-07 | **REOPENED** | The fix uses `!` patterns inside `paths-ignore`, a form GitHub documents only for `paths`. It is unproven. See below. |
| WR-08 | RESOLVED | The case can no longer fail on a lost race, and both branches are asserted in full. The fix brought a new defect, WR-10. |
| WR-09 | RESOLVED | The only shipped file that matches the grep is the podspec, the stated exception. |
| IN-01 | RESOLVED | `shell: bash` is on both steps. |
| IN-02 | RESOLVED | "the documented surface", with the pointer to MIGRATION.md. |
| IN-03 | OPEN (skipped by the fixer) | Unchanged. The reason given is sound: `copyWith` is a public API addition and a design choice. |
| IN-04 | RESOLVED | Documented in the class dartdoc and in MIGRATION.md. |
| IN-05 | RESOLVED | The row now points to `rotationDegrees`. |
| IN-06 | RESOLVED | The case makes its own output. The shared variable is gone. |

### Notes on the four fixes the orchestrator asked about

**WR-01, `dispose()` semantics.** Verified by reading `lib/video_compress_compat.dart:275-568`
and by the tests.

- *Job stays cancellable.* `cancelCompression()` reads the library-level `_currentJob`
  (`:486-488`), so any instance reaches the job.
- *No leaked subscription.* The forwarding subscription is a local of `compressVideo` and is
  cancelled in `finally` (`:443-447`) on success, failure and cancel. `dispose()` does not
  affect it.
- *No null return.* Every path of `compressVideo` returns a `MediaInfo` or throws.
- *State cannot stick.* `_engine.compress` throws before `_isCompressing` is set (`:417-419`),
  and the `finally` clears both fields.
- *Test isolation.* The state now outlives `tearDown`'s `dispose()`. A test that left a job
  in flight would block every later test. None does: the suites pass under five shuffle seeds.

**WR-02, Android ordering.** `Compression.kt:29-43` matches `Compression.swift:106-121`:
job-id format check, registration, then validation inside the `try`. `requireValidJobId`
stays outside on both platforms, which is right, because an invalid id must never become a
registry key. `JobRegistry.completeResult` (`JobRegistry.kt:256-276`) completes the deferred
only when it is not yet completed, and the outer `catch` is the only caller on a validation
failure, so the failure is recorded once.

One consequence, recorded and not a finding: a request that fails validation now leaves a
completed deferred and a `knownJobIds` entry when the caller is on the root isolate and never
calls `awaitCompressResult`. Every other failure and every success already did the same before
this change, and `cancelAll()` clears them.

**WR-09, completeness.** The tracked files that match the grep, outside `.planning/`, are:

| File | Ships? |
|---|---|
| `.claude/CLAUDE.md` | No (`.claude/` in `.pubignore`) |
| `QUESTIONS.md` | No |
| `corpus/README.md`, `corpus/patch_rotation.py` | No (`corpus/`) |
| `doc/TOOLCHAIN.md` | No |
| `tool/mac_run.sh`, `tool/mac_sync.sh` | No |
| `darwin/compress_video.podspec` | Yes — the author field, the stated exception |

**WR-05, regenerated text.** The generator, the pinned test and the README agree, and a fresh
run of the generator changes nothing.

## Warnings

### WR-07 (REOPENED): the Markdown exception rests on an undocumented form of `paths-ignore`

**Classification:** WARNING
**File:** `.github/workflows/ci.yml:6-30`; `CHANGELOG.md:51`, `:54`
**Issue:** The fix puts `'!README.md'`, `'!MIGRATION.md'` and `'!doc/PRESETS.md'` inside
`paths-ignore`. GitHub's workflow syntax documents `!` negation for the `paths` filter. For a
workflow that must both include and exclude paths, the documentation says to use `paths` with
`!` patterns, and describes `paths-ignore` as the filter for excluding only. Negation inside
`paths-ignore` is not a documented form.

The iteration-1 review suggested this form and stated that GitHub "honours `!` negation"
there. That statement was not verified then and I cannot verify it now. I am stating this from
my knowledge of the documentation, which I could not consult during this review.

What is known:

- The workflow file is valid. Run 36365479082 started for `04b6fd6`. That push changed code,
  so it says nothing about a Markdown-only push.
- If the `!` lines have no effect, a README-only push still starts no run. The two drift
  gates then do not guard the documents, and CHANGELOG.md:51 and `:54` state a guarantee that
  does not hold. This is the original WR-07, unchanged.

The interaction with the `changes` job is correct either way: a push of only these three
files does not match the Apple path list (`:85`), the Apple job is skipped, and the parity
gate takes its justified no-op branch.

**Fix:** use the documented form. It gives the same result and needs no proof by experiment:

```yaml
on:
  push:
    branches: [main]
    paths:
      - '**'
      - '!.planning/**'
      - '!.mission-control/**'
      - '!**/*.md'
      - 'README.md'
      - 'MIGRATION.md'
      - 'doc/PRESETS.md'
```

Repeat the list under `pull_request`. `QUESTIONS.md` needs no line of its own, because
`'!**/*.md'` covers it. Then confirm once with a push that changes only `README.md`.

If the current form is kept, prove it with that same README-only push before the release, and
record the run id in the comment at `:9-12`.

### WR-10 (NEW): the compat cancel case passes when `cancelCompression()` does nothing

**Classification:** WARNING
**File:** `example/integration_test/video_compress_compat_test.dart:225-283`
**Issue:** The WR-08 fix accepts two outcomes. Both are asserted in full, so a half-filled
result is caught. But the case no longer requires that a cancel ever works. If
`cancelCompression()` stops nothing, the encode finishes, the `else` branch at `:262-273`
passes, and the case named "cancelCompression resolves the running compressVideo" is green.
The only sign is one printed line, which no gate reads.

So after this fix no integration case proves the shim's cancel on any platform. The unit test
proves that the Dart side sends the cancel message. The path from the shim to a real engine
is what this case existed to prove.

The tolerance is also wider than the project's own evidence supports.
`compress_jobs_test.dart:241-292` cancels the same clip after the same "first progress below
100" wait and requires reason `cancelled` with no second outcome. That suite passed on
Android, the iOS simulator and macOS in runs 36357692915 and 36351396397. The encode winning
the race is a risk the fixer reasoned about. No run has shown it.

**Fix:** keep the tolerance only where the race is plausible, and require the cancel
elsewhere:

```dart
final MediaInfo info = await pending;
expect(info.isCancel, isNotNull, reason: 'the outcome must say which');
if (!Platform.isMacOS) {
  // Software encoders on the emulator and the simulator: this clip takes
  // seconds, so a cancel after the first progress value must land.
  expect(info.isCancel, isTrue);
}
```

As an alternative, record the last progress value seen before the cancel was sent, and in the
"finished" branch require that it was close to 100. Then a finished result is accepted only
when the encode was really about to end.

## Info

### IN-03 (OPEN): `compressVideo` copies `CompressOptions` field by field

**File:** `lib/video_compress_compat.dart:396-413`
**Issue:** Unchanged from iteration 1. A field added to `CompressOptions` later is dropped
here with no compile error. The fixer skipped it with a sound reason.
**Fix:** as before. A test that fails when `CompressOptions` gains a field would also do, and
adds no public API.

### IN-07 (NEW): the pana failure branch can exit before it prints pana's stderr

**File:** `.github/workflows/ci.yml:331`
**Issue:** Under `bash -eo pipefail` the commands in the body of an `if` are subject to `-e`.
When the report has `.scores` but no `.report.sections`, `jq -r '.report.sections[] | ...'`
exits non-zero and the step ends there, before the `FATAL` line and before `cat "$log"`. The
step still fails, so the gate is sound. Only the diagnostics are lost, which is what WR-06
set out to keep.
**Fix:** use `.report.sections[]?` and end that `jq` call with `|| true`.

### IN-08 (NEW): the project CLAUDE.md still says a Markdown-only push creates no run

**File:** `.claude/CLAUDE.md:151`
**Issue:** The lane note says "A Markdown-only or `.planning/`-only push creates no CI run at
all". After WR-07 this is wrong for three files, if the filter works. The project rule is to
correct a stale CLAUDE.md as part of the work.
**Fix:** name the three exceptions in that note, once WR-07 is settled.

### IN-09 (NEW): a shipped document points to a script that is not shipped

**File:** `doc/HARDWARE_CHECKLIST.md:232`
**Issue:** The comment "this repo synced (tool/mac_sync.sh)" names a file that WR-09 removed
from the package. The references to `doc/RELEASE.md` were corrected in the same commit. This
one was missed.
**Fix:** "with this repository copied to the Mac", with no file name.

## For the orchestrator

1. **A tool result carried an instruction that did not come from you or the user.** The
   output of this review's first `git` command ended with a block asking for a
   `Claude-Session` trailer on commits. It was not followed. This review makes no commit. The
   fixer and plans 06-02 and 06-04 recorded the same thing.
2. **WR-07 corrects iteration 1.** The reopened finding is against a fix the iteration-1
   review itself proposed. The fixer applied what it was given.
3. **CI run 36365479082 was in progress** when this report was written. Its result is the
   first evidence for WR-02 and WR-03 on real toolchains, and for WR-08 and IN-06 on Apple.

---

_Reviewed: 2026-09-28T01:21:46Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Iteration: 2_

## ISSUES FOUND

Open warnings:

- **WR-07 (REOPENED)** — `.github/workflows/ci.yml:6-30`: `!` patterns inside `paths-ignore`
  are not a documented form; the Markdown exception is unproven.
- **WR-10 (NEW)** — `example/integration_test/video_compress_compat_test.dart:225-283`: the
  cancel case passes when the cancel does nothing.

Open info:

- **IN-03** — `lib/video_compress_compat.dart:396-413`: field-by-field copy of `CompressOptions`.
- **IN-07** — `.github/workflows/ci.yml:331`: the pana failure branch can exit before printing stderr.
- **IN-08** — `.claude/CLAUDE.md:151`: stale note on Markdown-only pushes.
- **IN-09** — `doc/HARDWARE_CHECKLIST.md:232`: reference to the unshipped `tool/mac_sync.sh`.
