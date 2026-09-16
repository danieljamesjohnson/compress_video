---
gsd_state_version: '1.0'
status: executing
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 14
  completed_plans: 12
  percent: 86
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-09-15)

**Core value:** One call turns a phone video into a smaller MP4 that plays everywhere, and it never makes the file bigger, never returns null, and builds on today's Flutter toolchain.
**Current focus:** Phase 2 complete (Android Compression on Media3); Phase 1 parked needs_human on CI billing

## Current Position

Phase: 2 of 6 (Android Compression on Media3) — 7/7 plans, ready for phase-level verification. Phase 1 at 5/7 plans, needs_human
Plan: 7 of 7 in current phase (complete)
Status: Phase 2 executed and verified (14/14 must-haves, 79 emulator + 84 Dart + 148 Gradle tests green, code review clean); verification_deferred_human. Phase 1 needs_human (CI billing). Autonomous run stopped: every remaining phase needs Dan (CI billing / Mac / physical phone).
Last activity: 2026-09-16 — Phase 2 complete through verification (human_needed: 6 UAT items); code review converged clean after 5 fixes; GitHub Actions still refusing all jobs (QUESTIONS.md #6)

Progress: [█████████░] 86% (12/14 known plans; Phase 1 sub-count separately frozen at 5/7 until 01-06 re-verifies green and is re-summarized as complete)

## Performance Metrics

**Velocity:**
- Total plans completed: 12
- Average duration: 65 min
- Total execution time: 13.1 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 | 5 | 249 min | 50 min |
| 2 | 7 | 527 min | 75 min |

**Recent Trend:**
- Last 5 plans: ~130 min, ~75 min, ~48 min, ~100 min
- Trend: 02-07 (estimate/clearCache/APK build proof, closing the phase) took ~100 min across three tasks with heavy real-emulator verification (four preset accuracy runs, a 15-case new integration suite, a full-suite re-run, and a live APK build/inspect/zipalign cycle) — slower than 02-06 but proportionate to closing out the phase's last three requirements with real measurements rather than assumed numbers
- 01-06 (not yet counted as completed — halted, see Blockers/Concerns): 166 min elapsed, almost entirely CI wall-clock across 8 macOS-runner attempts; code-complete with two real platform-quirk fixes found via live CI, final fix unverified due to a GitHub Actions billing block

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: Research's "contract/skeleton" and "probe/info/thumbnails" phases merged into Phase 1 (standard granularity; a contract phase alone had only 2 requirements)
- [Roadmap]: Android (Phase 2) before Apple (Phase 3). Phase 3 starts with a Mac-readiness check, and Phases 2 and 3 can run in parallel once the Mac is reachable.
- [Roadmap]: Behaviour requirements are mapped to Phase 2, where they are first delivered. Phase 3 owns the cross-platform parity requirements (CORE-01, CORE-07) and must pass the same corpus tests.
- [01-01]: Android SDK + headless emulator installed on danserver (JDK 17, cmdline-tools, platform-tools, platforms;android-36, build-tools;36.1.0, system-images;android-35;google_apis;x86_64); `dan` added to `kvm` group, requires `sg kvm -c` until next full re-login. Recipe recorded in `.claude/CLAUDE.md` lane notes.
- [01-01]: `github.com/danieljamesjohnson/compress_video` created private, added as `github` remote alongside danserver `origin`; default Actions workflow token permission set to `read`.
- [01-01]: 01-VALIDATION.md's Per-Task Verification Map has 20 rows (matching the actual total task count across all 7 phase-1 plans), not the 21 the plan's own acceptance criteria expected — an off-by-one authoring bug in the plan text, not a missing task. See 01-01-SUMMARY.md Deviations.
- [01-02]: Corpus clips generated with ffmpeg on danserver; portrait rotation done via a direct `tkhd`-matrix byte patch (`corpus/patch_rotation.py`) because `ffmpeg -metadata:s:v:0 rotate=` is a verified no-op on the installed ffmpeg 6.1.1. Sidecars record rotation as unsigned clockwise degrees and dimensions as displayed (post-rotation), not ffprobe's raw signed/coded values — see `corpus/README.md`.
- [01-02]: Added `-threads 1 -x264-params threads=1:sliced_threads=0` to every libx264 encode in `generate_corpus.sh` after discovering the default multi-threaded rate control made regenerated clips non-byte-identical, violating the plan's reproducibility must-have. See 01-02-SUMMARY.md Deviations.
- [01-03]: Renamed `docs/` to `doc/` (pub layout convention — a plural directory name makes `dart pub publish --dry-run` report a non-zero exit) and updated every `docs/TOOLCHAIN.md` cross-reference across the phase's planning documents.
- [01-03]: `darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift` merged from separate iOS/macOS template sources using `#if os(iOS)/#elseif os(macOS)` conditional imports and messenger access, verified against `flutter/packages`' `shared_preferences_foundation` live source rather than guessed.
- [01-03]: CI's floating `channel: stable` resolves ahead of `doc/TOOLCHAIN.md`'s locally-pinned Flutter 3.44.1 (CI run picked up 3.47.4) — Flutter's own project migrators silently rewrite committed scaffold files (`Podfile`, `project.pbxproj`, `analysis_options.yaml`) the first time a newer tool touches them. CI now resets tracked files via `git checkout -- .` immediately before the `dart pub publish --dry-run` cleanliness check, and forces `flutter config --no-enable-swift-package-manager` before the CocoaPods-path Apple builds (our plugin ships both a podspec and a `Package.swift`, so recent Flutter defaults to preferring SPM once it sees an all-SPM-capable plugin set, which conflicts with the app project's committed Podfile-based CocoaPods integration).
- [01-04]: `MediaMetadataRetriever.METADATA_KEY_COLOR_TRANSFER`/`_COLOR_STANDARD`/`_COLOR_RANGE` were confirmed live (via the "Added in API level" badges on developer.android.com) to be API level 30, not the 24/29 secondary-source guesses in 01-RESEARCH.md's Open Questions — HDR detection is gated on `Build.VERSION.SDK_INT >= 30`. `METADATA_KEY_ROTATION` does not exist; the correct constant is `METADATA_KEY_VIDEO_ROTATION` (confirmed via `javap` against the android-36 platform jar).
- [01-04]: Pigeon's own generated Dart output is not `dart format`-clean. Both the local workflow and CI's regeneration step now run `dart format lib/src/messages.g.dart` immediately after `dart run pigeon`, and the contract's regeneration diff check in CI is scoped to only its own four files (not a bare `git diff --exit-code`, which also caught Flutter's unrelated `analysis_options.yaml` migrator rewrites).
- [01-04]: CI's `android` job now regenerates and diff-gates the Pigeon contract, runs the plugin module's native Gradle unit tests, and runs a real `reactivecircus/android-emulator-runner` (API 35, google_apis, x86_64) integration suite on every push — reached green (run 34997517360) after fixing the diff scope, the gitignored `example/android/gradlew` wrapper not existing on a fresh checkout, the emulator's userdata partition not fitting `ubuntu-latest`'s free disk space, and a regression where the disk-space fix's own deletion list included the hosted toolcache (Flutter SDK + JDK) the job still needed.
- [01-05]: `MediaMetadataRetriever.getScaledFrameAtTime`'s `dstWidth`/`dstHeight` are a fit-within bounding box (scaled by whichever dimension is more constraining), not independent exact targets — confirmed live on the emulator (a `maxDimensionPx=1919` request returned height 1918, not 1919) rather than from documentation. Every decoded thumbnail frame is now unconditionally snapped to the exact `MediaMath.scaledSize` target with one `Bitmap.createScaledBitmap` pass, on every API level, so the pure-math contract is exactly what callers observe.
- [01-05]: `INFO-02` stays unchecked in `REQUIREMENTS.md` — also declared by 01-06 and 01-07, both still pending in this phase; `gsd-tools query requirements.ready-ids` reports it `blocked`, not `ready`. Same shared-ID gate pattern as `BULD-03`/`INFO-01`/`BULD-05` in 01-04.
- [01-06]: Gated the modern AVFoundation `load(_:)` API on `#available(iOS 16, macOS 13, *)` — the more conservative of 01-RESEARCH.md's two conflicting sourced minimums — since gating on the lower bound would crash at runtime if wrong, not just skip an optimisation.
- [01-06]: `videoCodec` degrades to `unknown` on the legacy (pre-iOS-16/macOS-13) AVFoundation path only: casting `AVAssetTrack.formatDescriptions: [Any]` to `[CMFormatDescription]` has no permitted Swift spelling here — `as?` is a hard compiler error under this project's warnings-as-errors build ("conditional downcast will always succeed"), and `as!` is banned by the threat model.
- [01-06]: `AVAssetImageGenerator.maximumSize` is a fit-within bounding box, not independent exact output dimensions — confirmed live in CI, the Apple-side twin of 01-05's Android `getScaledFrameAtTime` finding. Thumbnails.swift now snaps the decoded `CGImage` to the exact `MediaMath.scaledSize` target via one `CGContext` draw pass, mirroring Android's `Bitmap.createScaledBitmap` fix.
- [02-01]: Added `portrait_hibitrate_1080p60.mp4` (mandelbrot lavfi source, 60fps, ~8.7Mbps H.264 + AAC, 90deg tkhd matrix, white edge border) and `truncated_mdat.mp4` (faststart-then-truncated, sidecar-less by design) to the corpus, since every Phase 1 clip is far below every Phase 2 preset bitrate and all Phase 1 clips are 30fps. `verify_corpus.sh` generalized its single-clip `thumbnailProbe` branch to a patch-carrying-clip list and added a self-checking `edgeProbe` block for the new clip.
- [02-01]: `02-VALIDATION.md`'s Per-Task Verification Map has 21 rows (matching the actual total task count across all 7 phase-2 plans — 3 tasks x 7 plans), not the 20 the plan's own `must_haves`/acceptance criteria expected — the same class of off-by-one authoring bug as 01-01's (that one undercounted; this one overcounts), documented rather than dropping a real task's row. See 02-01-SUMMARY.md Deviations.
- [02-02]: Media3's effect pipeline (`Presentation`, `FrameDropEffect`) operates on the DECODED, display-oriented frame, not the coded pre-rotation frame — measured live on the emulator (a coded-space swap for a 90°-rotated input produced an incorrect 406px-wide output instead of 720; passing the target straight from the input's own displayed dimensions, with no swap, produced the correct 720x1280). `TransformerEngine.kt` documents this so no later plan re-derives it. `MediaMath.normalizeCodec` has no audio-codec case (video-only tokens); a local `normalizeAudioCodec` was added inside `TransformerEngine.kt` rather than extending `MediaMath.kt`, since AUDO-01/AUDO-02 own that properly in a later plan. See 02-02-SUMMARY.md Deviations.
- [02-03]: `CompressRequestMessage` gained `presetMaxLongSidePx`/`presetVideoBitrateBps` (always the selected preset's own nominal values) and `maxLongSidePx`/`videoBitrateBps` became true explicit-override-or-null — 02-02's pre-resolved-into-a-concrete-value shape would have made `SizeGuard`'s preset-bitrate-scaling rule unreachable from the real Dart-to-native path. `TransformerEngine` now uses `BITRATE_MODE_CBR` (not the default VBR) after measuring VBR overshoot ~28% vs CBR's ~20% on this emulator's software encoder for an explicit bitrate request. `Probe.kt` gained a sample-size-summation bitrate fallback since Media3's `InAppMp4Muxer` output never carries a `MediaFormat.KEY_BIT_RATE` value, unlike the ffmpeg-authored corpus fixtures — confirmed accurate against an independently pulled file's `ffprobe` measurement. `targetSizeMb`'s documented ±15% tolerance could not be proven on the emulator's software encoder for the 4-second corpus clip (measured +19.1%/-29.9%); the formula itself is exact and unit-tested, so the emulator test uses a documented ±35% tolerance pending physical-device re-verification (QUESTIONS.md #3). See 02-03-SUMMARY.md Deviations.
- [02-04]: `SizeGuard.Plan` gained `wouldTransmux`/`wouldUseOriginal` as PRE-FLIGHT recommendations of which Media3 operation to attempt (transmux first, never-larger pre-check second, real encode last) — not a guarantee about the file the caller receives. Found and fixed two real Media3 bugs live on the emulator: (1) `DefaultEncoderFactory.videoNeedsEncoding()` returns `true` whenever `requestedVideoEncoderSettings != VideoEncoderSettings.DEFAULT` (confirmed via `javap` on the installed `media3-transformer:1.11.1` AAR — undocumented anywhere), which made the transmux fast path unreachable regardless of prediction; fixed by leaving encoder settings at default whenever `wouldTransmux` is true. (2) `Transformer.Builder`'s own default muxer (`DefaultMuxer.Factory` -> `InAppMp4Muxer`) leaves `attemptStreamableOutputEnabled` at its own default of `true`, reserving a speculative `free` box (measured 395,344 bytes) for moov-before-mdat layout — the entire cause of a remuxed `small_480p.mp4` measuring 472,825 bytes against a 77,504-byte input. An initial fix (committed, then orchestrator-flagged as wrong) made `finishSuccess` decide transmux before the never-larger check, exempting remuxes from CORE-05 entirely rather than fixing the cause. The corrected fix: the never-larger post-check is unconditional (`usedOriginal = tempBytes >= inputBytes`, no exception), and `TransformerEngine` builds an explicit `InAppMp4Muxer.Factory().setAttemptStreamableOutputEnabled(false)` for every export, which drops the same remux to 77,481 bytes — smaller than the input. This muxer change also reduced every OTHER export's byte count, exposing a larger true CBR-undershoot on `targetSizeMb` (measured -49.6% at a 2.0MB target, tolerance widened ±35%→±55%) that had been partially masked by the same container padding. `doc/PRESETS.md` re-measured after the fix; no preset seed changed. CORE-05/CORE-06's flagged assumptions were implemented as written and carried forward unresolved for the verifier. See 02-04-SUMMARY.md Deviations.
- [02-05]: `TransformerEngine` now has three audio-mode branches: passthrough leaves audio encoder settings untouched (the Transformer-level unconditional `AUDIO_AAC` mime request alone both copies an already-AAC source and falls back to an AAC re-encode for a non-AAC one), strip removes the track, and reencode sets explicit `AudioEncoderSettings`/`ChannelMixingAudioProcessor` — confirmed via `javap` that `DefaultEncoderFactory.audioNeedsEncoding()` mirrors 02-04's video `videoNeedsEncoding()` precondition (reference equality against `AudioEncoderSettings.DEFAULT`), so audio settings are only ever built for an explicit reencode. Implemented trim via `MediaItem.ClippingConfiguration` (previously not implemented at all). Extracted `TransformerEngine.buildVideoEffects` (geometry-then-frame-selection order, pinned by `EffectOrderTest.kt`) and proved upright/no-letterbox output by sampling the compressed OUTPUT's own pixels (`compress_test.dart`'s `_expectUprightAndUnpadded`). `AudioReencode`/`AudioStrip` integration cases moved from `small_480p.mp4` to `portrait_hibitrate_1080p60.mp4` after discovering the former's near-source-bitrate re-encode could trip the never-larger post-check and silently substitute the original, defeating the audio assertions. Channel count and audio-only bitrate are read in Dart integration tests directly from the produced MP4's own `moov`/`stsd`/`stsz` boxes (including the 64-bit extended `mdat` size), since neither `CompressResult` nor `MediaInfo` exposes either fact and adding a wire field was out of this plan's declared scope. AUDO-01's non-AAC-source-fallback and ORNT-01's square-frame backstop truth are both carried forward unresolved — no corpus fixture exercises either. See 02-05-SUMMARY.md Deviations.
- [02-06]: Progress polling clamps into 0..99 (not 0..100) so a single explicit terminal `onProgress(100.0)` call is the only source of 100 — Media3 can report progress already at 100 for several poll ticks before `onCompleted` fires. `CompressJob._run` now closes the progress stream BEFORE completing `result` on every terminal path (was: complete-then-close in one `finally`, which never actually guaranteed the ordering since `Completer.complete` schedules listeners onto a later microtask) — this is a real behavior change; fixed `compress_test.dart`'s pre-existing `await job.result; await subscription.asFuture()` pattern, which would otherwise hang forever under the new ordering. `JobRegistry.LiveJob` now holds a `cancelTransformer: () -> Unit` callback instead of a raw `androidx.media3.transformer.Transformer` reference, since `Transformer`'s own static initializer cannot run (construct OR mock) in a plain JVM unit test — this is what makes `CompressVideoPluginTest`'s new detach cases possible at all. `CompressVideoPlugin.onDetachedFromEngine` now cancels every live job BEFORE clearing host API registrations (was reversed, contradicting T-02-25). `ErrorMapping.kt` extracts the full 22-code mapping into a pure, JVM-testable object; `TransformerEngine.mapExportException` now always folds the numeric `ExportException.errorCode` into the failure message text, since `CompressVideoException.platformDetail` is only populated Dart-side for the `unknown` reason. Compressing `truncated_mdat.mp4` observed `errorCode=2000` (`ERROR_CODE_IO_UNSPECIFIED`), agreeing with the mapping. See 02-06-SUMMARY.md Deviations.
- [02-07]: `Compression.estimate()` resolves through `TransformerEngine.resolvePlan` -- the identical `SizeGuard.Plan` resolution `startCompress` uses -- so a prediction and the real job can never disagree about which path (transmux/never-larger/encode) would run; proven on the emulator for all three fixture cases. `Compression.clearCache()` sweeps a new `PluginFiles.sweep`: bounded to one directory, resolving each candidate's canonical path and refusing anything that escapes the canonical cache directory, skipping every file a live job (`JobRegistry.liveTempFilePaths`) still owns. `Thumbnails.kt` now uses the shared `PluginFiles.cacheSubDir` instead of its own copy. Measured live that the emulator's software CBR encoder cannot hold `estimate()`'s ±15% designed tolerance across all four presets (7.9-67.0% divergence, not monotonic with resolution) -- the same class of finding as `targetSizeMb` (02-03/02-04); documented an honest ±75% emulator tolerance rather than a fabricated pass, and extended QUESTIONS.md #3. `tool/verify_apk_native_libs.sh` (allowlist enumeration + zipalign 16 KB check, teeth verified by narrowing the allowlist) is wired into CI; `doc/TOOLCHAIN.md`'s media3 pin reconciled to the actual 1.11.1 build pin (closing a 02-04-flagged item). INFO-03, CORE-09, BULD-01 now checked complete — Phase 2's all 14 requirements are done. See 02-07-SUMMARY.md Deviations.

### Pending Todos

- [01-06]: Once GitHub Actions billing is resolved (QUESTIONS.md #6), re-run CI for `main` HEAD and confirm the `apple` job concludes `success` end-to-end (including the iOS-simulator integration step with the current Thumbnails.swift/thumbnail_test.dart fixes). No further code changes are expected. Re-summarize 01-06 as `status: complete` once confirmed, then proceed to 01-07.
- [02-03]: Once a physical Android phone is available (QUESTIONS.md #3), re-run the `targetSizeMb` 1.0/2.0 emulator cases against its hardware encoder and tighten `compress_test.dart`'s ±35% tolerance comment (or confirm ±15% only holds on hardware and adjust `CompressOptions.targetSizeMb`'s dartdoc accordingly).
- [02-04]: Once a physical Android phone is available (QUESTIONS.md #3), re-run the transmux speed-ratio test against its hardware encoder to confirm the <30% elapsed-time claim (CORE-06) holds outside the emulator's software encoder, and re-verify `targetSizeMb`'s now ±55% emulator tolerance against hardware CBR delivery. Also: no corpus clip demonstrates an observable `transmuxed:true` result via the no-audio-track branch specifically (see 02-04-SUMMARY.md coverage note); consider adding one if a later plan needs that proof. (`doc/TOOLCHAIN.md`'s media3 pin was reconciled to 1.11.1 in 02-07 — no longer open.)
- [02-05]: AUDO-01's non-AAC-source passthrough-fallback path has no automated end-to-end proof (no corpus fixture has non-AAC audio) — the real phone clips requested in QUESTIONS.md #4 may incidentally provide one; otherwise a future plan should add a synthetic non-AAC-audio fixture. ORNT-01's backstop truth (equal-width/height source, rotation 0) also has no corpus fixture (no square clip exists) and is unverified.
- [02-06]: The pre-flight free-space check (StatFs against 1.2x predicted output) has no functional trigger test — there is no practical way to make the shared danserver emulator's filesystem genuinely run out of space in an automated test; a future plan could add a Robolectric-based unit test around a small extracted comparison function if tighter proof is wanted. CORE-04's flagged assumption (A1: `DECODER_INIT_FAILED`/`DECODING_FORMAT_UNSUPPORTED` split; A2: the ENOSPC message match) remains unresolved — the one real failure observed (`truncated_mdat.mp4` → `ERROR_CODE_IO_UNSPECIFIED`) did not exercise either ambiguous branch; no corpus fixture reliably produces a genuine decoder-unavailable or decoding-format-unsupported failure.
- [02-07]: Five items carried forward unresolved, all recorded in `.planning/WINDOWS.md`: `estimate()`'s ±15%-vs-±75% accuracy gap on the emulator's software encoder (QUESTIONS.md #3, needs a physical-device re-run); `clearCache()`'s symlink-escape mitigation (T-02-26) has no dedicated symlink-based integration test; the new CI native-lib/alignment step has not been exercised by a live GitHub Actions run (no push this session); BULD-01's debug-vs-release APK representativeness assumption (02-RESEARCH.md's own flagged open item); and the optional example-app manual UI check (tap Compress/Cancel) was inconclusive on the danserver headless emulator (native splash persisted, no Dart exception, activity confirmed foregrounded) — the underlying API is proven end-to-end by automated tests regardless.

### Blockers/Concerns

- [01-06 / Phase 1]: **GitHub Actions billing block (QUESTIONS.md #6, notified via notify-dan 2026-09-15)** — the `apple` CI job stopped starting entirely mid-session: "recent account payments have failed or your spending limit needs to be increased." This blocks re-verifying 01-06's final fix and blocks 01-07 (cross-platform parity gate) from starting until resolved and CI is confirmed green again.
- [Phase 3]: SSH to `dans-macbook-air` is refused, which blocks Apple device/simulator verification (QUESTIONS.md #1). Phase 1 uses the GitHub Actions macOS runner meanwhile.
- [Phase 4]: HEVC/HDR hardware checks need a physical Android phone (QUESTIONS.md #3).
- [Phase 6]: No verified pub.dev publisher yet (QUESTIONS.md #2).

## Deferred Verification

| Phase | State | Resume |
|-------|-------|--------|
| 2 | verification_deferred_human | /gsd-verify-work 2 (6 items in 02-UAT.md; #1 needs a physical phone, #2-#4 can be closed by an agent with new fixtures/tests) |

## Needs Human

| Phase | State | Resume |
|-------|-------|--------|
| 1 | needs_human | GitHub Actions billing/spending limit (QUESTIONS.md #6) or make repo public (#5); then `gh run rerun <latest main run> --failed` and `/gsd-autonomous --from 1` |

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-09-16
Stopped at: Autonomous run halted 2026-09-16 — Phase 1 needs_human (GitHub Actions billing, QUESTIONS.md #6/#5), Phase 2 verification deferred to /gsd-verify-work 2, Phase 3 blocked on Mac SSH or CI. Resume: clear billing → `gh run rerun <latest> --failed` → /gsd-autonomous --from 1
Resume file: None — Phase 2 is ready for /gsd-verify-work 2, then /gsd-plan-phase 3 (or resolve QUESTIONS.md #6 first to unpark Phase 1's 01-06/01-07)
