---
phase: 01-typed-contract-ci-and-media-info
plan: 04
subsystem: media-info
tags: [pigeon, kotlin, media3-adjacent, mediametadataretriever, android-emulator, ci, coroutines]

# Dependency graph
requires:
  - phase: 01-01
    provides: Android SDK + headless KVM emulator on danserver, GitHub remote with read-only Actions token
  - phase: 01-02
    provides: Corpus clips (portrait_rot90, small_480p, noaudio_720p) + ground-truth sidecars (crossPlatform/tolerant split, unsigned-clockwise rotation, displayed dimensions)
  - phase: 01-03
    provides: compress_video plugin package scaffold, shared darwin/ Apple tree, typed error taxonomy (CompressVideoException/CompressVideoErrorReason), green path-gated CI on Linux+macOS
provides:
  - "pigeons/messages.dart: the single source of truth for the wire contract (MediaInfoMessage, ProbeHostApi, ThumbnailHostApi) that every native Probe/Thumbnails implementation in this phase and Phase 2+ builds against"
  - "CompressVideo.getMediaInfo(path): the plugin's first real public call, proven end-to-end Dart -> generated ProbeHostApi client -> Kotlin Probe -> MediaMetadataRetriever/MediaExtractor -> back, on the real Android emulator"
  - "Every INFO-01 field on Android: durationMs, rotation-corrected widthPx/heightPx, rotationDegrees, sizeBytes, normalised videoCodec, videoBitrateBps, frameRateFps, hasAudio, isHdr"
  - "MediaMath.kt and Arguments.kt: pure, unit-testable rotation/codec/rounding logic and centralised input validation, reusable by Thumbnails.kt in plan 01-05"
  - "CI now regenerates and diff-gates the Pigeon contract, runs the plugin's native Gradle unit tests, and runs the Dart integration suite on a real emulator on every push"
affects: [01-05, 01-06, 01-07]

# Actuals (#2632)
actuals:
  tokens: 27331
  tasks: 3
  commits: 7

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pigeon-generated Dart/Kotlin/Swift regenerated via `dart run pigeon` then immediately `dart format` on the generated Dart file -- Pigeon's own generator output is not dart-format-clean, and the repo's global `dart format --set-exit-if-changed` gate requires the committed file to already be formatted. CI's regeneration step now runs the same two commands before diffing, scoped to only the contract's own generated files (not a bare `git diff --exit-code`, which would also catch Flutter's unrelated analysis_options.yaml migrator rewrites)."
    - "Probe.kt: one MediaMetadataRetriever + one MediaExtractor per call, both released in a finally, all work on Dispatchers.IO via a suspend fun -- no shared mutable state, so concurrent calls never cross replies."
    - "Arguments.kt centralises all input validation (blank path, missing/unreadable file, zero-length file, canonicalisation) ahead of any native file API touch; Probe.kt calls it first."
    - "HDR detection gated on Build.VERSION.SDK_INT >= 30 (confirmed live against the 'Added in API level' badges on developer.android.com, not the 24/29 guesses in 01-RESEARCH.md's Open Questions) plus a try/catch; unavailable or unrecognised colour-transfer values map to isHdr=false, never an exception."
    - "example/test/widget_test.dart cannot use pumpAndSettle() once a widget performs real dart:io work (temp file + platform channel) during build: Flutter's offline test binding runs the whole test body inside a FakeAsync zone, and a real async gap that begins in that zone stays in it even if a later tester.runAsync() call tries to rescue it -- only wrapping the *entire* async chain in runAsync from its first await works. Fixed by pumping a bounded number of frames instead of settling to zero scheduled frames (the media-info panel's indeterminate spinner never lets pumpAndSettle converge anyway)."

key-files:
  created:
    - pigeons/messages.dart
    - lib/src/messages.g.dart
    - android/src/main/kotlin/com/danjjohnson/compress_video/Messages.g.kt
    - darwin/compress_video/Sources/compress_video/Messages.g.swift
    - test/messages_contract_test.dart
    - lib/src/media_info.dart
    - android/src/main/kotlin/com/danjjohnson/compress_video/MediaMath.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/Probe.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/MediaMathTest.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/ArgumentsTest.kt
    - test/media_info_mapping_test.dart
    - example/integration_test/media_info_test.dart
  modified:
    - lib/compress_video.dart
    - android/src/main/kotlin/com/danjjohnson/compress_video/CompressVideoPlugin.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/CompressVideoPluginTest.kt
    - example/lib/main.dart
    - example/test/widget_test.dart
    - example/pubspec.yaml
    - pubspec.yaml
    - .github/workflows/ci.yml

key-decisions:
  - "Confirmed live (2026-09-15) against the API-level badges on developer.android.com/reference/android/media/MediaMetadataRetriever: METADATA_KEY_COLOR_TRANSFER/_COLOR_STANDARD/_COLOR_RANGE were all added in API level 30 (Android 11), not the 24/29 secondary-source guesses 01-RESEARCH.md's Open Questions flagged. HDR detection is gated on Build.VERSION.SDK_INT >= 30."
  - "MediaMetadataRetriever.METADATA_KEY_ROTATION does not exist on this Android SDK; the correct constant is METADATA_KEY_VIDEO_ROTATION (confirmed via javap against the android-36 platform jar). 01-RESEARCH.md's Kotlin code example used the wrong name."
  - "Pigeon's generated Dart output is not dart-format-clean. Rather than leave the committed generated file unformatted (which would fail the repo's format gate) or leave the format gate unable to see real drift, both the local workflow and CI's regeneration step now run `dart format lib/src/messages.g.dart` immediately after `dart run pigeon`, and the contract's regeneration diff check is scoped to only its own four files."
  - "example/pubspec.yaml was missing the three corpus *.expected.json sidecars as declared assets (only the .mp4 clips were declared) -- the integration test's own sidecar load failed before ever reaching the platform channel. Added them."
  - "Added `meta: ^1.9.0` as an explicit pubspec dependency: Pigeon's generated messages.g.dart imports package:meta directly, which was previously only a transitive dependency via the flutter SDK -- dart pub publish --dry-run correctly flags any package a library file imports that isn't declared directly."

patterns-established:
  - "Every native probe/thumbnail implementation validates via Arguments.kt before touching any file API, and threading is suspend fun + Dispatchers.IO with retriever/extractor release in a finally -- the shape plan 01-05's Thumbnails.kt and 01-06's Swift side reuse."

requirements-completed: []  # BULD-03, INFO-01 and BULD-05 are all shared with sibling plans still pending in this phase (BULD-03/INFO-01 also declared by 01-06/01-07; BULD-05 also declared by 01-07). The shared-ID gate (#2388) blocks marking any of them Complete until every declaring plan finishes.

coverage:
  - id: D1
    description: "pigeons/messages.dart is the single wire-contract source of truth: MediaInfoMessage (10 unit-suffixed fields, nullable sentinels never 0/\"\"), ProbeHostApi.getMediaInfo, and ThumbnailHostApi's two methods declared in full though unimplemented until 01-05/01-06. Regeneration is byte-identical run to run."
    requirement: "BULD-03"
    verification:
      - kind: unit
        ref: "test/messages_contract_test.dart (2 tests, pin every field name/type at compile time)"
        status: pass
      - kind: other
        ref: "sha256sum before/after a second `dart run pigeon` + `dart format` run over all three generated files -- identical"
        status: pass
      - kind: other
        ref: "grep counts in the plan's own acceptance criteria (ProbeHostApi=1, ThumbnailHostApi=1, @async=3, CompressVideoError present in both native outputs)"
        status: pass
    human_judgment: false
  - id: D2
    description: "CompressVideo.getMediaInfo travels Dart -> generated ProbeHostApi -> Kotlin Probe -> MediaMetadataRetriever/MediaExtractor -> back on the real Android emulator, returning rotation-corrected dimensions (1080x1920 for portrait_rot90.mp4, not the coded 1920x1080) and every INFO-01 field, matching the corpus sidecar ground truth for all three clips."
    requirement: "INFO-01"
    verification:
      - kind: e2e
        ref: "example/integration_test/media_info_test.dart, 9 tests on emulator-5554 (3 clips against sidecars, 4 error cases, 1 concurrency case, 1 non-ASCII-filename case) -- all pass"
        status: pass
      - kind: unit
        ref: "android/src/test/kotlin/.../MediaMathTest.kt + ArgumentsTest.kt, 12 pure-JVM tests (rotation swap at 0/90/180/270 incl. a square coded frame, codec normalisation, half-up rounding at .4/.5, every Arguments rejection path)"
        status: pass
      - kind: unit
        ref: "test/media_info_mapping_test.dart, 8 tests (null-sentinel mapping, full field mapping, all six CompressVideoErrorReason codes, unrecognised-code fallback)"
        status: pass
    human_judgment: false
  - id: D3
    description: "No hand-written channel map remains in lib/; every quantity crossing the channel is a Pigeon-generated field. No android.util.Log or println call exists in any hand-written plugin Kotlin source. Every failure path (blank path, missing file, zero-byte file, non-video file) returns a typed CompressVideoException with the matching reason -- nothing returns null, no raw platform exception escapes."
    verification:
      - kind: other
        ref: "grep -RIl 'MethodChannel' lib/ -> 0 files; grep -Ec 'android.util.Log|println\\(' over CompressVideoPlugin.kt/Probe.kt/MediaMath.kt/Arguments.kt -> 0 (the one hit in the whole android/ tree is inside Pigeon-generated Messages.g.kt's own error-wrapping helper, which formats a stack trace string and never writes to logcat)"
        status: pass
      - kind: e2e
        ref: "integration test error cases: missing path -> fileNotFound, zero-byte/text file -> unsupportedInput, empty string -> unsupportedInput without crossing the platform channel"
        status: pass
    human_judgment: false
  - id: D4
    description: "CI regenerates and diff-gates the Pigeon contract, runs the plugin module's native Gradle unit tests, and runs the Dart integration suite on a real API-35 emulator on every push -- verified on a real green run, not just locally."
    requirement: "BULD-05"
    verification:
      - kind: e2e
        ref: "gh run view 34997517360 -> conclusion success; Android job's 'Regenerate the Pigeon contract...', 'Run Android native unit tests' and 'Run emulator integration tests' steps all completed success; Apple job unaffected and green"
        status: pass
    human_judgment: false

# Metrics
duration: 92min
completed: 2026-09-15
status: complete
---

# Phase 1 Plan 04: Pigeon Contract, End-to-End Media Info and CI Wiring Summary

**Full INFO-01 media-info contract (duration, rotation-corrected dimensions, codec, bitrate, frame rate, audio, HDR) proven end-to-end on the real Android emulator through a Pigeon-generated typed channel, with CI now regenerating the contract, running native unit tests, and running the emulator integration suite on every push.**

## Performance

- **Duration:** 92 min
- **Started:** 2026-09-15T15:35:00Z (approx.)
- **Completed:** 2026-09-15T17:07:00Z
- **Tasks:** 3 completed
- **Files modified:** 21 (13 created, 8 modified)

## Accomplishments
- Wrote `pigeons/messages.dart`: `MediaInfoMessage` (10 unit-suffixed fields, nullable sentinels never `0`/`""`), `ProbeHostApi.getMediaInfo`, and `ThumbnailHostApi`'s two methods declared in full for contract completeness though unimplemented until plans 01-05/01-06. Regeneration verified byte-identical via sha256 across two consecutive runs.
- Wired the whole stack for one clip first (the tracer slice): `CompressVideo.getMediaInfo` (const constructor, injectable `BinaryMessenger`, no singleton) → generated `ProbeHostApi` client → Kotlin `Probe` (suspend fun on `Dispatchers.IO`, `MediaMetadataRetriever` + `MediaExtractor` both released in a `finally`) → real emulator, and confirmed `portrait_rot90.mp4` returns displayed `1080x1920` (rotation-corrected), not the coded `1920x1080` — the exact bug class the incumbent shipped.
- Completed every remaining INFO-01 field: `videoCodec` (normalised via `MediaMath.normalizeCodec`, verified Android's `video/avc` and Apple's `avc1` both map to `h264`), `videoBitrateBps`/`frameRateFps` (read from the video track's own `MediaExtractor` format, never the container's), `hasAudio` (real audio-track scan), `isHdr` (`METADATA_KEY_COLOR_TRANSFER` guarded by `Build.VERSION.SDK_INT >= 30`, confirmed live against Android's own API-level badges, plus a try/catch).
- Added `Arguments.kt`, centralising all input validation (blank path, missing/unreadable/zero-length file, path canonicalisation) ahead of any native file API call — the threat-model mitigation for T-01-08.
- 16 native Gradle unit tests (`MediaMathTest`, `ArgumentsTest`, `CompressVideoPluginTest`), 20 root Dart tests (contract, exception, mapping), and 9 emulator integration tests (3 clips against sidecars, 4 error cases, concurrency, non-ASCII filename) all green.
- Extended CI's `android` job with three new steps after Analyze — Pigeon regeneration + scoped diff gate, the plugin module's `testDebugUnitTest`, and a real `reactivecircus/android-emulator-runner` (API 35, google_apis, x86_64) integration run — and drove the workflow to a real green run (34997517360) after four rounds of CI-only fixes.

## Task Commits

1. **Task 1: Define the Pigeon contract and commit its generated output** - `025546c` (feat)
2. **Task 2: End-to-end media info for one clip — Dart caller to MediaMetadataRetriever and back** - `902f1ba` (feat)
3. **Task 3: Complete the media-info contract, its unit tests, and the CI steps that run them** - `c5b22ab` (feat), `e33722e` (fix — CI), `1829321` (fix — CI), `eb80865` (fix — CI), `8aa8688` (fix — CI)

**Plan metadata:** (this commit, docs)

## Files Created/Modified
- `pigeons/messages.dart` - Wire contract: `MediaInfoMessage`, `ProbeHostApi`, `ThumbnailHostApi`
- `lib/src/messages.g.dart`, `android/.../Messages.g.kt`, `darwin/.../Messages.g.swift` - Pigeon-generated typed clients/servers
- `test/messages_contract_test.dart` - Compile-time field-name/type pin
- `lib/src/media_info.dart` - Hand-written immutable public `MediaInfo` model
- `lib/compress_video.dart` - `CompressVideo` public entry point with `getMediaInfo`
- `android/.../Probe.kt` - `ProbeHostApi` implementation: full INFO-01 field extraction
- `android/.../MediaMath.kt` - Pure rotation swap / codec normalisation / half-up rounding
- `android/.../Arguments.kt` - Pure input validation ahead of any native file API
- `android/.../CompressVideoPlugin.kt` - Registers `Probe` as `ProbeHostApi`; template channel removed
- `android/src/test/kotlin/.../MediaMathTest.kt`, `ArgumentsTest.kt`, `CompressVideoPluginTest.kt` - 16 native unit tests total
- `test/media_info_mapping_test.dart` - Mock-channel mapping/error-taxonomy coverage
- `example/integration_test/media_info_test.dart` - 9 emulator integration tests
- `example/lib/main.dart` - Shows decoded `MediaInfo` for the bundled portrait clip
- `example/pubspec.yaml` - Declares the three sidecar `.expected.json` files as assets
- `pubspec.yaml` - Adds explicit `meta` dependency
- `.github/workflows/ci.yml` - Pigeon regen gate, Gradle unit tests, emulator integration step

## Decisions Made
See `key-decisions` in frontmatter for the full list. Most consequential: the confirmed API level 30 for Android's colour-transfer HDR keys (resolving 01-RESEARCH.md's Open Question 1 with a live source check rather than trusting either secondary-source guess), and formatting the Pigeon-generated Dart file immediately after every regeneration so the repo's global format gate and the contract's own determinism gate can both hold simultaneously.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `MediaMetadataRetriever.METADATA_KEY_ROTATION` does not exist**
- **Found during:** Task 2, first Gradle compile of `Probe.kt`
- **Issue:** 01-RESEARCH.md's Kotlin code example used `METADATA_KEY_ROTATION`, which does not exist on the SDK; the compiler rejected it outright.
- **Fix:** Confirmed the correct constant name (`METADATA_KEY_VIDEO_ROTATION`) via `javap` against the actual android-36 platform jar rather than trusting the research pseudocode, and used it.
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/Probe.kt`
- **Verification:** Gradle build succeeds; emulator integration test passes
- **Committed in:** `902f1ba`

**2. [Rule 3 - Blocking] `example/pubspec.yaml` declared the corpus clips but not their sidecars as assets**
- **Found during:** Task 2, first emulator integration test run
- **Issue:** The integration test's own `rootBundle.loadString('assets/corpus/portrait_rot90.expected.json')` call failed ("asset does not exist") before ever reaching the platform channel, because only the three `.mp4` files were declared as assets, not the `.expected.json` sidecars already mirrored on disk by `corpus/sync_to_example.sh`.
- **Fix:** Added the three `.expected.json` paths to `example/pubspec.yaml`'s `assets:` list.
- **Files modified:** `example/pubspec.yaml`
- **Verification:** Integration test loads the sidecar and passes
- **Committed in:** `902f1ba`

**3. [Rule 3 - Blocking] Pigeon's generated Dart output conflicts with the repo's `dart format` gate**
- **Found during:** Task 3, final plan-level verification pass (`dart format --output=none --set-exit-if-changed .`)
- **Issue:** Pigeon 29.0.1's own Dart generator does not produce `dart format`-clean output (long unwrapped lines, non-idiomatic indentation). The plan's Task 1 committed the raw generated file, which the repo's global format gate then flagged.
- **Fix:** Run `dart format lib/src/messages.g.dart` immediately after every `dart run pigeon` invocation, both locally and in CI's regeneration step. Verified the `[pigeon, format]` sequence is itself deterministic (byte-identical on a second run) so the contract's own regeneration-determinism guarantee is unaffected.
- **Files modified:** `lib/src/messages.g.dart`, `.github/workflows/ci.yml`
- **Verification:** `dart format --output=none --set-exit-if-changed .` exits 0; CI's regeneration step passes on a real run
- **Committed in:** `c5b22ab`

**4. [Rule 3 - Blocking] `lib/src/messages.g.dart` imports `package:meta` without a direct pubspec dependency**
- **Found during:** Task 3, `dart pub publish --dry-run`
- **Issue:** Pigeon's own generated file imports `package:meta/meta.dart` directly. `meta` was only available transitively via the `flutter` SDK dependency, which `dart pub publish` correctly flags as a missing direct dependency for any file a library imports.
- **Fix:** Added `meta: ^1.9.0` to `pubspec.yaml`'s `dependencies:` section.
- **Files modified:** `pubspec.yaml`
- **Verification:** `dart pub publish --dry-run` no longer reports the missing-dependency error
- **Committed in:** `c5b22ab`

**5. [Rule 1 - Bug] CI's Pigeon regeneration diff was unscoped and caught unrelated Flutter migrator drift**
- **Found during:** Task 3, first real CI run of the new regeneration step (34994325208)
- **Issue:** CI's `flutter analyze` (running on the CI runner's newer floating Flutter 3.47.4 vs. the local 3.44.1 pin) triggers Flutter's own project migrator, which rewrites `analysis_options.yaml` (root and `example/`) with an added `exclude:` block before the regeneration step ever runs — the same class of drift the later "Reset files Flutter's own tooling may have rewritten" step exists to paper over for the publish check. An unscoped `git diff --exit-code` failed on that unrelated file, not on any real Pigeon contract mismatch.
- **Fix:** Scoped the diff to only `pigeons/messages.dart` and its three generated outputs.
- **Files modified:** `.github/workflows/ci.yml`
- **Verification:** Second CI run's regeneration step passed
- **Committed in:** `e33722e`

**6. [Rule 1 - Bug] `example/android/gradlew` does not exist on a fresh CI checkout**
- **Found during:** Task 3, second CI run (34994644935)
- **Issue:** `example/android/gradlew` is gitignored by Flutter's own plugin-example template and only exists locally because a prior `flutter build`/`pub get` materialized it. Calling `./gradlew` directly in a fresh CI checkout failed with "No such file or directory".
- **Fix:** Added `flutter build apk --config-only --debug` (generates the Android project files, including the wrapper, without building any artifacts) immediately before the `./gradlew` step.
- **Files modified:** `.github/workflows/ci.yml`
- **Verification:** Third CI run's Gradle step ran successfully
- **Committed in:** `1829321`

**7. [Rule 1 - Bug] The emulator's userdata partition doesn't fit in `ubuntu-latest`'s free disk space**
- **Found during:** Task 3, third CI run (34994973975)
- **Issue:** The emulator crashed at launch: "FATAL | Not enough space to create userdata partition. Available: 4498.95 MB ... need 7372.80 MB." `ubuntu-latest`'s default free space is tight once Flutter, Gradle and the Android SDK/system image are all installed, and the emulator runner's default AVD partition size doesn't fit.
- **Fix:** Added `-partition-size 2048` to `emulator-options` and a step removing large preinstalled toolchains this project never uses (dotnet, the Android NDK — no native `.so` code here — GHC, Boost) to reclaim headroom.
- **Files modified:** `.github/workflows/ci.yml`
- **Verification:** Fourth CI run's disk-space step reported 29GB free (up from the reported 4.5GB shortfall)
- **Committed in:** `eb80865`

**8. [Rule 1 - Bug] The disk-space fix's own deletion list included the hosted toolcache the job still needed**
- **Found during:** Task 3, fourth CI run (34996744085) — a regression introduced by fix #7 above
- **Issue:** Fix #7's deletion list included `$AGENT_TOOLSDIRECTORY` (`/opt/hostedtoolcache`), which is also where `subosito/flutter-action` caches the Flutter SDK and `actions/setup-java` caches the JDK — both already set up earlier in the same job and needed by every step after the deletion. The very next run showed the damage: the SDK manager's package-install calls silently no-op'd and the emulator runner's own pre-launch "kill any stale instance" `adb` call became a fatal step failure instead of the harmless no-op it should be on a fresh runner.
- **Fix:** Removed `$AGENT_TOOLSDIRECTORY` from the deletion list; kept dotnet/NDK/GHC/Boost, which alone comfortably cover the ~2.9GB shortfall fix #7's log reported.
- **Files modified:** `.github/workflows/ci.yml`
- **Verification:** Fifth CI run (34997517360) concluded `success` on both the Android and Apple jobs, with the emulator integration step itself passing
- **Committed in:** `8aa8688`

**9. [Rule 1 - Bug] `example/test/widget_test.dart`'s `pumpAndSettle()` hung indefinitely once `main.dart` gained a widget doing real `dart:io` work**
- **Found during:** Task 3, extending `example/lib/main.dart` to show decoded media info
- **Issue:** Flutter's offline widget-test binding (`flutter test`, not `flutter test integration_test`) runs the whole test body inside a `FakeAsync` zone. `_PortraitMediaInfoState`'s `_loadMediaInfo()` (asset load → temp file write → platform channel call) begins executing during `pumpWidget()`, inside that zone; a later `tester.runAsync()` call cannot rescue an already-in-flight async chain that started in the wrong zone — only wrapping the *entire* chain in `runAsync` from its first `await` works, which isn't practical for a `late final` field initialised during normal widget build. Combined with the media-info panel's indeterminate `CircularProgressIndicator` (which schedules frames forever while its future is pending), `pumpAndSettle()`'s "wait for zero scheduled frames" loop never converged and threw "pumpAndSettle timed out" after a simulated 10 minutes.
- **Fix:** Replaced `pumpAndSettle()` with a bounded number of explicit `pump()` calls, sufficient for the asset-list panel (which only does `rootBundle.load`, no real IO round trip) to render and be asserted on; the media-info panel's own correctness is separately proven by the emulator integration suite.
- **Files modified:** `example/test/widget_test.dart`
- **Verification:** `flutter test` in `example/` passes
- **Committed in:** `902f1ba` (the widget_test.dart fix landed alongside the Task 2 commit, ahead of `main.dart`'s own extension in Task 3, since the test's underlying vulnerability — any real-IO widget hanging pumpAndSettle — was introduced together with `main.dart`'s Task 3 changes; see Files Created/Modified for the exact commit each file landed in)

---

**Total deviations:** 9 auto-fixed (5 bugs, 4 blocking issues). Items 5-8 are consecutive CI-only fix iterations while driving the plan's own required `.github/workflows/ci.yml` steps to a real green run (four CI-fix commits total, at the plan's stated cap).
**Impact on plan:** All auto-fixes were necessary for correctness (rotation constant, asset declaration, publish-dependency validation) or to make the plan's own CI verification step true on a real run (regeneration gate, Gradle wrapper, disk space) rather than only locally. No scope creep — every fix targeted a specific, reproduced failure in this plan's own acceptance criteria or verification block. Item 9's `pumpAndSettle` fix is test-infrastructure-only; it does not affect the shipped plugin or example app behaviour.

## Issues Encountered

Driving the new CI steps to a real green run took five pushed iterations (feat commit `c5b22ab` + four `fix` commits) and roughly 45 minutes of CI wall-clock time across the runs, because each fix could only be verified by re-running the actual GitHub Actions workflow (emulator boot + Gradle cold-download times of 10-14 minutes per attempt). This is fully accounted for in the Deviations section above; no CI failure mode was left unresolved.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The Pigeon contract (`pigeons/messages.dart`) is the fixed wire shape every remaining native implementation in this phase builds against: `ThumbnailHostApi` is already declared in full, so plan 01-05 (Android thumbnails) and plan 01-06 (Apple probe + thumbnails) implement against a contract that will not need to change.
- `MediaMath.kt` and `Arguments.kt` are written as reusable pure logic; plan 01-05's `Thumbnails.kt` is expected to call `Arguments.requireReadableMediaFile` the same way `Probe.kt` does.
- CI now runs a real Android emulator integration suite on every push (in addition to the Apple job's iOS simulator/macOS builds), so plan 01-05/01-06's thumbnail tests will be caught by the same gate this plan just wired.
- `BULD-03`, `INFO-01` and `BULD-05` remain unchecked in `REQUIREMENTS.md` — all three are shared with sibling plans still pending (01-06/01-07 for `BULD-03`/`INFO-01`; 01-07 for `BULD-05`); the shared-ID gate correctly blocks marking any of them `Complete` until every declaring plan finishes.
- Ready for `01-05-PLAN.md` (Android thumbnails), the next wave in this phase.

---
*Phase: 01-typed-contract-ci-and-media-info*
*Completed: 2026-09-15*

## Self-Check: PASSED

- FOUND: all 13 created files and all 8 modified files listed above (verified with `[ -f ]`)
- FOUND commits: 025546c, 902f1ba, c5b22ab, e33722e, 1829321, eb80865, 8aa8688 (all present in `git log --oneline --all`)
- Re-ran plan-level verification after all fixes: `dart run pigeon --input pigeons/messages.dart` twice + `dart format lib/src/messages.g.dart` -> byte-identical (sha256), working tree clean against committed state
- `flutter test` (root, 20/20 pass), `flutter analyze --fatal-infos --fatal-warnings` (root and example/, both clean), `dart format --output=none --set-exit-if-changed .` (0 changed)
- `example/test/widget_test.dart` (1/1 pass), `bash corpus/verify_corpus.sh` (no drift)
- `example/integration_test/media_info_test.dart` on `emulator-5554`: 9/9 pass (re-run after the `main.dart` extension and formatting fixes)
- `example/android && ./gradlew :compress_video:testDebugUnitTest`: 16/16 pass
- `grep -RIl 'MethodChannel' lib/` -> 0 files; `android.util.Log|println(` -> 0 in every hand-written plugin Kotlin source
- Latest CI run (34997517360) conclusion: `success` — Android job's Pigeon regeneration, Gradle unit tests and emulator integration steps all `completed success`; Apple job unaffected and green
- `git status --short` clean at every commit boundary
