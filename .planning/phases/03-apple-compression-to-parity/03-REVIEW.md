---
phase: 03-apple-compression-to-parity
reviewed: 2026-09-26T03:20:00Z
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
  - android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/ArgumentsTest.kt
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
  critical: 0
  warning: 0
  info: 2
  total: 2
status: clean
---

# Phase 03: Code Review Report (Iteration 2 — verifying fixes)

**Reviewed:** 2026-09-26T03:20:00Z
**Depth:** standard
**Files Reviewed:** 30
**Status:** clean

## Summary

This is a re-review of iteration 1's three in-scope findings (CR-01, WR-01, WR-02), fixed on
`main` by commits `bb8968c`, `cf218ac`, `1def170`. All three are verified correct by direct
reading of the diffed code (no Swift toolchain is available on this machine either, so the
Swift changes were verified the same way the fixer verified them — by tracing the logic against
known-correct language semantics — plus cross-checking the Kotlin mirror, which *was* compiled
and unit-tested per the fix report).

**CR-01 (directory `outputPath` recursively deleted) — verified fixed on both platforms.**
`Arguments.requireWritableOutputParent` (Swift) and `Arguments.kt`'s Kotlin twin now both check
`isDirectory`/`isOutputPathDirectory` before any parent-directory check and reject with a typed
`"io"` error; `PluginFiles.moveIntoPlace` additionally refuses to `removeItem` a directory
destination as defence in depth. All three new regression tests (`ArgumentsTest.kt`'s JVM case,
and byte-identical XCTest cases in both `example/ios/RunnerTests/RunnerTests.swift` and
`example/macos/RunnerTests/RunnerTests.swift`, confirmed with `diff`) assert the right thing, and
the platform-neutral `compress_output_test.dart` case plants a sentinel file inside the directory
and asserts both the directory and the sentinel survive the rejected request — a real proof the
old recursive-delete path cannot fire, not just that an error is thrown. No gaps found.

**WR-02 (`abs(Int.min)` trap) — verified fixed.** `CompressionEngine.swift:949` now reads
`nsError.code.magnitude` (a `UInt`, which cannot trap for any `Int` input), used only in a string
interpolation immediately below. Single-line, mechanical, low-risk.

**WR-01 (unordered progress delivery) — verified fixed for the problem it targeted, with one
residual, pre-existing timing caveat noted below (not a regression from this fix).** The
`AsyncStream<Double>` replacement in `Compression.swift:59-77` is the standard, documented Swift
concurrency idiom (`var continuation: AsyncStream<T>.Continuation!; let stream = AsyncStream<T> {
continuation = $0 }`), and traced line-by-line it is sound:
- The build closure runs synchronously inside `AsyncStream.init`, so `progressContinuation` is
  guaranteed non-nil before `onProgress`'s closure (which force-unwraps it implicitly) can ever be
  invoked — no crash risk from the implicitly-unwrapped-optional pattern.
- `progressContinuation.yield(percent)` in `onProgress` is a synchronous, ordering-preserving
  enqueue; the single `for await percent in progressStream { try? await flutterApi.onProgress(...)
  }` consumer processes one value fully (including its own `await`) before pulling the next, so
  values are delivered to Dart in the exact order they were yielded regardless of how long any
  individual `flutterApi.onProgress` call suspends. This is precisely the ordering guarantee
  WR-01 asked for, and it is a real structural guarantee, not a scheduling coincidence.
- `defer { progressContinuation.finish() }` is registered once, right after the stream is created,
  and Swift's `defer` fires on every exit from `startCompress` — normal return, or a thrown error
  from any point including `engine.compress`'s `cancelled`/mapped-error paths. The stream is
  therefore always finished (never leaked, never left open) on the success, cancel, and error
  paths alike. Traced all three (`compress()`'s never-larger pre-check return, its real-encode
  throw/cancel branches, and `runTransmux`'s throw/cancel branch) — all propagate up through the
  single `return try await engine.compress(...)` call site the `defer` guards.
- `swift-tools-version: 5.9` (`darwin/compress_video/Package.swift`) with no strict-concurrency
  settings means the `Task { @MainActor [flutterApi] in ... }` capture (the same capture shape the
  pre-fix code already used at the same call site, so not a newly-introduced pattern) does not
  hit a Sendable-checking wall this project's toolchain enables.

No test-invalidating defect was found in this change. **Verification caveat carried over from the
fix report applies unchanged:** CI run 36212964031 (the push containing all three fixes) was still
in progress (Apple job not yet complete) at the time of this review — this is the first time the
AsyncStream code will actually be compiled. Nothing in this re-review found reason to expect a
compile failure, but that remains empirically unconfirmed until that run finishes.

The rest of the phase's scope (all files not touched by the three fix commits — `ErrorMapping.swift`,
`JobRegistry.swift`, `MediaMath.swift`, `SizeGuard.swift`, `Thumbnails.swift`,
`CompressVideoPlugin.swift`, the CI workflow, corpus/tool shell scripts, and the example/lib/test
Dart files) was re-scanned at standard depth and shows no new issues: no hardcoded secrets, no
dangerous functions, no empty catch blocks, no debug artifacts, and no logic changes since the
version already reviewed clean in iteration 1.

## Info

### IN-01: `CompressionEngine.resolvePlan` re-reads the input's audio codec independently for the free-space pre-check and the real compress call (carried forward, unchanged, no action required)

**File:** `darwin/compress_video/Sources/compress_video/CompressionEngine.swift:553-558`, `darwin/compress_video/Sources/compress_video/Compression.swift:126-146`
**Issue:** Unchanged from iteration 1's IN-01. `Compression.requireSufficientFreeSpace` and
`CompressionEngine.compress` each independently resolve a `SizeGuard.Plan`, and each resolution
re-reads the audio codec via a fresh `AVURLAsset`/track load. This is a documented, deliberate
tradeoff (see the doc comment at `CompressionEngine.swift:546-552`): the function is exposed
non-`private` specifically so the two call sites can never predict/produce different plans. Not a
defect. Flagged again only so a future refactor does not "simplify" it into a shared cached codec
read without re-reading that rationale.
**Fix:** No action required.

### IN-02: The terminal progress-100 tick and the `startCompress` reply race on MainActor scheduling — pre-existing, not introduced by the WR-01 fix

**File:** `darwin/compress_video/Sources/compress_video/Compression.swift:59-77`, `darwin/compress_video/Sources/compress_video/CompressionEngine.swift:419-427`
**Issue:** The WR-01 fix guarantees strict FIFO ordering *among* progress ticks relative to each
other, but it does not (and was not asked to) guarantee ordering between the final `onProgress(100.0)`
tick and the `CompressResultMessage` reply that completes the Dart-side `startCompress` future.
`engine.compress()` calls `onProgress(100.0)` (a synchronous `yield` into the stream) and then does
additional async work (`finishJob` → `buildResult`'s re-probe of the output file) before returning;
only once it returns does `startCompress`'s own `Task { @MainActor in ... }` context (per Pigeon's
generated wrapper) resume to send the reply. Meanwhile the stream's single consumer `Task` also
needs to be scheduled onto `MainActor` to actually call `flutterApi.onProgress(jobId:100.0)`. Both
are ordinary queued work on the same serial `MainActor` executor, and nothing in the code
establishes a happens-before relationship between "the final onProgress message is sent over the
channel" and "the startCompress reply is sent over the channel" — the `buildResult` async work
happening to take non-zero time after the yield is what biases this to resolve correctly in
practice, not a structural guarantee. `compress_jobs_test.dart`'s "ends with exactly one terminal
100" assertion would be immune to this specific race regardless (Dart's `compress_job.dart` closes
its progress stream in a `finally` block gated on the `startCompress` reply arriving, independent
of whether the native 100 tick won or lost the race — so a lost race would simply mean
`progressValues.last` is not `100.0`, i.e. the test *would* catch a regression here, it just isn't
proof one can't occur under different scheduling). This exact race (a fresh `Task` needing to be
scheduled onto `MainActor` for the final tick, competing with the outer call's own resumption) was
equally present in the pre-fix code at the same call site, so this is not a regression the WR-01
fix introduced — it is an orthogonal, pre-existing property of delivering progress and the result
over the same actor via independent Task scheduling, outside WR-01's stated scope (ordering
*among* progress ticks).
**Fix:** No action required for this iteration's scope. If this ever surfaces as a real flake,
the fix would be to have `engine.compress` explicitly await the progress stream's last delivery
(e.g. join on the last progress `Task`, or send the terminal 100 through the same reply path)
before constructing the `CompressResultMessage`, rather than relying on `buildResult`'s incidental
extra latency.

---

_Reviewed: 2026-09-26T03:20:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
