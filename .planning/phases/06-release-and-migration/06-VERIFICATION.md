---
phase: 06-release-and-migration
verified: 2026-09-28T02:48:16Z
status: human_needed
score: 2/4 ROADMAP criteria verified (2 wait on Dan-only steps); 19/19 plan must-have truths verified
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Decide the pub.dev publisher (QUESTIONS.md #2), then follow doc/RELEASE.md: run `dart pub publish` from a clean checkout of `main`, tag `v1.0.0`, push the tag to both remotes, and create the GitHub release. Afterwards open https://pub.dev/packages/compress_video/score."
    expected: "`compress_video` 1.0.0 is live on pub.dev and its score page shows 160/160 pub points. Only then is ROADMAP criterion 1 (and RELS-01) true, and only then can a developer switch to `compress_video` 'from pub.dev' as the phase goal says."
    why_human: "Publishing is irreversible (a version can be retracted but never deleted), needs Dan's Google account and his publisher choice, and is forbidden to agents by 06-CONTEXT.md and plan 06-04. Observed at verification time: https://pub.dev/api/packages/compress_video returns 404, no git tag exists, no GitHub release exists. Everything short of the publish is proven: `dart pub publish --dry-run` reports 0 warnings and pana grants 160/160, both locally at HEAD and in CI run 36366408783. pub.dev runs its own copy of pana, so its score page is the real check."
  - test: "Re-run doc/HARDWARE_CHECKLIST.md against a release build (`cd example && flutter build apk --release` for a physical Android phone; `flutter build ios --release --no-codesign` and `flutter build macos --release` on the MacBook Air) and record each result in that file with the date. Do this BEFORE the publish above; it is item 1 of doc/RELEASE.md's pre-publish checklist."
    expected: "Every checklist entry has a dated result from real hardware: hardware HEVC encode, HDR tone-map fidelity, the foreground-service walkthrough on a phone, the iOS suspension walkthrough."
    why_human: "ROADMAP criterion 4 has not happened. Every entry of doc/HARDWARE_CHECKLIST.md still reads 'not yet run'. It needs a physical Android phone (QUESTIONS.md #3), real phone clips including Dolby Vision (QUESTIONS.md #4) and the MacBook Air awake (QUESTIONS.md #8). No agent can do it."
  - test: "Read MIGRATION.md, the README sections 'Presets at a glance' and 'What this plugin deliberately does not do', and CHANGELOG.md's 1.0.0 entry as a developer who has never seen this package."
    expected: "Each reads as plain English, and a `video_compress` user can follow the migration without reading source code."
    why_human: "Tests prove every identifier, number and mapping is present and agrees with the code. Whether the prose is clear is a judgment (recorded as human_judgment in 06-02 D4, 06-03 D6 and 06-04 D4/D5). This does not block the publish; it is a courtesy read."
coincidental_reliance_items:
  - truth: "`cancelCompression` stops a running `compressVideo` on the macOS host"
    reason: incidental-ordering
    harden: "On macOS the integration case accepts a finished result as well as a cancelled one (review finding IN-10, open). In CI run 36366408783 the cancel did land on macOS, but nothing in the test forces it to. Either require `isCancel == true` on macOS too, as the case did before WR-08 and as compress_jobs_test.dart does, or print the last progress value before the cancel so a lost race can be told from a dead cancel."
---

# Phase 6: Release and Migration Verification Report

**Phase Goal:** A developer on `video_compress` can switch to `compress_video` from pub.dev by
changing one import. The documentation says exactly what each preset does and what the plugin
will not do.
**Verified:** 2026-09-28T02:48:16Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Summary

Everything an agent can deliver is delivered and was observed working, in this checkout and
in CI. The phase goal is **not yet literally true**, for one reason: the package is not on
pub.dev. That step and the hardware re-run are Dan's by design (06-CONTEXT.md, plan 06-04,
doc/RELEASE.md). They are recorded as human items and not as gaps, because no plan or code
change can close them.

| Part of the goal | State |
|---|---|
| Switch by changing one import | Proven on Android, iOS simulator and macOS in CI |
| "from pub.dev" | **Not yet.** pub.dev returns 404 for the package. Waits on Dan. |
| Docs say what each preset does | Proven. The table is generated and gated in CI. |
| Docs say what the plugin will not do | Proven. Ten non-goals, every D-06 item present. |

## What was run for this report, and where

All of it ran in the main checkout at `/home/dan/CodeProjects/compress-video`, HEAD `eef4ecf`,
on Flutter 3.47.5 stable. `analysis_options.yaml` was restored afterwards and `git status` is
clean. No source file was changed and nothing was committed, published, tagged or notified.

| Check | Result |
|---|---|
| `flutter test test/` | 221 passed, exit 0 |
| `flutter test tool/generate_preset_table.dart` then `git diff --exit-code README.md` | exit 0, README unchanged |
| `dart pub publish --dry-run` | `Package has 0 warnings.` |
| Dry-run file list, grep for `.planning`, `QUESTIONS.md`, `.gsd`, `.github`, `.claude`, `.mission-control`, `RELEASE.md`, `TOOLCHAIN.md`, `mac_run`, `mac_sync` | 0 matches |
| `dart doc --dry-run` | `Found 0 warnings and 0 errors.` |
| `pana --exit-code-threshold 0 --json .` (pana 0.23.19) | exit 0, `grantedPoints 160`, `maxPoints 160` |
| `gh run view 36366408783 --json jobs` | all four jobs `success`, head `7c3f273` |
| Job logs of that run, downloaded and grepped | see "CI evidence" below |
| The three parity artifacts of that run, downloaded | each holds `compat_compress_low_quality` |
| `curl` of `https://pub.dev/api/packages/compress_video` | 404 |
| `git tag -l`, `gh release list` | both empty |

Not run, and why:

- **The integration suite on a device.** Not run locally by this report. CI run 36366408783
  is the evidence, read from its logs.
- **Run 36370914935** (the README-only push `9c58899`) was still `in_progress` when this
  report was written. Its Android job had started and its Apple job was `skipped`, which is
  what the WR-07 filter should do. Its result is not evidence for anything here.

### Is the CI run still evidence for HEAD?

Run 36366408783 tested `7c3f273`. HEAD is four commits later. `git diff --stat 7c3f273 HEAD`
shows five files: `.claude/CLAUDE.md`, three `.planning/` files, and `README.md` (4 lines, at
lines 415-416, outside the preset-table markers). No code, test or workflow file changed. The
README change was re-checked at HEAD by the generator gate, dartdoc, pana and the dry-run
above, all of which read the README. The run stands.

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `compress_video` is live on pub.dev and scores 160/160 pub points | ? NEEDS HUMAN | **Not live:** pub.dev API returns 404. **Score half proven:** pana 160/160 locally at HEAD and in CI (log line `pana: 160/160 pub points`, step `pana: 160/160 pub points (RELS-01)` green). Dry-run 0 warnings, dartdoc 0 warnings, both local and CI. `pubspec.yaml` is 1.0.0 with android/ios/macos platforms, repository, issue tracker and five topics; LICENSE is MIT; `example/` is present. doc/RELEASE.md gives the procedure. |
| 2 | README has a plain-English per-platform preset table generated from the measured constants, and a section on what the plugin does not do | ✓ VERIFIED | README `### Presets at a glance` holds four rows (p360/p480/p720/p1080) between the markers, with cap, bitrate target, fps cap and the measured Android/iOS/macOS results. Values match `kPresetSpecs` (640/854/1280/1920; 0.8/1.2/2.5/5 Mbps). Regenerating at HEAD changes nothing. CI step `Verify README preset table matches the preset constants (RELS-02)` is green and sits before the `git checkout -- .` reset (ci.yml lines 281 < 293). `## What this plugin deliberately does not do` has ten bullets covering every D-06 item. |
| 3 | An app using `compressVideo`, `getMediaInfo`, `getFileThumbnail`, `cancelCompression` and `deleteAllCache` builds and works after switching to the compat import; MIGRATION.md maps every old API and `VideoQuality` value | ✓ VERIFIED | `lib/video_compress_compat.dart` (569 lines) implements every verb over `CompressVideo(maxConcurrentJobs: 1)`. The integration suite imports only the compat library and passed all six cases on the Android emulator, the iOS simulator and the macOS host in run 36366408783. MIGRATION.md has a row for every incumbent identifier and all eight `VideoQuality` values; `test/migration_doc_test.dart` ties the tables to the code and passes. |
| 4 | The TEST-01 hardware checklist has been re-run against the release build before publishing | ? NEEDS HUMAN | **Not done.** Every entry of doc/HARDWARE_CHECKLIST.md reads "not yet run". It is item 1, an unchecked box, of doc/RELEASE.md's pre-publish checklist, and QUESTIONS.md #3, #4 and #8 each carry a 2026-09-27 note that the release waits on them. |

**Score:** 2/4 ROADMAP criteria verified. The other two wait on steps only Dan can take.

### Plan must-have truths

| Plan | Truth (short) | Status | Evidence |
|---|---|---|---|
| 06-01 | One-line import switch compiles against every documented incumbent call | ✓ VERIFIED | `test/video_compress_compat_snippets_test.dart` runs the incumbent README's snippets with only the compat import; passes |
| 06-01 | Every shim call runs on the new engine and never returns `null`; cancel gives `MediaInfo(isCancel: true)` | ✓ VERIFIED | Code read: return types are non-nullable; the one `catch` (line 438) rethrows everything except `cancelled`. Unit and integration tests pass |
| 06-01 | Each `VideoQuality` maps to one `CompressOptions`, exposed as `compressOptions` | ✓ VERIFIED | Exhaustive `switch`, lines 105-131; matches the D-11 table |
| 06-01 | `isCompressing` true exactly while in flight; second call gives `StateError`; progress reaches every subscriber | ✓ VERIFIED | State reset in `finally` (lines 443-447). Behaviour exercised by unit tests and by the integration case on three platforms. The error arrives through the `Future`, as the incumbent's did; MIGRATION.md says so |
| 06-01 | No channel, no Pigeon change, no native code in the shim | ✓ VERIFIED | Imports are `dart:async`, `dart:io`, `dart:typed_data`, the public library twice, and `flutter/foundation.dart`. Channel-word grep over the whole file: 0 |
| 06-02 | MIGRATION.md maps every public 3.1.4 API and all eight `VideoQuality` values | ✓ VERIFIED | Sections 3, 4 and 5 read in full. Every identifier extracted from the incumbent snapshot has a row, plus `Compress`, `initProcessCallback`, `setProcessingStatus` |
| 06-02 | The `VideoQuality` table cannot disagree with the code | ✓ VERIFIED | `test/migration_doc_test.dart` passes |
| 06-02 | Each shim entry point passes an integration case on Android, iOS simulator and macOS | ✓ VERIFIED | Log lines of run 36366408783: the group `video_compress compat import` ran to its last case in `Run emulator integration tests`, `...iOS simulator (part 2)` and `...macOS (part 2)` |
| 06-02 | The shim's output dimensions and duration agree across platforms in the parity job | ✓ VERIFIED | Artifacts: Android 360x640, 4032 ms; iOS 360x640, 4000 ms; macOS 360x640, 4000 ms; tolerance 34 ms. `Cross-platform parity` green |
| 06-02 | MIGRATION.md's switch example is the code the snippet test compiles | ✓ VERIFIED | The line `MediaInfo mediaInfo = await VideoCompress.compressVideo(` appears once in each |
| 06-03 | README table gives cap, bitrate, fps and the measured per-platform result | ✓ VERIFIED | Table read from README |
| 06-03 | Table is generated, never typed; CI regenerates and diffs | ✓ VERIFIED | Generator idempotent at HEAD; CI step green |
| 06-03 | Non-goals section names every D-06 item | ✓ VERIFIED | Web, FFmpeg, filters/overlays/watermarks/stitching, keep-HDR, background-isolate progress, below Android 15, iOS background, upload, software HEVC: all present |
| 06-03 | Changing a preset constant without regenerating turns CI red | ✓ VERIFIED | The gate is `regenerate; git diff --exit-code README.md`, which by construction fails on any difference. 06-03 recorded exit 1 on a changed constant. Not repeated here, because it means editing a source file |
| 06-04 | pubspec 1.0.0, platforms, metadata; dry-run 0 warnings locally and in CI | ✓ VERIFIED | File read; dry-run run here; CI log line `Package has 0 warnings.` |
| 06-04 | CI runs pana and fails unless granted equals max | ✓ VERIFIED | Step green; threshold is 0; pana pinned to 0.23.19; a second `jq` check compares granted with max |
| 06-04 | Every public symbol carries dartdoc | ✓ VERIFIED | `Analyze` step green with `public_member_api_docs`; dartdoc 0 warnings locally and in CI |
| 06-04 | CHANGELOG 1.0.0 lists the breaking changes and names the compat import, MIGRATION.md and the table | ✓ VERIFIED | `### Breaking changes (since 0.1.0)` holds `const`, `maxConcurrentJobs`, `encoderUnavailable`, `outOfSpace`, `interrupted`; `### Added in 1.0.0` names both |
| 06-04 | doc/RELEASE.md gives the procedure, hardware re-run first; no executor ran any of it | ✓ VERIFIED | File read. No tag, no release, pub.dev 404 |

**Score:** 19/19 plan truths verified.

### Prohibitions

Every prohibition in the four plans names a command as its check. Each was run or read here.

| Plan | Prohibition | Result |
|---|---|---|
| 06-01 | No hand-written channel in the shim | Held. Grep is 0 over the whole file |
| 06-01 | No failure swallowed into `null` or `debugPrint` | Held. 0 matches outside comments |
| 06-01 | No untyped map parsed; no `fromJson` | Held. 0 matches outside comments |
| 06-02 | No `timeout-minutes` raised; part 2 steps not merged | Held. The phase's diff of ci.yml adds or removes no `timeout-minutes:` line; both `(part 2)` steps exist |
| 06-02 | No shim change without its unit test | Held. WR-01 changed both files in one commit (48aa3b0) |
| 06-02 | No Mac command in a loop | Held, per the SUMMARY: one probe. Cannot be re-observed |
| 06-03 | Nothing hand-edited between the markers | Held. Regeneration leaves README unchanged |
| 06-03 | doc/PRESETS.md's measured rows not hand-edited | Held. The file did change in this phase (WR-09, 2 lines), but only prose: "danserver" became "the development host". No table row changed, and the README regenerates unchanged |
| 06-03 | No preset constant changed | Held. `lib/src/presets.dart` has no diff in this phase |
| 06-04 | No publish, tag, release or notification | Held. pub.dev 404; no tag; no release; the last `compress-video` line in `notify-dan.log` is 2026-09-27T03:42 -05:00, before this phase began |
| 06-04 | Hardware re-run not marked done | Held. Unchecked box; every checklist entry "not yet run" |
| 06-04 | No CI gate lowered | Held. `analysis_options.yaml` has no diff in this phase; the only `exit-code-threshold` is 0 |

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `lib/video_compress_compat.dart` | The compat library | ✓ VERIFIED | 569 lines, 17 `@Deprecated`, in the publish archive, imported by three test files and the integration suite |
| `test/video_compress_compat_test.dart` | Unit coverage through the fake host | ✓ VERIFIED | 808 lines, passes |
| `test/video_compress_compat_snippets_test.dart` | Incumbent README snippets, run | ✓ VERIFIED | 296 lines, passes |
| `MIGRATION.md` | Old API to new API guide | ✓ VERIFIED | 254 lines, six sections, in the publish archive |
| `test/migration_doc_test.dart` | Guard for MIGRATION.md | ✓ VERIFIED | 260 lines, passes |
| `example/integration_test/video_compress_compat_test.dart` | One real-engine case per entry point | ✓ VERIFIED | 347 lines, six cases, green on three platforms in CI |
| `tool/run_ios_integration_suites.sh` | Suite in the default list | ✓ VERIFIED | Line 62 |
| `tool/preset_table.dart`, `tool/generate_preset_table.dart` | Renderer and generator | ✓ VERIFIED | 302 and 52 lines; generator reads `kPresetSpecs` and doc/PRESETS.md |
| `test/preset_table_test.dart` | Renderer tests | ✓ VERIFIED | 427 lines, passes |
| `README.md` | Table, non-goals, Install, Migrating | ✓ VERIFIED | All four sections present; "Not yet published" line gone |
| `pubspec.yaml` | 1.0.0 metadata | ✓ VERIFIED | Read in full |
| `CHANGELOG.md` | 1.0.0 entry | ✓ VERIFIED | `## 1.0.0`, no `## Unreleased`, `## 0.1.0` kept |
| `doc/RELEASE.md` | Publish procedure | ✓ VERIFIED | 91 lines; excluded from the archive on purpose (WR-09) |
| `.github/workflows/ci.yml` | Table gate, pana gate, dartdoc gate, compat suite on Apple | ✓ VERIFIED | All four present and green in run 36366408783 |
| `.pubignore` | Planning and agent files kept out of the archive | ✓ VERIFIED | Dry-run file list has none of them |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| compat library | `lib/compress_video.dart` | `CompressVideo(maxConcurrentJobs: 1)` | ✓ WIRED | Line 282. Since WR-01 the engine belongs to the library and not to the instance, so it outlives `dispose()` |
| `VideoQuality.compressOptions` | `CompressPreset` | exhaustive `switch` | ✓ WIRED | Lines 105-131 |
| integration suite | compat library | its only plugin import | ✓ WIRED | Line 18 |
| `PARITY_JSON` record | `tool/check_parity.sh` | `compression` key | ✓ WIRED | Record present in all three artifacts; parity job green |
| generator | `lib/src/presets.dart` | `kPresetSpecs`, `CompressOptions().maxFps` | ✓ WIRED | README values equal the constants |
| generator | doc/PRESETS.md | `parseMeasuredRows` | ✓ WIRED | README cells carry the measured numbers |
| doc/RELEASE.md | QUESTIONS.md #2 | publisher step, options A and B | ✓ WIRED | Item 4 of the checklist |
| ci.yml pana step | the package | granted compared with max | ✓ WIRED | Log line `pana: 160/160 pub points` |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|---|---|---|---|---|
| README preset table | caps, bitrates | `kPresetSpecs` | Yes | ✓ FLOWING |
| README preset table | per-platform results | doc/PRESETS.md measured rows | Yes | ✓ FLOWING |
| compat `MediaInfo` from `compressVideo` | path, size, dimensions, duration | `CompressResult` from the real engine | Yes; 360x640 on three platforms | ✓ FLOWING |
| compat `MediaInfo` from `getMediaInfo` | dimensions, rotation, size | the engine's typed `MediaInfo` | Yes; equals the corpus sidecar in CI | ✓ FLOWING |

### CI evidence (run 36366408783, head `7c3f273`)

| Job | Step | Result |
|---|---|---|
| Android | Analyze | success |
| Android | Verify no hand-written channel plumbing remains | success |
| Android | Run emulator integration tests (compat suite included) | success |
| Android | Run Dart unit tests | success |
| Android | Verify README preset table matches the preset constants (RELS-02) | success |
| Android | Dry-run publish | success, `Package has 0 warnings.` |
| Android | pana: 160/160 pub points (RELS-01) | success, `pana: 160/160 pub points` |
| Android | dartdoc: zero warnings (RELS-01) | success, `Found 0 warnings and 0 errors.` |
| Apple | Run corpus integration tests on the iOS simulator (part 2) | success; compat group ran |
| Apple | Run corpus integration tests on macOS (part 2) | success; compat group ran |
| Cross-platform parity | Android vs iOS, macOS vs iOS | success |

In this run the cancel case resolved as cancelled on all three platforms, macOS included.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Unit suite passes at HEAD | `flutter test test/` | 221 passed | ✓ PASS |
| README table is what the generator writes | generator, then `git diff --exit-code README.md` | exit 0 | ✓ PASS |
| Package is publishable | `dart pub publish --dry-run` | 0 warnings | ✓ PASS |
| Package is granted every pub point | `pana --exit-code-threshold 0 --json .` | 160/160 | ✓ PASS |
| Documentation builds clean | `dart doc --dry-run` | 0 warnings, 0 errors | ✓ PASS |

### Probe Execution

Step 7c: SKIPPED. No plan or summary of this phase declares a `probe-*.sh`, and the
repository has no `scripts/*/tests/probe-*.sh`.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| RELS-01 | 06-04 | Published on pub.dev, 160/160 pub points | ? NEEDS HUMAN | Ready to publish and scoring 160/160 on pana. Not published. Dan's step |
| RELS-02 | 06-03 | README preset table per platform, and a non-goals section | ✓ SATISFIED | ROADMAP criterion 2 above |
| RELS-03 | 06-01, 06-02 | Migration guide and a compat layer for a one-line import switch | ✓ SATISFIED | ROADMAP criterion 3 above |

All three phase requirement IDs appear in a plan's `requirements:` field. No orphaned
requirement: REQUIREMENTS.md maps only RELS-01, RELS-02 and RELS-03 to Phase 6.

**REQUIREMENTS.md still shows all three as `[ ]` and `Pending`.** RELS-02 and RELS-03 can be
marked complete, citing run 36366408783. RELS-01 should stay `Pending` until the package is on
pub.dev. ROADMAP.md's four plan boxes for this phase are also still unchecked. Both files
must be edited by hand, not with a `gsd-tools` writer.

### Anti-Patterns Found

A grep for `TBD`, `FIXME`, `XXX`, `TODO`, `HACK` and `PLACEHOLDER` over the fourteen files
this phase created or changed found nothing. `setLogLevel` is an empty method on purpose, and
its dartdoc and MIGRATION.md both say so.

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| `lib/video_compress_compat.dart` | 396-413 | `CompressOptions` copied field by field (review IN-03, open) | ℹ️ Info | A field added to `CompressOptions` later is dropped by the shim with no compile error. No effect today |
| `example/integration_test/video_compress_compat_test.dart` | 258-273 | macOS accepts a finished result in the cancel case (review IN-10, open) | ℹ️ Info | On macOS a cancel that does nothing would still pass. The shim's cancel is shared Dart code and is required to land on Android and iOS |
| `doc/RELEASE.md` | 77 | "To run pana by hand" activates pana with no version | ℹ️ Info | CI pins 0.23.19. A newer pana run by hand may score differently from CI |

### Code review and the mid-phase fix

- Review reached `approved` at iteration 3. Fifteen findings of iteration 1 and five of
  iteration 2 were fixed. IN-03 was skipped with a reason. IN-10 is open. IN-11 was fixed
  after the review, in `b19e3b1`.
- The Apple `awaitCompressResult` registration race (quick task 260927-r4k) was a Phase 5
  defect that surfaced in this phase's first Apple run. Its fix is in the tree, and the Phase
  5 suite `jobs_background_test.dart` has passed on Apple in two runs since: 36351396397 and
  36366408783. The quick task's own summary notes that no test reproduces the race itself,
  so green runs are consistent with the fix and do not prove it.
- WR-02 (Android validation order) was read and not run: no test sends a request that Dart
  accepts and native rejects. It does not bear on any Phase 6 truth.

### Human Verification Required

### 1. Publish to pub.dev

**Test:** Decide the publisher (QUESTIONS.md #2), then follow doc/RELEASE.md: `dart pub
publish`, tag `v1.0.0`, push the tag, create the GitHub release. Then open
`https://pub.dev/packages/compress_video/score`.
**Expected:** Version 1.0.0 is live and the score page shows 160/160.
**Why human:** Irreversible, needs Dan's Google account and his decision, and is forbidden to
agents.

### 2. Hardware checklist on a release build

**Test:** Re-run doc/HARDWARE_CHECKLIST.md against release builds on a physical Android
phone and on the MacBook Air, and record each result with its date. Do this before item 1.
**Expected:** Every entry has a dated result from real hardware.
**Why human:** Needs a phone, real clips and the Mac (QUESTIONS.md #3, #4, #8).

### 3. Read the documents as a newcomer

**Test:** Read MIGRATION.md, the two README sections and the CHANGELOG 1.0.0 entry.
**Expected:** Plain English; the migration can be followed without reading source.
**Why human:** Clarity is a judgment. This does not block the publish.

### Gaps Summary

No gap that a plan can close. Nothing is missing, stubbed or unwired, and every automated
gate is green locally at HEAD and in CI.

Two ROADMAP criteria are open, and both wait on Dan:

1. **The package is not on pub.dev.** Until it is, the words "from pub.dev" in the phase goal
   are not true. It is one documented command away, after the publisher choice.
2. **The hardware checklist has not been re-run.** doc/RELEASE.md puts it before the
   publish.

**Recommended next action:** record this report, mark RELS-02 and RELS-03 complete by hand,
and leave RELS-01 and ROADMAP criteria 1 and 4 open until Dan has done items 1 and 2 above.
Whether this warrants a push to Dan is the orchestrator's call: both items are things only
he can do.

---

_Verified: 2026-09-28T02:48:16Z_
_Verifier: Claude (gsd-verifier)_
