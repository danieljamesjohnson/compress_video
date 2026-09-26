# Roadmap: compress_video

## Overview

This roadmap starts with a typed Pigeon contract. The first real calls through it read media info
and thumbnails on all three platforms, with CI green on Linux and macOS runners. Next comes the
Media3 Transformer engine on Android. danserver can verify that phase on its own, and it fixes
the behaviour every platform must match: presets, never-larger output, transmux, upright
portrait, audio, per-job progress and cancel. Then the Apple AVAssetReader/Writer engine is built
to parity on iOS and macOS. After that come the differentiators every competitor got wrong: HDR
tone-mapping, HEVC with fallback, hard audio inputs and a real-clip corpus in CI. The job queue,
background isolates and Android foreground service come next. The last phase publishes
`compress_video` on pub.dev as a drop-in migration from `video_compress`.

Research suggested seven phases. Its "contract/skeleton" and "probe/info/thumbnails" phases are
merged here into Phase 1. On its own, the contract phase had only two requirements, and its
success criteria read as tasks. A real media-info call through the contract proves the contract
works (standard granularity: 4-6 phases).

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Typed Contract, CI and Media Info** - Pigeon contract proven by media info and thumbnails on Android, iOS and macOS, with CI green
- [ ] **Phase 2: Android Compression on Media3** - One-call compression on Android with presets, never-larger, transmux, upright portrait, audio and per-job progress/cancel
- [ ] **Phase 3: Apple Compression to Parity** - The same calls and behaviour on iOS and macOS, via CocoaPods and SPM, with the example app on all three platforms
- [ ] **Phase 4: Codecs, HDR and Hard Inputs** - HDR tone-mapping, HEVC with fallback, 5.1/PCM/no-audio sources and the real-clip corpus in CI
- [ ] **Phase 5: Jobs, Isolates and Background** - Job queue with concurrency limit, background-isolate calls, Android foreground service, honest iOS interruption
- [ ] **Phase 6: Release and Migration** - Published on pub.dev at 160/160 with preset tables, migration guide and a `video_compress` compatibility layer

## Phase Details

### Phase 1: Typed Contract, CI and Media Info

**Goal**: A Flutter developer can add the plugin and read accurate media info and thumbnails on Android, iOS and macOS. The calls go through a typed, unit-documented contract, and CI keeps it building.
**Depends on**: Nothing (first phase)
**Requirements**: BULD-03, BULD-05, INFO-01, INFO-02
**Success Criteria** (what must be TRUE):

  1. Calling media info on the portrait corpus clip returns the displayed (rotation-corrected) width and height, the rotation, the duration in milliseconds, the size, codec, bitrate, frame rate, has-audio and is-HDR. The values match on the Android emulator and the iOS simulator.
  2. A thumbnail requested at 1500 ms of a portrait clip comes back upright, from the same moment on every platform, as bytes or as a uniquely named JPEG file that honours the quality and max-dimension options.
  3. A missing or non-video file produces a typed error with a reason on every platform. It never produces `null` or a crash.
  4. Every quantity crossing the channel is a Pigeon-generated field whose unit is in its name and documented in the Dart API. No hand-written method-channel maps remain.
  5. A push to the repository triggers CI on a Linux runner (Android) and a macOS runner (iOS/macOS). CI builds the plugin and example, runs Dart and native unit tests, and goes red on any analyzer warning.

**Plans**: 7 plans

Plans:
**Wave 1**

- [x] 01-01-PLAN.md — Android toolchain and emulator on danserver, private GitHub repo, toolchain pins, API-coverage declaration, validation contract
- [x] 01-02-PLAN.md — Generated corpus: three phone-shaped clips with a real display matrix, ground-truth sidecars and a drift verifier

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-03-PLAN.md — Plugin package scaffold, shared `darwin/` Apple tree, typed error taxonomy, CI on Linux and macOS

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 01-04-PLAN.md — Pigeon contract and the end-to-end media-info tracer: Dart API to Kotlin to MediaMetadataRetriever, green on the emulator

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 01-05-PLAN.md — Thumbnails on Android: upright bytes and unique files at an exact millisecond, with boundary and concurrency coverage
- [x] 01-06-PLAN.md — Apple core in the shared `darwin/` tree: Probe, Thumbnails, XCTest on iOS and macOS, verified on the CI macOS runner — halt resolved, CI run 35606910435 confirmed green

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 01-07-PLAN.md — Cross-platform parity gate, full pipeline green, phase sign-off

**Research**: Needed. Check current AGP/Kotlin/Pigeon versions and the plugin template for SPM + CocoaPods. Work out how to install the Android SDK and emulator on headless Linux with an AMD GPU (KVM acceleration), and how to run emulators on GitHub Actions.
**Notes**: Apple-side verification in this phase uses the GitHub Actions macOS runner, because SSH to the MacBook Air is blocked (QUESTIONS.md #1). Create the corpus directory with the first clips (portrait, already-small, no audio) here. Phase 4 expands it.

### Phase 2: Android Compression on Media3

**Goal**: On Android, one call turns a phone video into a smaller, upright H.264/AAC MP4 with a typed result. The output is never larger than the input, and each job has its own progress and cancel.
**Depends on**: Phase 1
**Requirements**: CORE-02, CORE-03, CORE-04, CORE-05, CORE-06, CORE-08, CORE-09, ORNT-01, AUDO-01, AUDO-02, JOBS-01, JOBS-02, INFO-03, BULD-01
**Success Criteria** (what must be TRUE):

  1. On the Android emulator, the portrait corpus clip compressed with a preset or an explicit max-long-side / bitrate / target-MB option comes out as a smaller H.264/AAC MP4. It plays upright with no black bars, frame rate is capped at 30 fps with no upscaling, and the typed result reports bytes before/after, the displayed width/height, duration, codec and elapsed time.
  2. Compressing the already-small corpus clip returns the original bytes with `usedOriginal` reported, instead of a bigger file. A clip that already meets the target is remuxed without re-encoding (`transmuxed: true`) in a fraction of the encode time.
  3. With default options, AAC audio is passed through and reported as not re-encoded. The caller can force an AAC re-encode at a chosen bitrate and channel count, or strip audio, and the result reflects that choice.
  4. Two jobs started together each have their own 0-100 progress stream and completion future. Cancelling one resolves it as Cancelled and deletes its partial file. Failures (unsupported input, out of space) arrive as typed errors and never crash the app.
  5. A pre-flight estimate for a clip and options returns output size and duration without encoding, within the documented tolerance of the real result. Output lands in the chosen directory/name or a unique cache name, and `clearCache()` deletes only the plugin's files. The Android build uses Media3 Transformer, minSdk 23 and compileSdk 36, contains no `.so` files, and builds on the current stable AGP/Kotlin.

**Plans**: 7/7 plans executed

Plans:
**Wave 1**

- [x] 02-01-PLAN.md — High-bitrate 60 fps portrait corpus clip and a structurally damaged clip, with derived sidecars, an edge probe, the filled validation contract and the coverage declaration

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 02-02-PLAN.md — Pigeon compression contract, the Dart type surface, and the tracer: one call turns the high-bitrate clip into a smaller upright MP4 through Media3 on the emulator

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 02-03-PLAN.md — `SizeGuard`: presets, explicit max-long-side / bitrate / target-MB targets, the 30 fps cap, even dimensions and the never-upscale rule

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 02-04-PLAN.md — Never-larger pre-check and post-check, the transmux fast path with a measured speed ratio, and `doc/PRESETS.md` generated from measurement

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 02-05-PLAN.md — Audio passthrough, re-encode and strip with channel mixing; trim; upright output and no black bars proven by sampling the compressed file

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 02-06-PLAN.md — Per-job progress and cancellation, idempotent cancel, the full 22-code error mapping and the pre-flight free-space check

**Wave 7** *(blocked on Waves 4 and 6 completion)*

- [x] 02-07-PLAN.md — Pre-flight estimate sharing one resolver with the real job, output placement and a bounded `clearCache()`, the APK native-library and 16 KB proof, and CI wiring

**Research**: Not flagged. Media3 Transformer, `VideoEncoderSettings`, `Presentation` and `ClippingConfiguration` are covered in research/STACK.md. The preset table (maxLongSide × bitrate) is a measurement task on the corpus, not a research task. A phase research pass ran anyway and produced `02-RESEARCH.md`, which pinned media3 1.11.1 live, verified the Transformer main-Looper contract, and found every existing corpus clip too low-bitrate to exercise a real encode — the reason plan 02-01 exists.
**Notes**: This phase sets the observable behaviour that Phase 3 must match. Write the README preset constants from measured sizes here so later docs are generated, not written from memory. The gate for this phase is the local emulator: GitHub Actions is refused on an account billing limit (QUESTIONS.md #6), so CI wiring is written and committed but a refused run is recorded as an external blocker, never as a task failure.

### Phase 3: Apple Compression to Parity

**Goal**: The same Dart call gives the same observable result on iOS and macOS as on Android, installs through CocoaPods or SPM, and trims exactly on every platform.
**Depends on**: Phase 1 (contract). Phase 2 for the cross-platform parity sign-off.
**Requirements**: CORE-01, CORE-07, BULD-02, BULD-04
**Success Criteria** (what must be TRUE):

  1. On the iOS simulator and on macOS, the portrait corpus clip compresses to a smaller, upright H.264/AAC MP4. Presets, explicit targets, never-larger, transmux, audio options, typed errors, per-job progress and cancel behave as they do on Android, and the same corpus integration tests pass on all three platforms.
  2. A trim from 2000 ms to 7000 ms produces an output 5 s long, within one frame, on Android, iOS and macOS.
  3. A fresh Flutter app adds the plugin and builds for iOS and macOS with CocoaPods and, separately, with Swift Package Manager. iOS and macOS use one shared Swift core.
  4. The example app runs on Android, iOS and macOS. In it, a user picks a video, sets options, watches live progress, can cancel, and plays the compressed result.

**Plans**: 6/9 plans executed

Plans:
**Wave 1**

- [ ] 03-01-PLAN.md — Mac build host (second Flutter SDK, `tool/mac_sync.sh`, `tool/mac_run.sh`, SPM builds of the current example), the 10-second trim fixture with its derived `trim` sidecar block, the filled validation contract and the coverage declaration

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 03-02-PLAN.md — Pure Swift ports: `SizeGuard`, `ErrorMapping` and `PluginFiles`, pinned by XCTest twins carrying the Kotlin suite's own numeric cases on both Apple platforms
- [x] 03-03-PLAN.md — Example app rewrite (BULD-04): pick, options, live estimate, compress, progress, cancel, result card, playback, with a widget suite covering all seven states on Linux

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 03-04-PLAN.md — The Apple engine tracer: one Dart call through `AVAssetReader`/`AVAssetWriter` to a smaller upright MP4, plus the job registry and the two platform-specific teardown paths

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 03-05-PLAN.md — Transmux fast path, the unconditional two-stage never-larger rule, and the three audio modes

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 03-06-PLAN.md — Per-job progress, cancellation with partial-file deletion ordered first, the wired error taxonomy and the free-space pre-check

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 03-07-PLAN.md — Trim within one frame on all three platforms (CORE-07), the shared-resolver estimate, output placement and bounded `clearCache()`, and the measured Apple preset tables

**Wave 7** *(blocked on Waves 2 and 6 completion)*

- [ ] 03-08-PLAN.md — `status: partial`. Compression records added to the parity gate (all four suites, two-comparison `parity` job) and CI's `apple` job widened with a macOS `integration_test` run, a fixed macOS launch-flake watchdog, and a macOS SPM build — all green on CI run 36202392709. `tool/verify_fresh_app.sh` (task 1, BULD-02's fresh-app CocoaPods/SPM proof) not yet written: blocked on the MacBook Air being unreachable (QUESTIONS.md #8)

**Wave 8** *(blocked on Wave 7 completion)*

- [ ] 03-09-PLAN.md — Phase sign-off: committed simulator and macOS screenshots closing 02-UAT.md #6, one observed green `apple` + `parity` CI run, and the cross-platform sameness wording

**UI hint**: yes
**Research**: Needed. Topics: AVAssetWriter output settings for 8-bit/HDR reader output, `sourceFormatHint`, deriving progress without the deprecated export-session `progress`, and differences between macOS and iOS.
**Notes**: **Start with a Mac-readiness check.** Confirm that `ssh dans-macbook-air` works and that Xcode with iOS simulators, CocoaPods and Flutter are installed (QUESTIONS.md #1). If the check fails, build against the GitHub Actions macOS runner and record in STATE.md that device checks are outstanding. **Parallelizable with Phase 2 once the Mac is available.** The two phases share only the Phase 1 Pigeon contract.

### Phase 4: Codecs, HDR and Hard Inputs

**Goal**: The inputs every competitor got wrong come out correct: HDR phone video is not washed out, HEVC is used only where hardware supports it, and unusual audio never fails. A real-clip corpus in CI keeps it that way.
**Depends on**: Phase 2, Phase 3
**Requirements**: CDEC-01, CDEC-02, CDEC-03, AUDO-03, TEST-01
**Success Criteria** (what must be TRUE):

  1. A portrait iPhone Dolby Vision clip and a Pixel HLG10 clip from the corpus each compress, with default options, to a smaller upright SDR MP4 that is not washed out. The result reports `toneMapped: true` on Android and on Apple.
  2. With HEVC opt-in, a device that has a hardware HEVC encoder produces HEVC. A device without one produces H.264, and the result reports the fallback. With keep-HDR opt-in, a capable device outputs HEVC 10-bit HDR and an incapable one falls back to tone-mapped SDR, again reported.
  3. The 5.1-audio, PCM-audio and no-audio corpus clips and the 4K60 clip all compress successfully on the Android emulator and the iOS simulator, by downmixing or re-encoding, without an error.
  4. CI runs the full committed corpus (Dolby Vision, HLG10, portrait, 4K60, PCM, no audio, 5.1, already-small) through integration tests on the Android emulator and iOS simulator. A documented hardware checklist covers HEVC hardware encode and HDR tone-map fidelity on physical devices and has been run once.

**Plans**: TBD
**Research**: Needed. Topics: Media3 `HdrMode` behaviour by API level and device, Apple keep-HDR writer settings, and HEVC capability probing on both platforms.
**Notes**: Hardware HEVC/HDR checks need a physical Android phone (QUESTIONS.md #3) and an Apple device through the Mac (QUESTIONS.md #1).

### Phase 5: Jobs, Isolates and Background

**Goal**: Apps can queue several compressions, run them off the main isolate, and keep an Android job alive in the background, with honest behaviour when iOS suspends the app.
**Depends on**: Phase 2, Phase 3 (per-job model on both engines). Independent of Phase 4.
**Requirements**: JOBS-03, JOBS-04, JOBS-05
**Success Criteria** (what must be TRUE):

  1. Submitting three jobs runs them one at a time by default. With a concurrency limit of 2, two run at once. Each job reports its own progress and result.
  2. A compression started from a background isolate completes and returns its typed result, with no main-isolate-only failure.
  3. On Android 15/16, a job with the `mediaProcessing` foreground-service option keeps running and completes after the user sends the app to the background.
  4. On iOS, suspending the app mid-job resolves the job with a retryable Interrupted error, never a hang or `null`, and the README documents this behaviour.

**Plans**: TBD
**Research**: Needed. Topics: the `mediaProcessing` foreground-service lifecycle and time limits on Android 15/16, and iOS background-task limits.
**Notes**: Can run in parallel with Phase 4. Both depend only on Phases 2 and 3.

### Phase 6: Release and Migration

**Goal**: A developer on `video_compress` can switch to `compress_video` from pub.dev by changing one import. The documentation says exactly what each preset does and what the plugin will not do.
**Depends on**: Phase 4, Phase 5
**Requirements**: RELS-01, RELS-02, RELS-03
**Success Criteria** (what must be TRUE):

  1. `compress_video` is live on pub.dev and scores 160/160 pub points (documentation, example, platform declarations, analysis clean).
  2. The README has a plain-English table of each preset's resolution, bitrate and fps on each platform, generated from the measured preset constants, and a section on what the plugin deliberately does not do.
  3. An app using `video_compress`'s `compressVideo`, `getMediaInfo`, `getFileThumbnail`, `cancelCompression` and `deleteAllCache` builds and works after switching to the compatibility import. MIGRATION.md maps every old API and `VideoQuality` value to the new API.
  4. The TEST-01 hardware checklist has been re-run against the release build before publishing.

**Plans**: TBD
**Research**: Skip. pub.dev publishing and scoring are well documented.
**Notes**: Publishing needs a verified pub.dev publisher, or Dan's decision to publish under his Google account (QUESTIONS.md #2).

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6.
Phases 2 and 3 can run in parallel once the Mac is reachable. Phases 4 and 5 can run in parallel.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Typed Contract, CI and Media Info | 5/7 | In progress | - |
| 2. Android Compression on Media3 | 7/7 | In Progress|  |
| 3. Apple Compression to Parity | 5/9 | In Progress | - |
| 4. Codecs, HDR and Hard Inputs | 0/TBD | Not started | - |
| 5. Jobs, Isolates and Background | 0/TBD | Not started | - |
| 6. Release and Migration | 0/TBD | Not started | - |
