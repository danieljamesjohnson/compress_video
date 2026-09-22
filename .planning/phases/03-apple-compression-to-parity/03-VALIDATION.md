---
phase: 3
slug: apple-compression-to-parity
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-09-22
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Dart `flutter_test` (unit, root and example, runs on Linux) + Gradle `testDebugUnitTest` on the JUnit 5 platform (Android native unit) + XCTest via `xcodebuild test` on the Mac (Apple native unit, one byte-identical source file per platform) + `flutter test integration_test/<suite> -d <simulator udid>` (iOS e2e), `flutter test integration_test -d macos` (macOS desktop e2e) and `flutter test integration_test -d emulator-5554` (Android e2e) |
| **Config file** | `android/build.gradle.kts` for the Android JVM unit tests; the `Runner` scheme in `example/ios/Runner.xcworkspace` and `example/macos/Runner.xcworkspace` for XCTest; `tool/mac_run.sh` (created by plan 01) is the single entry point for every remote Apple run |
| **Quick run command** | `flutter analyze --fatal-infos --fatal-warnings && flutter test` (root, seconds) and, for native math changes, `bash tool/mac_run.sh xctest-ios` (Mac, under a minute once synced) |
| **Full suite command** | `bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test && bash tool/mac_run.sh macos` for the Apple side, plus `cd example && flutter test integration_test -d emulator-5554` for the Android side of every parity comparison |
| **Estimated runtime** | Quick: seconds locally; roughly 30–60 s for an XCTest run once `mac_sync.sh` has pushed the tree. Full: a single compression integration case on the iOS simulator's software H.264 encoder is budgeted 10–20 s, so each Apple platform's full integration directory is budgeted 5–10 minutes of remote wall-clock, and the Android emulator side keeps Phase 2's measured 3–5 minutes. |

---

## Sampling Rate

- **After every task commit:** `flutter analyze --fatal-infos --fatal-warnings && flutter test`, plus `bash tool/mac_run.sh xctest-ios` when a Swift source file changed
- **After every plan wave:** the plan's own automated command from the map below, then the full Apple integration directory on the simulator and on the macOS host, plus the Android emulator suite whenever a parity value moved
- **Before `/gsd-verify-work`:** every integration suite green on all three platforms, an observed CI run with both the `apple` and `parity` jobs successful, `bash corpus/verify_corpus.sh` clean and `bash tool/check_parity_test.sh` green
- **Max feedback latency:** 60 seconds for a single remote Apple integration case — not the template's 3 seconds. The path is danserver → rsync → SSH → simulator boot → a real software H.264 encode; a 3-second bound is not achievable for any test that actually encodes video on a remote host, and stating a fake one would hide when feedback really is slow.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 | 1 | BULD-02 | T-03-01, T-03-02, T-03-05 | The rsync destination on the Mac is a single hard-coded path so `--delete` can never reach outside it; remote commands are built from fixed templates with quoted interpolation; no secret or user path is echoed | cli | `bash -n tool/mac_sync.sh && bash -n tool/mac_run.sh && bash tool/mac_sync.sh && bash tool/mac_run.sh build-ios && bash tool/mac_run.sh build-macos` | ❌ W0 | ⬜ pending |
| 3-01-02 | 01 | 1 | CORE-07 | T-03-03, T-03-04 | The new clip self-asserts its duration, frame rate, coded dimensions, stream count and size cap, and the sidecar derivation refuses a trim range that is not strictly inside the measured duration | cli | `bash corpus/generate_corpus.sh && sha256sum corpus/*.mp4 > /tmp/corpus-t1.txt && bash corpus/generate_corpus.sh && sha256sum corpus/*.mp4 > /tmp/corpus-t2.txt && diff /tmp/corpus-t1.txt /tmp/corpus-t2.txt && bash corpus/verify_corpus.sh && bash corpus/sync_to_example.sh && git diff --exit-code example/assets/corpus corpus` | ❌ W0 | ⬜ pending |
| 3-01-03 | 01 | 1 | — | — | N/A | cli | `test -s .planning/phases/03-apple-compression-to-parity/COVERAGE.md && test "$(awk '/^\| Task ID/,/^$/' .planning/phases/03-apple-compression-to-parity/03-VALIDATION.md \| grep -c '^\| 3-0')" = "$(for f in .planning/phases/03-apple-compression-to-parity/03-0*-PLAN.md; do grep -cE '^[[:space:]]*<name>Task ' "$f"; done \| paste -sd+ \| bc)"` | ✅ | ⬜ pending |
| 3-02-01 | 02 | 2 | CORE-01 | — | The ported resolver imports no media framework, so it is exercisable as plain Swift with no simulator and no file on disk | unit | `bash tool/mac_sync.sh && bash tool/mac_run.sh xctest-ios && diff example/ios/RunnerTests/RunnerTests.swift example/macos/RunnerTests/RunnerTests.swift` | ❌ W0 | ⬜ pending |
| 3-02-02 | 02 | 2 | CORE-01 | — | The transmux headroom comparison stays integer cross-multiplication, so the two engines cannot disagree at the boundary values a float would round differently | unit | `bash tool/mac_sync.sh && bash tool/mac_run.sh xctest-ios && bash tool/mac_run.sh xctest-macos && diff example/ios/RunnerTests/RunnerTests.swift example/macos/RunnerTests/RunnerTests.swift && git diff --exit-code -- android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt android/src/test/kotlin/com/danjjohnson/compress_video/SizeGuardTest.kt` | ❌ W0 | ⬜ pending |
| 3-02-03 | 02 | 2 | CORE-01 | T-03-06, T-03-07, T-03-08, T-03-09 | The cache sweep resolves symlinks and refuses anything outside the resolved cache directory, never recurses, error messages carry a code and no path, and an unmapped platform code fails a size-asserted known-code test instead of degrading silently | unit | `bash tool/mac_sync.sh && bash tool/mac_run.sh xctest-ios && bash tool/mac_run.sh xctest-macos && diff example/ios/RunnerTests/RunnerTests.swift example/macos/RunnerTests/RunnerTests.swift` | ❌ W0 | ⬜ pending |
| 3-03-01 | 03 | 2 | BULD-04 | T-03-11, T-03-13, T-03-SC | The macOS entitlement added is read-only and user-selected rather than a blanket file grant; both new packages carry the flutter.dev publisher tag verified live in research, and the lockfile diff is reviewed | widget+cli | `cd example && flutter pub get && cd .. && flutter analyze --fatal-infos --fatal-warnings && cd example && flutter test && flutter build apk --debug` | ❌ W0 | ⬜ pending |
| 3-03-02 | 03 | 2 | BULD-04 | T-03-10, T-03-12 | Only the picked file's basename and byte size are rendered; a player initialisation failure is a rendered line rather than a throw, and the result card survives it | cli | `flutter analyze --fatal-infos --fatal-warnings && PATH=$HOME/development/flutter-stable/bin:$PATH dart format --output=none --set-exit-if-changed example/lib && cd example && flutter build apk --debug` | ❌ W0 | ⬜ pending |
| 3-03-03 | 03 | 2 | BULD-04 | T-03-10, T-03-12 | The widget suite asserts the basename-only tile, the no-overflow behaviour at a 200-character filename, and the non-throwing playback failure path | widget | `flutter analyze --fatal-infos --fatal-warnings && cd example && flutter test && flutter test integration_test/media_info_test.dart -d emulator-5554` | ❌ W0 | ⬜ pending |
| 3-04-01 | 04 | 3 | CORE-01 | T-03-14, T-03-15, T-03-16, T-03-17, T-03-18 | The job id is pattern-validated before it becomes a filename stem, the input path is symlink-resolved before the asset is opened, every AVFoundation call site wraps its failure into a typed error, the copy loop leaves the MainActor, and no logging call is introduced | integration | `bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test/compress_test.dart --plain-name 'default options produces a'` | ✅ | ⬜ pending |
| 3-04-02 | 04 | 3 | CORE-01 | T-03-19 | Both platform teardown hooks cancel every live job before clearing registrations, and the weaker macOS guarantee is documented in code rather than assumed equivalent | unit | `bash tool/mac_sync.sh && bash tool/mac_run.sh xctest-ios && bash tool/mac_run.sh xctest-macos && diff example/ios/RunnerTests/RunnerTests.swift example/macos/RunnerTests/RunnerTests.swift` | ❌ W0 | ⬜ pending |
| 3-04-03 | 04 | 3 | CORE-01 | — | Every geometry and rate value comes from one resolver call and the writer's settings dictionary is pre-flight validated, so a rejected combination fails at construction rather than mid-encode | integration | `bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test/compress_test.dart --plain-name 'upright' && bash tool/mac_run.sh ios integration_test/compress_test.dart --plain-name 'cap the output frame rate' && bash tool/mac_run.sh macos integration_test/compress_test.dart --plain-name 'upright'` | ✅ | ⬜ pending |
| 3-05-01 | 05 | 4 | CORE-01 | T-03-21 | The export session runs with network-use optimisation off so no header rewrite can pad a short remux past its own input size, and both branches share one completion path | integration | `bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test/compress_test.dart --plain-name 'report transmuxed'` | ✅ | ⬜ pending |
| 3-05-02 | 05 | 4 | CORE-01 | T-03-20, T-03-21, T-03-22 | The substitution copies into the plugin-owned destination and never returns the caller's input path, the post-check is unconditional on real measured bytes, and the rejected temp file is deleted | integration | `bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test/compress_test.dart --plain-name 'copies the original instead of encoding' && bash tool/mac_run.sh ios integration_test/compress_test.dart --plain-name 'never returns a file larger than the' && cd example && flutter test integration_test/compress_test.dart -d emulator-5554` | ✅ | ⬜ pending |
| 3-05-03 | 05 | 4 | CORE-01 | T-03-23 | Passthrough is chosen only after checking the source track's media subtype; anything else falls back to an AAC re-encode and reports it, so no unplayable track can ship | integration | `bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test/compress_audio_test.dart && bash tool/mac_run.sh macos integration_test/compress_audio_test.dart && cd example && flutter test integration_test/compress_audio_test.dart -d emulator-5554` | ✅ | ⬜ pending |
| 3-06-01 | 06 | 5 | CORE-01 | — | Progress is clamped below the terminal value so the single explicit completion signal is the only source of 100, and every forwarded call hops to the main queue | integration | `bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test/compress_jobs_test.dart --plain-name 'exactly one 100'` | ✅ | ⬜ pending |
| 3-06-02 | 06 | 5 | CORE-01 | T-03-24, T-03-28 | The partial file is deleted before the result resolves, cancellation is a registry lookup by exact id with no wildcard match, and cancelling one job leaves the others running | integration | `bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test/compress_jobs_test.dart --plain-name 'cancelling mid-flight' && bash tool/mac_run.sh ios integration_test/compress_jobs_test.dart --plain-name 'cancelling one of three' && bash tool/mac_run.sh macos integration_test/compress_jobs_test.dart --plain-name 'cancelling mid-flight'` | ✅ | ⬜ pending |
| 3-06-03 | 06 | 5 | CORE-01 | T-03-25, T-03-26, T-03-27 | The free-space pre-check runs before any reader or writer exists and falls back when the primary capacity key is unusable; every failure is typed, carries the platform code not a path, and leaves no partial file | integration | `bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test/compress_jobs_test.dart && bash tool/mac_run.sh macos integration_test/compress_jobs_test.dart && cd example && flutter test integration_test/compress_jobs_test.dart -d emulator-5554` | ✅ | ⬜ pending |
| 3-07-01 | 07 | 6 | CORE-07 | T-03-29 | An inverted, zero-length or out-of-range trim is rejected by the Dart validators before the channel and mirrored natively, and the fixture's own sidecar refuses a range outside the measured duration | integration | `bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test/compress_test.dart && bash tool/mac_run.sh macos integration_test/compress_test.dart --plain-name 'trim' && cd example && flutter test integration_test/compress_test.dart -d emulator-5554 --plain-name 'trim'` | ✅ | ⬜ pending |
| 3-07-02 | 07 | 6 | CORE-01 | T-03-30, T-03-31, T-03-32 | An explicit output path must have an existing parent and is symlink-resolved; the cache sweep stays bounded to the plugin's own subdirectory and skips live jobs; the estimate builds no media object | integration | `bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test/compress_output_test.dart && bash tool/mac_run.sh macos integration_test/compress_output_test.dart && bash tool/mac_run.sh ios integration_test/thumbnail_test.dart && cd example && flutter test integration_test/compress_output_test.dart -d emulator-5554` | ✅ | ⬜ pending |
| 3-07-03 | 07 | 6 | CORE-01 | T-03-33 | Every published preset number comes from the measurement harness's own machine-readable output, with the device, date and reproduction command stated, so the table is reproducible rather than asserted | other | `test -s doc/PRESETS.md && grep -q 'simulator' doc/PRESETS.md && grep -q '2992' corpus/README.md && dart pub publish --dry-run && bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test/compress_output_test.dart` | ✅ | ⬜ pending |
| 3-08-01 | 08 | 7 | BULD-02 | T-03-34, T-03-38 | The fresh-app script evaluates no input, runs a fixed build sequence, restores the global package-manager setting and removes its temporary directory on every exit path | cli | `bash -n tool/verify_fresh_app.sh && bash tool/mac_sync.sh && bash tool/mac_run.sh shell 'bash tool/verify_fresh_app.sh --spm-only' && git status --porcelain` | ❌ W0 | ⬜ pending |
| 3-08-02 | 08 | 7 | BULD-02 | T-03-37 | The per-suite timeout bound and the one simulator-reset retry are preserved as the suite list widens, so a real failure stays attributable rather than becoming an unexplained timeout | other | `test "$(grep -c 'Android-only until Phase 3' .github/workflows/ci.yml)" = "0" && grep -q 'verify_fresh_app.sh' .github/workflows/ci.yml && grep -q 'parity-macos' .github/workflows/ci.yml && git push github HEAD:main && gh run list --limit 3` | ✅ | ⬜ pending |
| 3-08-03 | 08 | 7 | CORE-01, CORE-07 | T-03-35, T-03-36 | A missing or empty parity artifact is fatal rather than a match, a key present on only one platform is a failure, and the gate's own self-test proves both directions before it is trusted | cli | `bash tool/check_parity_test.sh && cd example && flutter test integration_test -d emulator-5554 && cd .. && git push github HEAD:main && gh run list --limit 3` | ✅ | ⬜ pending |
| 3-09-01 | 09 | 8 | BULD-04 | T-03-42 | Screenshots are read back and described before commit so nothing unexpected in frame is published, and only the one UAT item this evidence actually closes is marked resolved | manual+cli | `test "$(ls .planning/phases/03-apple-compression-to-parity/*.png 2>/dev/null \| wc -l)" -ge 2 && test "$(grep -c '\[pending\]' .planning/phases/02-android-compression-on-media3/02-UAT.md)" -le 5` | ❌ W0 | ⬜ pending |
| 3-09-02 | 09 | 8 | CORE-01, CORE-07 | T-03-41 | The CI result is read back per job from the API against a recorded run id rather than inferred from a badge or a remembered pass | other | `flutter analyze --fatal-infos --fatal-warnings && flutter test && bash corpus/verify_corpus.sh && bash tool/check_parity_test.sh && dart pub publish --dry-run && bash tool/mac_sync.sh && bash tool/mac_run.sh ios integration_test && bash tool/mac_run.sh macos && cd example && flutter test integration_test -d emulator-5554` | ✅ | ⬜ pending |
| 3-09-03 | 09 | 8 | BULD-02, BULD-04, CORE-01, CORE-07 | T-03-39, T-03-40, T-03-43 | Every requirement row is closed only with its evidence named, every planning-markdown edit is by hand with its diff reviewed, and everything unproven is carried forward in writing | other | `flutter analyze --fatal-infos --fatal-warnings && dart pub publish --dry-run && grep -q 'PRESETS' README.md && test -n "$(git diff --name-only .planning/REQUIREMENTS.md)"` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Row count note:** this table was seeded at plan time with 27 rows, from nine plans of three tasks each. Plan 03-01 task 3 re-counts the real total with `for f in .planning/phases/03-apple-compression-to-parity/03-0*-PLAN.md; do grep -cE '^[[:space:]]*<name>Task ' "$f"; done` and corrects this table to that number if they differ, recording both. Phase 1 and Phase 2 each shipped an off-by-one here because a plan's prose miscounted (01-01 undercounted, 02-01 overcounted), so the counted number is authoritative and the claimed one is not.

---

## Wave 0 Requirements

Test infrastructure created inside this phase, none of which exists as of plan 03-01:

- [ ] `tool/mac_sync.sh` and `tool/mac_run.sh` — the Mac build-host workflow every Apple verification in this phase runs through (03-01)
- [ ] `corpus/trim_source_10s.mp4` and its sidecar `trim` block — without it the phase's own trim criterion cannot be expressed (03-01)
- [ ] `darwin/compress_video/Sources/compress_video/SizeGuard.swift`, `ErrorMapping.swift`, `PluginFiles.swift` — the pure ports, none of which exists yet (03-02)
- [ ] New `SizeGuard`, `ErrorMapping`, `PluginFiles` and `JobRegistry` sections in both `example/ios/RunnerTests/RunnerTests.swift` and `example/macos/RunnerTests/RunnerTests.swift`, kept byte-identical (03-02, 03-04)
- [ ] `darwin/compress_video/Sources/compress_video/CompressionEngine.swift`, `Compression.swift`, `JobRegistry.swift` — the engine itself (03-04)
- [ ] `example/lib/src/compression_runner.dart` and `example/test/main_screen_test.dart` — the seam and the widget suite that let the example screen be tested on Linux with no device (03-03)
- [ ] Platform-guard removal in all four `example/integration_test/compress_*_test.dart` suites, which is what makes them run on Apple at all (03-04, 03-05, 03-06, 03-07)
- [ ] The new 2000 to 7000 ms trim case in `compress_test.dart` (03-07)
- [ ] `tool/verify_fresh_app.sh` — BULD-02's four-build proof (03-08)
- [ ] `PARITY_JSON` emission in the four compression suites plus the extended `tool/check_parity.sh` and `tool/check_parity_test.sh` (03-08)
- [ ] The widened `apple` job and the two-comparison `parity` job in `.github/workflows/ci.yml` (03-08)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| The example app's visual behaviour on a real display — progress advancing, the result card's fields, cancel returning the controls to idle | BULD-04 | No automated assertion can confirm that a rendered screen is legible and behaves as the design contract describes; this is also what 02-UAT.md item 6 has been waiting for | Plan 03-09 task 1: launch the example app on the booted iOS simulator and on the macOS host, drive pick → compress → cancel → compress → play, capture screenshots of the compressing and done states, commit them into this phase directory, read them back and describe them, and mark 02-UAT.md item 6 resolved with a reference to the committed files |

Everything else in this phase is automated. Where a behaviour has no corpus fixture — a non-AAC audio source for the passthrough fallback, and a genuine decoder-unavailable failure — it is carried forward as an explicitly unproven branch in the owning plan's summary rather than claimed by a manual check nobody can repeat.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s (the documented, environment-realistic bound — see Sampling Rate; the template's 3s default is not achievable for a remote Apple run that performs a real software H.264 encode)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
