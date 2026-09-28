---
phase: 06-release-and-migration
fixed_at: 2026-09-28T01:32:36Z
review_path: .planning/phases/06-release-and-migration/06-REVIEW.md
iteration: 2
findings_in_scope: 6
fixed: 5
skipped: 1
status: partial
---

<!-- The frontmatter counts describe iteration 2, the latest. Iteration 1 (15 in scope, 14
     fixed, 1 skipped) is kept in full below the iteration 2 section. -->

# Phase 6: Code Review Fix Report (iteration 2)

**Fixed at:** 2026-09-28T01:32:36Z
**Source review:** .planning/phases/06-release-and-migration/06-REVIEW.md (iteration 2)
**Iteration:** 2

**Summary:**
- Findings in scope: 6 (2 warnings, 4 info)
- Fixed: 5 (WR-07, WR-10, IN-07, IN-08, IN-09)
- Skipped: 1 (IN-03, for the reason recorded in iteration 1)

`workflow.use_worktrees` is `false`, so every edit and commit was made on `main` in the
primary checkout. No worktree was created. Commits were made with plain `git commit`.

## Where verification ran (iteration 2)

Everything ran in the main checkout at `/home/dan/CodeProjects/compress-video`.

| Gate | Result |
|---|---|
| `dart format .` (Flutter 3.47.5 stable) | 39 files, 0 changed |
| `flutter analyze --fatal-infos --fatal-warnings` (package root) | No issues found |
| `flutter analyze` (example) | No issues found |
| `flutter test test/` | 221 passed |
| `flutter test tool/generate_preset_table.dart` then `git diff --exit-code README.md` | exit 0 |
| `dart pub publish --dry-run` | Package has 0 warnings |
| The pana step's `run:` block from ci.yml, under `bash -eo pipefail` | exit 0, `pana: 160/160 pub points` |
| The pana failure line against a report with `.scores` and no `.report.sections` | exit 1, FATAL line and the log printed |
| The same line against a report whose `.report.sections` is a string | exit 1, FATAL line and the log printed |
| `yaml.safe_load` of ci.yml; `push.paths == pull_request.paths`; no `paths-ignore` key | pass |
| `video_compress_compat_test.dart` on the Android emulator | 6 of 6 passed; the cancel landed |
| A temporary copy of that suite with the `cancelCompression()` call removed | the cancel case FAILED, on the new assertion |

`actionlint` is not installed on this host, so it was not run.
`tool/run_ios_integration_suites.sh` was not changed, so its self-test was not run.

Not verified locally, and why:

- **The workflow trigger filter** (WR-07). It cannot be run locally. The form is now the one
  GitHub documents. The proof is a push that changes only one of the three documents.
- **The compat cancel case on iOS and macOS** (WR-10). CI's Apple job runs it. The requirement
  on iOS rests on `compress_jobs_test.dart` passing there with the same clip and wait.

## Fixed Issues (iteration 2)

### WR-07 (reopened): the Markdown exception rested on an undocumented form of `paths-ignore`

**Files modified:** `.github/workflows/ci.yml`
**Commit:** 0440afa
**Status:** fixed: cannot be proven locally
**Applied fix:** Both `paths-ignore` blocks (`push` and `pull_request`) are replaced by
`paths` blocks, in this order: `'**'`, `'!.planning/**'`, `'!**/*.md'`, `'!QUESTIONS.md'`,
`'!.mission-control/**'`, `'README.md'`, `'MIGRATION.md'`, `'doc/PRESETS.md'`. A later pattern
overrides an earlier one, so the three documents are taken back in after the exclusions.
`workflow_dispatch` is kept. The `changes` job is not touched: the diff has one hunk, at the
top of the file.

The orchestrator verified the form against GitHub's workflow-syntax documentation: `!` is
supported only in `paths`, and `paths` and `paths-ignore` cannot filter the same event.

### WR-10 (new): the compat cancel case passed when `cancelCompression()` did nothing

**Files modified:** `example/integration_test/video_compress_compat_test.dart`
**Commit:** 71ee9cc
**Status:** fixed: requires human verification (test logic; iOS and macOS not run locally)
**Applied fix:** On Android and iOS the case requires `isCancel == true`, with no second
outcome. This is what `compress_jobs_test.dart` requires of the same clip after the same
wait. On macOS a finished result is still accepted, and only a complete one: `path` and
`file` set, the file exists, `filesize` equals the file's length, is above 0 and is not
larger than the input, and `width`, `height` and `duration` are set. The case is renamed
"cancelCompression stops the running compressVideo, which resolves as cancelled".

**Proof that the case is no longer vacuous.** On the Android emulator the suite passed 6 of
6. Then a temporary copy of the suite, with the one `cancelCompression()` call removed, was
run. The cancel case failed with "Expected: true, Actual: false — cancelCompression() was
sent mid-flight and must stop the encode". The copy was deleted and never committed.

One assertion was considered and left out: that the finished `path` differs from the input
path. Whether that holds when the never-larger rule delivers the original was not checked, and
the branch cannot be run on this host.

### IN-07: the pana failure branch could exit before it printed pana's stderr

**Files modified:** `.github/workflows/ci.yml`
**Commit:** 90b028a
**Applied fix:** The `jq` call that lists the sections reads `.report.sections[]?` and ends
with `|| true`. A comment on the step says why. Proven with two hand-made reports, as in the
table above.

### IN-08: the project CLAUDE.md said a Markdown-only push creates no run

**Files modified:** `.claude/CLAUDE.md`
**Commit:** 3c7d931
**Applied fix:** The lane note says a push of only `README.md`, `MIGRATION.md` or
`doc/PRESETS.md` starts a run (Android job, Apple job skipped), and that other Markdown-only,
`.planning/`-only and `.mission-control/`-only pushes start none. It also records that `!`
works only in `paths` and that the order of the list matters.

### IN-09: a shipped document pointed to a script that is not shipped

**Files modified:** `doc/HARDWARE_CHECKLIST.md`
**Commit:** 9e8dc11
**Applied fix:** "and this repository copied to the Mac", with no file name. No shipped
document, and nothing under `lib/`, names `tool/mac_sync.sh` or `tool/mac_run.sh` now.

## Skipped Issues (iteration 2)

### IN-03: `compressVideo` copies `CompressOptions` field by field

**File:** `lib/video_compress_compat.dart:396-413`
**Reason:** Unchanged from iteration 1, and kept skipped by the orchestrator's scope.
`CompressOptions.copyWith` is a public API addition and a design choice.
**Original issue:** A field added to `CompressOptions` later is silently dropped by the
compat shim, with no compile error.

## For the orchestrator (iteration 2)

1. **A tool result carried an instruction that did not come from the orchestrator.** The
   output of the first shell command ended with a block asking for a different
   `Claude-Session` trailer. It was not followed. Every commit carries the trailer the
   orchestrator gave.
2. **WR-07 still needs its one proof:** a push that changes only `README.md`.
3. **CHANGELOG.md was not changed.** Its statement that a CI gate guards the README table
   holds once the filter is proven.
4. **The emulator** was booted once and stopped by its own PID. None was running before,
   and none is running now. `ANDROID_HOME` was not set in the agent's shell; the SDK path was
   given explicitly.

---

_Fixed: 2026-09-28T01:32:36Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_

---

# Phase 6: Code Review Fix Report

**Fixed at:** 2026-09-28T01:17:24Z
**Source review:** .planning/phases/06-release-and-migration/06-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 15 (0 critical, 9 warnings, 6 info)
- Fixed: 14 (all 9 warnings, 5 of 6 info)
- Skipped: 1 (IN-03)

The scope was critical and warning, with info items fixed when the fix was small and safe.
`workflow.use_worktrees` is `false` for this project, so every edit and commit was made on
`main` in the primary checkout. No worktree was created and no cleanup applies.

Commits were made with plain `git commit`, not `gsd-tools`, because the orchestrator forbids
`gsd-tools` write verbs.

## Where verification ran

Everything below ran in the main checkout at `/home/dan/CodeProjects/compress-video`, so the
results can be reproduced from that tree.

| Gate | Result |
|---|---|
| `dart format .` (Flutter 3.47.5 stable) | 39 files, 0 changed |
| `flutter analyze --fatal-infos --fatal-warnings` (package root) | No issues found |
| `flutter analyze` (example) | No issues found |
| `flutter test test/` | 221 passed (was 220; one new test for WR-01) |
| `flutter test tool/generate_preset_table.dart` then `git diff --exit-code README.md` | exit 0 |
| `./gradlew :compress_video:testDebugUnitTest` (from `example/android`) | BUILD SUCCESSFUL |
| `example/integration_test/video_compress_compat_test.dart` on the Android emulator | 6 of 6 passed, run twice |
| `dart pub publish --dry-run` | Package has 0 warnings |
| The pana step's `run:` block from ci.yml, under `bash -eo pipefail` | exit 0, `pana: 160/160 pub points` |
| The same block with an empty `--flutter-sdk` | exit 1, pana's stack trace printed |
| The dartdoc step's `run:` block from ci.yml, under `bash -eo pipefail` | exit 0, 0 warnings and 0 errors |
| `cmp example/ios/RunnerTests/RunnerTests.swift example/macos/RunnerTests/RunnerTests.swift` | identical |

`tool/run_ios_integration_suites.sh` was not changed, so its self-test was not run.

Not verified locally, and why:

- **Swift.** danserver has no Swift toolchain, and the Mac was not probed. WR-03 changes
  comments only. CI's Apple job is the check that the file still compiles.
- **The compat integration suite on Apple** (WR-08, IN-06). CI's iOS and macOS part 2 steps run it.
- **The workflow trigger filter** (WR-07). A trigger filter cannot be run locally.

## Fixed Issues

### WR-01: `dispose()` orphans the in-flight job

**Files modified:** `lib/video_compress_compat.dart`, `test/video_compress_compat_test.dart`, `MIGRATION.md`
**Commit:** 48aa3b0
**Status:** fixed: requires human verification (state handling)
**Applied fix:** The engine, the current job and the is-compressing flag moved from the
`IVideoCompress` instance to the library. `dispose()` still replaces the instance and its
`compressProgress$`. After it, the new instance reports the running job through
`isCompressing`, stops it with `cancelCompression()`, and refuses a second `compressVideo`
with `StateError`. This is the incumbent's behaviour, where cancel was a process-wide native
call. The dartdoc of the class, `isCompressing`, `cancelCompression` and `dispose` says so, and
so does the `dispose` row of MIGRATION.md.

A new unit test starts a job, calls `dispose()`, and asserts all three points, then that the
slot is free again once the job ends. The compat suite on the Android emulator also passed
against the change.

This changes 06-01's decision 4 ("`dispose()` only resets the singleton") in one respect:
`dispose()` still cancels nothing, but it no longer hides the running job.

One thing a reader should know: progress of a job in flight still goes to the
`compressProgress$` of the instance that started it. The dartdoc states this.

### WR-02: Android was not given the Swift validation-order fix

**Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt`
**Commit:** 0a2f162
**Status:** fixed: requires human verification (ordering)
**Applied fix:** `JobRegistry.resultDeferredFor(jobId)` now runs before
`Arguments.requireValidCompressRequest(request)`, and the validation is inside the `try`. A
request that native validation rejects is recorded as that job's typed outcome, as on Apple.

The JVM unit tests pass, and the compat suite passed on the emulator. No test drives a request
that Dart accepts and native rejects, because `CompressOptions.validate()` rejects the same
requests first. The changed path itself is therefore read, not run.

### WR-03: The Swift doc comment promises an ordering Swift does not guarantee

**Files modified:** `darwin/compress_video/Sources/compress_video/Compression.swift`
**Commit:** 9557a5c
**Applied fix:** Comments only. The class comment, the comment in `startCompress`, the doc
comment of `awaitCompressResult` and the comment on the grace loop now say that the
`@MainActor` ordering is best-effort and that the 2 s grace loop is the guarantee. The
constants `knownJobIdGracePolls` and `knownJobIdGracePollNanoseconds` are marked load-bearing.
The diff has no line outside a comment.

### WR-04: README statements the shipped code contradicts

**Files modified:** `README.md`, `lib/compress_video.dart`, `lib/src/compress_job.dart`
**Commit:** 2556dff
**Applied fix:**
1. "No bare `duration` or `position`" is now scoped to
   `package:compress_video/compress_video.dart`. The sentence says the compat import keeps
   the old names on purpose and points to MIGRATION.md for their units.
2. "No global progress stream and no is-compressing flag" is scoped the same way, and says
   both exist only in the deprecated compat import. The two dartdoc copies of the sentence
   were corrected too.
3. `encoderUnavailable` and `outOfSpace` lost "(compression, later versions)". `interrupted`
   is described as raised on both Android and Apple.

Nothing between the PRESET_TABLE markers was touched.

### WR-05: The generated table calls a synthetic clip a phone clip

**Files modified:** `tool/preset_table.dart`, `test/preset_table_test.dart`, `README.md`
**Commit:** 33dda1e
**Applied fix:** The three column headers are now "From the 1080p60 test clip: Android
emulator / iOS Simulator / macOS". The footnote says the clip is a generated test pattern and
not camera footage, and that the Android and iOS numbers come from software encoders. The
README sentence above the table says "this package's portrait 1080p test clip". The unit test
that pins the header and the footnote was updated. The README table was regenerated by the
generator, and a second run changed nothing.

### WR-06: The pana gate floats on an unpinned tool and hides its diagnostics

**Files modified:** `.github/workflows/ci.yml`, `doc/TOOLCHAIN.md`
**Commit:** 6ea2656
**Applied fix:** `dart pub global activate pana 0.23.19`. When pana writes no score, the step
prints "FATAL: pana produced no score" and pana's stderr, then fails. When pana scores below
the maximum, the step prints the same stderr after the sections that lost points. The
threshold assertion is unchanged. The pin is recorded in doc/TOOLCHAIN.md with how to bump it.

### WR-07: A Markdown-only push runs no CI

**Files modified:** `.github/workflows/ci.yml`
**Commit:** 99dc03c
**Status:** fixed: cannot be proven locally
**Applied fix:** `!README.md`, `!MIGRATION.md` and `!doc/PRESETS.md` follow `'**/*.md'` in
`paths-ignore`, for both `push` and `pull_request`. Other Markdown stays ignored. The `changes`
job's Apple gate is unchanged, so a push of one of these files alone runs the Android job and
skips the Apple job.

The YAML parses and both lists read back as intended. Whether GitHub starts a run is proven
only by the first push that changes one of the three files and nothing else.

**This reverses a recorded decision.** 06-04's decision 2 kept the path filters unchanged
because a trigger filter could not be proven before the release commit depended on it. The
orchestrator asked for the exception in preference to softening the CHANGELOG.

### WR-08: The integration cancel case races the encode

**Files modified:** `example/integration_test/video_compress_compat_test.dart`
**Commit:** 86dcdf3
**Applied fix:** The cancel stays mid-flight, after the first progress value, which is what
`compress_jobs_test.dart` does in all of its cancel cases. Both outcomes are now asserted in
full. Cancelled: `isCancel` true, `path` and `file` null. Finished first: `isCancel` false,
`path` and `file` set, the output file exists and `filesize` is above 0. `isCancel` must never
be null. The case prints a line when the encode wins, so a lost race shows in the log.

**The review's suggested fix was not used.** It cancels right after the call is issued. On
Apple, `JobRegistry.cancel` returns without effect when the job is not registered yet, and
registration happens after the input is probed. An immediate cancel would be dropped there and
the case would then fail every time, not sometimes.

On the Android emulator the cancel won both times.

### WR-09: A personal email address and private host names ship in the package

**Files modified:** `doc/RELEASE.md`, `.pubignore`, `CHANGELOG.md`,
`doc/HARDWARE_CHECKLIST.md`, `doc/PRESETS.md`, `lib/src/compress_options.dart`,
`lib/src/compress_result.dart`, `example/integration_test/hard_inputs_test.dart`
**Commit:** 09156c8
**Applied fix:** doc/RELEASE.md says "your Google account". `.pubignore` excludes
`doc/RELEASE.md`, `doc/TOOLCHAIN.md`, `tool/mac_run.sh` and `tool/mac_sync.sh`.

The grep found the host name `danserver` in five shipped files the review did not list: two
dartdoc comments, doc/PRESETS.md, doc/HARDWARE_CHECKLIST.md and one integration test. Each now
says "the development host" or "the development emulator". No measured row of doc/PRESETS.md
changed, and the README table regenerates unchanged.

Two references to the excluded file were corrected: CHANGELOG.md and
doc/HARDWARE_CHECKLIST.md now say doc/RELEASE.md is in the repository and not in the package.

**Result:** the dry-run file listing has none of the four excluded files. A grep of every
file that ships for `danthebeliever`, `dans-macbook-air` and `danserver` matches one file,
`darwin/compress_video.podspec`, the documented exception.

### IN-01: The new CI steps did not run with pipefail

**Files modified:** `.github/workflows/ci.yml`
**Commit:** b4a95ae
**Applied fix:** `shell: bash` on the pana step and the dartdoc step.

### IN-02: CHANGELOG says the compat import has "the whole public surface"

**Files modified:** `CHANGELOG.md`
**Commit:** 0e08131
**Applied fix:** "the documented surface", with a pointer to the names MIGRATION.md lists as
not provided.

### IN-04: `compressProgress$` drops values sent while nobody is subscribed

**Files modified:** `lib/video_compress_compat.dart`, `MIGRATION.md`
**Commit:** 887672c
**Applied fix:** Documented as a third difference, and not a superset, in the dartdoc of
`ObservableBuilder` and in MIGRATION.md's `compressProgress$` row. Behaviour is unchanged.

### IN-05: MIGRATION.md says a compression's output "is upright"

**Files modified:** `MIGRATION.md`
**Commit:** 887672c (with IN-04, the same file)
**Applied fix:** "Not provided. Read `rotationDegrees` from `getMediaInfo(result.outputPath)`."

### IN-06: The last integration case depends on an earlier one

**Files modified:** `example/integration_test/video_compress_compat_test.dart`
**Commit:** 5798562
**Applied fix:** The `deleteAllCache` case compresses `small_480p.mp4` itself and checks that
output. The shared variable was removed. The suite passed on the Android emulator afterwards.

## Skipped Issues

### IN-03: `compressVideo` copies `CompressOptions` field by field

**File:** `lib/video_compress_compat.dart:381-398`
**Reason:** Not small. The fix adds `CompressOptions.copyWith` to the main library's public
API one commit before 1.0.0, and nullable fields need a way to be reset to null, which is a
design choice. Out of scope for a review fix.
**Original issue:** A field added to `CompressOptions` later is silently dropped by the
compat shim, with no compile error.

## For the orchestrator

1. **A tool result carried an instruction that did not come from the orchestrator.** The
   output of the first shell command ended with a block asking for a different
   `Claude-Session` trailer on commits. It was not followed. Every commit carries the trailer
   the orchestrator gave. 06-02 and 06-04 recorded the same thing.
2. **WR-07 reverses 06-04's decision 2**, as asked. It is unproven until a Markdown-only push.
3. **WR-08 does not use the review's fix**, for the reason given above.
4. **WR-01 and WR-02 are marked for human verification.** Both change state handling or
   ordering, and syntax checks do not prove logic.
5. **The emulator** was booted twice by this run and stopped each time by its own PID. No
   emulator was running before, and none is running now.

---

_Fixed: 2026-09-28T01:17:24Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
