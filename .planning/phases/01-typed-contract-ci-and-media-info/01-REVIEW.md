---
phase: 01-typed-contract-ci-and-media-info
reviewed: 2026-09-21T19:00:00Z
depth: standard
files_reviewed: 46
files_reviewed_list:
  - analysis_options.yaml
  - android/build.gradle.kts
  - android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/CompressVideoPlugin.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/MediaMath.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/Messages.g.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/Probe.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/Thumbnails.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/ArgumentsTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/CompressVideoPluginTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/MediaMathTest.kt
  - corpus/generate_corpus.sh
  - corpus/patch_rotation.py
  - corpus/sync_to_example.sh
  - corpus/verify_corpus.sh
  - darwin/compress_video/Package.swift
  - darwin/compress_video.podspec
  - darwin/compress_video/Sources/compress_video/Arguments.swift
  - darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift
  - darwin/compress_video/Sources/compress_video/MediaMath.swift
  - darwin/compress_video/Sources/compress_video/Messages.g.swift
  - darwin/compress_video/Sources/compress_video/Probe.swift
  - darwin/compress_video/Sources/compress_video/Thumbnails.swift
  - example/integration_test/media_info_test.dart
  - example/integration_test/thumbnail_test.dart
  - example/ios/RunnerTests/RunnerTests.swift
  - example/lib/main.dart
  - example/macos/RunnerTests/RunnerTests.swift
  - example/macos/Runner.xcodeproj/project.pbxproj
  - example/pubspec.yaml
  - example/test/widget_test.dart
  - .github/workflows/ci.yml
  - .gitignore
  - lib/compress_video.dart
  - lib/src/compress_video_exception.dart
  - lib/src/media_info.dart
  - lib/src/messages.g.dart
  - pigeons/messages.dart
  - .pubignore
  - pubspec.yaml
  - test/compress_video_exception_test.dart
  - test/media_info_mapping_test.dart
  - test/messages_contract_test.dart
  - test/thumbnail_api_test.dart
  - tool/check_parity.sh
  - tool/check_parity_test.sh
findings:
  critical: 0
  warning: 0
  info: 1
  total: 1
status: clean
---

# Phase 01: Code Review Report (re-review, iteration 2)

**Reviewed:** 2026-09-21
**Depth:** standard
**Files Reviewed:** 46
**Status:** clean

## Summary

This is iteration 2, a re-review after the fix pass recorded in
`01-REVIEW-FIX.md` (commits `f3d5dd6`, `c55c0ef`, `89fd89b`, `c9bca86`). All four
findings from iteration 1 (CR-01, WR-01, WR-02, WR-03/IN-02) were re-verified directly
against the current code, not just trusted from the fix report, and each is confirmed
genuinely resolved with no regressions.

**CR-01 (CI path filter gap).** Confirmed fixed and hardened beyond the minimal
suggestion. `tool/` and `corpus/` are now in the `changes` job's filter regex
(`.github/workflows/ci.yml:71`), so any PR touching `tool/check_parity.sh` or
`tool/check_parity_test.sh` now forces the `apple` job to run. The `parity` job no
longer depends on `needs.apple.result == 'success'` to execute at all — its new `gate`
step (lines 454-473) explicitly branches on `apple`'s result: `success` proceeds,
`skipped` is checked against `needs.changes.outputs.apple` (a legitimate skip is a
clean no-op; a skip that contradicts the changes filter is a loud `FATAL` failure), and
anything else (`failure`, `cancelled`) is also a loud failure. Traced both required
semantics by hand: (1) a change to only `tool/` or `corpus/` now causes `apple=true` →
`apple` job runs → self-test step (`bash tool/check_parity_test.sh`) actually executes
before the real diff, closing the exact "green CI, ungated regression" hole the
original finding described; (2) a change to only Android-relevant paths (e.g.
`android/build.gradle.kts`) causes `apple=false` → `apple` skipped → gate's `skipped`
branch confirms the skip against `changes`' own output and passes clean, so a
legitimately-scoped change is never penalized for the Apple job not running. This was
also exercised for real: the CI run captured in the fix report shows the `apple` job
correctly triggered by this exact push (which touched `tool/`, `darwin/`, and the
workflow file itself), and separately shows the new gate correctly turning a real
`apple` failure into a loud, named `parity` job failure rather than a silent skip.
Verified `.github/workflows/ci.yml` is still valid YAML.

**WR-01 (Apple symlink resolution).** Confirmed fixed. `standardizedAbsolutePath` in
`Arguments.swift:160-197` now calls `.resolvingSymlinksInPath()` on the full path when
it already exists, and — for a not-yet-existing `outputPath` — walks up to the nearest
existing ancestor, resolves symlinks there, and reattaches the nonexistent suffix
literally, mirroring `File.canonicalFile`'s behavior on the Kotlin side for the same
not-yet-existing-leaf case. Traced the ancestor-walk loop by hand for termination and
safety, specifically to answer whether it can loop, block, or throw:
- **Cannot loop indefinitely.** Each iteration calls `deletingLastPathComponent()`,
  which strictly shortens the path by one component; the loop's own exit condition
  (`existingAncestor.path != "/"`) is defensive against `deletingLastPathComponent()`
  becoming a no-op once it reaches `/` (root is idempotent under that call). For any
  absolute path (guaranteed by `URL(fileURLWithPath:)`), this converges in at most the
  path's component count — bounded, typically under 20 iterations even for a deeply
  nested simulator sandbox path.
- **Cannot block.** Every check in the loop is `FileManager.fileExists(atPath:)`, a
  synchronous local `stat(2)`-class call with no network or long-running I/O involved;
  nothing in this function is `async`, awaits anything, or acquires a lock.
  `resolvingSymlinksInPath()` is likewise a synchronous, local, bounded call.
- **Cannot throw.** `standardizedAbsolutePath` is not a `throws` function and contains
  no call that can propagate an error out of it; it always returns a `String`.
- Hand-traced the exact failing-test scenario ("outputPath whose parent directory does
  not exist") in `thumbnail_test.dart`: `.../does_not_exist_dir/thumb.jpg` under a
  freshly created temp dir resolves in exactly two loop iterations (walking up past
  `does_not_exist_dir` to the existing temp dir) and reassembles the identical path —
  correct, not a hang risk.

Given this, the CI hang the fix report attributes to a known
`flutter test -d <sim>` app-launch flake (zero test output before Flutter's harness
even attaches to the launched app, both original and retry) is the more plausible
explanation than a WR-01 regression: the code that would run inside that hung suite is
synchronous and bounded by construction, and the hang manifests *before* any Dart test
code — and therefore before any call into `Arguments.swift` — executes at all. This
matches the CI comment's own record of the same flake on 2026-09-15 and again on
2026-09-21.

One residual, non-blocking gap carried forward as an info item below: the
not-yet-existing-ancestor branch of `standardizedAbsolutePath` (the new code this fix
actually added) has not yet been exercised by a passing CI run on real Apple hardware/
simulator, only by static/code-level analysis and by the Swift compiler accepting it
(proven indirectly: `media_info_test.dart`, compiled in the same target, ran and passed
in the same job). This does not block the fix — the logic is sound by inspection — but
it should be closed out once the simulator flake clears.

**WR-02 (Apple codec-detection documentation).** Confirmed fixed as documentation, per
the review's own offered fallback path. `Probe.swift`'s legacy-path comment
(lines 80-84), `MediaInfo.videoCodec`'s dartdoc, and the README's field table +
"Known limitation" callout all now name the exact iOS 13-15/macOS 11-12 boundary and
cross-reference each other. Verified the documentation is technically accurate against
the code: the async path (`#available(iOS 16, macOS 13, *)`) does call
`track.load(.formatDescriptions)` as the dartdoc claims, and the legacy path does
hardcode `formatDescriptions = []` as described. `dart analyze` confirms no issues in
`lib/src/media_info.dart`.

**WR-03 / IN-02 (`check_parity.sh` null guards).** Confirmed fixed. `durationMs` (both
platforms), the sidecar's `durationToleranceMs`, each `patchRgb[i]` channel, and the
sidecar's `rgbTolerance` are all now guarded for `"null"`/empty before being used in
bash arithmetic, each producing a clean, field-naming `MISMATCH` via the existing
`fail()` helper (which sets a flag and lets the script continue — confirmed `continue`
after each new guard correctly returns to the right enclosing loop: the per-clip `for`
loop for `durationMs`, the per-channel `for i in 0 1 2` loop for `patchRgb`). Ran
`bash tool/check_parity_test.sh` directly during this review (not just trusting the fix
report): all four fixtures — within-tolerance pass, out-of-tolerance fail naming the
field, missing-`durationMs` fail naming the field, missing-`patchRgb` fail naming
`thumbnail.patchRgb[0]` — pass cleanly.

No new Critical or Warning issues were found in this iteration. `flutter analyze
--fatal-infos --fatal-warnings` was re-run during this review and reports no issues.

## Info

### IN-01: WR-01's new not-yet-existing-ancestor branch remains unexercised by a passing CI run

**File:** `darwin/compress_video/Sources/compress_video/Arguments.swift:178-196`

**Issue:** The ancestor-walking loop added for WR-01 is sound by code inspection (see
Summary above: bounded, synchronous, non-throwing) and is known to compile (the Apple
job's Swift build succeeded and ran `media_info_test.dart` to completion in the same
job before `thumbnail_test.dart` hung). But no CI run has yet completed
`thumbnail_test.dart`'s "outputPath whose parent directory does not exist" and
"an explicit outputPath is honoured exactly" tests, which are the only tests
exercising this specific branch, due to the unrelated simulator app-launch flake. This
is not a defect in the fix — it is a gap in verification coverage, tracked here so it
isn't lost.

**Fix:** Re-run the Apple CI job (or investigate the hosted macOS runner's simulator
health, as the fix report already recommends) until `thumbnail_test.dart` completes
cleanly, and confirm the two relevant test cases pass. Optionally add a dedicated
symlinked-output-directory test case (a genuine symlink in the yet-to-exist prefix) to
either `thumbnail_test.dart` or a Swift XCTest, since no current test constructs a
symlinked ancestor and so even a clean CI run would only prove the "no symlinks
present" path through this new code, not symlink resolution itself.

---

_Reviewed: 2026-09-21_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
