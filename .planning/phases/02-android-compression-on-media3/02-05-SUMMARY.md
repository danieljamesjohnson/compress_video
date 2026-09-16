---
phase: 02-android-compression-on-media3
plan: 05
subsystem: compression-engine
tags: [media3, transformer, kotlin, audio, channel-mixing, clipping-configuration, orientation, mp4-box-parsing]

# Dependency graph
requires:
  - phase: 02-android-compression-on-media3
    provides: "02-04's TransformerEngine architecture (never-larger pre/post-check, wouldTransmux-gated DefaultEncoderFactory, InAppMp4Muxer with streamable output disabled) and SizeGuard.Plan's already-clamped audio bitrate resolution (02-03 rule 5), both extended rather than re-decided by this plan"
provides:
  - "TransformerEngine's three audio-mode branches: passthrough (unconditional AUDIO_AAC transformer-level mime request, no audio-specific encoder settings, transparently copies an AAC source or falls back to an AAC re-encode of a non-AAC one), strip (setRemoveAudio), and reencode (explicit AudioEncoderSettings at SizeGuard's clamped bitrate plus a ChannelMixingAudioProcessor/ChannelMixingMatrix.createForConstantGain whenever the requested channel count differs from the source's own)"
  - "MediaItem.ClippingConfiguration-based trim, replacing no trim implementation at all -- setEndPositionMs takes an end position, not a duration, documented inline against the incumbent's own trim bug"
  - "TransformerEngine.buildVideoEffects: the video effects list extracted into a pure, internal companion function (geometry first, frame selection second) that EffectOrderTest exercises directly with no Transformer/Looper"
  - "compress_test.dart's _expectUprightAndUnpadded: samples a compressed OUTPUT's own pixels (thumbnail probe + four edge-midpoint samples, scaled from source-displayed to this output's own displayed coordinates) to prove upright orientation and no black-bar padding, reused across the default-preset and long-side-adjacency cases"
  - "compress_audio_test.dart's _readMp4AudioTrackInfo: a test-only ISO/IEC 14496-12 box walker (moov -> trak(soun) -> mdia -> minf -> stbl -> stsd/stsz, including the 64-bit extended mdat size Media3's disabled-streamable-output layout produces) that reads channel count and an audio-only bitrate estimate directly from the produced file's own bytes, since neither CompressResult nor MediaInfo exposes either fact"
  - "Completed dartdoc for AudioOptions/AudioPassthrough/AudioReencode/AudioStrip, CompressResult.audioReencoded/audioCodec/widthPx/heightPx; AudioReencode boundary tests mirrored on both sides of the channel (compress_options_test.dart, ArgumentsTest.kt)"
affects: [02-06, 02-07, phase-6-readme]

# Actuals (#2632)
actuals:
  tokens: 25000
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Audio encoder settings (AudioEncoderSettings, ChannelMixingAudioProcessor) are only ever added to DefaultEncoderFactory for an explicit REENCODE request -- confirmed via javap on the installed media3-transformer:1.11.1 AAR that DefaultEncoderFactory.audioNeedsEncoding() mirrors the video videoNeedsEncoding() bug 02-04 found (plain reference/Object equality against AudioEncoderSettings.DEFAULT, since AudioEncoderSettings has no equals() override) -- so passthrough and strip never touch audio encoder settings, preserving the transmux fast path for an already-AAC source"
    - "Transformer.Builder.setAudioMimeType(AUDIO_AAC) stays unconditional across every audio mode -- it is what makes an already-AAC passthrough copy cleanly (matching mime, no forced transcode) AND what makes a non-AAC passthrough source fall back to an AAC re-encode automatically, with no separate branch needed for either outcome"
    - "TransformerEngine.buildVideoEffects: video effects list construction extracted into an internal companion function with no Context/Looper/Transformer dependency, exactly mirroring SizeGuard.resolve()'s own pure-function shape -- EffectOrderTest proves the pinned geometry-then-frame-selection order without an emulator"
    - "Test-only MP4 box parsing (compress_audio_test.dart) as the pattern for verifying native facts CompressResult/MediaInfo don't expose over the wire -- the Dart-side counterpart to Probe.kt's own native sample-size-summation fallback (02-03), applied here to channel count and audio-only bitrate instead of video bitrate"

key-files:
  created: []
  modified:
    - android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/SizeGuardTest.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/ArgumentsTest.kt
    - lib/src/compress_options.dart
    - lib/src/compress_result.dart
    - test/compress_options_test.dart
    - example/integration_test/compress_audio_test.dart
    - example/integration_test/compress_test.dart

key-decisions:
  - "TransformerEngine.buildVideoEffects was extracted (and EffectOrderTest.kt written) during Task 1's audio-processor wiring, one task ahead of the plan's own Task 2 assignment -- the audio-processor list needed a clean insertion point next to the existing video-effects construction, and extracting both into the companion object at once avoided duplicating that construction. Task 2 only had to add the Dart-side orientation/trim proofs; the Kotlin side was already done and tested."
  - "AudioReencode/AudioStrip integration cases were moved from small_480p.mp4 to portrait_hibitrate_1080p60.mp4 after a live failure: small_480p.mp4's own video bitrate (~130kbps) sits close enough to the resolved preset-scaled target that this emulator's CBR software encoder's known overshoot (02-03) can push a genuine re-encode's byte count at or above the input's own size, tripping CORE-05's unconditional never-larger post-check and silently substituting the original file -- which would have made every audio assertion in that test vacuous (the audio track observed would be the untouched source's, not the reencoded one). portrait_hibitrate_1080p60.mp4's ~8.7Mbps source shrinks by design regardless of what the audio track does, isolating the audio behavior cleanly."
  - "Channel count and an audio-only bitrate estimate are read in the Dart integration test directly from the produced MP4's own moov/stsd/stsz boxes rather than by adding a wire field to MediaInfoMessage/CompressResultMessage. Task 1's declared file list did not include pigeons/messages.dart, Probe.kt, or a public MediaInfo/CompressResult field, and the audio-only bitrate in particular is native-internal information TransformerEngine.kt's own doc comments say has no other consumer -- adding it to the public wire contract for one test file's benefit would have been scope creep past what the plan declared. Reading the file's own bytes directly is also the same 'prove what actually came out of it' philosophy the plan already applies to pixels for orientation."
  - "AudioEncoderSettings' bitrate is taken from SizeGuard.Plan.audioBitrateBps (rule 5's already-clamped resolution) rather than re-deriving or re-clamping the request's own raw bitrate a second time in TransformerEngine -- SizeGuard is the single source of truth for that number, exactly as it already is for video bitrate."

patterns-established:
  - "A DefaultEncoderFactory branch that forces a real encode (video, audio, or both) must build ITS OWN non-default settings object per track it intends to change, and must never build one for a track it means to leave alone -- the video/audio halves of TransformerEngine's encoderFactory now follow this rule symmetrically, both traceable to the same javap-verified DEFAULT-equality precondition."

requirements-completed: [AUDO-01, AUDO-02, ORNT-01]

coverage:
  - id: D1
    description: "Default options (AudioPassthrough) on an AAC source copy the audio track: audioReencoded false, audioCodec aac, and the output still has audio -- the passthrough proof covers both that the track survived AND that it was not re-encoded"
    requirement: AUDO-01
    verification:
      - kind: integration
        ref: "compress_audio_test.dart#'default options (AudioPassthrough) on an AAC source copy the audio track...'"
        status: pass
    human_judgment: false
  - id: D2
    description: "AudioOptions.strip produces an output with no audio track at all: audioCodec null, audioReencoded false"
    requirement: AUDO-02
    verification:
      - kind: integration
        ref: "compress_audio_test.dart#'AudioOptions.strip produces an output with no audio track at all...'"
        status: pass
    human_judgment: false
  - id: D3
    description: "AudioOptions.reencode honours the requested bitrate and channel count exactly: 64000bps/2ch and 1ch cases both re-probe as AAC with the exact requested channel count and a measured bitrate within 25 percent of the request, read directly from the produced file's own mp4a/stsz boxes"
    requirement: AUDO-02
    verification:
      - kind: integration
        ref: "compress_audio_test.dart#'AudioOptions.reencode at 64000bps/2 channels...'"
        status: pass
      - kind: integration
        ref: "compress_audio_test.dart#'the same reencode request at 1 channel re-probes as exactly 1 channel'"
        status: pass
    human_judgment: false
  - id: D4
    description: "A requested audio bitrate outside the device AAC encoder's 8000-960000bps range is clamped rather than rejected, on both the pure resolution function and the real encoder path; the resolution function's clamp/fallback rules are unit-proven in both directions plus the source-fallback case"
    requirement: AUDO-02
    verification:
      - kind: unit
        ref: "SizeGuardTest.kt#requestedAudioBitrateInsideTheRange_passesThroughUnchanged, #noRequestedAudioBitrate_fallsBackToTheSourceSOwnAudioBitrate, #requestedAudioBitrateBelow8000_clampedUpToTheFloor, #requestedAudioBitrateAbove960000_clampedDownToTheCeiling"
        status: pass
      - kind: integration
        ref: "compress_audio_test.dart#'a reencode request at 1000bps succeeds with the bitrate clamped up...'"
        status: pass
    human_judgment: false
  - id: D5
    description: "A source whose audio is not MP4-compatible AAC is re-encoded to AAC by default rather than failing (the default path falls back rather than crashing on an unusual audio track)"
    requirement: AUDO-01
    verification: []
    human_judgment: true
    rationale: "No corpus fixture in this project carries a non-AAC audio track, so this path has no automated end-to-end proof. The implementation relies on Transformer.Builder.setAudioMimeType(AUDIO_AAC) being called unconditionally regardless of audio mode, which Media3's own 'transcode only if necessary' semantics should transcode any non-matching source into -- reasoned from verified source (02-RESEARCH.md, this plan's own javap reads) but not observed live. This is the same AUDO-01 edge the plan itself flags as deliberately unresolved (see 02-05-PLAN.md's 'Flagged assumption' section) -- surfaced here for the verifier, not closed by fiat."
  - id: D6
    description: "Compressing portrait_hibitrate_1080p60.mp4 at the default preset produces an upright output (height greater than width, matching the result's own reported dimensions) with no black-bar padding, proven by sampling the compressed OUTPUT's own pixels at the sidecar's thumbnail-patch and all four edge-midpoint coordinates"
    requirement: ORNT-01
    verification:
      - kind: integration
        ref: "compress_test.dart#'default preset compresses the portrait clip to an upright output with no black-bar padding...'"
        status: pass
    human_judgment: false
  - id: D7
    description: "A maxLongSidePx exactly equal to the source's own displayed long side triggers no rescale at all (output dimensions equal the source's exactly), and the un-rescaled output is still proven upright and unpadded by the same pixel probe -- proving the probe generalizes past the default preset, not just at it"
    requirement: ORNT-01
    verification:
      - kind: integration
        ref: "compress_test.dart#'a maxLongSidePx exactly equal to the source long side is not rescaled at all...'"
        status: pass
    human_judgment: false
  - id: D8
    description: "A trim from 500ms to 3500ms, implemented with Media3's MediaItem.ClippingConfiguration (setEndPositionMs taking an end position, not a duration), produces an output whose re-probed duration matches the requested 3000ms range within one output frame"
    requirement: null
    verification:
      - kind: integration
        ref: "compress_test.dart#'a trim from 500ms to 3500ms produces an output whose duration matches the requested 3000ms range...'"
        status: pass
    human_judgment: false
  - id: D9
    description: "The video effects list is built in one fixed, documented order (geometry first, frame selection second), pinned by a JVM unit test that constructs no Transformer"
    requirement: null
    verification:
      - kind: unit
        ref: "EffectOrderTest.kt (4 cases: both apply in order, geometry only, frame-selection only, neither)"
        status: pass
    human_judgment: false
  - id: D10
    description: "The bitrate knob demonstrably reaches the audio encoder rather than being ignored: a 64000bps and a 128000bps reencode of the same clip produce measurably different audio bitrates in the expected direction, each within 25 percent of its own request"
    requirement: AUDO-02
    verification:
      - kind: integration
        ref: "compress_audio_test.dart#'a 64000bps and a 128000bps reencode of the same clip produce measurably different audio bitrates...'"
        status: pass
    human_judgment: false
  - id: D11
    description: "Every audio boundary (bitrateBps 0/negative rejected, 1 accepted as clamped-not-rejected; channels 0/3 rejected, 1/2 accepted) is mirrored identically on both sides of the platform channel"
    requirement: AUDO-02
    verification:
      - kind: unit
        ref: "test/compress_options_test.dart (32 total cases) + ArgumentsTest.kt's validateAudioReencode_* cases"
        status: pass
    human_judgment: false
  - id: D12
    description: "ORNT-01's backstop truth -- a source with rotation 0 and equal displayed width/height produces a result whose widthPx equals heightPx and adds no rotation of its own -- is carried forward unresolved, per the plan's own 'verification: backstop' marking"
    requirement: ORNT-01
    verification: []
    human_judgment: true
    rationale: "No corpus fixture has a square (width == height) frame, so this specific truth has no automated proof in this phase. The plan itself marks this must-have's verification as 'backstop' rather than requiring a dedicated test; carried forward unresolved for the verifier rather than closed by fiat or a fabricated fixture."

duration: ~75min (estimated -- start time not captured at invocation)
completed: 2026-09-16
status: complete
---

# Phase 2 Plan 5: Audio Modes, Channel Mixing, Trim and Orientation Proof Summary

**All three audio modes (passthrough with automatic AAC fallback, strip, and reencode with exact channel-count and clamped-bitrate control via ChannelMixingAudioProcessor/AudioEncoderSettings) working and honestly reported, plus Media3 ClippingConfiguration-based trim and a pixel-probe proof that the compressed output is upright with no black-bar padding.**

## Performance

- **Duration:** ~75 min (estimated; start time not captured at invocation)
- **Completed:** 2026-09-16
- **Tasks:** 3
- **Files modified:** 9 (0 created, 9 modified)

## Accomplishments

- `TransformerEngine` now branches on `AudioModeMessage`: passthrough leaves the audio pipeline untouched (relying on the Transformer-level unconditional `AUDIO_AAC` mime request to both copy an already-AAC source and automatically fall back to an AAC re-encode for a non-AAC one), strip removes the track via `setRemoveAudio`, and reencode sets explicit `AudioEncoderSettings` (bitrate from `SizeGuard`'s already-clamped resolution) plus a `ChannelMixingAudioProcessor`/`ChannelMixingMatrix.createForConstantGain` whenever the requested channel count differs from the source's own.
- Confirmed via `javap` on the installed `media3-transformer:1.11.1` AAR that `DefaultEncoderFactory.audioNeedsEncoding()` mirrors the video `videoNeedsEncoding()` precondition 02-04 found (reference/`Object.equals` against `AudioEncoderSettings.DEFAULT`, since the class has no `equals()` override) -- audio encoder settings are therefore only ever built for an explicit reencode, never passthrough or strip, preserving the transmux fast path for an already-AAC source.
- Implemented trim with Media3's own `MediaItem.ClippingConfiguration` (previously not implemented at all) -- `setEndPositionMs` takes an end position, not a duration, documented inline against the incumbent's own trim bug.
- Extracted the video effects list into `TransformerEngine.buildVideoEffects`, a pure companion function with no Transformer/Looper dependency, and wrote `EffectOrderTest.kt` (4 cases) pinning the geometry-then-frame-selection order.
- Extended `compress_test.dart` with `_expectUprightAndUnpadded`, sampling a compressed OUTPUT's own pixels (thumbnail patch + four edge-midpoint samples, coordinates scaled from the sidecar's source-displayed values to this particular output's own dimensions) to prove upright orientation and no letterboxing at both the default preset and an explicit long-side-adjacency case, plus a trim duration assertion.
- Wrote `compress_audio_test.dart` (7 cases) covering all three audio modes, the bitrate clamp, exact channel-count honouring, and a two-bitrate precision proof -- reading channel count and an audio-only bitrate estimate directly from the produced MP4's own `moov`/`stsd`/`stsz` boxes (including the 64-bit extended `mdat` size Media3's disabled-streamable-output layout produces), since neither `CompressResult` nor `MediaInfo` exposes either fact.
- Completed dartdoc for `AudioOptions` and its three subclasses, `CompressResult.audioReencoded`/`audioCodec`/`widthPx`/`heightPx`, and mirrored the `AudioReencode` boundary cases (negative bitrate rejected, `1` accepted-as-clamped, both channel values accepted) identically on both sides of the platform channel.

## Task Commits

Each task was committed atomically:

1. **Task 1: The three audio modes, with channel mixing and a clamped bitrate** - `137b1ff` (feat)
2. **Task 2: Upright output with no black bars, proven by sampling the compressed file's own pixels** - `2cba388` (feat)
3. **Task 3: Document the audio and orientation contract, and close the AUDO-02 boundaries on both sides** - `a753440` (docs)

## Files Created/Modified

- `android/.../TransformerEngine.kt` - Three audio-mode branches, `ChannelMixingAudioProcessor`/`AudioEncoderSettings` wiring, `MediaItem.ClippingConfiguration` trim, `buildVideoEffects` extraction, `readAudioChannelCount` helper
- `android/.../SizeGuardTest.kt` - Two new audio-bitrate-resolution cases (inside-range passthrough, source-own-bitrate fallback)
- `android/.../ArgumentsTest.kt` - Negative-bitrate and bitrate-of-1 cases mirroring the new Dart boundary tests
- `android/.../EffectOrderTest.kt` *(created)* - 4-case JVM suite pinning the video effects order, no Transformer
- `lib/src/compress_options.dart` - Completed `AudioOptions`/`AudioPassthrough`/`AudioReencode`/`AudioStrip` dartdoc
- `lib/src/compress_result.dart` - Completed `audioReencoded`/`audioCodec`/`widthPx`/`heightPx` dartdoc
- `test/compress_options_test.dart` - 5 new `AudioReencode` boundary cases (32 total, up from 28)
- `example/integration_test/compress_audio_test.dart` *(created)* - 7-case audio-mode integration suite with a test-only MP4 box parser
- `example/integration_test/compress_test.dart` - `_expectUprightAndUnpadded` helper + 3 new orientation/adjacency/trim cases

## Decisions Made

See `key-decisions` in frontmatter for the full list. Most consequential: moving the `AudioReencode`/`AudioStrip` integration cases from `small_480p.mp4` to `portrait_hibitrate_1080p60.mp4` after a live failure showed the former could trip the never-larger post-check and silently defeat the audio assertions; and reading channel count/audio bitrate directly from the produced file's own MP4 boxes in Dart rather than adding a wire-contract field outside this plan's declared file scope.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `AudioOptions.reencode`/`AudioStrip` integration cases against `small_480p.mp4` tripped the never-larger post-check, defeating the audio assertions**
- **Found during:** Task 1, first live emulator run of the `AudioReencode` 64000bps/2-channel case
- **Issue:** `small_480p.mp4`'s own video bitrate (~130kbps) is close enough to the resolved preset-scaled target that this emulator's known CBR software-encoder overshoot (02-03) pushed the real re-encode's byte count to exactly the input's own size, triggering `finishSuccess`'s unconditional never-larger post-check and substituting the original file. The test then observed the untouched source's audio (`audioReencoded: false`), not the reencoded track the test meant to check.
- **Fix:** Moved the `AudioReencode` cases (64000/2ch, 1ch, 1000bps-clamp, and the two-bitrate precision case) to `portrait_hibitrate_1080p60.mp4`, whose ~8.7Mbps source shrinks by design at every preset regardless of what the audio track does, isolating the audio behavior cleanly from the never-larger predicate.
- **Files modified:** `example/integration_test/compress_audio_test.dart`
- **Verification:** All `AudioReencode` cases pass with `audioReencoded: true` and the correct channel count/bitrate on the corrected fixture
- **Committed in:** `137b1ff`

**2. [Rule 1 - Bug] The test-only MP4 box parser initially failed to locate `moov` at all**
- **Found during:** Task 1, first run of the `AudioReencode` channel-count assertion
- **Issue:** `TransformerEngine`'s `InAppMp4Muxer.Factory().setAttemptStreamableOutputEnabled(false)` (02-04) writes `moov` AFTER `mdat`, and for a compressed clip of this size `mdat`'s own box size no longer fits a 32-bit field -- it uses the ISO/IEC 14496-12 64-bit extended-size form (`size == 1`, followed by a big-endian `uint64`). The box walker's first version treated that `1` as a literal 1-byte box size, corrupting the offset for every subsequent box and never reaching `moov`.
- **Fix:** `_findBox` (and a temporary debug dump used to diagnose this) now detects `size == 1` and reads the real 64-bit size from the following 8 bytes before advancing.
- **Files modified:** `example/integration_test/compress_audio_test.dart`
- **Verification:** Live box-tree dump confirmed `moov`/`trak`/`mdia`/`stsd`/`stsz` all resolve correctly after the fix; all channel-count and bitrate assertions pass
- **Committed in:** `137b1ff`

---

**Total deviations:** 2 auto-fixed (1 test-fixture-choice bug that would have silently defeated its own assertions, 1 box-parsing bug in test-only code).
**Impact on plan:** Both fixes are confined to the test file; no production `TransformerEngine.kt` behavior was changed by either. No scope creep: the fixture change stays within Task 1's own declared file, and the box-parsing fix corrects the same test-only helper it was found in.

## Known Stubs

None -- every deliverable is wired to real Media3 behavior and proven on the emulator, except the two explicitly flagged, unresolved coverage items (D5, D12 above) which are documented gaps, not stubs.

## Issues Encountered

None beyond the two deviations documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All three audio modes, trim, and the orientation/no-letterbox proof are in place and proven on the emulator; `AUDO-01`, `AUDO-02` and `ORNT-01` are ready to mark complete (verified via `gsd-tools query requirements.ready-ids`: 3/3 ready, no sibling plan shares these IDs).
- **AUDO-01's flagged assumption is carried forward unresolved, per the plan's own instruction** (see coverage D5): no corpus fixture in this project has non-AAC audio, so the "falls back to AAC re-encode for a non-AAC source" path is reasoned from verified Media3 source/javap reads but not observed live. A future phase adding a non-AAC fixture (or the real-phone-clip work QUESTIONS.md #4 already tracks) should close this.
- **ORNT-01's backstop truth (equal-width/height source, rotation 0) is also carried forward unresolved** (see coverage D12): no square corpus fixture exists to prove it.
- `TransformerEngine.buildVideoEffects`'s extraction and `EffectOrderTest.kt` are ready for any future plan that adds a third video effect (HDR tone-mapping, Phase 4) needing to slot into the same pinned-order list.
- The test-only MP4 box-parsing pattern in `compress_audio_test.dart` (`_findBox`/`_readMp4AudioTrackInfo`) is available as a template for any future test that needs to verify a native fact neither `CompressResult` nor `MediaInfo` exposes over the wire, without expanding the public wire contract for a single test's benefit.
- Ready for `02-06-PLAN.md` (cancel/error-mapping depth).

---
*Phase: 02-android-compression-on-media3*
*Completed: 2026-09-16*

## Self-Check: PASSED

- FOUND: `android/src/test/kotlin/com/danjjohnson/compress_video/EffectOrderTest.kt`, `example/integration_test/compress_audio_test.dart` (both created, verified with `[ -f ]`)
- FOUND commits: `137b1ff`, `2cba388`, `a753440` (all present in `git log --oneline --all`)
- `cd example/android && ./gradlew :compress_video:testDebugUnitTest` -- all pass (including 4 new `EffectOrderTest` cases, 2 new `SizeGuardTest` cases, 2 new `ArgumentsTest` cases)
- `flutter test` (root) -- 72/72 pass (32 in `compress_options_test.dart`, up from 28)
- `cd example && flutter test integration_test -d emulator-5554` -- 54/54 pass across `media_info_test.dart` (9), `compress_test.dart` (22, including 3 new orientation/adjacency/trim cases), `compress_audio_test.dart` (7, all new), `thumbnail_test.dart` (16)
- `flutter analyze --fatal-infos --fatal-warnings` (root and `example/`) -- both clean
- `dart format --output=none --set-exit-if-changed .` -- 0 changed
- `dart pub publish --dry-run` -- exit 0, 0 warnings
- All acceptance-criteria grep checks for all three tasks re-verified against final committed files
- `git status --short` clean at every commit boundary
