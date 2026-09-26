---
phase: 4
slug: codecs-hdr-and-hard-inputs
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-09-25
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Dart `flutter_test` (root unit tests, run on danserver) + Gradle `testDebugUnitTest` (Android JVM unit) + XCTest via `xcodebuild test` on the CI macOS runner (Apple native unit, one byte-identical source file per platform) + `flutter test integration_test -d emulator-5554` (Android e2e, whole directory in one process) + `tool/run_ios_integration_suites.sh <udid\|macos>` (iOS simulator and macOS desktop e2e, one process per suite behind a launch watchdog) + `corpus/verify_corpus.sh` and `tool/check_parity_test.sh` (shell gates) |
| **Config file** | `android/build.gradle.kts` for the Android JVM unit tests; the `Runner` scheme in `example/ios/Runner.xcworkspace` and `example/macos/Runner.xcworkspace` for XCTest; `.github/workflows/ci.yml` for every Apple execution, since the MacBook Air was unreachable at planning time (probe timed out) and CI is the Apple verifier |
| **Quick run command** | `flutter analyze --fatal-infos --fatal-warnings && flutter test` (seconds on danserver) plus `cd android && ./gradlew :compress_video:testDebugUnitTest` for the capability-probe and `SizeGuard` changes |
| **Full suite command** | `cd example && flutter test integration_test -d emulator-5554` locally, plus an observed CI run whose `Android`, `Apple` and `Cross-platform parity` jobs all conclude `success` |
| **Estimated runtime** | Quick: seconds. Android emulator directory: 5–10 minutes with the new suite (the 4K60 case is the long pole, bounded at 120 s per test). Apple: 60–100 minutes per pushed run across the split simulator and macOS steps — budget three pushed attempts per Apple-touching plan. |

---

## Sampling Rate

- **After every task commit:** `flutter analyze --fatal-infos --fatal-warnings && flutter test`, plus the Android native unit tests whenever Kotlin changed, plus `bash corpus/verify_corpus.sh` whenever anything under `corpus/` changed.
- **After every plan:** the plan's own automated command from the map below, then the whole `flutter test integration_test -d emulator-5554` directory on the booted emulator.
- **Before `/gsd-verify-work 4`:** a CI run green on all four jobs with the new suite passing on the Android emulator, the iOS simulator and the macOS host; `bash tool/check_parity_test.sh` and `bash tool/run_ios_integration_suites_test.sh` green; `doc/HARDWARE_CHECKLIST.md` present, internally consistent and honestly marked as not yet run.
- **Max feedback latency:** seconds for the Dart and JVM layers; roughly 3–10 minutes for an Android emulator integration case that performs a real encode; 60–100 minutes for anything that can only be observed on an Apple runner. A shorter Apple bound is not achievable and stating one would hide when feedback really is slow.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 4-01-01 | 01 | 1 | TEST-01 | T-04-01, T-04-02, T-04-03 | The generation and sidecar scripts write only inside their own directory using relative names, the mirror verifies each copy by sha256, and the drift gate re-derives every sidecar so a hand-edited fixture cannot pass | cli+integration | `bash corpus/generate_corpus.sh && bash corpus/verify_corpus.sh --write && bash corpus/verify_corpus.sh && bash corpus/sync_to_example.sh && cd example && flutter test integration_test/hard_inputs_test.dart -d emulator-5554` | ❌ W0 | ⬜ pending |
| 4-01-02 | 01 | 1 | TEST-01 | T-04-01, T-04-02, T-04-03, T-04-04 | Each new fixture self-asserts its structural properties before the script declares success, and every clip is synthetic lavfi output carrying no host or user data | cli+integration | `bash corpus/generate_corpus.sh && bash corpus/verify_corpus.sh && cd example && flutter test integration_test/hard_inputs_test.dart -d emulator-5554` | ❌ W0 | ⬜ pending |
| 4-01-03 | 01 | 1 | TEST-01 | T-04-05, T-04-06 | Each split CI step writes its own log so no step can silently discard another's parity lines, and no timeout is raised to absorb the seventh suite | cli+ci | `bash -n tool/run_ios_integration_suites.sh && bash tool/run_ios_integration_suites_test.sh && gh run list --limit 3` | ❌ W0 | ⬜ pending |
| 4-02-01 | 02 | 2 | CDEC-02 | T-04-07, T-04-10 | The tone-map result flag is computed from the export's own output colour info behind a `!usedOriginal` guard, so it describes the delivered file rather than the request, and every new branch funnels through the existing typed-error boundary | integration | `flutter analyze --fatal-infos --fatal-warnings && flutter test && cd example && flutter test integration_test/hard_inputs_test.dart -d emulator-5554` | ❌ W0 | ⬜ pending |
| 4-02-02 | 02 | 2 | CDEC-02 | T-04-07, T-04-08, T-04-09 | The fallback is exactly two attempts, gated so a cancellation stays terminal and an ordinary failure is never retried, each attempt builds fresh state and the first attempt's temp file is deleted before the second starts | integration | `flutter analyze --fatal-infos --fatal-warnings && flutter test && cd example && flutter test integration_test -d emulator-5554` | ❌ W0 | ⬜ pending |
| 4-02-03 | 02 | 2 | AUDO-03 | T-04-10, T-04-11 | A more-than-stereo track can no longer take the remux fast path, the forced downmix target is an engine-side constant rather than the source's own unsuitable bitrate, and the produced file's real channel count is read from its own descriptor | unit+integration | `cd android && ./gradlew :compress_video:testDebugUnitTest && cd ../example && flutter test integration_test -d emulator-5554` | ❌ W0 | ⬜ pending |
| 4-03-01 | 03 | 3 | CDEC-01 | T-04-12, T-04-13, T-04-14 | The accepted-string set widens by exactly two values on both host validators, the hardware decision uses the platform's own accelerated flag rather than name matching, and the reported codec is re-probed from the produced file | unit+integration | `flutter analyze --fatal-infos --fatal-warnings && flutter test && cd android && ./gradlew :compress_video:testDebugUnitTest && cd ../example && flutter test integration_test/hard_inputs_test.dart -d emulator-5554` | ❌ W0 | ⬜ pending |
| 4-03-02 | 03 | 3 | CDEC-03 | T-04-14, T-04-15 | The codec gate and the HDR gate are computed from one shared decision so a fallback cannot produce HEVC-but-SDR, and the integration case asserts the codec on the fallback branch rather than only the flags | integration | `flutter analyze --fatal-infos --fatal-warnings && cd example && flutter test integration_test -d emulator-5554` | ❌ W0 | ⬜ pending |
| 4-03-03 | 03 | 3 | CDEC-01, CDEC-03 | T-04-13, T-04-16 | Both capability answers are proven on plain JVM with fabricated encoder lists including a vendor name that must not match, and the documentation states plainly which branch has never executed | unit | `cd android && ./gradlew :compress_video:testDebugUnitTest && cd .. && flutter test test/compress_options_test.dart && dart pub publish --dry-run` | ❌ W0 | ⬜ pending |
| 4-04-01 | 04 | 4 | CDEC-02 | T-04-19 | The Swift validators mirror the Kotlin ones case for case, the shared resolver ports regain parity, and the tone-map reporting is derived from a re-probe of the delivered file | unit+integration | `flutter analyze --fatal-infos --fatal-warnings && diff example/ios/RunnerTests/RunnerTests.swift example/macos/RunnerTests/RunnerTests.swift && gh run list --limit 3` | ❌ W0 | ⬜ pending |
| 4-04-02 | 04 | 4 | CDEC-01, CDEC-03 | T-04-18, T-04-20, T-04-21 | The capability answer is treated as a hint that the writer's own pre-flight check still validates, the bitrate key stays inside the compression-properties dictionary, and the runner's architecture is logged rather than assumed | unit+integration | `diff example/ios/RunnerTests/RunnerTests.swift example/macos/RunnerTests/RunnerTests.swift && git push github HEAD:main && gh run list --limit 3` | ❌ W0 | ⬜ pending |
| 4-04-03 | 04 | 4 | AUDO-03 | T-04-17, T-04-22 | Unusual audio routes through the existing typed-error funnel, the forced downmix never upmixes a mono source, and a rejected settings dictionary fails before any writer session starts | integration | `cd example && flutter test integration_test -d emulator-5554 && cd .. && git push github HEAD:main && gh run list --limit 3` | ❌ W0 | ⬜ pending |
| 4-05-01 | 05 | 5 | TEST-01 | T-04-23, T-04-24 | A case present on only one platform stays fatal, new fields are compared exactly rather than tolerantly, and the gate's teeth are demonstrated once by a deliberately corrupted fixture | cli+ci | `bash tool/check_parity_test.sh && git push github HEAD:main && gh run list --limit 3` | ❌ W0 | ⬜ pending |
| 4-05-02 | 05 | 5 | TEST-01 | T-04-27 | The hardware checklist carries a dated not-yet-run status so an unproven claim stays visible, and no preset number is published without a named source | cli | `test -s doc/HARDWARE_CHECKLIST.md && flutter analyze --fatal-infos --fatal-warnings && dart pub publish --dry-run` | ❌ W0 | ⬜ pending |
| 4-05-03 | 05 | 5 | TEST-01, CDEC-01, CDEC-02, CDEC-03, AUDO-03 | T-04-25, T-04-26 | Requirements are marked only where named evidence exists, and the planning files are hand-edited rather than written by a regex-based tool that has corrupted them before | cli | `flutter analyze --fatal-infos --fatal-warnings && flutter test && bash corpus/verify_corpus.sh && bash tool/check_parity_test.sh && bash tool/run_ios_integration_suites_test.sh && dart pub publish --dry-run && cd example && flutter test integration_test -d emulator-5554` | ❌ W0 | ⬜ pending |

**Row-count self-check.** This table must carry exactly one row per real task across the five
plan files. Verify with:

```bash
awk '/^\| Task ID/,0' .planning/phases/04-codecs-hdr-and-hard-inputs/04-VALIDATION.md | grep -c '^| 4-0'
for f in .planning/phases/04-codecs-hdr-and-hard-inputs/04-0*-PLAN.md; do grep -cE '^[[:space:]]*<name>Task ' "$f"; done | paste -sd+ | bc
```

The two numbers must agree. If they do not, fix the table to match the plans and record which
direction the discrepancy went — that exact off-by-one authoring bug has occurred twice in this
project (01-01 undercounted, 02-01 overcounted) and both times the honest fix was to document it
rather than drop a real task's row.

---

## Wave 0 Gaps

Every row above is marked `❌ W0` because the files that would run those commands do not exist
before this phase:

- [ ] `example/integration_test/hard_inputs_test.dart` — the suite covering CDEC-01, CDEC-02, CDEC-03 and AUDO-03 (created by 04-01, expanded by 04-02 through 04-05)
- [ ] The five new corpus clips and their sidecars, plus the `hdr`, `hdrProbe` and `audio` sidecar blocks (04-01)
- [ ] `android/.../CodecCapabilities.kt` + `CodecCapabilitiesTest.kt` (04-03) and `darwin/.../CodecCapabilities.swift` + its XCTest cases (04-04) — the injectable capability probes that make both answers testable without hardware
- [ ] `doc/HARDWARE_CHECKLIST.md` — TEST-01's hardware half (04-05); a documentation artifact, but its absence is a real Wave 0 gap
