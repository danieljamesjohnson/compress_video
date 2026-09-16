---
phase: 02-android-compression-on-media3
verified: 2026-09-15T00:00:00Z
status: human_needed
score: 14/14 must-haves verified
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Re-run CompressOptions.targetSizeMb and CompressEstimate.outputBytes accuracy cases on a physical Android phone's hardware H.264 encoder"
    expected: "Confirm whether the phone's hardware encoder holds the originally designed ±15% tolerance, or whether the emulator-measured wide deviation (±55% for targetSizeMb, ±75% for estimate()) is intrinsic to Media3's CBR rate control generally and the dartdoc/QUESTIONS.md #3 caveat should stay permanent"
    why_human: "Requires a physical Android device (QUESTIONS.md #3); cannot be produced by the software-only emulator encoder, and the divergence is measured, not a code defect (SizeGuardTest.kt proves the underlying formula is exact)"
  - test: "Construct a symlink inside <cacheDir>/compress_video/ that points outside the cache directory, then call clearCache(), and confirm the external target survives"
    expected: "PluginFiles.sweep's canonical-path containment check skips the symlink rather than following it, per T-02-26's mitigation"
    why_human: "No integration test in this phase constructs an actual symlink to exercise the escape path (WINDOWS.md #4); the containment logic is code-reviewed and reasoned, not functionally proven"
  - test: "Compress a source whose audio track is genuinely not MP4-compatible AAC (e.g. MP3 or Vorbis audio in an MP4/MKV container) with default AudioOptions"
    expected: "The engine falls back to an AAC re-encode and reports audioReencoded: true, per AUDO-01's default-path requirement, rather than crashing or silently producing the wrong output"
    why_human: "No corpus fixture in this project carries a non-AAC audio track (02-05-SUMMARY.md D5); the implementation relies on Transformer.Builder.setAudioMimeType(AUDIO_AAC) being unconditional, reasoned from source but not observed live"
  - test: "Trigger a genuine ERROR_CODE_DECODER_INIT_FAILED or ERROR_CODE_DECODING_FORMAT_UNSUPPORTED export failure (a codec neither the device's hardware nor software decoder supports) and confirm it maps to decoderUnavailable vs unsupportedInput as documented"
    expected: "The mapping in ErrorMapping.kt for these two specific codes matches real platform behavior for at least one real occurrence of each"
    why_human: "The only real platform failure observed this phase (truncated_mdat.mp4 -> ERROR_CODE_IO_UNSPECIFIED) did not exercise either ambiguous branch (02-06-SUMMARY.md D12); no corpus fixture reliably produces either code"
  - test: "Fill the emulator's (or a physical device's) destination filesystem to near capacity and start a compression job"
    expected: "Compression.requireSufficientFreeSpace's pre-flight StatFs check (1.2x predicted output) rejects with outOfSpace before a Transformer is built, and a mid-encode ENOSPC also maps to outOfSpace"
    why_human: "There is no safe way to fill the shared, multi-agent danserver emulator's filesystem in an automated test without risking the host (02-06-SUMMARY.md D11); the arithmetic is code-reviewed against SizeGuard's own unit-tested numbers but not functionally triggered"
  - test: "Run the example app's compress screen on a real display (or a device with working software rendering) and watch progress move, then cancel mid-run"
    expected: "Progress bar advances, result line appears with bytes/dimensions/elapsed time, cancel resolves the button back to idle"
    why_human: "Explicitly optional per 02-07-PLAN.md's <human-check>; attempted on the headless danserver emulator and was inconclusive (app stuck on native splash with no Dart exception -- WINDOWS.md #5), consistent with this project's documented headless-rendering false-alarm pattern. The underlying compress()/cancel() calls are already proven end to end by the automated suites using the identical public API"
---

# Phase 2: Android Compression on Media3 Verification Report

**Phase Goal:** On Android, one call turns a phone video into a smaller, upright H.264/AAC MP4
with a typed result. The output is never larger than the input, and each job has its own
progress and cancel.
**Verified:** 2026-09-15 (re-run against the current, post-code-review-fix `main`)
**Status:** human_needed
**Re-verification:** No — initial verification

## Method

This is not a re-statement of SUMMARY.md's claims. Every truth below was checked against the
actual codebase and, wherever the check was runnable in this environment, executed directly by
the verifier in this session (not inferred from prior SUMMARY narration):

- `flutter analyze --fatal-infos --fatal-warnings` (root) — clean
- `flutter test` (root) — **84/84 pass**
- `cd example/android && ./gradlew :compress_video:testDebugUnitTest` — **148/148 pass** (0
  failures, 0 skipped, across `ArgumentsTest` 45, `CompressVideoPluginTest` 4, `EffectOrderTest`
  4, `ErrorMappingTest` 29, `MediaMathTest` 25, `SizeGuardTest` 41)
- `bash corpus/verify_corpus.sh` — all 4 sidecars match their clips; `truncated_mdat.mp4`
  confirmed still probes as video by design
- Relaunched the headless emulator (it had crashed between test runs — a known,
  previously-documented shared-host memory-pressure issue, not a code defect) and ran, one file
  at a time, every emulator integration suite on `emulator-5554`:
  - `compress_test.dart` — **22/22 pass**
  - `compress_audio_test.dart` — **7/7 pass**
  - `compress_jobs_test.dart` — **10/10 pass**
  - `compress_output_test.dart` — **15/15 pass**
  - `thumbnail_test.dart` (Phase 1 regression) — **16/16 pass**
  - `media_info_test.dart` (Phase 1 regression) — **9/9 pass**
  - Total: **79/79 emulator integration tests pass**, matching the count claimed in
    `02-06-SUMMARY.md`/`02-07-SUMMARY.md`
- `flutter build apk --debug` then `bash tool/verify_apk_native_libs.sh` — **exit 0**; only
  `lib/*/libflutter.so` (per ABI) and the debug-only
  `lib/arm64-v8a/libVkLayer_khronos_validation.so` present, all on the allowlist; `zipalign -c -P
  16 -v 4` reports every entry OK (16 KB page-safe)
- Read the actual Kotlin/Dart source for every load-bearing claim in the SUMMARYs (the
  unconditional never-larger post-check, the streamable-output-disabled muxer, the 22-entry
  `ErrorMapping` table, the 9-value `CompressVideoErrorReason` enum, the synchronous
  `CompressJob compress(...)` signature, the `cancelled || terminal` idempotency guard, the
  `resolvePlan`/`sweep` shared-resolver wiring) and confirmed each matches the narration
- Confirmed all commit hashes cited across the 7 SUMMARYs and both REVIEW files exist in
  `git log`
- Read `02-REVIEW.md` (iteration 2, `status: clean`, 0 critical/0 warning/3 info) and
  `02-REVIEW-FIX.md` (5/5 in-scope findings fixed) in full, and spot-checked the fixed code
  directly rather than trusting the reports' own re-verification narrative (see WR-01/CR-01
  confirmation below)

## Goal Achievement

### Observable Truths (mapped to ROADMAP.md's 5 Success Criteria)

| # | Truth (ROADMAP Success Criterion) | Status | Evidence |
|---|---|---|---|
| 1 | Portrait corpus clip compressed with a preset or explicit target comes out smaller, H.264/AAC, upright, no black bars, fps capped at 30 with no upscale, typed result reports bytes/dims/duration/codec/elapsed | ✓ VERIFIED | `compress_test.dart` 22/22 pass live on `emulator-5554`: preset ladder (p360/p480/p720/p1080), explicit `maxLongSidePx`/`videoBitrateBps`/`targetSizeMb`, 60fps→30fps cap measured against the sidecar's recorded source rate, no-upscale cases, upright+unpadded pixel-probe assertions on the compressed OUTPUT itself. `CompressResult` fields read directly from source (`lib/src/compress_result.dart`): `outputPath, inputBytes, outputBytes, widthPx, heightPx, durationMs, videoCodec, audioCodec, elapsedMs` all present, non-null on success |
| 2 | Already-small clip returns original bytes with `usedOriginal`; an already-qualifying clip is remuxed (`transmuxed: true`) in a fraction of the encode time | ✓ VERIFIED | `compress_test.dart`: never-larger (`small_480p.mp4` at p360 → `usedOriginal:true`), transmux (`small_480p.mp4` default → `transmuxed:true`), and a direct measured speed-ratio assertion (remux < 30% of a real encode's elapsed time) all pass. Source confirmed: `TransformerEngine.kt:401` computes `usedOriginal = tempBytes >= inputBytes` **unconditionally** (not gated on whether a remux was attempted), and transmux is only reported when `!usedOriginal` (line 419) — the exact fix for the CR review's caught defect (see Deviations note below) |
| 3 | AAC passthrough not re-encoded by default; caller can force re-encode (bitrate+channels) or strip; result reflects the choice | ✓ VERIFIED | `compress_audio_test.dart` 7/7 pass live: passthrough (`audioReencoded:false`, `audioCodec:aac`), strip (`audioCodec:null`), reencode at 64000bps/2ch and 1ch (channel count exact, bitrate within 25%), bitrate clamping (1000bps → clamped up), and a two-bitrate differentiation case all pass |
| 4 | Two jobs independent progress/future; cancel resolves Cancelled + deletes partial file; failures typed, never crash | ✓ VERIFIED | `compress_jobs_test.dart` 10/10 pass live: single-job progress (0-100 monotonic, exactly one terminal 100), two-job independence (no cross-talk), cancel (partial file gone before future resolves), idempotent cancel, cancel-after-completion no-op, cancel-one-of-three, 4 real-failure cases (a genuinely damaged file, missing path, zero-byte file, renamed text file) all typed, none crash. `test/compress_job_test.dart`'s 10 platform-free cases (part of the 84 root `flutter test` passes) cover identity/routing/no-listener/late-subscription/closed-exactly-once |
| 5 | Pre-flight estimate returns size/duration without encoding within documented tolerance; output placement + `clearCache()` scoped correctly; build uses Media3, minSdk 23, compileSdk 36, no `.so`, current stable AGP/Kotlin | ✓ VERIFIED | `compress_output_test.dart` 15/15 pass live: `estimate()` matches exact resolved dimensions on all 4 presets and its documented (widened, see below) byte tolerance; `wouldTransmux`/`wouldUseOriginal` agree with the real job's `transmuxed`/`usedOriginal` in all 3 fixture cases; estimate() wall-clock << real encode's `elapsedMs`; output placement (default cache path, explicit path incl. non-ASCII, missing-parent → `io`) all correct; `clearCache()` scoped to its own subdirectory only, no-op on empty/absent, never touches a live job's file. Native-lib check run directly by this verifier: **exit 0**, allowlist-only, 16 KB aligned. `android/build.gradle.kts` confirmed: `minSdk = 23`, `compileSdk = 36`, all 4 media3 artifacts pinned `1.11.1` |

**Score:** 5/5 roadmap Success Criteria verified; 14/14 plan-declared must-have truth clusters
verified with direct evidence (see Requirements Coverage below for the per-requirement mapping)

### Flagged Design Assumptions — Verifier Judgment

Several plans explicitly carried forward unresolved interpretive assumptions rather than closing
them by fiat, per their own instructions. Verifier disposition on each:

- **CORE-05 "equality counts as larger"** (a same-size re-encode is substituted with the
  original): reasonable and conservative — a same-size lossy re-encode is strictly worse quality
  for no size benefit. **Accepted as correct**, not requiring further human review.
- **CORE-06 "<30% of encode time" for transmux speed**: the roadmap text ("a fraction of the
  encode time") does not fix a number; 30% is a documented, defensible interpretation and is
  measured, not eyeballed. **Accepted as correct**.
- **`targetSizeMb`/`estimate()` tolerance widened from the phase-context's original ±15% target
  to a measured, documented ±55%/±75%** on this emulator's software CBR encoder: `SizeGuardTest.kt`
  proves the underlying formula is exact (the divergence is real encoder rate-control behavior,
  not an arithmetic bug), and both dartdocs state the wider, honest number rather than a
  fabricated pass. ROADMAP Success Criterion 5 says "within the **documented** tolerance" (not a
  fixed percentage), which this technically satisfies. However, whether a physical phone's
  hardware encoder holds nearer the originally-designed 15% remains genuinely unknown and
  QUESTIONS.md #3 already tracks it — **routed to human verification** (see frontmatter) rather
  than silently accepted, since it materially affects what callers should expect in production.

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `lib/src/compress_job.dart` | `CompressJob` sync return, per-job stream/future/cancel, no global state | ✓ VERIFIED | `class CompressJob` present; `compress()` returns `CompressJob` not `Future<CompressJob>` (grep confirmed 1 match, 0 `Future<CompressJob>`); no `compressProgress`/`isCompressing` anywhere in `lib/` |
| `lib/src/compress_options.dart` | `CompressOptions`/`CompressPreset`/`AudioOptions`, full `validate()` | ✓ VERIFIED | Present; 24+ validation unit tests pass (part of the 84) |
| `lib/src/compress_result.dart` | `CompressResult`/`CompressEstimate`, `toneMapped`/`hevcFallback` reserved fields | ✓ VERIFIED | Present with dartdoc on every field; reserved fields present and always `false` this phase |
| `lib/src/compress_video_exception.dart` | 9-value `CompressVideoErrorReason` | ✓ VERIFIED | Exactly 9 values in the documented order (original 6 + `encoderUnavailable, outOfSpace, interrupted`) |
| `android/.../TransformerEngine.kt` | One Transformer/job on main Looper, re-probe for truth, audio modes, effects order, never-larger/transmux | ✓ VERIFIED | `Looper.myLooper() != Looper.getMainLooper()` guard present in `Compression.kt:156`; `finishSuccess` unconditional `usedOriginal = tempBytes >= inputBytes`; `buildVideoEffects` companion function backing `EffectOrderTest` |
| `android/.../SizeGuard.kt` | Pure preset/target/never-larger/transmux resolver, no Android import | ✓ VERIFIED | 41 JVM unit tests pass; `wouldTransmux`/`wouldUseOriginal` predicates present and shared |
| `android/.../ErrorMapping.kt` | 22-code pure mapping, no Android/Media3 import | ✓ VERIFIED | Exactly 22 named `ERROR_CODE_*` constants, `KNOWN_ERROR_CODES` set-size-asserted by its own test; 29 `ErrorMappingTest` cases pass |
| `android/.../JobRegistry.kt` | Cancel idempotent incl. against same-tick natural completion | ✓ VERIFIED | `cancel()` no-ops on `job.cancelled \|\| job.terminal` (line 109); `job.terminal` set by `stopPolling`, which fires synchronously in the terminal `Transformer.Listener` callback |
| `android/.../PluginFiles.kt` | Single cache-dir definition, bounded `sweep`, atomic write/delete | ✓ VERIFIED | `sweep()` present, used by `Compression.clearCache()`; `Thumbnails.kt` confirmed to use the same `PluginFiles.cacheSubDir` (grep) |
| `tool/verify_apk_native_libs.sh` | Allowlist enumeration + 16 KB alignment, runnable locally/CI | ✓ VERIFIED | Ran directly against a freshly built debug APK: exit 0, correct allowlist, alignment OK |
| `doc/PRESETS.md`, `tool/measure_presets.dart` | Measured (not seeded) preset table | ✓ VERIFIED (existence+content) | Present; SUMMARY documents the measurement methodology; not independently re-measured by the verifier (would require a full preset re-run, already covered by the passing `compress_test.dart` ladder assertion) |
| `.github/workflows/ci.yml` | Runs native-lib/alignment check + build-constraint grep | ✓ VERIFIED (wiring only) | `verify_apk_native_libs.sh`, `minSdk = 23`, `compileSdk = 36`, media3 `1.11.` grep all present in the workflow file; **not exercised by a live CI run** this session (external blocker, QUESTIONS.md #6/#3, WINDOWS.md #3 — consistent with the verification environment note that a missing CI run is not itself a gap) |
| `02-VALIDATION.md` | Filled Test Infrastructure/Sampling/Per-Task map | ⚠️ Partially stale | Content is fully filled (not template placeholders), but frontmatter `status:` still reads `draft` and the Per-Task Verification Map's own Status column still reads `⬜ pending` for every row despite the underlying tests actually passing (confirmed live by this verifier). This is a documentation-hygiene gap in the tracking artifact itself, not a functional gap — informational only, see Anti-Patterns |
| `COVERAGE.md` | Declares no external API integration | ✓ VERIFIED | Present, correct one-line declaration |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `lib/compress_video.dart` | `android/.../Compression.kt` | Generated `CompressHostApi` channel | ✓ WIRED | Proven end-to-end by every passing integration test (79/79) |
| `android/.../TransformerEngine.kt` | `android/.../SizeGuard.kt` | `resolvePlan()`, single shared resolver | ✓ WIRED | `resolvePlan` called from `compress()`, `Compression.estimate()`, and `Compression.requireSufficientFreeSpace()` — grep-confirmed 3 call sites, one function, cannot diverge |
| `android/.../TransformerEngine.kt` | `android/.../Probe.kt` | Re-probing the finished output for every result field | ✓ WIRED | Confirmed via source read; results assert against the re-probed file, not `ExportResult`'s own approximate fields |
| `android/.../TransformerEngine.kt` | `android/.../ErrorMapping.kt` | `mapExportException` → `ErrorMapping.reasonForExportFailure` | ✓ WIRED | Grep-confirmed call site; live-observed failure (`truncated_mdat.mp4` → code 2000 → `io`) matches |
| `android/.../Compression.kt` | `android/.../PluginFiles.kt` | `clearCache()` → `PluginFiles.sweep` | ✓ WIRED | Grep-confirmed; `compress_output_test.dart`'s 3 `clearCache()` cases pass live |
| `android/.../Thumbnails.kt` | `android/.../PluginFiles.kt` | Shared `cacheSubDir`, no private copy | ✓ WIRED | Grep-confirmed no private directory construction remains in `Thumbnails.kt`; 16/16 `thumbnail_test.dart` regression cases pass |
| `.github/workflows/ci.yml` | `tool/verify_apk_native_libs.sh` | CI step running the same script | ✓ WIRED (config only) | Present in workflow YAML; not exercised by a live run this session (see artifact note above) |

### Behavioral Spot-Checks / Full Suite Runs

| Behavior | Command | Result | Status |
|---|---|---|---|
| Dart unit suite | `flutter test` | 84/84 pass | ✓ PASS |
| Native unit suite | `./gradlew :compress_video:testDebugUnitTest` | 148/148 pass (0 fail) | ✓ PASS |
| Corpus integrity | `bash corpus/verify_corpus.sh` | All sidecars match; damaged fixture confirmed probeable | ✓ PASS |
| Compress core (presets/never-larger/transmux/orientation/trim) | `flutter test integration_test/compress_test.dart -d emulator-5554` | 22/22 pass | ✓ PASS |
| Audio modes | `flutter test integration_test/compress_audio_test.dart -d emulator-5554` | 7/7 pass | ✓ PASS |
| Jobs/cancel/errors | `flutter test integration_test/compress_jobs_test.dart -d emulator-5554` | 10/10 pass | ✓ PASS |
| Estimate/output/clearCache | `flutter test integration_test/compress_output_test.dart -d emulator-5554` | 15/15 pass | ✓ PASS |
| Phase 1 regression: thumbnails | `flutter test integration_test/thumbnail_test.dart -d emulator-5554` | 16/16 pass | ✓ PASS |
| Phase 1 regression: media info | `flutter test integration_test/media_info_test.dart -d emulator-5554` | 9/9 pass | ✓ PASS |
| APK native-library allowlist + 16 KB alignment | `flutter build apk --debug && bash tool/verify_apk_native_libs.sh` | exit 0; allowlist-only; all entries aligned | ✓ PASS |
| `flutter analyze --fatal-infos --fatal-warnings` | root | No issues found | ✓ PASS |

**Note:** the emulator (`emulator-5554`) crashed and had to be relaunched mid-verification
(`sg kvm -c 'emulator -avd compress_video_api35 ...'`) — the same shared-host memory-pressure
issue documented in `02-02-SUMMARY.md`'s Issues Encountered section. Not a code defect; recorded
for continuity.

### Requirements Coverage

All 14 requirement IDs declared for this phase in ROADMAP.md are declared across the 7 plans'
`requirements:` frontmatter (union matches exactly, no omissions) and are marked `[x]` in
`REQUIREMENTS.md`. No orphaned requirements found.

| Requirement | Declaring Plan(s) | Status | Evidence |
|---|---|---|---|
| CORE-02 | 02-01, 02-02, 02-03, 02-04 | ✓ SATISFIED | Preset/explicit-target resolution proven live (`compress_test.dart`), pure unit-tested (`SizeGuardTest`), measured preset table (`doc/PRESETS.md`) |
| CORE-03 | 02-02, 02-06 | ✓ SATISFIED | Typed `CompressResult`, never resolves null, every field populated from re-probe; `compress_jobs_test.dart` D10 asserts full field population across all its cases |
| CORE-04 | 02-06 | ✓ SATISFIED (with 1 human item) | 22-code `ErrorMapping` table-driven, 1 real observed failure agrees; 2 ambiguous codes (DECODER_INIT_FAILED/DECODING_FORMAT_UNSUPPORTED split) not exercised by any real observed failure — routed to human verification |
| CORE-05 | 02-01, 02-04 | ✓ SATISFIED | Never-larger post-check is unconditional (source-confirmed); pre-check + post-check both proven live |
| CORE-06 | 02-04 | ✓ SATISFIED | Transmux detected from `ExportResult`'s own conversion-process fields, measured speed ratio proven live |
| CORE-08 | 02-01, 02-03 | ✓ SATISFIED | 30fps cap, no-upscale, half-up rounding, even-dimension floor all unit- and integration-proven |
| CORE-09 | 02-07 | ✓ SATISFIED | Output placement + bounded, canonical-path-checked `clearCache()` proven live; symlink-escape path specifically not exercised — routed to human verification |
| ORNT-01 | 02-01, 02-05 | ✓ SATISFIED | Upright + no-black-bars proven by sampling the compressed OUTPUT's own pixels, live |
| AUDO-01 | 02-05 | ✓ SATISFIED (with 1 human item) | AAC passthrough proven live; non-AAC-source fallback has no corpus fixture — routed to human verification |
| AUDO-02 | 02-05 | ✓ SATISFIED | Reencode/strip/clamp all proven live across bitrate and channel-count boundaries |
| JOBS-01 | 02-02, 02-06 | ✓ SATISFIED | Per-job independent stream/future, no global state, monotonic progress, single terminal 100, all proven live and unit-tested |
| JOBS-02 | 02-06 | ✓ SATISFIED | Cancel typed/idempotent/deletes-partial/cancel-all-on-detach all proven live and unit-tested, including the WR-01 race fix |
| INFO-03 | 02-07 | ✓ SATISFIED (with 1 human item) | `estimate()` shares the same resolver, agrees with real outcomes on 3 fixtures; byte-accuracy tolerance widened and honestly documented — physical-device confirmation routed to human verification |
| BULD-01 | 02-02, 02-07 | ✓ SATISFIED | minSdk 23, compileSdk 36, media3 1.11.1 pinned, no `.so` beyond Flutter's own, 16 KB aligned — all independently re-verified by this verifier against a freshly built APK |

No orphaned requirements. No requirement blocked.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| `02-VALIDATION.md` | frontmatter | `status: draft` and every Per-Task row still `⬜ pending` despite the underlying tests passing | ℹ️ Info | Documentation-hygiene only — the tracking artifact was never updated post-execution to reflect actual green results this verifier independently confirmed. Does not affect the phase's actual goal achievement |
| `example/integration_test/compress_output_test.dart` | 139 | Test description text says "within 15 percent" while the actual assertion (`emulatorAccuracyTolerance = 0.75`, line 92) checks 75 percent | ℹ️ Info | Cosmetic — the code comment above the constant (lines 78-92) documents the real number correctly; only the test's own `reason:`-style description string is stale. Could mislead someone reading test output names in isolation |

No debt markers (`TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER`) found in any of the 58 files
this phase's SUMMARYs list as created/modified. No stub returns, no hardcoded empty data flowing
to a result, no swallowed failures found by direct source reading.

### Code Review Cross-Check

`02-REVIEW.md` (iteration 2) reports `status: clean`, 0 critical, 0 warning, 3 info, after
`02-REVIEW-FIX.md` closed all 5 iteration-1 critical/warning findings (CR-01, WR-01 through
WR-04). This verifier independently re-read the fixed code rather than trusting the reports:

- **WR-01** (cancel-vs-completion race): confirmed `JobRegistry.cancel()` no-ops on
  `job.cancelled || job.terminal` (line 109 of `JobRegistry.kt`), and `job.terminal` is set
  synchronously inside the terminal `Transformer.Listener` callback via `stopPolling` — genuinely
  fixed, not just reported fixed.
- **Never-larger unconditional post-check** (the CORE-05 defect the review's own iteration-1
  cycle caught mid-plan-04, not a numbered CR/WR item but load-bearing for this phase's core
  value): confirmed at `TransformerEngine.kt:401` — `tempBytes >= inputBytes` runs with no
  exemption for a remux.
- The 3 remaining Info items (`Probe.kt`'s `finally`-block secondary-exception edge,
  `compress_job.dart`'s same-tick-cancel signal, and `example/lib/main.dart`'s demo-only
  generation-guard) are all genuinely low-severity and confirmed present as described — none
  affect this phase's must-have truths.

## Human Verification Required

See frontmatter `human_verification:` for the full structured list (6 items). Summary:

1. **Physical-device accuracy re-check** for `targetSizeMb`/`estimate()` — the widened emulator
   tolerances (±55%/±75%) are honestly documented and formula-proven, but whether real hardware
   holds closer to the originally-designed ±15% is unknown (QUESTIONS.md #3).
2. **`clearCache()` symlink-escape** — implemented and code-reviewed, no dedicated symlink test
   (WINDOWS.md #4).
3. **Non-AAC-source audio fallback** — implemented and reasoned from source, no corpus fixture
   exercises it end to end (02-05-SUMMARY.md D5).
4. **CORE-04's two ambiguous error-code branches** — the one real observed failure this phase
   produced didn't exercise either (02-06-SUMMARY.md D12).
5. **Pre-flight free-space check** — implemented and code-reviewed, cannot be safely triggered on
   the shared emulator host (02-06-SUMMARY.md D11).
6. **Optional example-app UI smoke test** — inconclusive on the headless emulator; not required
   for this phase (WINDOWS.md #5), listed for completeness.

None of these are evidence of a broken or unwired implementation — every one is an explicitly
self-flagged, honestly documented coverage boundary the plans themselves asked the verifier to
surface rather than resolve by fiat. They gate a human sign-off, not a re-plan.

## Gaps Summary

**No gaps found.** Every one of the 5 ROADMAP.md Success Criteria and all 14 declared requirement
IDs are backed by passing, independently-re-executed automated evidence (84 Dart unit tests, 148
native unit tests, 79 emulator integration tests, a live APK native-library/alignment check, and
direct source reading of every load-bearing claim). Code review converged clean at 0
critical/0 warning. The only reason this report is not `passed` is the six explicitly-flagged,
self-documented coverage boundaries above, all of which the phase's own plans instructed be
surfaced for human judgment rather than closed by fiat — per the verification decision tree, any
non-empty human-verification list routes status to `human_needed` even when every other truth is
verified.

---

*Verified: 2026-09-15*
*Verifier: Claude (gsd-verifier)*
