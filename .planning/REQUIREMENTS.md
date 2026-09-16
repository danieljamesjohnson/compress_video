# Requirements: compress_video

**Defined:** 2026-09-15
**Core Value:** One call turns a phone video into a smaller MP4 that plays everywhere, and it never makes the file bigger, never returns null, and builds on today's Flutter toolchain.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Core compression

- [ ] **CORE-01**: App can compress a local video file to an H.264 + AAC MP4 with a single call, on Android, iOS and macOS, with the same Dart API and the same observable behaviour on each
- [x] **CORE-02**: Caller can choose output size by a named preset (documented per platform: what resolution and bitrate it really produces) or by an explicit target: max long side in pixels, video bitrate, or target file size in MB
- [x] **CORE-03**: Caller receives a typed result: output path, bytes before and after, width, height, duration, codec used, whether the video track was transmuxed, whether HDR was tone-mapped, elapsed time; the call never resolves to `null`
- [x] **CORE-04**: Failures surface as typed errors with a reason (unsupported input, encoder unavailable, out of space, interrupted, cancelled); no failure can crash the host app, and no failure is swallowed into a debug print
- [x] **CORE-05**: Output is never larger than the input: when the encode would be bigger, the plugin returns the original bytes (copied to the output path) and the result says so
- [x] **CORE-06**: When the input already satisfies the target (resolution, fps, codec, bitrate), the plugin remuxes without re-encoding and completes in a fraction of the encode time; the result reports it
- [ ] **CORE-07**: Caller can trim with start and end in milliseconds; the output duration matches the requested range within one frame on every platform
- [x] **CORE-08**: Caller can cap the output frame rate (default cap 30 fps); resolution and frame rate are never upscaled
- [x] **CORE-09**: Caller can choose the output directory and file name; the default is a unique name in the app cache directory, and a `clearCache()` removes only files the plugin created

### Orientation, codecs and HDR

- [x] **ORNT-01**: Portrait and rotated inputs play upright in every common player, the result's width/height describe the displayed orientation, and the frame has no black bars or padding
- [ ] **CDEC-01**: H.264 is the default codec; caller can opt into HEVC, which is used only when a hardware encoder exists and otherwise falls back to H.264 with the fallback reported in the result
- [ ] **CDEC-02**: HDR input (Dolby Vision profile 8, HLG, HDR10) is tone-mapped to SDR by default so the output is not washed out; the result reports that tone-mapping happened
- [ ] **CDEC-03**: Caller can opt to keep HDR (HEVC 10-bit) on devices that support it; on devices that do not, the plugin falls back to tone-mapped SDR and reports it

### Audio

- [x] **AUDO-01**: Audio is passed through without re-encoding when the source track is MP4-compatible AAC, and the result says whether audio was re-encoded
- [x] **AUDO-02**: Caller can force AAC re-encode with a chosen bitrate and channel count, or strip audio entirely
- [ ] **AUDO-03**: Sources with unusual audio (5.1 channels, PCM, no audio track) compress successfully by downmixing or re-encoding rather than failing

### Jobs, progress and cancellation

- [x] **JOBS-01**: Each compression is a job with its own progress stream (0–100) and completion future; there is no global progress stream shared across calls
- [x] **JOBS-02**: Caller can cancel a job; the job resolves with a distinct Cancelled outcome, and any partial output file is deleted
- [ ] **JOBS-03**: Caller can submit several jobs; they run sequentially by default with an optional concurrency limit, and each reports its own progress
- [ ] **JOBS-04**: The API can be called from a background isolate
- [ ] **JOBS-05**: On Android, caller can opt into a `mediaProcessing` foreground service so a job survives the app going to the background; on iOS the plugin documents that exports are interrupted on suspension and surfaces that case as a retryable Interrupted error

### Media info and thumbnails

- [ ] **INFO-01**: Caller can read media info for a file: duration, rotation-corrected width and height, rotation, file size, video codec, bitrate, frame rate, whether it has audio, whether it is HDR
- [ ] **INFO-02**: Caller can get a thumbnail at a position given in milliseconds (the same unit on every platform), as bytes or as a file with a unique name, rotation-correct, with JPEG quality and maximum dimension options
- [x] **INFO-03**: Caller can ask for an estimate of output size and duration for a given input and options without running the encode

### Build, platforms and verification

- [x] **BULD-01**: Android implementation uses Media3 Transformer with minSdk 23, builds on the current stable AGP and Kotlin with the AGP-9 built-in Kotlin path, targets compileSdk 36, and contains no native `.so` code (16 KB page-size safe by construction)
- [ ] **BULD-02**: iOS (13+) and macOS (11+) implementations share one Swift core, and the package installs through both CocoaPods and Swift Package Manager
- [ ] **BULD-03**: Dart and native sides communicate through Pigeon-generated typed messages; every quantity has one unit documented in the Dart API
- [ ] **BULD-04**: The example app picks a video, compresses it with chosen options, shows live progress, cancels, and plays the result, on all three platforms
- [ ] **BULD-05**: CI builds the plugin and example on every push for Android (Linux runner) and iOS/macOS (macOS runner), runs Dart unit tests and native unit tests, and fails on analyzer warnings
- [ ] **TEST-01**: A committed real-clip corpus (iPhone Dolby Vision, Pixel HLG10, portrait, 4K60, PCM audio, no audio, 5.1 audio, an already-small clip) runs through integration tests on the Android emulator and iOS simulator in CI, with a documented checklist of hardware-only checks (HEVC hardware encode, HDR tone-map fidelity) run on physical devices before each release

### Release and migration

- [ ] **RELS-01**: Package is published on pub.dev as `compress_video` and scores 160/160 pub points (documentation, example, platform declarations, analysis clean)
- [ ] **RELS-02**: README contains a plain-English table of what each preset does on each platform (resolution, bitrate, fps) and a section on what the plugin deliberately does not do
- [ ] **RELS-03**: A migration guide maps every `video_compress` API and `VideoQuality` enum value to the new API, and a compatibility layer exposes the old verbs (`compressVideo`, `getMediaInfo`, `getFileThumbnail`, `cancelCompression`, `deleteAllCache`) over the new engine so a dependent can switch with a one-line import change

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Platforms

- **PLAT-01**: Web implementation via WebCodecs plus a JS muxer (video-only on Safari < 26)
- **PLAT-02**: Windows and Linux via platform media APIs (not FFmpeg)

### Features

- **FEAT-01**: GIF to MP4 conversion
- **FEAT-02**: Batch API with a single aggregate progress and per-item results
- **FEAT-03**: Pause and resume a job across app backgrounding on Android
- **FEAT-04**: AV1 output where a hardware encoder exists

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| FFmpeg dependency | 100 MB binaries, effectively GPL, slow software encode; "100% native" is why users chose the incumbent |
| Watermarks, filters, stitching, editing | Different product; one request (6 reactions) in six years of the incumbent's tracker |
| Upload / networking | The app's job; the plugin only produces a file |
| Web in v1 | 12 reactions total; Safari support only complete from 26; needs the native core stable first |
| Server-side transcoding | Out of the on-device problem entirely |
| Supporting Android < 23 | Media3 ≥ 1.9 requires 23; the incumbent's users are on modern toolchains |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

Behaviour requirements with no platform named are mapped to Phase 2 (Android), where they are
first delivered. Phase 3 (Apple) must pass the same corpus tests as a parity gate, and it owns
the requirements that name all platforms explicitly (CORE-01, CORE-07, BULD-04).

| Requirement | Phase | Status |
|-------------|-------|--------|
| CORE-01 | Phase 3 | Pending |
| CORE-02 | Phase 2 | Complete |
| CORE-03 | Phase 2 | Complete |
| CORE-04 | Phase 2 | Complete |
| CORE-05 | Phase 2 | Complete |
| CORE-06 | Phase 2 | Complete |
| CORE-07 | Phase 3 | Pending |
| CORE-08 | Phase 2 | Complete |
| CORE-09 | Phase 2 | Complete |
| ORNT-01 | Phase 2 | Complete |
| CDEC-01 | Phase 4 | Pending |
| CDEC-02 | Phase 4 | Pending |
| CDEC-03 | Phase 4 | Pending |
| AUDO-01 | Phase 2 | Complete |
| AUDO-02 | Phase 2 | Complete |
| AUDO-03 | Phase 4 | Pending |
| JOBS-01 | Phase 2 | Complete |
| JOBS-02 | Phase 2 | Complete |
| JOBS-03 | Phase 5 | Pending |
| JOBS-04 | Phase 5 | Pending |
| JOBS-05 | Phase 5 | Pending |
| INFO-01 | Phase 1 | Pending |
| INFO-02 | Phase 1 | Pending |
| INFO-03 | Phase 2 | Complete |
| BULD-01 | Phase 2 | Complete |
| BULD-02 | Phase 3 | Pending |
| BULD-03 | Phase 1 | Pending |
| BULD-04 | Phase 3 | Pending |
| BULD-05 | Phase 1 | Pending |
| TEST-01 | Phase 4 | Pending |
| RELS-01 | Phase 6 | Pending |
| RELS-02 | Phase 6 | Pending |
| RELS-03 | Phase 6 | Pending |

**Coverage:**

- v1 requirements: 33 total (this file first said 32, but it lists 33 IDs)
- Mapped to phases: 33
- Unmapped: 0 ✓

---
*Requirements defined: 2026-09-15*
*Last updated: 2026-09-15 after roadmap creation (traceability filled)*
