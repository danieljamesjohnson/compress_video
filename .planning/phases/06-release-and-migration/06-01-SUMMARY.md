---
phase: 06-release-and-migration
plan: 01
subsystem: api
tags: [dart, flutter, compatibility, migration, video_compress, deprecation]

requires:
  - phase: 02-android-compression
    provides: CompressVideo.compress, CompressOptions/presets, CompressResult, clearCache
  - phase: 05-jobs-and-background
    provides: the per-instance FIFO queue (maxConcurrentJobs) and CompressJob.cancel
  - phase: 01-foundation
    provides: getMediaInfo, getThumbnail/getThumbnailFile, the typed exception taxonomy
provides:
  - "package:compress_video/video_compress_compat.dart: the incumbent's public surface on the new engine"
  - "VideoQuality.compressOptions: the single source of the VideoQuality -> CompressOptions mapping (for MIGRATION.md and tests)"
  - "A fake-host pattern covering every host call the shim reaches (test/video_compress_compat_test.dart)"
affects: [06-02, 06-03, 06-04, MIGRATION.md, README, CHANGELOG, dartdoc coverage, pana]

actuals:
  tokens: 14291
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Compat shim is pure Dart over the public library: two imports of compress_video.dart (hide MediaInfo + prefix cv), no generated messages, no channel"
    - "Every compat symbol carries @Deprecated with the replacement call and a pointer to MIGRATION.md"
    - "Files are compared after resolveSymbolicLinks before anything is deleted"

key-files:
  created:
    - lib/video_compress_compat.dart
    - test/video_compress_compat_test.dart
    - test/video_compress_compat_snippets_test.dart
  modified: []

key-decisions:
  - "compressVideo's StateError is delivered through the returned Future (async method), as the incumbent did, not thrown synchronously; it is still raised before any channel call"
  - "deleteOrigin compares input and output as files (symbolic links resolved), not as strings, and keeps the input whenever the comparison cannot be made"
  - "A compression's MediaInfo.orientation is left null rather than claimed to be 0"
  - "IVideoCompress has a private constructor; the only way to get one is the VideoCompress getter, as with the incumbent's abstract class"
  - "ObservableBuilder.notSubscribed never returns to true after an unsubscribe, matching the incumbent"

patterns-established:
  - "Compat tests import the main library with `show` so the two MediaInfo classes never collide"
  - "Snippet tests: one function per documented snippet, verbatim body, run against the fake host"

requirements-completed: [RELS-03]

coverage:
  - id: D1
    description: "Every VideoQuality value maps to exactly one documented CompressOptions, exposed as VideoQuality.compressOptions"
    requirement: "RELS-03"
    verification:
      - kind: unit
        ref: "test/video_compress_compat_test.dart#VideoQuality every value maps to exactly the documented CompressOptions"
        status: pass
    human_judgment: false
  - id: D2
    description: "getMediaInfo, getByteThumbnail, getFileThumbnail and deleteAllCache run on the new engine and throw typed exceptions instead of returning null"
    requirement: "RELS-03"
    verification:
      - kind: unit
        ref: "test/video_compress_compat_test.dart#getMediaInfo, thumbnails, deleteAllCache groups"
        status: pass
    human_judgment: false
  - id: D3
    description: "compressVideo keeps single-in-flight (StateError, isCompressing), forwards progress to every compressProgress$ subscriber, and resolves a cancel to MediaInfo(isCancel: true)"
    requirement: "RELS-03"
    verification:
      - kind: unit
        ref: "test/video_compress_compat_test.dart#compressVideo group"
        status: pass
    human_judgment: false
  - id: D4
    description: "deleteOrigin deletes the input only after success and only when the output is a different file"
    requirement: "RELS-03"
    verification:
      - kind: unit
        ref: "test/video_compress_compat_test.dart#compressVideo deleteOrigin group (6 cases, real temp files)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The incumbent README's snippets compile and run with only the import changed"
    requirement: "RELS-03"
    verification:
      - kind: unit
        ref: "test/video_compress_compat_snippets_test.dart"
        status: pass
    human_judgment: false
  - id: D6
    description: "The pushed commits are green on CI's Dart gates (Analyze, Run Dart unit tests, Dry-run publish, channel plumbing grep)"
    requirement: "RELS-03"
    verification:
      - kind: other
        ref: "gh run view 36349144752 --json jobs"
        status: unknown
    human_judgment: true
    rationale: "CI run 36349144752 was still in progress when this plan returned; the orchestrator relays its result. The same four gates passed locally."

duration: 9min
completed: 2026-09-27
status: complete
---

# Phase 6 Plan 01: video_compress compatibility library Summary

**`package:compress_video/video_compress_compat.dart`: the full `video_compress` 3.1.4 surface (`VideoCompress`, `VideoQuality`, compat `MediaInfo`, `compressProgress$`) as a deprecated pure-Dart shim over `CompressVideo(maxConcurrentJobs: 1)`, with the incumbent README's snippets compiled and run against it.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-09-27T20:36:46Z
- **Completed:** 2026-09-27T20:45:30Z
- **Tasks:** 3 of 3
- **Files modified:** 3 (all new; 1,619 lines)

## Accomplishments

- An app that switches its import to the compat library compiles against every call the incumbent documents. 39 new unit tests cover this; the package's test count went from 100 to 139.
- Nothing returns `null`. A failure throws the typed `CompressVideoException`, and a cancelled compression resolves to `MediaInfo(isCancel: true)`.
- The `VideoQuality` mapping lives in one place, `VideoQuality.compressOptions`. 06-02's MIGRATION.md can read it from there.
- The shim adds no channel, no Pigeon change and no native code. `git diff --stat HEAD~3 -- pigeons android darwin` is empty.

## Task Commits

1. **Task 1: The compat library surface and the VideoQuality mapping** - `bf0f581` (feat)
2. **Task 2: compressVideo, progress, cancel, thumbnails and cache on the new engine** - `60f8db8` (feat)
3. **Task 3: The incumbent README snippets compile and run against the shim; push** - `457ffd1` (test)

Pushed to `origin` and `github` at `457ffd1`.

## CI

| Run | Commit | Status when this plan returned |
|---|---|---|
| 36349144752 | `457ffd1` | **pending** (in progress, 6 s old) |

This is pushed CI attempt 1 of the plan's budget of 3. The run was not polled, per the orchestrator's rule.

The same gates passed locally, on Flutter 3.47.5 stable:

| Gate | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | exit 0, 34 files, 0 changed |
| `flutter analyze --fatal-infos --fatal-warnings` | No issues found |
| `flutter test test/` | 139 passed |
| `dart pub publish --dry-run` | Package has 0 warnings |
| Channel-primitive grep over `lib/video_compress_compat.dart` | 0 matches |

## Files Created/Modified

- `lib/video_compress_compat.dart` - the compatibility library (546 lines)
- `test/video_compress_compat_test.dart` - 33 unit tests through a fake host (777 lines)
- `test/video_compress_compat_snippets_test.dart` - 6 tests that run the README snippets (296 lines)

## Decisions Made

1. **`StateError` arrives through the `Future`.** The plan's behaviour block says a second `compressVideo` "throws `StateError` synchronously (before any channel call)". `compressVideo` is an `async` method, so the error is delivered through the returned `Future`, which is what the incumbent did. A caller using `.catchError` keeps working. The check still runs before any `await` and before any channel call, and the test asserts that the fake host saw exactly one `startCompress`.
2. **A compression's `MediaInfo.orientation` is `null`.** The plan lists the fields to map and orientation is not one of them. A transmuxed or copied output may still carry rotation metadata, so 0 would be a guess.
3. **`IVideoCompress` cannot be constructed by callers.** The incumbent's class was abstract. Here the constructor is private and the `VideoCompress` getter is the only source.
4. **`dispose()` only resets the singleton.** It does not cancel a job in flight, as with the incumbent. The dartdoc says so.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `deleteOrigin` deleted the input when the output was a symbolic link to it**
- **Found during:** Task 2
- **Issue:** The plan's guard is `result.outputPath != path`, a string comparison. A second name for the same file passes it. The first fix used `FileSystemEntity.identical`, which does not follow symbolic links, and the new test showed the input being deleted through the alias. This is threat T-06-01 (high).
- **Fix:** Both paths go through `resolveSymbolicLinks()` first. The input is deleted only if the resolved paths differ and `FileSystemEntity.identical` also says they are different files. If the comparison throws, the input is kept.
- **Files modified:** `lib/video_compress_compat.dart`, `test/video_compress_compat_test.dart`
- **Verification:** the test "leaves the input when the output path is another name for the same file" failed before the fix and passes after it.
- **Committed in:** `60f8db8`

### Process deviations

**2. One commit per task, not separate RED and GREEN commits.** The tasks are marked `tdd="true"`, but Task 3 of the plan names exactly three commits and the orchestrator ran with TDD mode off. The tests were written first in tasks 1 and 2 and were seen to fail (compile errors on the missing symbols) before the implementation was written.

**3. `WINDOWS.md` was not updated.** The pending CI check is an unrun verification, which the executor protocol records with `gsd-tools windows append`. That is a write verb and the orchestrator forbids those. It is recorded here instead, under CI and in coverage entry D6.

---

**Total deviations:** 1 auto-fixed (Rule 1), 2 process.
**Impact on plan:** The fix closes a data-loss path in the plan's own threat register. No scope was added.

## Issues Encountered

- **`flutter analyze` and `flutter test` on Flutter 3.47.5 rewrite `analysis_options.yaml`.** Each run adds an `analyzer: exclude:` block for `build/**` and `android/**`. This is the Flutter project migrator that ci.yml's "Reset files" step already works around. The file was restored with `git checkout -- analysis_options.yaml` before every commit and was never committed. Later plans in this phase will see the same thing.
- **`FileSystemEntity.identical` does not follow symbolic links.** See deviation 1.

## Threat Register Outcome

| Threat | Disposition | Outcome |
|---|---|---|
| T-06-01 `deleteOrigin` deleting a file the app needs | mitigate | Done, and stronger than planned. 6 tests with real temp files. |
| T-06-02 `isCompressing` stuck true | mitigate | Done. Flags reset in `finally`; tested after a failure, a cancel and a rejected argument. |
| T-06-03 errors swallowed into `null` | mitigate | Done. No catch-to-null; the only `catch` rethrows everything except `cancelled`. |
| T-06-04 a hand-written channel in the shim | mitigate | Done. Grep is 0 over the whole file, comments included. |

No new security surface was introduced beyond the threat model. The only file access the shim adds is `deleteOrigin`.

## Known Stubs

None. `setLogLevel` is a documented no-op by design (the plan specifies it).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **06-02 can start.** MIGRATION.md should take the mapping table from the dartdoc of `VideoQualityCompressOptions.compressOptions`, and should state decisions 1 and 2 above plus the non-null return types.
- **RELS-03 is not complete yet.** This plan delivers the compatibility layer. The migration guide and the integration suite are 06-02, which also declares RELS-03.
- **Open:** the result of CI run 36349144752.

## Self-Check: PASSED

- FOUND: `lib/video_compress_compat.dart`, `test/video_compress_compat_test.dart`, `test/video_compress_compat_snippets_test.dart`
- FOUND: commits `bf0f581`, `60f8db8`, `457ffd1`
- All task acceptance criteria re-run and passing, except the CI criterion of task 3, which is pending.

---
*Phase: 06-release-and-migration*
*Completed: 2026-09-27*

## Orchestrator CI resolution (2026-09-27, after execution)

- Run 36349144752 (06-01's push) was cancelled by 06-03's push under the workflow's cancel-in-progress concurrency, as expected.
- Run 36349558026 (06-03's push, covering 06-01's commits too): Android job **green** (including the new "Verify README preset table matches the preset constants (RELS-02)" step); Apple job **failed** in the Phase 5 suite `jobs_background_test.dart` ("awaitCompressResult called for unknown jobId"), a latent Apple-side registration race unrelated to Phase 6 code. Fixed by quick task 260927-r4k (`404dff4`, `b8ee2f9`, `74c7206`).
- Run 36351396397 (quick-task push, containing every Phase 6 wave 1 commit): **all four jobs green** (Detect Apple-relevant changes, Android, Apple, Cross-platform parity). This run is the CI evidence for the "pending" criteria above; they are now satisfied.
