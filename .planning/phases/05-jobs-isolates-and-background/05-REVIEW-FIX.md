---
phase: 05-jobs-isolates-and-background
fixed_at: 2026-09-27T18:15:11Z
review_path: .planning/phases/05-jobs-isolates-and-background/05-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 5: Code Review Fix Report

**Fixed at:** 2026-09-27T18:15:11Z
**Source review:** .planning/phases/05-jobs-isolates-and-background/05-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 4
- Fixed: 4
- Skipped: 0

**Scope note:** `fix_scope` was `critical_warning` (nominally CR-01, WR-01, WR-02). The
orchestrator's dispatch explicitly named a fourth finding, IN-01 (the
`verify_apk_foreground_service_manifest.sh` gap), for inclusion as well, so all four
findings documented in 05-REVIEW.md's body were fixed. (05-REVIEW.md's frontmatter
reports `critical: 2` / `total: 5`, but the document body only contains four numbered
findings -- one Critical (CR-01), two Warnings (WR-01, WR-02), one Info (IN-01). This
looks like a pre-existing counting inconsistency in the source review itself, not
something introduced here; all four findings actually present in the body were
addressed.)

## Fixed Issues

### CR-01: ForegroundServiceHost can be left running (with a stale "0 videos" notification) if the last hosted job detaches before the service has actually started

**Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/ForegroundServiceHost.kt`, `android/src/test/kotlin/com/danjjohnson/compress_video/ForegroundServiceHostTest.kt`
**Commit:** c630c82
**Applied fix:** `onStartCommand` now re-checks `ref.hostedCount` immediately after posting the
foreground notification and calls `stopSelf(startId)` when it is `0` -- closing the race where
`startForegroundService()`'s deferred `onCreate()`/`onStartCommand()` runs after the one job that
triggered the start has already fully detached again. Added a JVM regression test
(`singleAttachThenDetach_leavesZeroHostedJobs_forADeferredStartCommandToObserve`) proving the
`Ref` bookkeeping this check relies on. Verified: `:compress_video:testDebugUnitTest` (all 6
`ForegroundServiceHostTest` cases pass, including the new one) and a clean `compileDebugKotlin`.

### WR-02: The shared ForegroundServiceHost notification is never refreshed when a job detaches, only when one attaches

**Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/ForegroundServiceHost.kt`
**Commit:** b4fc528
**Applied fix:** `detach()` now calls `instance?.refreshNotification()` in the `else` branch
(when `shouldStop` is `false`, i.e. other jobs remain hosted), mirroring what `attach()` already
does for the non-first-job case. No new unit test was added for this one: `refreshNotification()`
is a method on the real `Service` instance, which this project's plain-JVM test suite has no
Robolectric shadow to instantiate (the same constraint `ForegroundServiceHostTest`'s own doc
comment documents for testing `Ref` instead of the real service). Verified via a clean
`compileDebugKotlin` and the full `ForegroundServiceHostTest` suite still passing.

### WR-01: `awaitCompressResult` hangs forever (never fails typed) for a job id that was never started or whose result was already consumed

**Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/JobRegistry.kt`, `android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt`, `android/src/test/kotlin/com/danjjohnson/compress_video/JobRegistryTest.kt` (new), `darwin/compress_video/Sources/compress_video/JobRegistry.swift`, `darwin/compress_video/Sources/compress_video/Compression.swift`, `test/await_compress_result_test.dart` (new)
**Commit:** 4b5b7a9
**Applied fix:** Both `JobRegistry`s now track every job id ever started (`knownJobIds` /
Swift's `knownJobIds`) and every job id whose result has already been delivered once
(`consumedJobIds`), populated at the same point each platform's `startCompress` already
pre-registers a job (`resultDeferredFor`/`registerJob`) and at the point a result is
consumed/delivered (`forgetResult` on Android; both the `resultOutcomes` and `resultWaiters`
delivery paths on Swift). `Compression.awaitCompressResult`/`.swift` check `isConsumedJobId` then
`isKnownJobId` before ever calling the underlying await, throwing a typed `CompressVideoError`
(reason `"unknown"`) with a distinct, diagnosable message for each of the two cases instead of
falling into `getOrPut`/`withCheckedThrowingContinuation`, which previously manufactured a
deferred/continuation nothing would ever complete. The shipped Dart wrapper (`CompressJob._run`)
is unaffected -- it only ever awaits a jobId it always started first, exactly once.

Added a new JVM test file (`JobRegistryTest.kt`, 4 cases) exercising the new
`isKnownJobId`/`isConsumedJobId`/`cancelAll`-reset bookkeeping directly (the same pattern
`ForegroundServiceHostTest` uses to test `Ref` rather than a real `Service`, since `Compression`
itself asserts the main Looper, which throws in this project's plain-JVM unit tests). Added a new
Dart test file (`test/await_compress_result_test.dart`, 2 cases) that installs a fake host API on
the generated `awaitCompressResult` channel (the same channel-mocking technique
`test/thumbnail_api_test.dart` and `test/compress_job_test.dart` already use) replying with the
new typed failure shape, proving the generated `CompressHostApi.awaitCompressResult` proxy
decodes it into a `PlatformException(code: 'unknown')` rather than hanging.

**Verification caveat:** no Swift toolchain is available in this environment (danserver has none
installed, and the MacBook Air over `ssh dans-macbook-air` was unreachable -- connection timed
out -- when probed for this fix). The Swift changes in `JobRegistry.swift`/`Compression.swift`
were therefore verified by careful manual re-reading only (Tier 1: brace/type/actor-isolation
correctness against the surrounding file, matching the already-`@MainActor`-isolated patterns
`completeResult`/`awaitResult` already use) and by mirroring the Kotlin fix's logic closely --
not by an actual `swiftc`/Xcode build. This should be confirmed by CI's macOS/iOS jobs (or a
future run with the Mac reachable) before this finding is considered fully closed on the Apple
side.

### IN-01: `verify_apk_foreground_service_manifest.sh` doesn't check `android:exported="false"` on the merged manifest

**Files modified:** `tool/verify_apk_foreground_service_manifest.sh`
**Commit:** 0b8ed88
**Applied fix:** Added an `awk`-based block-isolation step that extracts the
`ForegroundServiceHost` `<service>` element's own attribute lines (bounded by the next `E: `
line in `aapt2 dump xmltree`'s output) before checking `foregroundServiceType` and the new
`android:exported="false"` assertion against that isolated block -- rather than grepping the
whole merged manifest, which declares several other services/providers that are also
`exported=false` and could have let an unscoped check pass even if this specific service's own
attribute were wrong or missing.

Deviated from the review's suggested implementation: the review's Fix text speculated the
exported attribute would render as hex `0x0` in `aapt2 dump xmltree` output; running the
updated script against the project's real, currently-built debug APK (`example/build/app/
outputs/flutter-apk/app-debug.apk`, via the already-installed Android SDK/`aapt2` on this box)
showed `aapt2` actually renders it as the literal token `false`/`true`, so the check matches
that instead. Also verified negatively: a synthetic manifest fragment with `exported=true` for
the ForegroundServiceHost block (and a sibling node's real `exported=false` attribute alongside
it) correctly fails the isolated check while the sibling's `exported=false` is correctly ignored,
proving the block-isolation logic has teeth and cannot be satisfied by the wrong node's
attribute. `bash -n` syntax-checked; the full script re-run against the real APK passes.

## Skipped Issues

None -- all four findings in scope were fixed.

---

_Fixed: 2026-09-27T18:15:11Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
