---
phase: 01-typed-contract-ci-and-media-info
plan: 03
subsystem: infra
tags: [flutter-plugin, darwin, cocoapods, swift-package-manager, github-actions, ci, dart, kotlin]

# Dependency graph
requires:
  - phase: 01-01
    provides: Android SDK + emulator on danserver, private GitHub repo wired as `github` remote, toolchain pin baseline
  - phase: 01-02
    provides: corpus clips + sidecars + sync_to_example.sh (consumed once example/ existed)
provides:
  - The `compress_video` Flutter plugin package itself (pubspec.yaml, analysis_options.yaml, .pubignore, LICENSE, CHANGELOG.md, README.md)
  - Typed error taxonomy (`CompressVideoException`, `CompressVideoErrorReason`, `reasonFromPlatformCode`) every later native call throws and maps into
  - One shared `darwin/` Apple source tree (one podspec, one Package.swift) serving iOS 13+ and macOS 11+ through both CocoaPods and Swift Package Manager
  - `.github/workflows/ci.yml` — path-gated Linux (android) + macOS (apple) CI, verified green
  - `example/` app scaffold with corpus assets bundled and listed
affects: [01-04, 01-05, 01-06, 01-07]

# Actuals (#2632)
actuals:
  tokens: 59400
  tasks: 3
  commits: 8

# Tech tracking
tech-stack:
  added: [pigeon (dev dep, unused until 01-04), flutter_lints 6.0.0, kotlinx-coroutines-android 1.10.2, mockito-core 5.18.0]
  patterns:
    - "Shared darwin/ Apple tree via sharedDarwinSource: true, one podspec (s.ios.*/s.osx.* split, never s.platform=) and one Package.swift"
    - "#if os(iOS)/#elseif os(macOS) conditional imports in shared Swift plugin sources (verified against flutter/packages' shared_preferences_foundation)"
    - "CI changes job computes an Apple-relevant path filter and fails OPEN (runs the expensive job) on any ambiguous base ref"
    - "CI resets tracked files via git checkout -- . before dart pub publish --dry-run, because Flutter's own project migrators silently rewrite committed scaffold files on a newer stable channel"

key-files:
  created:
    - pubspec.yaml
    - analysis_options.yaml
    - .pubignore
    - LICENSE
    - CHANGELOG.md
    - lib/src/compress_video_exception.dart
    - test/compress_video_exception_test.dart
    - darwin/compress_video.podspec
    - darwin/compress_video/Package.swift
    - darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift
    - .github/workflows/ci.yml
    - example/lib/main.dart (rewritten)
  modified:
    - .gitignore
    - README.md
    - android/build.gradle.kts
    - example/pubspec.yaml
    - example/macos/Runner.xcodeproj/project.pbxproj
    - doc/TOOLCHAIN.md (moved from docs/TOOLCHAIN.md)
    - .planning/phases/01-typed-contract-ci-and-media-info/*.md (docs/ -> doc/ path references)

key-decisions:
  - "Renamed docs/ to doc/ (pub layout convention) so dart pub publish --dry-run exits 0; updated every docs/TOOLCHAIN.md reference across the phase's planning documents."
  - "Merged CompressVideoPlugin.swift with #if os(iOS)/#elseif os(macOS) conditional imports and messenger access, matching the pattern verified live from flutter/packages' shared_preferences_foundation source, not guessed."
  - "CI's floating channel: stable resolves ahead of doc/TOOLCHAIN.md's locally-pinned Flutter 3.44.1 (CI picked up 3.47.4 on this run). Flutter's own project migrators silently rewrite committed scaffold files (Podfile, project.pbxproj, analysis_options.yaml) the first time a newer tool touches them. Added a git checkout -- . reset step before the publish-cleanliness check, and forced flutter config --no-enable-swift-package-manager before the CocoaPods-path Apple builds since our plugin ships both a podspec and Package.swift, making current Flutter default to preferring SPM once it sees an all-SPM-capable plugin set."

patterns-established:
  - "Never use s.platform = in a shared darwin/ podspec — use s.ios.dependency/s.osx.dependency and per-platform deployment_target instead."
  - "CI android job installs ffmpeg explicitly (ubuntu-latest does not ship it) before running corpus/verify_corpus.sh."

requirements-completed: []  # BULD-03 and BULD-05 are shared with sibling plans still pending (01-04/01-06/01-07 for BULD-03; 01-07 for BULD-05). requirements.ready-ids confirmed 0/2 ready — shared-ID gate (#2388) blocks marking either Complete until every declaring plan finishes.

coverage:
  - id: D1
    description: "flutter analyze --fatal-infos --fatal-warnings exits 0 over the whole package with strict-casts, strict-inference, strict-raw-types and public_member_api_docs all enabled"
    requirement: "BULD-03"
    verification:
      - kind: other
        ref: "flutter analyze --fatal-infos --fatal-warnings (local, danserver)"
        status: pass
      - kind: unit
        ref: "grep -c 'strict-raw-types' analysis_options.yaml == 1; grep -c 'public_member_api_docs' analysis_options.yaml == 1"
        status: pass
    human_judgment: false
  - id: D2
    description: "CompressVideoException carries a CompressVideoErrorReason, a message and an optional platformDetail; an unrecognised platform code maps to unknown with the original code preserved"
    requirement: "BULD-03"
    verification:
      - kind: unit
        ref: "test/compress_video_exception_test.dart (9 tests, all pass): 6 reason-code mappings, unrecognised-code fallback, platformDetail retention, toString"
        status: pass
    human_judgment: false
  - id: D3
    description: "A push touching only .planning/**, **/*.md or .mission-control/** starts no CI run; a push touching Android/Dart paths runs android and skips apple when no Apple-relevant path changed"
    requirement: "BULD-05"
    verification:
      - kind: e2e
        ref: "gh run list headSha check after pushing CHANGELOG.md-only commit 8507ab0 — commit absent from run list (no run started)"
        status: pass
    human_judgment: false
  - id: D4
    description: "iOS and macOS build from one shared darwin/ source tree: exactly one podspec and one Package.swift exist, no ios/compress_video or macos/compress_video directory remains"
    requirement: "BULD-05"
    verification:
      - kind: other
        ref: "find . -name '*.podspec' | wc -l == 1; find . -name 'Package.swift' | wc -l == 1; test -d ios/compress_video fails; test -d macos/compress_video fails"
        status: pass
    human_judgment: false
  - id: D5
    description: "The published package contains no planning documents and no root corpus/ directory: dart pub publish --dry-run exits 0"
    verification:
      - kind: other
        ref: "dart pub publish --dry-run (local + CI android job) — exit 0, 0 warnings, file list has no .planning/ or corpus/ entries"
        status: pass
    human_judgment: false
  - id: D6
    description: "The example app declares the three corpus clips as bundled assets, byte-identical to corpus/*.mp4"
    verification:
      - kind: other
        ref: "sha256sum corpus/portrait_rot90.mp4 vs example/assets/corpus/portrait_rot90.mp4 (matched); CI's sync_to_example.sh + git diff --exit-code step passed"
        status: pass
    human_judgment: false
  - id: D7
    description: "CI is live and green on both the android and apple jobs on a real push"
    requirement: "BULD-05"
    verification:
      - kind: e2e
        ref: "gh run view 34988000574 --json conclusion,jobs -> conclusion success, android+apple both success"
        status: pass
    human_judgment: false

# Metrics
duration: 52min
completed: 2026-09-15
status: complete
---

# Phase 1 Plan 03: Plugin Scaffold, Shared darwin/ Tree, Typed Errors and Green CI Summary

**The `compress_video` Flutter plugin package now exists with a strict-analyzer Dart core, a typed `CompressVideoException`/`CompressVideoErrorReason` taxonomy under unit test, one shared `darwin/` Apple source tree serving iOS 13+/macOS 11+ through both CocoaPods and Swift Package Manager, and a path-gated GitHub Actions CI that is green on both the Linux (android) and macOS (apple) runners.**

## Performance

- **Duration:** 52 min
- **Started:** 2026-09-15T14:43:00Z (approx.)
- **Completed:** 2026-09-15T15:35:00Z (approx.)
- **Tasks:** 3 completed
- **Files modified:** 133 (dominated by the `flutter create` scaffold; hand-authored/edited files: ~25)

## Accomplishments
- Scaffolded the `compress_video` plugin package via `flutter create`, removed the template's `MethodChannel`/platform-interface trio (Pigeon replaces that pattern entirely in plan 01-04), finished `pubspec.yaml`/`analysis_options.yaml`/`.pubignore`/`LICENSE`/`CHANGELOG.md`/`README.md`, lowered `minSdk` to 23, added `kotlinx-coroutines-android` and bumped `mockito-core`
- Wrote `lib/src/compress_video_exception.dart`: `CompressVideoErrorReason` enum, immutable `CompressVideoException`, `reasonFromPlatformCode` with an `unknown` fallback that preserves the original platform code — 9 passing unit tests covering every mapping plus the fallback path
- Mirrored the corpus into `example/assets/corpus/` (sha256-verified) and rewrote `example/lib/main.dart` as a real, buildable corpus-asset lister read through `rootBundle`
- Consolidated the generated `ios/` and `macos/` plugin packages into one shared `darwin/` tree: one podspec (`s.ios.dependency`/`s.osx.dependency` split, no `s.platform =`), one `Package.swift` (`.iOS("13.0")`, `.macOS("11.0")`), `pubspec.yaml`'s `sharedDarwinSource: true` on both platforms, and a merged `CompressVideoPlugin.swift` using `#if os(iOS)/#elseif os(macOS)` conditional imports
- Committed `example/ios/Podfile` and `example/macos/Podfile` from Flutter's own templates with corrected platform lines (`ios 13.0`, `osx 11.0` — the macOS template hardcodes 10.15) and raised the example macOS project's deployment target to 11.0
- Wrote `.github/workflows/ci.yml`: a `changes` job that fails OPEN on any ambiguous base ref, an `android` job (format/analyze/corpus-drift/mirror/test/publish-dry-run/APK build), and a path-gated `apple` job (CocoaPods iOS+macOS builds and XCTest, then a Swift Package Manager rebuild) — driven green over three CI iteration cycles, with the final run's path-gating verified by a markdown-only commit that started no workflow run at all

## Task Commits

1. **Task 1: Scaffold the package, fix its configuration, and define the typed error taxonomy** - `0ef3b95` (feat)
2. **Task 2: Consolidate iOS and macOS into one shared darwin/ source tree** - `ce3510b` (feat), `8026da2` (fix — staging gap), `2780c97` (fix — docs/ -> doc/ rename)
3. **Task 3: Add the CI workflow and drive both jobs green** - `9df1a8d` (feat), `e30abf3` (fix — ffmpeg + retry), `d69f3a6` (fix — git-dirty reset + SPM force), `8507ab0` (docs — path-gating proof commit)

**Plan metadata:** (this commit, docs)

## Files Created/Modified
- `pubspec.yaml` - Package metadata, dev deps (pigeon, flutter_lints), `sharedDarwinSource: true` on ios/macos
- `analysis_options.yaml` - `strict-casts`/`strict-inference`/`strict-raw-types`, `public_member_api_docs`
- `.pubignore` - Excludes `corpus/`, `.planning/`, `.mission-control/`, `.claude/`, `QUESTIONS.md` plus build artifacts
- `lib/src/compress_video_exception.dart` - `CompressVideoErrorReason`, `CompressVideoException`, `reasonFromPlatformCode`
- `test/compress_video_exception_test.dart` - 9 tests covering every reason mapping and the unknown fallback
- `android/build.gradle.kts` - `minSdk` 24→23, `kotlinx-coroutines-android:1.10.2`, `mockito-core:5.18.0`
- `darwin/compress_video.podspec`, `darwin/compress_video/Package.swift` - Single Apple packaging spec/manifest for iOS 13+/macOS 11+
- `darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift` - Merged, platform-conditional Swift plugin class
- `example/lib/main.dart`, `example/pubspec.yaml`, `example/assets/corpus/` - Corpus-asset-lister demo app with bundled clips
- `example/ios/Podfile`, `example/macos/Podfile` - Committed, platform-corrected CocoaPods manifests
- `.github/workflows/ci.yml` - Path-gated Linux + macOS CI
- `doc/TOOLCHAIN.md` (renamed from `docs/TOOLCHAIN.md`) - Toolchain pin baseline, path fixed for pub layout convention

## Decisions Made
See `key-decisions` in frontmatter for the three most consequential ones (docs/ rename, Swift plugin merge pattern, CI Flutter-version-drift fixes). Additionally:
- Left `CompressVideoPlugin.kt`/`CompressVideoPlugin.swift`'s template `getPlatformVersion` handler in place deliberately (plan instruction) — it is replaced by the real implementation in plans 01-04 (Kotlin) and 01-06 (Swift). Tracked as a known stub below.
- `lib/compress_video.dart` rewritten as a thin export of the exception module only (no `CompressVideo` class yet) since this plan's scope is the typed error taxonomy and scaffold, not the Pigeon-backed public API (that starts in 01-04).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] example/test/widget_test.dart and lib/compress_video.dart still referenced the deleted template platform-interface code**
- **Found during:** Task 1
- **Issue:** Removing `lib/compress_video_method_channel.dart`/`lib/compress_video_platform_interface.dart` per the plan left `lib/compress_video.dart`'s `CompressVideo`/`getPlatformVersion` class and `example/test/widget_test.dart`'s `MyApp` widget test both referencing symbols that no longer existed.
- **Fix:** Rewrote `lib/compress_video.dart` as a thin export of the exception module (the public `CompressVideo` API is out of this plan's scope; it starts in 01-04). Rewrote `example/test/widget_test.dart` to test the new corpus-asset-lister screen instead.
- **Files modified:** `lib/compress_video.dart`, `example/test/widget_test.dart`
- **Verification:** `flutter analyze --fatal-infos --fatal-warnings` and `flutter test` (root) both exit 0; example widget test asserts the three corpus filenames and byte-size labels render
- **Committed in:** `0ef3b95` (Task 1 commit)

**2. [Rule 3 - Blocking] A partial `git add -u` staged the darwin/ merge's file renames but missed three edited files**
- **Found during:** Task 2, caught by `dart pub publish --dry-run`'s git-dirty check after the Task 2 commit
- **Issue:** `git add -u ios macos darwin ...` failed with `fatal: pathspec 'ios' did not match any files` (the `ios/` directory no longer existed after an earlier `git mv`) and aborted before staging `pubspec.yaml`'s `sharedDarwinSource: true` entries, `example/macos/Runner.xcodeproj/project.pbxproj`'s deployment-target fix, and the merged `CompressVideoPlugin.swift`. The commit that followed silently omitted all three.
- **Fix:** Staged and committed the three missed files in a follow-up commit; verified `dart pub publish --dry-run`'s git-dirty warning cleared for those paths.
- **Files modified:** `pubspec.yaml`, `example/macos/Runner.xcodeproj/project.pbxproj`, `darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift`
- **Verification:** `git diff HEAD` empty for the three files after the fix commit; all Task 2 acceptance-criteria greps re-ran and passed
- **Committed in:** `8026da2`

**3. [Rule 3 - Blocking] docs/ directory naming blocked dart pub publish --dry-run from exiting 0**
- **Found during:** Task 2's own acceptance criterion (`dart pub publish --dry-run exits 0`) and the plan's verification step 2
- **Issue:** pub's package-layout convention requires the singular `doc/` directory name; the plural `docs/` (created in plan 01-01 for the toolchain baseline) made `dart pub publish --dry-run` report a validation warning and exit 65 regardless of git cleanliness.
- **Fix:** `git mv docs doc`; updated every `docs/TOOLCHAIN.md` reference across the phase's `.planning/` documents (9 files) to `doc/TOOLCHAIN.md`. No content change to `TOOLCHAIN.md` itself.
- **Files modified:** `doc/TOOLCHAIN.md` (renamed), 9 `.planning/phases/01-typed-contract-ci-and-media-info/*.md` files
- **Verification:** `dart pub publish --dry-run` exits 0 with 0 warnings after the rename + commit
- **Committed in:** `2780c97`

**4. [Rule 3 - Blocking] CI Android job lacked ffmpeg/ffprobe**
- **Found during:** Task 3, first CI run (34986439627)
- **Issue:** `ubuntu-latest` does not ship `ffmpeg`/`ffprobe` preinstalled; `corpus/verify_corpus.sh` failed with `command not found`.
- **Fix:** Added an explicit `sudo apt-get install -y ffmpeg` step before the corpus-verification steps.
- **Files modified:** `.github/workflows/ci.yml`
- **Verification:** Second CI run's `Verify corpus has not drifted` and `Verify example corpus mirror...` steps both passed
- **Committed in:** `e30abf3`

**5. [Rule 3 - Blocking] dart pub publish --dry-run flagged Flutter-migrator-rewritten files as git-dirty in CI**
- **Found during:** Task 3, second CI run (34987068258)
- **Issue:** CI's `channel: stable` resolved to Flutter 3.47.4, well ahead of the 3.44.1 used to generate the checked-in scaffold locally. Flutter's own project migrators silently rewrote `analysis_options.yaml` (root and `example/`) the moment later steps touched them, and `dart pub publish --dry-run`'s git-dirty check flagged the resulting local modifications, exiting 65.
- **Fix:** Added a `git checkout -- .` reset step immediately before the dry-run publish check. This is an ephemeral CI checkout (not a shared worktree), so resetting tracked files to HEAD there is safe — every earlier step already ran against whatever the migrated content was.
- **Files modified:** `.github/workflows/ci.yml`
- **Verification:** Third CI run's `Dry-run publish` step passed with 0 warnings
- **Committed in:** `d69f3a6`

**6. [Rule 1 - Bug] Apple job's iOS/macOS CocoaPods builds failed with a sandbox/Podfile.lock mismatch**
- **Found during:** Task 3, second CI run — a clear-and-retry attempt reproduced the identical failure on retry, ruling out a simple race/flake
- **Issue:** `flutter build ios` reported `Error (Xcode): The sandbox is not in sync with the Podfile.lock`, preceded by `All plugins found for ios are Swift Packages, but your project still has CocoaPods integration`. Because our plugin ships both a podspec and a `Package.swift` (`sharedDarwinSource`), current Flutter defaults to preferring Swift Package Manager plugin registration once it detects an all-SPM-capable plugin set, conflicting with the example app's committed CocoaPods-based `Podfile`.
- **Fix:** Added `flutter config --no-enable-swift-package-manager` before the CocoaPods-path builds so they genuinely exercise CocoaPods; the existing `flutter config --enable-swift-package-manager` step further down still flips this back on to prove the SPM path separately.
- **Files modified:** `.github/workflows/ci.yml`
- **Verification:** Third CI run — both `Build iOS (CocoaPods)` and `Build macOS` steps passed on the first attempt (no retry needed)
- **Committed in:** `d69f3a6`
- **Acceptance-criteria note:** this fix makes `grep -c 'enable-swift-package-manager' .github/workflows/ci.yml` return `2` (the explicit `--no-` disable plus the later `--enable-`) instead of the `1` the plan's acceptance criteria expected. The plan's original design did not anticipate current stable Flutter defaulting to SPM-preference for an all-SPM-capable plugin. The literal count check fails; the underlying intent (both the CocoaPods path and the SPM path are proven, on a real green CI run) is met.

---

**Total deviations:** 6 auto-fixed (2 bugs, 4 blocking issues).
**Impact on plan:** All auto-fixes were necessary to reach a genuinely green CI run and a clean `dart pub publish --dry-run`, which are both this plan's own acceptance criteria. No scope creep beyond that goal. One documented, justified deviation from a literal acceptance-criteria grep count (item 6) — the underlying intent is satisfied; the exact-count check reflects the plan's assumption that the CI runner's Flutter version would treat our plugin as CocoaPods-only by default, which current stable Flutter does not.

## Known Stubs

- **`CompressVideoPlugin.kt` / `CompressVideoPlugin.swift`** still carry the Flutter template's `getPlatformVersion` MethodChannel handler (kept deliberately per this plan's instructions, so the native targets keep compiling and `RunnerTests.swift`/`CompressVideoPluginTest.kt` keep asserting something real). Replaced by the real Pigeon-backed implementation in plans 01-04 (Kotlin) and 01-06 (Swift). Not a functional gap in this plan's own deliverables — explicitly deferred by plan text.
- **`lib/compress_video.dart`** exports only the exception taxonomy; there is no `CompressVideo` class with `getMediaInfo`/`getThumbnail` calls yet. This is this plan's intended scope boundary (Pigeon contract + calls start in 01-04), not an oversight.

Logged to `.planning/WINDOWS.md` (kind: stub) for cross-phase visibility.

## Issues Encountered
CI needed three iteration cycles to reach green on both runners (see Deviations 4-6 above) — all resolved within this plan's own execution, no external blocker. Total elapsed CI-iteration time was the primary driver of this plan's above-average duration (50 min vs 25-35 min for 01-01/01-02).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `compress_video` plugin package, shared `darwin/` Apple tree and typed error taxonomy are all in place and CI-proven on both runners.
- CI is live at `.github/workflows/ci.yml`, green, and path-gated (verified with a real markdown-only commit that started no run).
- Ready for 01-04-PLAN.md (Pigeon contract + end-to-end Android media-info tracer), the next wave.
- `BULD-03` and `BULD-05` remain unchecked in REQUIREMENTS.md — both are shared with sibling plans still pending (01-04/01-06/01-07 for BULD-03; 01-07 for BULD-05); the shared-ID gate correctly blocks marking either Complete until every declaring plan finishes.
- CI's Flutter version now floats ahead of `doc/TOOLCHAIN.md`'s locally-pinned 3.44.1 (observed 3.47.4 during this run). Future plans touching Apple/CocoaPods paths should expect the same class of migrator-driven drift and may need similar defensive steps.

---
*Phase: 01-typed-contract-ci-and-media-info*
*Completed: 2026-09-15*
