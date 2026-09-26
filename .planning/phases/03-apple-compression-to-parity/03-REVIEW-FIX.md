---
phase: 03-apple-compression-to-parity
fixed_at: 2026-09-26T02:49:44Z
review_path: .planning/phases/03-apple-compression-to-parity/03-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 03: Code Review Fix Report

**Fixed at:** 2026-09-26T02:49:44Z
**Source review:** .planning/phases/03-apple-compression-to-parity/03-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 3 (fix_scope: critical_warning -- CR-01, WR-01, WR-02; IN-01 excluded by scope)
- Fixed: 3
- Skipped: 0

Verification note: no Swift toolchain is available on this machine (per project CLAUDE.md).
Every Swift change below was verified with Tier 1 (re-read the modified section, confirm the
fix is present and surrounding code is intact) and, where a check was actually runnable, Tier 2:
the Kotlin-side ArgumentsTest change was compiled and run via `./gradlew :compress_video:
testDebugUnitTest` (45/45 tests passed, including the new case) and the Dart-side integration
test change was verified with `dart format` (clean) and `flutter analyze` (no issues) against
the flutter-stable SDK. All verification ran in the main checkout (`workflow.use_worktrees` is
`false` for this project, so no isolated worktree was created).

## Fixed Issues

### CR-01: A pre-existing directory at `outputPath` is silently deleted (recursively) instead of rejected

**Files modified:** `darwin/compress_video/Sources/compress_video/Arguments.swift`,
`darwin/compress_video/Sources/compress_video/PluginFiles.swift`,
`android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt`,
`android/src/test/kotlin/com/danjjohnson/compress_video/ArgumentsTest.kt`,
`example/ios/RunnerTests/RunnerTests.swift`,
`example/macos/RunnerTests/RunnerTests.swift`,
`example/integration_test/compress_output_test.dart`
**Commit:** `bb8968c`
**Applied fix:** `Arguments.requireWritableOutputParent` (both Swift and Kotlin) now rejects an
`outputPath` that already exists as a directory with a typed `CompressVideoError(reason: "io")`
before any encode is attempted -- Android's `Arguments.kt` did not previously guard this either
(it only failed safely, and late, when `File.renameTo` refused to overwrite a directory after a
full wasted encode), so both platforms were changed together for parity, matching the review's
explicit instruction to check Android's behavior and keep the platforms identical.
`PluginFiles.moveIntoPlace` (Swift) also now refuses to `removeItem` a directory destination as
defence in depth, so a future call site that skips the upstream validation still cannot
recursively delete a directory. Added an `XCTest` case
(`testRequireWritableOutputParentOutputPathIsExistingDirectoryRejectedAsIo`) to both
`example/ios/RunnerTests/RunnerTests.swift` and `example/macos/RunnerTests/RunnerTests.swift`
(kept byte-identical, confirmed with `diff`), a matching JVM
`ArgumentsTest.requireWritableOutputParent_outputPathIsExistingDirectory_rejectedAsIo` (compiled
and passed via Gradle), and a platform-neutral `compress_output_test.dart` integration test that
passes a directory as `outputPath` and asserts both the directory and a sentinel file inside it
survive the rejected request.

### WR-01: Progress percentages are forwarded via unstructured per-call `Task`s with no ordering guarantee

**Files modified:** `darwin/compress_video/Sources/compress_video/Compression.swift`
**Commit:** `cf218ac`
**Applied fix:** Replaced the per-`onProgress`-call unstructured `Task { @MainActor in ... }`
with a single `AsyncStream<Double>` set up once per `startCompress` call: the `onProgress`
closure now only does a synchronous `progressContinuation.yield(percent)` (a FIFO-preserving
enqueue), and one consuming `Task { @MainActor [flutterApi] in for await percent in
progressStream { ... } }` delivers every value to `flutterApi.onProgress` in the exact order the
native copy loop emitted them, regardless of how long any individual await suspends. A `defer {
progressContinuation.finish() }` ends the stream (and the consuming task) when `startCompress`
returns or throws.
**Verification caveat:** no Swift toolchain is available on this machine to compile-check this
change (confirmed: `which swift`/`swiftc` both fail). The change was reviewed line-by-line
against known-correct Swift concurrency idioms (the classic
`AsyncStream<Element> { continuation in ... }` initializer, the `{ @MainActor [capture] in ... }`
closure attribute-then-capture-list ordering, and `@discardableResult` on
`Continuation.yield(_:)`), and Tier 1 (re-read) confirms the fix text is present with intact
surrounding code -- but this is a logic/concurrency change with no compiler or test run behind
it. **Status: fixed: requires human verification** -- confirm on a machine with Xcode before this
phase ships (build the darwin target and re-run `compress_jobs_test.dart`'s progress-ordering
assertion).

### WR-02: `abs(nsError.code)` traps if `nsError.code == Int.min`

**Files modified:** `darwin/compress_video/Sources/compress_video/CompressionEngine.swift`
**Commit:** `1def170`
**Applied fix:** Replaced `let magnitude = abs(nsError.code)` with `let magnitude =
nsError.code.magnitude` (a `UInt`), used only in string interpolation immediately below --
`UInt.magnitude` can never trap for any `Int` input, unlike `abs(_:)` on `Int.min`. This is a
small, mechanical, single-line change with no surrounding logic altered; verified by Tier 1
re-read only (no Swift toolchain available), and accepted as `fixed` without the human-review
caveat given its mechanical nature and single call site (used only in a string interpolation, no
other consumer of `magnitude`'s type in this function).

## Skipped Issues

None -- all in-scope findings (CR-01, WR-01, WR-02) were fixed. IN-01 was excluded by
`fix_scope: critical_warning` and left untouched, per the review's own note that it documents a
deliberate tradeoff requiring no action.

---

_Fixed: 2026-09-26T02:49:44Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
