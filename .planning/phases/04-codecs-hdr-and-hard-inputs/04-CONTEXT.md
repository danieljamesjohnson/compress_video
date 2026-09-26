# Phase 4: Codecs, HDR and Hard Inputs - Context

**Gathered:** 2026-09-26
**Status:** Ready for planning
**Mode:** Smart discuss, recommended answers AUTO-ACCEPTED. Dan was not available (the run was
started with "resume phase 3 at 03-06 and go full auto" on 2026-09-25 and this phase began
overnight). Every decision below is the orchestrator's recommended answer, not a Dan decision;
any of them can be overridden by editing this file before or during planning.

<domain>
## Phase Boundary

The inputs every competitor got wrong come out correct on Android, iOS and macOS: HDR phone
video (Dolby Vision profile 8, HLG, HDR10) is tone-mapped to SDR by default and reported as
such; HEVC is an opt-in that is used only where a hardware encoder exists and otherwise falls
back to H.264 with the fallback reported; keep-HDR is an opt-in that outputs HEVC 10-bit HDR
where the device can and falls back to tone-mapped SDR, reported, where it cannot; sources with
5.1, PCM or no audio, and a 4K60 source, compress without error by downmixing or re-encoding. A
committed corpus covering all of these runs through integration tests on the Android emulator
and the iOS simulator in CI, and a documented hardware checklist covers what only physical
devices can prove. Requirements: CDEC-01, CDEC-02, CDEC-03, AUDO-03, TEST-01.

Out of scope: web/WebCodecs, background/foreground-service work (Phase 5), release packaging
(Phase 6).

</domain>

<decisions>
## Implementation Decisions

### HDR inputs and tone-mapping
- The real iPhone Dolby Vision and Pixel HLG10 clips (QUESTIONS.md #4) are not on danserver.
  Generate 10-bit HEVC HLG (arib-std-b67) and PQ/HDR10 (smpte2084, bt2020) corpus clips with
  ffmpeg now, sidecars machine-derived like every other clip (`generate_corpus.sh` +
  `verify_corpus.sh --write`), and reserve named corpus slots plus identical test cases for the
  real phone clips so they slot in the moment Dan drops them. Do not block the phase on them.
  ffmpeg cannot author Dolby Vision RPU metadata; the DV profile-8 case is real-clip-only and is
  listed in the hardware checklist until that clip exists.
- "Not washed out" is asserted by sampling the produced file, as the Phase 3 orientation tests
  do: the synthetic HDR clips carry a known pattern with known SDR expectations; the test asserts
  the sampled saturation/luma land within a documented tolerance and that the result reports
  `toneMapped: true`.
- Android: request Media3 `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL` first, fall back to
  `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_MEDIACODEC` (API 31+); if neither path is available on the
  device, fail with a typed `unsupportedInput` error rather than emit washed-out video. Never
  silently pass HDR through when SDR was requested.
- Apple: keep Phase 3's decision (D-08 in 03-CONTEXT.md): the reader outputs 8-bit BGRA so the
  system tone-maps HDR to SDR; assert the result on the simulator.

### HEVC opt-in and keep-HDR
- Hardware HEVC detection: Android enumerates `MediaCodecList` for a `video/hevc` encoder whose
  name is not a software codec (`c2.android.`, `OMX.google.`, `c2.sw`, `OMX.SEC.*.sw` prefixes);
  Apple asks VideoToolbox (`VTCopySupportedPropertyDictionaryForEncoder` with
  `kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder`). The Android emulator
  and the iOS simulator have no hardware HEVC encoder, so CI exercises the fallback path; HEVC
  success itself lives in the hardware checklist.
- HEVC fallback is reported through the existing `hevcFallback: true` result field with H.264
  output. No new field.
- Keep-HDR output is HEVC Main10 carrying the source's transfer function (HLG or PQ) with
  BT.2020 primaries: Apple via `AVVideoColorPropertiesKey` + `AVVideoProfileLevelKey` HEVC
  Main10 (WWDC20 10010); Android via Media3 `HDR_MODE_KEEP_HDR`. Requires a hardware HEVC
  10-bit encoder; otherwise fall back.
- Keep-HDR fallback is tone-mapped SDR H.264 reported as `toneMapped: true` and
  `hevcFallback: true`; document that "keep-HDR requested and `toneMapped: true`" means the
  fallback happened. No new result field.

### Unusual audio and 4K60
- 5.1 audio is downmixed to stereo AAC at 128 kbps (Media3 `ChannelMixingAudioProcessor`;
  AVAssetWriter 2-channel AAC), reported `audioReencoded: true`.
- PCM audio is re-encoded to stereo AAC at 128 kbps, reported `audioReencoded: true`.
- No-audio sources continue to produce no audio track (already proven in Phases 2-3).
- The 4K60 corpus clip is synthetic 3840x2160 at 60 fps, 2-3 s, bitrate capped so the file
  stays a few MB, so decode on the emulator and simulator fits the 120 s per-test timeout.
- All of these cases live in ONE new suite, `example/integration_test/hard_inputs_test.dart`,
  wired into `tool/run_ios_integration_suites.sh`'s suite list, the Android emulator step, and
  the PARITY_JSON compression records, rather than spread across the existing suites.

### CI and the hardware checklist
- `doc/HARDWARE_CHECKLIST.md` documents the hardware-only checks (HEVC hardware encode, keep-HDR
  output, HDR tone-map fidelity by eye, `targetSizeMb`/estimate tolerances on a hardware
  encoder per QUESTIONS.md #3) with exact commands and expected results. "Has been run once" is
  a Deferred Item until a physical Android phone (QUESTIONS.md #3) and the Mac plus an Apple
  device are available, the same way Phase 3 deferred its Mac-only proofs. Do not block on it.
- New corpus clips are generated by `corpus/generate_corpus.sh`, verified by
  `corpus/verify_corpus.sh --write`, mirrored by `corpus/sync_to_example.sh`; CI's drift gate
  covers them. Never hand-commit a clip or a sidecar.
- Keep the 90-minute simulator-suite budget; if the new suite pushes the Apple job past it,
  split the suites across two CI steps rather than raising timeouts again.
- On the iOS simulator, keep-HDR and HEVC opt-in assert the fallback path only.

### Claude's Discretion
- Exact ffmpeg filter graphs and encoder settings for the synthetic HDR and 4K60 clips.
- Whether the tone-map fidelity assertion samples one frame or several.
- Internal shape of the codec-capability probe (a small `CodecCapabilities` type on each
  platform mirroring the other, per the Phase 3 parity conventions).
- How the Android and Apple probes are unit-tested without hardware (injectable codec lists).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/src/compress_options.dart`: `VideoCodec` (h264 default, hevc reserved) and `HdrMode`
  (`toneMapToSdr` only accepted so far) already exist; Phase 4 activates the reserved values.
- `CompressResult` already carries `toneMapped`, `hevcFallback`, `audioReencoded`; the Pigeon
  contract (`pigeons/messages.dart`) carries them too. No contract shape change is needed for
  the recommended reporting decisions.
- Corpus tooling: `corpus/generate_corpus.sh` (clips A-F), `corpus/verify_corpus.sh --write`
  (sidecars), `corpus/sync_to_example.sh`; CI drift gate.
- Test patterns: sidecar-driven assertions; produced-file sampling for orientation
  (`compress_test.dart`); esds-authoritative audio probing (`compress_audio_test.dart`);
  PARITY_JSON records and `tool/check_parity.sh` with its self-test.
- Engines: Android `TransformerEngine` (Media3 1.11 Transformer: `setVideoMimeType`,
  `Composition.setHdrMode`, audio processors); Apple `CompressionEngine` (AVAssetReader/Writer,
  transmux fast path, `finishJob` never-larger post-check), `ErrorMapping.swift`,
  `SizeGuard` on both platforms.
- CI: `tool/run_ios_integration_suites.sh` (per-suite watchdog, iOS and macOS), 90-minute step
  budget, preset measurement steps, parity job with three artifacts.

### Established Patterns
- Never-larger post-check is unconditional on both platforms (do not bypass for HDR/HEVC).
- Every failure is a typed `CompressVideoError`; new failure modes get a mapped reason on both
  platforms and a parity note if the buckets differ (corpus/README.md pattern).
- Cross-platform behaviour is proven by the same Dart integration suite on all three platforms
  plus PARITY_JSON records; platform-specific XCTest/JVM unit tests cover pure logic.
- Mac work is probed once (`timeout 15 ssh -o ConnectTimeout=8 -o BatchMode=yes
  dans-macbook-air true`), never looped; CI is the Apple verifier when the Mac is asleep.

### Integration Points
- `Arguments.kt` / `Arguments.swift` `requireValidCompressRequest`: currently rejects
  `videoCodec != h264` and `hdrMode != toneMapToSdr`; Phase 4 relaxes both with capability
  probing behind them.
- `SizeGuard` resolution feeds encoder settings; HEVC changes the bitrate ladder assumptions
  (document in `doc/PRESETS.md`).
- Android `TransformerEngine.finishSuccess` / Apple `CompressionEngine.finishJob` build the
  result; `toneMapped`/`hevcFallback` are set there.

</code_context>

<specifics>
## Specific Ideas

- Success criterion 1 names real phone clips; the synthetic HLG/PQ clips prove the pipeline in
  CI now and the real clips (QUESTIONS.md #4) prove Dolby Vision profile 8 and real camera
  metadata later, with identical assertions.
- Research (plan-phase) must verify against the pinned Media3 1.11 sources which
  `HdrMode` values the emulator's software decoder/encoder path actually supports at API 35,
  and what VideoToolbox reports on the simulator, before the plan promises CI assertions.

</specifics>

<deferred>
## Deferred Ideas

- Running the hardware checklist on a physical Android phone and an Apple device (blocked on
  QUESTIONS.md #3 and the Mac; tracked as a Deferred Item once the checklist exists).
- Real Dolby Vision / HLG10 phone clips joining the corpus (QUESTIONS.md #4).
- Tightening `targetSizeMb` and estimate tolerances on hardware encoders (QUESTIONS.md #3).

</deferred>
