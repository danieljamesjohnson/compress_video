---
phase: 1
slug: typed-contract-ci-and-media-info
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-15
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Dart `flutter_test` (unit) + `integration_test` (emulator/simulator) + JUnit 5 with Mockito (Android native unit) + XCTest (Apple native unit) |
| **Config file** | `analysis_options.yaml` + `test/` + `example/integration_test/` + `android/src/test/kotlin/` + `example/{ios,macos}/RunnerTests/` — all created in plan 01-03 / 01-04 |
| **Quick run command** | `flutter test` |
| **Full suite command** | `.github/workflows/ci.yml` — the `android` job (Dart unit + Gradle unit + emulator integration) and the `apple` job (XCTest + iOS-simulator integration + macOS build) both green |
| **Estimated runtime** | quick ~20 s local; full ~25 min in CI |

---

## Sampling Rate

- **After every task commit:** Run `flutter test`
- **After every plan wave:** Run the full CI workflow on the pushed ref, checked with `gh run watch`
- **Before `/gsd-verify-work`:** Both CI jobs green on the phase's final commit
- **Max feedback latency:** 20 s locally (`flutter test`), ~25 min for the full suite

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | BULD-05 | T-01-01 / T-01-02 | SDK archive checksum verified before unzip; sudo limited to apt + usermod | cli | `flutter doctor -v` + `adb devices` | ✅ | ⬜ pending |
| 1-01-02 | 01 | 1 | BULD-05 | T-01-03 | Repo created private; default workflow token read-only | cli | `gh repo view --json visibility` | ✅ | ⬜ pending |
| 1-01-03 | 01 | 1 | BULD-05 | — | N/A | cli | `grep -q 'Verified on' docs/TOOLCHAIN.md` | ✅ | ⬜ pending |
| 1-02-01 | 02 | 1 | INFO-01 | T-01-04 | ffmpeg runs only on locally generated input | cli | `bash corpus/generate_corpus.sh && ffprobe ...` | ✅ | ⬜ pending |
| 1-02-02 | 02 | 1 | INFO-01, INFO-02 | T-01-05 | Sidecars regenerated from the committed clips, never hand-edited | cli | `bash corpus/verify_corpus.sh` | ✅ | ⬜ pending |
| 1-03-01 | 03 | 2 | BULD-03 | T-01-06 | Dependency pins from the verified legitimacy audit | unit | `flutter test test/compress_video_exception_test.dart` | ✅ | ⬜ pending |
| 1-03-02 | 03 | 2 | BULD-03 | T-01-07 | `.pubignore` keeps planning + corpus out of the published package | cli | `dart pub publish --dry-run` | ✅ | ⬜ pending |
| 1-03-03 | 03 | 2 | BULD-05 | T-01-SC, T-01-17 | Actions pinned to major tags; `permissions: contents: read` | ci | `gh run view <id> --json conclusion` | ✅ | ⬜ pending |
| 1-04-01 | 04 | 3 | BULD-03 | T-01-06 | Typed contract replaces untyped channel maps | unit | `flutter test test/messages_contract_test.dart` | ✅ | ⬜ pending |
| 1-04-02 | 04 | 3 | INFO-01 | T-01-08, T-01-09 | Path validated; decoder failure mapped to a typed reason | integration | `cd example && flutter test integration_test/media_info_test.dart` | ✅ | ⬜ pending |
| 1-04-03 | 04 | 3 | INFO-01, BULD-05 | T-01-10 | No file path or metadata written to the platform log | unit+integration | `./gradlew :compress_video:testDebugUnitTest` + `flutter test integration_test` | ✅ | ⬜ pending |
| 1-05-01 | 05 | 4 | INFO-02 | T-01-11, T-01-13 | outputPath canonicalised; maxDimensionPx bounded | integration | `cd example && flutter test integration_test/thumbnail_test.dart` | ✅ | ⬜ pending |
| 1-05-02 | 05 | 4 | INFO-02 | T-01-12 | Thumbnail files land in the app-private cache directory | integration | `cd example && flutter test integration_test/thumbnail_test.dart` | ✅ | ⬜ pending |
| 1-05-03 | 05 | 4 | INFO-02 | T-01-11 | Argument validation unit-tested on pure Kotlin | unit | `./gradlew :compress_video:testDebugUnitTest` | ✅ | ⬜ pending |
| 1-06-01 | 06 | 4 | INFO-01 | T-01-14, T-01-15 | No force-unwrap on AVFoundation optionals | unit | `xcodebuild test` (apple CI job) | ✅ | ⬜ pending |
| 1-06-02 | 06 | 4 | INFO-02 | T-01-14, T-01-16 | Thumbnail writes confined to the caches directory | unit | `xcodebuild test` (apple CI job) | ✅ | ⬜ pending |
| 1-06-03 | 06 | 4 | INFO-01, INFO-02 | T-01-15 | Pure-logic parity with Android asserted by XCTest | unit | `xcodebuild test` (apple CI job) | ✅ | ⬜ pending |
| 1-07-01 | 07 | 5 | BULD-05 | T-01-18 | Third-party actions pinned to reviewed major tags | ci | `gh run view <id> --json conclusion,jobs` | ✅ | ⬜ pending |
| 1-07-02 | 07 | 5 | INFO-01, INFO-02 | T-01-19 | CI logs carry no absolute user paths or secrets | ci | `gh run view <id> --log` + `gh run view --json conclusion` | ✅ | ⬜ pending |
| 1-07-03 | 07 | 5 | BULD-03, BULD-05 | — | N/A | cli | `grep -c 'nyquist_compliant: true' 01-VALIDATION.md` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

All test infrastructure is created inside this phase: `test/` (plan 01-03 T1),
`example/integration_test/media_info_test.dart` (01-04 T2), `example/integration_test/thumbnail_test.dart`
(01-05 T1), `android/src/test/kotlin/**` (01-04 T3), `example/{ios,macos}/RunnerTests/**` (01-03 T2, replaced 01-06 T3),
`.github/workflows/ci.yml` (01-03 T3).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| HEVC hardware encode and HDR tone-map fidelity | (Phase 4) | Needs a physical phone; no emulator/simulator exposes real hardware encoders or display-referred HDR tone-mapping | Out of scope for Phase 1 — deferred to Phase 4 (Codecs, HDR and Hard Inputs), pending a physical Android phone (QUESTIONS.md #3) |

All other phase-1 behaviours have automated verification.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 1s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
