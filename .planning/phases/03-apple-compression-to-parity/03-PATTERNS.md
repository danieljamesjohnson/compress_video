# Phase 3: Apple Compression to Parity - Pattern Map

**Mapped:** 2026-09-22
**Files analyzed:** 18 (6 new Swift engine files + 2 XCTest twins + CI/tool/example edits)
**Analogs found:** 18 / 18

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|-----------------|---------------|
| `darwin/compress_video/Sources/compress_video/SizeGuard.swift` | utility (pure math) | transform | `android/.../SizeGuard.kt` | exact (line-for-line port) |
| `darwin/compress_video/Sources/compress_video/CompressionEngine.swift` | service (media engine) | streaming/file-I/O | `android/.../TransformerEngine.kt` | exact (role+flow), Swift style from `darwin/.../Probe.swift` |
| `darwin/compress_video/Sources/compress_video/JobRegistry.swift` | store (in-memory registry) | event-driven | `android/.../JobRegistry.kt` | exact (role+flow) |
| `darwin/compress_video/Sources/compress_video/ErrorMapping.swift` | utility (pure mapping) | transform | `android/.../ErrorMapping.kt` | exact (role+flow) |
| `darwin/compress_video/Sources/compress_video/PluginFiles.swift` | utility (file I/O) | file-I/O | `android/.../PluginFiles.kt` | exact (role+flow) |
| `darwin/compress_video/Sources/compress_video/Compression.swift` | controller (`CompressHostApi` impl) | request-response | `android/.../Compression.kt`; Swift async style from `darwin/.../Probe.swift` | exact (role+flow) |
| `darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift` (extend) | config/registration | request-response | itself (existing file, extend registration pattern) | exact |
| `example/ios/RunnerTests/RunnerTests.swift` + macOS twin (extend) | test (XCTest) | CRUD/transform | itself + `android/.../SizeGuardTest.kt`, `ErrorMappingTest.kt` (numeric case source) | exact |
| `corpus/generate_corpus.sh` (extend) | utility (shell) | batch | itself | exact |
| `corpus/verify_corpus.sh` (extend) | utility (shell) | batch | itself | exact |
| `tool/check_parity.sh` (extend) | utility (shell) | transform | itself + `tool/check_parity_test.sh` | exact |
| `.github/workflows/ci.yml` `apple`/`parity` jobs (extend) | config (CI) | batch | itself | exact |
| `tool/mac_sync.sh` (new) | utility (shell) | file-I/O | `tool/verify_apk_native_libs.sh` (shell style) | role-match |
| `tool/mac_run.sh` (new) | utility (shell) | request-response | `tool/verify_apk_native_libs.sh` | role-match |
| `tool/verify_fresh_app.sh` (new) | utility (shell) | batch | `tool/verify_apk_native_libs.sh` | role-match |
| `example/lib/main.dart` (rewrite) | component (Flutter screen) | request-response | itself (existing screen, Phase 2) | exact |
| `example/integration_test/compress_*_test.dart` (unskip + extend) | test (integration) | CRUD | themselves (existing suites) | exact |
| `example/pubspec.yaml`, `Info.plist`, `*.entitlements` | config | — | themselves | exact |

## Pattern Assignments

### `darwin/compress_video/Sources/compress_video/SizeGuard.swift` (utility, transform)

**Analog:** `android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt` (307 lines, read in full)

Port this **line-for-line**, same rule numbering (1-7), same field names, same constants. Key structural pieces to mirror exactly:

**Data shapes** (lines 22-149 of the Kotlin): `InputInfo` (probed facts, nullable = unknown, never a sentinel `0`), `Options` (explicit-override-or-`null` fields plus always-set preset fields), `Plan` (resolved output: `targetWidthPx/HeightPx`, `effectiveFps`, `videoBitrateBps`, `audioBitrateBps`, `outputDurationMs`, `predictedOutputBytes`, `wouldTransmux`, `wouldUseOriginal`). In Swift these become `struct`s (no AVFoundation import — a Swift `enum SizeGuard { }` namespace, matching `MediaMath`'s existing enum-namespace style in `darwin/.../MediaMath.swift`).

**Core resolution function** (`resolve(input:options:)`, Kotlin lines 155-279): 7 rules in order —
1. `effectiveLongSidePx` capped at input's own displayed long side
2. `scale` ratio
3. `targetWidthPx/HeightPx` via `MediaMath.floorToEvenMin16` (Swift already has an equivalent-shaped helper in `MediaMath.swift`; add `floorToEvenMin16` there if missing, matching `scaledSize`'s existing style)
4. `effectiveFps` never upscales
5. audio bitrate clamped to `[MIN_AUDIO_BITRATE_BPS, MAX_AUDIO_BITRATE_BPS]`
6. video bitrate precedence: explicit → targetSizeMb → preset-scaled, always capped at input's own bitrate
7. `predictedOutputBytes` (remux = input size; else bitrate*duration*overhead)

Then `wouldTransmux` (7 AND-ed conditions, integer cross-multiplication `* 100`/`* 115` not floating `1.15` — copy this exactly to avoid binary-float boundary bugs) and `wouldUseOriginal` (pre-check only, equality counts as "would not help").

**Constants to port verbatim** (lines 281-306): `MIN_AUDIO_BITRATE_BPS = 8000`, `MAX_AUDIO_BITRATE_BPS = 960000`, `DEFAULT_AUDIO_BITRATE_BPS = 128000`, `VIDEO_BITRATE_FLOOR_BPS = 200000`, `NOMINAL_PRESET_FPS = 30.0`, `MUX_OVERHEAD_FACTOR = 0.97`, `CONTAINER_OVERHEAD_FACTOR = 1.03`. Re-verify the Apple software encoder's own bitrate floor is compatible with `VIDEO_BITRATE_FLOOR_BPS` (Android's is emulator-measured; document if Apple's AAC/H264 encoders need different min/max — flag a deviation rather than silently reusing Android's numbers unverified).

---

### `darwin/compress_video/Sources/compress_video/CompressionEngine.swift` (service, streaming/file-I/O)

**Analog:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt` (738 lines — grep for `fun compress`, `fun resolvePlan`, `fun finishSuccess`, `fun mapExportException` rather than reading whole file) for the *shape* of the pipeline; **Swift async/threading style from `darwin/.../Probe.swift`** (already read in full, 217 lines).

**Imports pattern** (from `Probe.swift` lines 1-10):
```swift
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif
```

**Dual-availability load pattern** (`Probe.swift` lines 28-39, 59-97): every AVFoundation property load needs the `#available(iOS 16, macOS 13, *)` branch (modern `await asset.load(.duration)`) vs. the legacy `loadValuesAsynchronously(forKeys:)` continuation-wrapped path (`awaitLegacyLoad`, lines 140-163) — copy this helper verbatim into `CompressionEngine.swift` or factor it into a shared internal helper, since this project's floor (iOS 13/macOS 11) is below the modern API's floor (iOS 16/macOS 13) for property loading, and below iOS 18/macOS 15 for the modern export API (RESEARCH.md Pattern 4).

**Error wrapping pattern** (`Probe.swift` lines 40-48, 89-97, 111-122): every AVFoundation call site wraps in `do { ... } catch let error as CompressVideoError { throw error } catch { throw CompressVideoError(code:, message:, details: error.localizedDescription) }` — never let a raw `NSError`/`AVError` propagate unmapped; route through `ErrorMapping.swift` for the reason code specifically, but keep this catch-and-wrap shape.

**Reader-side resize** — per RESEARCH.md Pattern 2, use `outputSettings` width/height keys directly, never `AVAssetReaderVideoCompositionOutput`. **Rotation** — set `AVAssetWriterInput.transform = sourceTrack.preferredTransform`, matching how `Probe.swift` line 99 already reads it via `MediaMath.rotationDegrees(from:)` in the *reverse* direction. **Trim** — `AVAssetReader.timeRange` + `AVAssetWriter.startSession(atSourceTime:)`, per RESEARCH.md Pattern 3 (this supersedes CONTEXT.md's "-start" phrasing — same observable outcome, standard mechanism). **Transmux** — `AVAssetExportSession` version-gated per RESEARCH.md Pattern 4. **Threading** — the copy loop must run OFF the MainActor the Pigeon call arrives on (RESEARCH.md Pattern 1 — the inverse of Android's TransformerEngine constraint, which must stay ON the main Looper).

**Never-larger post-check**, mirror `TransformerEngine.kt`'s `finishSuccess` (`usedOriginal = tempBytes >= inputBytes`, unconditional, every path including transmux — CLAUDE.md lane note repeats this).

**Progress derivation**: last-appended video sample pts / output duration, clamped 0..99, dispatched to main queue via `CompressVideoFlutterApi.onProgress` at most every 250ms, terminal `100` before the result reply — same clamp rule as Android.

---

### `darwin/compress_video/Sources/compress_video/JobRegistry.swift` (store, event-driven)

**Analog:** `android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt` (132 lines, read in full)

Port the shape directly: a dictionary keyed by `jobId` holding a `LiveJob`-equivalent struct/class with `cancel: () -> Void` closure (not a direct `AVAssetWriter`/`AVAssetReader` reference — keeps it testable, same reasoning as the Kotlin doc comment lines 14-20), `tempFile: URL`, `cancelled`/`terminal` flags. Main-queue-confined instead of main-Looper-confined — same synchronization argument (no lock, single-thread confinement is the guard).

**Core methods to port 1:1**: `register(jobId:job:)`, `find(jobId:)`, `remove(jobId:)`, `stopPolling(jobId:)` (marks `terminal` — same WR-01 race-window closing logic, lines 71-94), `cancel(jobId:)` (no-op if unknown/cancelled/terminal — same double-resolution guard), `cancelAll()` (used by both iOS `detachFromEngine` and macOS `handleWillTerminate`, RESEARCH.md Pattern 5), `liveTempFilePaths() -> Set<String>` (used by `PluginFiles.sweep`, mirrors `canonicalPath` → Swift's `URL.standardizedFileURL`/`resolvingSymlinksInPath().path`).

---

### `darwin/compress_video/Sources/compress_video/ErrorMapping.swift` (utility, transform)

**Analog:** `android/src/main/kotlin/com/danjjohnson/compress_video/ErrorMapping.kt` (135 lines, read in full)

Same table shape: an exhaustive `switch` over AVError codes → `CompressVideoErrorReason` string, plus a `KNOWN_ERROR_CODES`-equivalent `Set` asserted by a test (mirrors `ErrorMappingTest.kt`'s "assert the set size directly" pattern so a future code omitted from the mapping table fails a test instead of silently falling to `.unknown`).

**IMPORTANT correction from RESEARCH.md**: the real Swift `AVError.Code` case names are `.decoderNotFound`/`.encoderNotFound` and `.decoderTemporarilyUnavailable`/`.encoderTemporarilyUnavailable` — NOT `.decoderNotAvailable`/`.encoderNotAvailable` as CONTEXT.md's prose states. Use the RESEARCH.md-verified names.

**Mapping table** (per CONTEXT.md, corrected names): missing file → `fileNotFound`; `.fileFormatNotRecognized` / no video track / unreadable → `unsupportedInput`; `.decoderNotFound`/decode failed → `decoderUnavailable`; `.encoderNotFound`/`.encoderTemporarilyUnavailable` → `encoderUnavailable`; `.diskFull` + pre-flight `volumeAvailableCapacityForImportantUsageKey` check against 1.2x predicted bytes → `outOfSpace`; everything else → `io` with the `NSError` domain/code folded into the message (same "numeric-code-in-message" rule as Android's `reasonForExportFailure`, lines 121-129, which does a message-string `enospc`/"no space left" check as secondary defense — port that same secondary check).

---

### `darwin/compress_video/Sources/compress_video/PluginFiles.swift` (utility, file-I/O)

**Analog:** `android/src/main/kotlin/com/danjjohnson/compress_video/PluginFiles.kt` (105 lines, read in full)

Port directly: `cacheSubDir()` → `FileManager.urls(for: .cachesDirectory, in: .userDomainMask).first` + `compress_video` subdirectory, create-if-missing, throw `CompressVideoError(code: "io", ...)` on failure (mirrors Kotlin lines 23-29). `tempFileBeside(destination:)` → same-directory temp file for atomic rename (Kotlin lines 35-36). `moveIntoPlace(tempFile:destination:)` → `FileManager.default.moveItem` wrapped in do/catch → `io` error (Kotlin lines 42-49). `quietDelete(_:)` → best-effort delete, ignore errors (Kotlin lines 52-54). `sweep(cacheDir:skipCanonicalPaths:)` → **same canonical-path containment logic**: resolve `cacheDir`'s own canonical path, list only its immediate contents (never recursive), skip anything whose canonical path doesn't start with the cache dir's own canonical prefix (symlink escape guard, Kotlin lines 68-98) and anything in `skipCanonicalPaths` (live job exclusion). Use `URL.resolvingSymlinksInPath().path` for "canonical path" the way `Arguments.swift`'s `standardizedAbsolutePath` already does (lines 176-198) — reuse that exact resolution idiom rather than inventing a new one.

---

### `darwin/compress_video/Sources/compress_video/Compression.swift` (controller, request-response)

**Analog:** `android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt` (184 lines, read in full); **Swift `HostApi` conformance style from `darwin/.../Probe.swift`** (`final class Probe: ProbeHostApi { func getMediaInfo(path:) async throws -> MediaInfoMessage { ... } }`, lines 20-21).

**Class shape**: `final class Compression: CompressHostApi` holding a `flutterApi: CompressVideoFlutterApi` and an `engine: CompressionEngine`. Every entry point is `async throws`, unlike Android's explicit `requireMainLooper` assertion — Pigeon delivers the call already on the MainActor (RESEARCH.md Pattern 1's key insight), so `Compression.startCompress` must instead **hop OFF** the MainActor to run the actual engine work (the inverse of Android's `requireMainLooper` guard).

**`startCompress(path:jobId:request:)`** mirrors Kotlin lines 23-54: validate jobId format (`^[0-9]+-[0-9a-f]{16}$`, same regex), `Arguments.requireValidCompressRequest` (extend `Arguments.swift` with this — mirror the existing `requireValidThumbnailArgs` pattern at lines 141-159), `Arguments.requireReadableMediaFile(path)` (already exists, reuse), probe via `Probe` (reused, unchanged), resolve destination via `PluginFiles.cacheSubDir` + `<jobId>.mp4` or `Arguments.requireWritableOutputParent(outputPath)` (already exists, reuse), pre-flight free-space check (see below), then hand off to `CompressionEngine.compress(...)`.

**`cancel(jobId:)`** mirrors Kotlin lines 56-60: validate jobId, `JobRegistry.cancel(jobId)`.

**`estimate(path:request:)`** mirrors Kotlin lines 76-94: validate + probe like `startCompress`, resolve `SizeGuard.Plan` through the exact same `resolvePlan` helper the compress path uses (never a separate computation — "the plan resolver both paths share" guarantee), map to `EstimateMessage`.

**`clearCache()`** mirrors Kotlin lines 104-109: `PluginFiles.sweep(cacheDir, JobRegistry.liveTempFilePaths())`.

**Pre-flight free-space check** (`requireSufficientFreeSpace`, Kotlin lines 125-146): use `URL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])` (per RESEARCH.md's "Don't Hand-Roll" table — first-party `URLResourceKey`, not a hand-rolled `statfs` wrapper) against `1.2 * plan.predictedOutputBytes`, throw `outOfSpace` with the same "predicted output is N bytes, requiring approximately M bytes..." message shape (Kotlin lines 138-144) if insufficient.

---

### `darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift` (extend)

**Analog:** itself (28 lines, read in full) — extend the existing `register(with:)` pattern.

**Registration pattern to extend** (current file, lines 17-28):
```swift
public class CompressVideoPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #elseif os(macOS)
      let messenger = registrar.messenger
    #endif

    ProbeHostApiSetup.setUp(binaryMessenger: messenger, api: Probe())
    ThumbnailHostApiSetup.setUp(binaryMessenger: messenger, api: Thumbnails())
  }
}
```
Add `CompressHostApiSetup.setUp(binaryMessenger: messenger, api: Compression(flutterApi: CompressVideoFlutterApi(binaryMessenger: messenger), engine: CompressionEngine()))`. Add **per-platform teardown** exactly per RESEARCH.md Pattern 5 — do NOT write one `#if os(iOS)`-guarded `detachFromEngine` and assume it covers macOS:
```swift
#if os(iOS)
public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
  JobRegistry.cancelAll()
}
#elseif os(macOS)
public func handleWillTerminate(_ notification: Notification) {
  JobRegistry.cancelAll()
}
#endif
```
`detachFromEngine` cancels every live job BEFORE tearing down registrations (T-02-25 requirement carried over from Android).

---

### `example/ios/RunnerTests/RunnerTests.swift` + `example/macos/RunnerTests/RunnerTests.swift` (test, extend)

**Analog:** themselves (357 lines each, byte-identical, read the first 80 lines of the iOS copy) plus **numeric test cases sourced from the Android `SizeGuardTest.kt`/`ErrorMappingTest.kt`** (find via Grep — not yet read this session, locate before planning: `android/src/test/kotlin/.../SizeGuardTest.kt`, `ErrorMappingTest.kt`).

**File header pattern** (lines 1-19 of the current file):
```swift
#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import Cocoa
  import FlutterMacOS
#endif
import XCTest

@testable import compress_video

// ... comment noting byte-identical-between-platforms convention, diffed in CI
class RunnerTests: XCTestCase {
```

**Test case pattern** (lines 24-58): `// MARK: - <TypeName>.<functionName>` section header, one `func test<Description>()` per case, `XCTAssertEqual(result.field, expected)`. For `SizeGuardTests`, add a new `// MARK: - SizeGuard.resolve` section with one test function per `SizeGuardTest.kt` case, **same input values, same expected outputs** — this is the plan's explicit "SAME numeric cases" requirement. Apply the identical addition to BOTH `example/ios/RunnerTests/RunnerTests.swift` and `example/macos/RunnerTests/RunnerTests.swift` — CI diffs them for byte-identity.

---

### Shell tooling: `tool/mac_sync.sh`, `tool/mac_run.sh`, `tool/verify_fresh_app.sh` (new)

**Analog:** `tool/verify_apk_native_libs.sh` and `tool/check_parity.sh` for shell style (not read this session in full — Grep their shebang/set flags before writing: likely `#!/usr/bin/env bash` + `set -euo pipefail`, matching the project's general shell convention referenced in CLAUDE.md's CI notes). Note the **CI `reactivecircus` `script:` gotcha already documented in project CLAUDE.md**: each line of THAT specific runner input is a separate shell — not relevant to these standalone scripts (which run as normal single-invocation bash), but worth cross-referencing if `mac_run.sh` is ever inlined into a CI `script:` block.

`tool/mac_sync.sh`: rsync-based, excludes `.git`, `build/`, `.dart_tool/`, `.planning/`, `**/Pods` per CONTEXT.md — no direct analog exists in the repo; write fresh following the existing tool/ scripts' header/comment-block convention (each existing tool script opens with a purpose comment block — mirror that).

`tool/mac_run.sh` / `tool/verify_fresh_app.sh`: wrap remote `PATH` setup + simulator boot + `flutter test`/`flutter build` invocations with perl-`alarm` bounds — reuse whatever alarm-wrapping helper `.github/workflows/ci.yml`'s existing macOS steps already use (grep `alarm` in `ci.yml` before writing, to copy the exact perl invocation rather than reinventing it).

---

### `.github/workflows/ci.yml` `apple`/`parity` jobs (extend)

**Analog:** itself — `apple` job at line 279, `parity` job at line 441 (not read in full this session; read both job bodies before planning, especially the current suite-allowlist and the `changes`/path-filter job at lines 29-37 mentioned in CLAUDE.md lane notes). Extend the `apple` job to drop the two-suite allowlist and run every `integration_test/*.dart` suite, add the SPM build step (if 01-06 didn't land it), the `tool/verify_fresh_app.sh` four-build step, and a macOS desktop `flutter test integration_test -d macos` run. Extend `parity` to diff Android-vs-iOS AND macOS-vs-iOS `PARITY_JSON` records.

---

### `example/lib/main.dart` (rewrite)

**Analog:** itself (301 lines, existing Phase 2 manual-check screen) — read in full before rewriting to preserve whatever state-management/widget structure it already uses, then replace per CONTEXT.md's BULD-04 spec (picker → options → progress/cancel → result card → playback). Reuse `CompressOptions`/`CompressResult` Dart types already generated by Pigeon (same as Phase 2).

---

## Shared Patterns

### Dual API-availability branching (iOS 16/macOS 13 property-load floor; iOS 18/macOS 15 export floor)
**Source:** `darwin/compress_video/Sources/compress_video/Probe.swift` lines 28-39, 59-97
**Apply to:** `CompressionEngine.swift` (every AVAsset/AVAssetTrack property load, every `AVAssetExportSession` progress mechanism)
```swift
if #available(iOS 16, macOS 13, *) {
  duration = try await asset.load(.duration)
} else {
  try await awaitLegacyLoad(asset, keys: ["duration", "tracks"])
  duration = asset.duration
}
```

### Error-wrap-and-rethrow at every AVFoundation call site
**Source:** `Probe.swift` lines 40-48
**Apply to:** All new engine files touching AVFoundation
```swift
} catch let error as CompressVideoError {
  throw error
} catch {
  throw CompressVideoError(code: "unsupportedInput", message: "...", details: error.localizedDescription)
}
```

### Canonical/symlink-resolved path handling
**Source:** `darwin/compress_video/Sources/compress_video/Arguments.swift` lines 176-198 (`standardizedAbsolutePath`)
**Apply to:** `PluginFiles.swift`'s `sweep`, `JobRegistry.swift`'s `liveTempFilePaths`
Reuse `URL.standardizedFileURL` + `resolvingSymlinksInPath().path`, with the "resolve existing prefix, reattach nonexistent suffix" walk for not-yet-existing output paths — do not reinvent path canonicalization.

### Pure-Swift, no-framework-import math/mapping objects
**Source:** `darwin/compress_video/Sources/compress_video/MediaMath.swift` (enum namespace, no AVFoundation import)
**Apply to:** `SizeGuard.swift`, `ErrorMapping.swift` — both must be exercisable as plain Swift unit tests with no simulator, exactly like `MediaMath`/`Arguments` already are in `RunnerTests.swift`.

### CompressVideoError construction
**Source:** used throughout `Probe.swift`/`Arguments.swift`
```swift
CompressVideoError(code: "<reason>", message: "<human message>", details: <String?>)
```
**Apply to:** Every throwing site in `ErrorMapping.swift`, `Compression.swift`, `CompressionEngine.swift`, `PluginFiles.swift`.

### Never-larger, unconditional, every path
**Source:** `android/.../TransformerEngine.kt` `finishSuccess` (`usedOriginal = tempBytes >= inputBytes`), CLAUDE.md lane note
**Apply to:** `CompressionEngine.swift`'s post-check on both the real-encode branch and the transmux branch — no exemption for either.

## No Analog Found

None — every new file has at least a role-match analog (Android Kotlin twin for engine files, Swift style file for language idiom, or an existing shell/CI/Dart file for tooling).

## Metadata

**Analog search scope:** `android/src/main/kotlin/com/danjjohnson/compress_video/`, `darwin/compress_video/Sources/compress_video/`, `example/ios/RunnerTests/`, `example/macos/RunnerTests/`, `tool/`, `corpus/`, `.github/workflows/ci.yml`, `example/lib/main.dart`, `example/integration_test/`
**Files scanned/read in full:** `SizeGuard.kt`, `JobRegistry.kt`, `ErrorMapping.kt`, `PluginFiles.kt`, `Compression.kt`, `Probe.swift`, `Arguments.swift`, `CompressVideoPlugin.swift`, `MediaMath.swift`, `RunnerTests.swift` (partial, 80/357 lines — pattern established, remaining lines are more test cases of the same shape)
**Not yet read (locate and read during planning):** `android/src/test/kotlin/.../SizeGuardTest.kt`, `ErrorMappingTest.kt` (numeric case source for XCTest twins), `TransformerEngine.kt` full body (738 lines — grep target line numbers for `compress`/`resolvePlan`/`finishSuccess`/`mapExportException` before reading), `.github/workflows/ci.yml` `apple`/`parity` job bodies in full, `tool/check_parity.sh`, `tool/verify_apk_native_libs.sh` (shell style reference), `example/lib/main.dart` in full, `corpus/generate_corpus.sh`/`verify_corpus.sh`
**Pattern extraction date:** 2026-09-22
