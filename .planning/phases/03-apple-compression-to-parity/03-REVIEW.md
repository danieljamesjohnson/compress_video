---
phase: 03-apple-compression-to-parity
reviewed: 2026-09-26T02:42:27Z
depth: standard
files_reviewed: 30
files_reviewed_list:
  - .github/workflows/ci.yml
  - corpus/generate_corpus.sh
  - corpus/sync_to_example.sh
  - corpus/verify_corpus.sh
  - darwin/compress_video/Sources/compress_video/Arguments.swift
  - darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift
  - darwin/compress_video/Sources/compress_video/Compression.swift
  - darwin/compress_video/Sources/compress_video/CompressionEngine.swift
  - darwin/compress_video/Sources/compress_video/ErrorMapping.swift
  - darwin/compress_video/Sources/compress_video/JobRegistry.swift
  - darwin/compress_video/Sources/compress_video/MediaMath.swift
  - darwin/compress_video/Sources/compress_video/PluginFiles.swift
  - darwin/compress_video/Sources/compress_video/SizeGuard.swift
  - darwin/compress_video/Sources/compress_video/Thumbnails.swift
  - example/integration_test/compress_audio_test.dart
  - example/integration_test/compress_jobs_test.dart
  - example/integration_test/compress_output_test.dart
  - example/integration_test/compress_test.dart
  - example/ios/RunnerTests/RunnerTests.swift
  - example/macos/RunnerTests/RunnerTests.swift
  - example/lib/main.dart
  - example/lib/src/compression_runner.dart
  - example/lib/src/main_screen.dart
  - example/test/main_screen_test.dart
  - example/test/widget_test.dart
  - lib/src/compress_result.dart
  - tool/check_parity.sh
  - tool/check_parity_test.sh
  - tool/measure_presets_ci.sh
  - tool/run_ios_integration_suites.sh
  - tool/run_ios_integration_suites_test.sh
findings:
  critical: 1
  warning: 2
  info: 1
  total: 4
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-09-26T02:42:27Z
**Depth:** standard
**Files Reviewed:** 30
**Status:** issues_found

## Summary

This phase ports the Apple compression pipeline (AVAssetReader/AVAssetWriter + AVAssetExportSession
transmux) to parity with Android's Media3 Transformer. The engineering is unusually disciplined:
the never-larger post-check in `CompressionEngine.finishJob` is genuinely the single unconditional
site both the encode and transmux branches funnel through, `JobRegistry`'s terminal/cancelled race
window is closed exactly as documented, `ErrorMapping`'s `knownAVErrorCodes` size is pinned by a
test so a future code silently degrading to `"unknown"` fails loud, the NFC-normalisation fix at
both reporting boundaries (`CompressionEngine.buildResult`, `Thumbnails.writeJpegAtomically`) is
applied at the correct choke point with regression tests proving the underlying Darwin behaviour,
and the CI/shell tooling (`check_parity.sh`, `run_ios_integration_suites.sh`, the corpus generator)
is self-tested against fixtures rather than merely "runs and doesn't crash." `SizeGuard.swift`'s
port of the shared resolver is line-for-line traceable against its own rule numbering.

Against that backdrop, one real gap was found: neither `Arguments.requireWritableOutputParent` nor
`PluginFiles.moveIntoPlace` guards against a caller-supplied `outputPath` that already names an
existing directory, and `moveIntoPlace`'s `removeItem(at:)` call will silently recurse-delete that
directory's entire contents before the rename. This is a genuine data-loss path reachable on both
the real-encode/transmux success path and the never-larger copy-original path, and it has no test
coverage anywhere in the corpus or `RunnerTests.swift`. Two lower-severity findings (an unstructured
per-progress-tick `Task` with no ordering guarantee, and an unguarded `abs()` call that traps on
`Int.min`) round out the report.

## Critical Issues

### CR-01: A pre-existing directory at `outputPath` is silently deleted (recursively) instead of rejected

**File:** `darwin/compress_video/Sources/compress_video/PluginFiles.swift:51-64`
**Issue:**
`Arguments.requireWritableOutputParent` (`Arguments.swift:76-100`) only validates that
`outputPath`'s *parent* directory exists and is writable — it never checks whether `outputPath`
itself already exists as a directory. `PluginFiles.moveIntoPlace`, which every success path in
`CompressionEngine` funnels through (the real encode and transmux paths via `finishJob`, and the
never-larger path via `copyOriginalAtomically`), does this before renaming the temp file into
place:

```swift
static func moveIntoPlace(tempFile: URL, destination: URL) throws {
  do {
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: tempFile, to: destination)
  } ...
}
```

`FileManager.fileExists(atPath:)` returns `true` for a directory just as readily as a file, and
`FileManager.removeItem(at:)` recursively deletes a non-empty directory's entire contents with no
distinction from removing a single file. A host app that passes an existing directory as
`CompressOptions.outputPath` (a plausible caller mistake — e.g. accidentally passing a directory
the app meant to write *into*, or a path that used to be a file and is now a directory due to
unrelated app state) causes this plugin to silently wipe that directory and everything under it,
with no error and no typed `CompressVideoError` warning the caller beforehand. This is exactly the
class of native side effect this file's own module doc says validation exists to prevent
("turning a traversal attempt into a typed `CompressVideoError` instead of an unexpected native
failure") — but the directory case is not covered by that validation.

This is reachable on every success path (`finishJob`'s two branches and
`copyOriginalAtomically`), and is untested: `RunnerTests.swift`'s `Arguments
.requireWritableOutputParent` tests (lines 224-266) only cover a missing parent directory, an
existing writable parent, and the NFC round-trip — none construct an `outputPath` that is itself
an existing directory. No `compress_output_test.dart` case does either (checked: only "parent does
not exist" and "parent exists and is writable" outputPath cases are exercised).

**Fix:** Reject an `outputPath` that already exists as a directory in `Arguments
.requireWritableOutputParent`, before any encode is attempted:

```swift
static func requireWritableOutputParent(_ outputPath: String) throws -> String {
  let standardizedPath = standardizedAbsolutePath(outputPath)
  let parentPath = (standardizedPath as NSString).deletingLastPathComponent
  let fileManager = FileManager.default

  var isDirectory: ObjCBool = false
  if fileManager.fileExists(atPath: standardizedPath, isDirectory: &isDirectory), isDirectory.boolValue {
    throw CompressVideoError(
      code: "io",
      message: "outputPath already exists as a directory",
      details: nil
    )
  }
  ... // existing parent-directory checks unchanged
}
```

As defence in depth, `PluginFiles.moveIntoPlace` should also refuse to `removeItem` a directory
rather than trusting every call site to have validated this upstream:

```swift
if fileManager.fileExists(atPath: destination.path, isDirectory: &isDir), isDir.boolValue {
  throw CompressVideoError(code: "io", message: "destination exists and is a directory", details: nil)
}
```

## Warnings

### WR-01: Progress percentages are forwarded via unstructured per-call `Task`s with no ordering guarantee

**File:** `darwin/compress_video/Sources/compress_video/Compression.swift:57-61`
**Issue:** `startCompress` wires `CompressionEngine`'s `onProgress` callback like this:

```swift
onProgress: { [flutterApi] percent in
  Task { @MainActor in
    try? await flutterApi.onProgress(jobId: jobId, percent: percent)
  }
}
```

The native copy loop already guarantees the *values* passed to this closure are monotonically
non-decreasing (`CompressionEngine.runCopyLoop`'s `lastSentProgress` gate), but each invocation
spawns a brand-new, independent, unstructured `Task`. Nothing serializes these tasks relative to
each other beyond "each happens to be `@MainActor`-isolated" — if an earlier task's `await
flutterApi.onProgress(...)` call suspends (e.g. waiting on the binary messenger round trip) while a
later task's call does not, the later percentage can reach the Dart side before the earlier one,
producing an out-of-order progress stream on the Dart side even though native emission order was
correct. `compress_jobs_test.dart` (`example/integration_test/compress_jobs_test.dart:150-152`)
asserts the received stream is sorted, so this would be caught if it manifested during a test run,
but the code has no structural guarantee preventing it — it currently relies on scheduling
happening to preserve order on the tested runners.

**Fix:** Serialize delivery explicitly, e.g. by awaiting each call directly against the
already-`@MainActor`-isolated context that `CompressHostApiSetup.setUp` establishes (removing the
manual `Task {}` wrapper) or by funnelling all progress sends for a job through a single
job-scoped async sequence/actor that guarantees FIFO delivery regardless of individual call
suspension points.

### WR-02: `abs(nsError.code)` traps if `nsError.code == Int.min`

**File:** `darwin/compress_video/Sources/compress_video/CompressionEngine.swift:945`
**Issue:**

```swift
let magnitude = abs(nsError.code)
```

`Int.magnitude`/`abs(_:)` on a signed integer traps (crashes) when applied to `Int.min`, because
its positive counterpart is not representable. `nsError.code` here comes from an `NSError` in the
`AVFoundationErrorDomain`; in practice every documented `AVError` code is a small negative number
nowhere near `Int.min`, so this is unlikely to fire — but it is a native crash path with no upstream
validation guarding it, in code whose entire purpose (per its own comment two lines above) is to
turn every underlying failure into a typed `CompressVideoError` rather than crash. A malformed or
unexpected `NSError` (e.g. from a future OS version, a different domain incorrectly routed here, or
a fuzzed/corrupted error object) reaching this line with `code == Int.min` would crash the host app
instead of surfacing an `"io"`/`"unknown"` typed error.

**Fix:** Use the overflow-safe form:

```swift
let magnitude = nsError.code.magnitude
```
and format `magnitude` (a `UInt`) instead of relying on `abs`'s trapping `Int` result — this can
never trap for any `Int` input.

## Info

### IN-01: `CompressionEngine.resolvePlan(inputURL:inputInfo:request:)` re-reads the input's audio codec independently for the free-space pre-check and the real compress call

**File:** `darwin/compress_video/Sources/compress_video/CompressionEngine.swift:553-558`, `darwin/compress_video/Sources/compress_video/Compression.swift:126-146`
**Issue:** `Compression.requireSufficientFreeSpace` and `CompressionEngine.compress` both resolve a
`SizeGuard.Plan` for the same job, and each resolution independently calls `CompressionEngine
.readAudioCodec(at:)`, which opens a fresh `AVURLAsset` and loads its audio track's format
description from disk. This is a correctness non-issue (the same deterministic input produces the
same codec both times, so the two `Plan`s cannot disagree) but it is two extra asset loads and one
extra track/format-description read per compress call purely to keep the free-space check and the
real encode "unable to disagree" — a documented, deliberate tradeoff (the comment at
`CompressionEngine.swift:546-552` calls this out explicitly as the reason the function is not
`private`). Flagging only because a future change to `resolvePlan`'s call sites should preserve
this "exposed on purpose" contract rather than "simplify" it into a shared cached codec read that
could silently reintroduce the disagreement risk this design avoids.
**Fix:** No action required; this is a documented tradeoff, noted here only so it isn't
"simplified" away by a future refactor without re-reading the rationale in the doc comment.

---

_Reviewed: 2026-09-26T02:42:27Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
