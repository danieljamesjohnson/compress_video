---
phase: 2
slug: android-compression-on-media3
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-09-15
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Dart `flutter_test` (unit) + Gradle `testDebugUnitTest` on the JUnit 5 platform (native unit, already configured in `android/build.gradle.kts`) + `flutter test integration_test` on `emulator-5554` (e2e) — all three already wired by Phase 1, this phase only adds test files and CI steps to the existing pattern |
| **Config file** | `android/build.gradle.kts` (its `testOptions.unitTests.all` block enabling the JUnit 5 platform, already present) |
| **Quick run command** | `flutter test` (root Dart unit tests, seconds) + `cd example/android && ./gradlew :compress_video:testDebugUnitTest` (native unit tests, seconds) |
| **Full suite command** | `cd example && flutter test integration_test` on `emulator-5554` (minutes) |
| **Estimated runtime** | Quick: seconds. Full: a single compression integration case is budgeted 10–15 s (the API 35 x86_64 emulator's only H.264 encoder, `c2.android.avc.encoder`, is software-only; measured `measured-frame-rate-1920x1080-range = "44-49"` in 02-RESEARCH.md). The full suite (~15–20 cases across this phase plus Phase 1's two suites) is budgeted 3–5 minutes of emulator wall-clock. |

---

## Sampling Rate

- **After every task commit:** Run `flutter test` + `cd example/android && ./gradlew :compress_video:testDebugUnitTest`
- **After every plan wave:** Run `cd example && flutter test integration_test` on `emulator-5554`
- **Before `/gsd-verify-work`:** Full emulator suite green, plus the APK native-lib/zipalign check (02-07)
- **Max feedback latency:** 15 seconds for a single emulator integration case (not the template's 2-second default) — the software H.264 encoder on this emulator has no hardware acceleration, so a real encode of even a short corpus clip takes several seconds; 2 seconds is not achievable for any test that actually encodes video on this device.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 1 | CORE-05, CORE-08 | T-02-02 | Every new corpus clip self-asserts its own structural properties (bitrate, fps, coded dims, rotation matrix, size cap) before being accepted; a clip that came out wrong fails the script naming itself, never reaches the corpus | cli | `bash corpus/generate_corpus.sh && sha256sum corpus/*.mp4 > /tmp/corpus-run1.txt && bash corpus/generate_corpus.sh && sha256sum corpus/*.mp4 > /tmp/corpus-run2.txt && diff /tmp/corpus-run1.txt /tmp/corpus-run2.txt` | ✅ | ⬜ pending |
| 2-01-02 | 01 | 1 | ORNT-01 | T-02-01 | `verify_corpus.sh` re-derives every sidecar (including the new `edgeProbe` block) from the committed clip and fails on any drift; sidecars are never hand-edited | cli | `bash corpus/verify_corpus.sh && bash corpus/sync_to_example.sh && git diff --exit-code example/assets/corpus && cd example && flutter pub get` | ✅ | ⬜ pending |
| 2-01-03 | 01 | 1 | — | — | N/A | cli | `test -s .planning/phases/02-android-compression-on-media3/COVERAGE.md && test "$(grep -c '{' .planning/phases/02-android-compression-on-media3/02-VALIDATION.md)" = "0" && test "$(awk '/^\| Task ID/,/^$/' .planning/phases/02-android-compression-on-media3/02-VALIDATION.md \| grep -c '^\| 2-0')" = "21"` | ✅ | ⬜ pending |
| 2-02-01 | 02 | 2 | CORE-03 | — | Typed contract (`CompressRequestMessage`/`CompressResultMessage`/`EstimateMessage`) regenerates deterministically into Dart/Kotlin/Swift; the 9-value error taxonomy replaces any ad hoc reason string | unit | `dart run pigeon --input pigeons/messages.dart && dart format lib/src/messages.g.dart && git diff --exit-code -- pigeons/messages.dart lib/src/messages.g.dart android/src/main/kotlin/com/danjjohnson/compress_video/Messages.g.kt darwin/compress_video/Sources/compress_video/Messages.g.swift && flutter analyze --fatal-infos --fatal-warnings && flutter test` | ✅ | ⬜ pending |
| 2-02-02 | 02 | 2 | CORE-02, CORE-03 | — | `CompressOptions.validate()` rejects every invalid combination with `unsupportedInput` before the channel is touched; no message reaches the channel on a rejection | unit | `flutter analyze --fatal-infos --fatal-warnings && flutter test` | ❌ W0 | ⬜ pending |
| 2-02-03 | 02 | 2 | CORE-02, CORE-03, JOBS-01, BULD-01 | T-02-04 / T-02-05 / T-02-06 / T-02-07 / T-02-08 / T-02-SC | `jobId` validated against the digit-hyphen-hex pattern before use as a filename stem; input validated read-only before any codec touches it; every terminal outcome replies with a typed error, never a rethrow; output confined to the plugin cache directory; input file never mutated; the four new media3 deps are first-party Google Maven artifacts, manually audited | integration | `cd example && flutter test integration_test/compress_test.dart -d emulator-5554` | ❌ W0 | ⬜ pending |
| 2-03-01 | 03 | 3 | CORE-02, CORE-08 | T-02-09, T-02-12 | `SizeGuard` caps the effective long side and video bitrate at the input's own; both output dimensions round down to even with a 16px floor; pure JVM code, no platform import | unit | `cd example/android && ./gradlew :compress_video:testDebugUnitTest` | ❌ W0 | ⬜ pending |
| 2-03-02 | 03 | 3 | CORE-02, CORE-08 | T-02-09 | The engine reads one resolved plan from `SizeGuard` rather than computing its own scaling arithmetic; the frame-rate cap uses `FrameDropEffect`, never the still-image frame-rate setter | integration | `cd example && flutter test integration_test/compress_test.dart -d emulator-5554` | ✅ | ⬜ pending |
| 2-03-03 | 03 | 3 | CORE-02 | T-02-10, T-02-11 | Every `CompressOptions.validate()` rejection is mirrored in `Arguments.kt` as the native authority, so a caller reaching the generated host API directly gets the same typed rejection | unit+integration | `flutter test && cd example && flutter test integration_test/compress_test.dart -d emulator-5554 && cd android && ./gradlew :compress_video:testDebugUnitTest` | ✅ | ⬜ pending |
| 2-04-01 | 04 | 4 | CORE-05 | T-02-13, T-02-14, T-02-15 | The pre-check skips an encode that would not help; the post-check substitutes the original on the real byte count, never the prediction; substitution always copies into the plugin's own cache directory, never returns the caller's input path | integration | `cd example && flutter test integration_test/compress_test.dart -d emulator-5554` | ✅ | ⬜ pending |
| 2-04-02 | 04 | 4 | CORE-06 | T-02-14 | `transmuxed` is read from the export result's own per-track conversion-process fields, never re-derived by a second prober; the composition-level transmux flags are never set | integration+unit | `cd example && flutter test integration_test/compress_test.dart -d emulator-5554 && cd android && ./gradlew :compress_video:testDebugUnitTest` | ✅ | ⬜ pending |
| 2-04-03 | 04 | 4 | CORE-02 | T-02-16 | `doc/PRESETS.md` numbers are measured on this phase's corpus on this device, not copied from memory, the seed constants, or the incumbent | other | `cd example && flutter test integration_test/compress_test.dart -d emulator-5554 && cd .. && test -s doc/PRESETS.md && dart pub publish --dry-run` | ❌ W0 | ⬜ pending |
| 2-05-01 | 05 | 5 | AUDO-01, AUDO-02 | T-02-17, T-02-18, T-02-19 | Audio bitrate is clamped into the device AAC encoder's 8000–960000 range before it reaches encoder settings; channel changes go through `ChannelMixingAudioProcessor`, never hand-rolled sample math; `audioReencoded` is read from the export result, never the request | integration | `cd example && flutter test integration_test/compress_audio_test.dart -d emulator-5554` | ❌ W0 | ⬜ pending |
| 2-05-02 | 05 | 5 | ORNT-01 | T-02-20 | No hand-rolled rotation math — the platform rotates portrait video and writes the metadata, and the existing re-probe path reads it; trim uses Media3's `ClippingConfiguration` with a validated start-before-end range | integration+unit | `cd example && flutter test integration_test/compress_test.dart -d emulator-5554 && cd android && ./gradlew :compress_video:testDebugUnitTest` | ❌ W0 | ⬜ pending |
| 2-05-03 | 05 | 5 | AUDO-02 | T-02-17 | Every audio boundary (bitrate, channel count) is rejected or clamped identically in `CompressOptions.validate()` and the native `Arguments.kt` mirror | unit+integration | `flutter test && cd example && flutter test integration_test/compress_audio_test.dart -d emulator-5554 && cd android && ./gradlew :compress_video:testDebugUnitTest` | ✅ | ⬜ pending |
| 2-06-01 | 06 | 6 | JOBS-01 | T-02-24 | Progress events are routed by exact job id; an event for an unknown id is dropped without throwing; no code path in this task writes to the platform log | unit+integration | `flutter test test/compress_job_test.dart && cd example && flutter test integration_test/compress_jobs_test.dart -d emulator-5554` | ❌ W0 | ⬜ pending |
| 2-06-02 | 06 | 6 | JOBS-02 | T-02-23, T-02-25 | `cancel()` is a registry lookup by exact id; an unknown or already-terminal id is a successful no-op that touches no file; the engine-detach callback cancels every live job and deletes every partial file before clearing registration | integration+unit | `cd example && flutter test integration_test/compress_jobs_test.dart -d emulator-5554 && cd android && ./gradlew :compress_video:testDebugUnitTest` | ✅ | ⬜ pending |
| 2-06-03 | 06 | 6 | CORE-04 | T-02-21, T-02-22 | Every one of the 22 `ExportException` codes maps to a typed reason through one pure function that preserves the original code as detail; a pre-flight `StatFs` check rejects with `outOfSpace` before a Transformer is built; no failure path logs or leaves a partial file | unit+integration | `cd example/android && ./gradlew :compress_video:testDebugUnitTest && cd .. && flutter test integration_test/compress_jobs_test.dart -d emulator-5554` | ❌ W0 | ⬜ pending |
| 2-07-01 | 07 | 7 | INFO-03 | — | `estimate()` calls the same `SizeGuard` resolver the compress path uses and builds no Transformer, decodes no frame — estimate and compress can never disagree about which path a job will take | integration+unit | `cd example && flutter test integration_test/compress_output_test.dart -d emulator-5554` | ❌ W0 | ⬜ pending |
| 2-07-02 | 07 | 7 | CORE-09 | T-02-26, T-02-27, T-02-28 | `clearCache()` sweeps only the immediate contents of the plugin's own cache subdirectory, resolving each candidate's canonical path and skipping anything not inside it (no recursion, no symlink escape), and skips any file a live job still owns | integration | `cd example && flutter test integration_test/compress_output_test.dart -d emulator-5554 && flutter test integration_test/thumbnail_test.dart -d emulator-5554` | ✅ | ⬜ pending |
| 2-07-03 | 07 | 7 | BULD-01 | T-02-29, T-02-30 | `tool/verify_apk_native_libs.sh` enumerates every native library in the shipped APK against an explicit allowlist and fails on anything unexpected, then runs the platform's 16 KB page-alignment check; CI runs the same script | other | `cd example && flutter build apk --debug && cd .. && bash tool/verify_apk_native_libs.sh && cd example && flutter test integration_test -d emulator-5554` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Row count note:** this table has 21 rows, not the 20 the plan's `must_haves`/`acceptance_criteria` state. The plan's own task enumeration ("ids `2-01-01` through `2-01-03` ... `2-07-01` through `2-07-03`") is 7 plans × 3 tasks = 21, and an independent `for f in 02-01-PLAN.md 02-02-PLAN.md 02-03-PLAN.md 02-04-PLAN.md 02-05-PLAN.md 02-06-PLAN.md 02-07-PLAN.md; do grep -cE '^\s*<task type=' "$f"; done` count over the real plan files also returns 3 for every one of the seven plans (21 total). This is the same class of authoring off-by-one already recorded for Phase 1 in `01-01-SUMMARY.md` (that one undercounted by one; this one overcounts the stated target by one) — documented as a plan-text deviation in `02-01-SUMMARY.md`, not silently forced to match the wrong number by dropping a real task's row.

---

## Wave 0 Requirements

Test infrastructure created inside this phase, none of which exists yet as of this plan (02-01):

- [ ] `example/integration_test/compress_test.dart` — compression integration suite (CORE-02/03/05/06/08/09, ORNT-01)
- [ ] `example/integration_test/compress_audio_test.dart` — audio integration suite (AUDO-01/02)
- [ ] `example/integration_test/compress_jobs_test.dart` — jobs/cancel/error integration suite (JOBS-01/02, CORE-04)
- [ ] `example/integration_test/compress_output_test.dart` — estimate/output-placement/clearCache integration suite (INFO-03, CORE-09)
- [ ] `android/src/test/kotlin/com/danjjohnson/compress_video/SizeGuardTest.kt` — native unit coverage of the pure resolver (CORE-02/05/06/08, INFO-03)
- [ ] `android/src/test/kotlin/com/danjjohnson/compress_video/ErrorMappingTest.kt` — table-driven coverage of all 22 export error codes (CORE-04)
- [ ] `test/compress_options_test.dart` (Dart) — `CompressOptions` validation rejection suite (CORE-02, AUDO-02)
- [ ] `test/compress_job_test.dart` (Dart) — platform-free job identity and stream-lifecycle suite (JOBS-01)
- [ ] `android/src/test/kotlin/com/danjjohnson/compress_video/EffectOrderTest.kt` — pinned video-effects-list order (ORNT-01)
- [ ] `tool/measure_presets.dart` + `doc/PRESETS.md` — the measurement harness and its generated preset table (CORE-02)
- [ ] `tool/verify_apk_native_libs.sh` — native-library allowlist and 16 KB alignment check, wired into CI (BULD-01)

---

## Manual-Only Verifications

None. Every acceptance criterion in this phase is provable on the local emulator (`emulator-5554`) or by a JVM/Dart unit test — see the Per-Task Verification Map above.

Separately, and not a gate for this phase: GitHub Actions CI is blocked on an account billing/spending-limit issue (`QUESTIONS.md` #6). Plan 02-07 wires the native-library and integration-suite CI steps regardless; a CI run refused for billing is recorded there as an external blocker, never as a task failure, and the local emulator plus the local `tool/verify_apk_native_libs.sh` script remain this phase's actual gate.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 15s (the documented, device-realistic bound — see Sampling Rate above; the template's 2s default is not achievable for a test that runs a real software H.264 encode)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
