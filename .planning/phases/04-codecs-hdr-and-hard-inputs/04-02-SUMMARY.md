---
phase: 04-codecs-hdr-and-hard-inputs
plan: 02
subsystem: api
tags: [media3, hdr, tone-mapping, composition, channel-mixing, audio-downmix, transformer]

# Dependency graph
requires:
  - phase: 04-codecs-hdr-and-hard-inputs
    provides: "04-01's corpus fixtures (hdr_hlg10.mp4, hdr_pq10.mp4, surround51_480p.mp4, pcm_audio_480p.mov, uhd_4k60.mp4), hdr/hdrProbe/audio sidecar vocabulary, and hard_inputs_test.dart"
provides:
  - "Composition/EditedMediaItemSequence wrapping on every TransformerEngine export, with resolveHdrMode choosing HDR_MODE_KEEP_HDR for non-HDR sources (required for transmux to survive) and HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL for HDR ones"
  - "OpenGL-then-MediaCodec HDR tone-map fallback chain (attemptExport local suspend function, fresh Transformer+temp file per attempt, job-scoped monotonic progress) ending in a typed unsupportedInput error naming the exhausted chain"
  - "toneMapped/hevcFallback threaded as real parameters through finishSuccess into buildResultFromDestination; toneMapped computed from ExportResult.colorInfo via ColorInfo.isTransferHdr, guarded by !usedOriginal"
  - "_expectHdrFidelity Dart helper (saturation/dominance/white-luma sampling) wired into both HDR test cases, proven-correct code that has not yet executed successfully on this emulator"
  - "SizeGuard.InputInfo.audioChannelCount and the extended wouldTransmux predicate (AUDO-03) with 4 new unit cases"
  - "Engine-side forced audio re-encode (2-channel target, 128000bps constant) for any non-AAC or >2-channel source under default AudioPassthrough"
  - "A manual ITU-R BS.775-inspired 5.1-to-stereo ChannelMixingMatrix, since Media3's own createForConstantGain(6, 2) is not implemented"
  - "doc/HARDWARE_CHECKLIST.md (new, ahead of its originally-planned 04-05 creation) documenting the confirmed HDR tone-map hardware limitation"
affects: [04-03, 04-04, 04-05]

# Actuals (#2632)
actuals:
  tokens: 20950
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Composition wrapping is unconditional on every export path; HdrMode itself branches on the probed input's own isHdr flag (HDR_MODE_KEEP_HDR for non-HDR, tone-map mode only for HDR) -- Composition.Builder's default HdrMode is NOT interchangeable with an explicit non-zero one for a non-HDR source, confirmed live via TransformerUtil.shouldTranscodeVideo bytecode"
    - "A per-attempt local suspend function (attemptExport) closing over job-scoped state (editedMediaItem, encoderFactory, jobId, lastSentProgress) is the shape for a retry chain that must never reuse a Transformer or temp file across attempts, while keeping progress monotonic across the whole job"
    - "An engine-side forced-decision boolean (audioForcedReencode) computed once, before processors/encoder factory, is the shape for 'default options must still do X' requirements that request validation alone cannot express"
    - "When ExportResult's own conversion-process enum is ambiguous for a specific source shape (raw/PCM), trust this engine's own forcing decision (which mirrors Media3's shouldTranscodeAudio bytecode) rather than the enum alone"

key-files:
  created:
    - doc/HARDWARE_CHECKLIST.md
  modified:
    - android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/SizeGuardTest.kt
    - example/integration_test/hard_inputs_test.dart
    - corpus/README.md

key-decisions:
  - "resolveHdrMode returns HDR_MODE_KEEP_HDR (0) for a non-HDR source, not the tone-map mode -- found live, not assumed: TransformerUtil.shouldTranscodeVideo forces a transcode whenever TransformationRequest.hdrMode is non-zero regardless of whether the input is HDR, so requesting the tone-map mode unconditionally (as originally written) silently broke the transmux fast path for every ordinary H.264 clip. Fixed before the task 1 commit."
  - "Both HDR test cases assert one of two legitimate outcomes (successful tone-map + fidelity check, or an exhausted-chain unsupportedInput error) rather than a single hard-coded expectation, matching this codebase's own established idiom for hardware-dependent divergence (compress_test.dart's/compress_audio_test.dart's AudioStrip cases). Confirmed live: BOTH attempts fail on this specific emulator (codes 5001 then 3003) -- a genuine software-GL/software-decoder limitation, not a code bug."
  - "A manual 5.1-to-stereo ChannelMixingMatrix was required: ChannelMixingMatrix.createForConstantGain(6, 2) throws UnsupportedOperationException on the installed media3-common-1.11.1 AAR, contradicting 04-RESEARCH.md's 'Don't Hand-Roll' assumption of general (int,int) coverage."
  - "audioReencoded also trusts this engine's own audioEncodeForced decision, not only ExportResult.audioConversionProcess: for a raw PCM source Media3 reports audioConversionProcess as TRANSMUXED even though a real AudioEncoderSettings-driven AAC encode ran (confirmed by re-probing the output's own esds) -- the trivial PCM decode step appears to drive the classification rather than the real encode step."
  - "doc/HARDWARE_CHECKLIST.md was created now, ahead of its originally-planned 04-05 creation (ROADMAP.md), because 04-02-PLAN.md task 2's own action text explicitly requires documenting the environment limitation there. 04-05 should extend this file, not assume it needs creating."

requirements-completed: []

coverage:
  - id: D1
    description: "TransformerEngine wraps every export in a Composition/EditedMediaItemSequence, calling the Composition start overload unconditionally, with HdrMode resolved from the probed input's own HDR flag rather than a literal"
    requirement: CDEC-02
    verification:
      - kind: unit
        ref: "android/src/test/kotlin/.../SizeGuardTest.kt (existing suite unaffected) + full example/integration_test suite (92/92) proving no transmux regression"
        status: pass
    human_judgment: false
  - id: D2
    description: "toneMapped/hevcFallback are threaded as real computed parameters (never hardcoded false) through finishSuccess into buildResultFromDestination; toneMapped is derived from ExportResult.colorInfo via ColorInfo.isTransferHdr, guarded by !usedOriginal"
    requirement: CDEC-02
    verification:
      - kind: unit
        ref: "grep -v comment 'toneMapped = false' count 0; grep 'isTransferHdr' count >=1 in TransformerEngine.kt"
        status: pass
    human_judgment: false
  - id: D3
    description: "The OpenGL-then-MediaCodec HDR fallback chain runs exactly two attempts with fresh Transformer/temp-file state each, and exhausts to a typed unsupportedInput error naming the chain -- proven live: both hdr_hlg10.mp4 and hdr_pq10.mp4 exhaust the chain on this emulator (codes 5001 then 3003), correctly typed, ErrorMapping.kt untouched"
    requirement: CDEC-02
    verification:
      - kind: integration
        ref: "example/integration_test/hard_inputs_test.dart HDR group, run locally on emulator-5554 (both cases pass, exercising the catch branch)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The tone-mapped-output-is-not-washed-out fidelity assertion (_expectHdrFidelity: saturation, dominance, white-luma) is implemented and wired into both HDR test cases, but has never executed against a real successful tone-map on this hardware -- a confirmed environment limitation (doc/HARDWARE_CHECKLIST.md), not a code defect"
    requirement: CDEC-02
    verification: []
    human_judgment: true
    rationale: "No successful tone-map has ever occurred on the compress_video_api35 emulator (both OpenGL and MediaCodec paths fail with distinct, correctly-typed codes) -- the fidelity assertion's own success branch is real, reviewed code but is unproven on real output pending a physical Android device (QUESTIONS.md #3) or a future emulator/OS update. A human (or a later plan with hardware access) must verify this once such a device is available."
  - id: D5
    description: "SizeGuard.wouldTransmux additionally requires audioChannelCount to be unknown or at most 2, so a 5.1 clip can never take the remux fast path with six channels intact -- proven by 4 new unit cases (6ch disqualifies, 2ch qualifies, 3ch disqualifies, null/unknown qualifies) and live by surround51_480p.mp4 reporting transmuxed:false"
    requirement: AUDO-03
    verification:
      - kind: unit
        ref: "SizeGuardTest.kt: wouldTransmux_sixChannelAudio_disqualifies, wouldTransmux_twoChannelAudio_stillQualifies, wouldTransmux_threeChannelAudio_disqualifies, wouldTransmux_unknownAudioChannelCount_stillQualifies"
        status: pass
      - kind: integration
        ref: "hard_inputs_test.dart: surround51_480p.mp4 case (transmuxed:false, audioReencoded:true, 2 channels read from esds)"
        status: pass
    human_judgment: false
  - id: D6
    description: "5.1 AAC, PCM and non-AAC sources under default AudioPassthrough are forcibly re-encoded to 2-channel 128kbps AAC (never SizeGuard's own audioBitrateBps) rather than sailing through untouched -- proven live for both surround51_480p.mp4 (5.1 AAC) and pcm_audio_480p.mov (LPCM), both reporting audioReencoded:true and re-probing as genuine AAC"
    requirement: AUDO-03
    verification:
      - kind: integration
        ref: "hard_inputs_test.dart: surround51_480p.mp4 and pcm_audio_480p.mov cases, run locally on emulator-5554"
        status: pass
    human_judgment: false
  - id: D7
    description: "A source with no audio track still produces an output with no audio track (unchanged from Phases 2-3), and the 4K60 corpus clip compresses without error inside the suite's 120-second per-test bound (measured ~6.4s)"
    requirement: AUDO-03
    verification:
      - kind: integration
        ref: "hard_inputs_test.dart: noaudio_720p.mp4 and uhd_4k60.mp4 cases, run locally on emulator-5554; UHD_4K60_MEASURED elapsedMs=6391"
        status: pass
    human_judgment: false

duration: ~4h (mostly local emulator verification, two real bugs found and fixed via live debugging, one emulator restart after an OOM-related crash)
completed: 2026-09-26
status: complete
---

# Phase 4 Plan 2: Android HDR Tone-Mapping and Forced Audio Downmix Summary

**Media3 `Composition`/`HdrMode` wrapping with an OpenGL-then-MediaCodec tone-map fallback chain (proven to exhaust correctly-typed on this emulator's software GL/decoder), plus a forced 5.1/PCM-to-stereo-AAC downmix backed by a hand-derived `ChannelMixingMatrix` Media3 itself doesn't implement.**

## Performance

- **Duration:** ~4h (local verification only; no CI push yet for this response)
- **Started:** 2026-09-26 (session start)
- **Completed:** 2026-09-26
- **Tasks:** 3 (tracer: Composition wrapping + honest reporting; fallback chain + fidelity assertion; forced audio downmix)
- **Files modified:** 6 (1 created, 5 modified)

## Accomplishments

- `TransformerEngine.compress` now wraps every export in an `EditedMediaItemSequence`/`Composition` and starts via the `Composition` overload unconditionally. `resolveHdrMode` picks `HDR_MODE_KEEP_HDR` for a non-HDR source and `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL` for a genuinely HDR one — the KEEP_HDR branch was a real bug fix found live (see Deviations), not the plan's literal "always tone-map" text, because `TransformerUtil.shouldTranscodeVideo` forces a transcode for ANY non-zero `HdrMode` regardless of input HDR status.
- `toneMapped`/`hevcFallback` are threaded as real parameters (never hardcoded `false`) through `finishSuccess` into `buildResultFromDestination`; `toneMapped` is computed from `ExportResult.colorInfo` via `ColorInfo.isTransferHdr`, guarded by `!usedOriginal`.
- A local `attemptExport` suspend function inside `compress()` performs one HDR tone-map attempt (its own `Transformer`, its own temp file, its own `JobRegistry` registration); `compress()` calls it with `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL` and retries with `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_MEDIACODEC` only for a genuinely-HDR, non-cancelled failure on API 31+. Progress stays monotonic across the retry via a job-scoped `lastSentProgress`. Exhausting both paths throws a typed `unsupportedInput` error naming the chain and the last `ExportException` code; `ErrorMapping.kt` is untouched.
- **Confirmed live on the danserver emulator (`compress_video_api35`, API 35, `swiftshader_indirect` software GL): both HDR clips exhaust the fallback chain.** The OpenGL attempt fails with code 5001 (`ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED` — logcat traces this to the GL effects pipeline's input `Surface` being released before the goldfish HEVC decoder can configure against it); the MediaCodec retry then fails with code 3003 (`ERROR_CODE_DECODING_FORMAT_UNSUPPORTED` — the decoder rejects the requested tone-mapped output colour-transfer configuration outright). Both are genuine, documented software-GL/software-decoder capability gaps (04-RESEARCH.md Pitfall 3, and Pitfall 4 now resolved in the negative for the full Transformer pipeline), not a code bug — recorded in `doc/HARDWARE_CHECKLIST.md`.
- `hard_inputs_test.dart`'s HDR group asserts exactly one of two legitimate outcomes per clip (tone-map success + `_expectHdrFidelity`, or the typed exhausted-chain error), matching this codebase's own established idiom for hardware-dependent divergence. Both cases pass today via the exhausted-chain branch.
- `_expectHdrFidelity` (saturation/dominance/white-luma sampling of the produced file's own pixels, scaled from source- to output-displayed coordinates exactly like `compress_test.dart`'s `_expectUprightAndUnpadded`) is fully implemented and wired in, ready to exercise the moment hardware allows a real tone-map.
- `SizeGuard.InputInfo` gains `audioChannelCount: Int? = null`; `wouldTransmux` now additionally requires it to be unknown or at most 2 — 4 new unit cases prove both directions plus the unknown-count fallback.
- `TransformerEngine` computes `audioForcedReencode` once (request isn't already an explicit reencode/strip, input has audio, codec isn't AAC or channels exceed 2) and forces a 2-channel, 128000bps (named constant, never `SizeGuard.Plan.audioBitrateBps`) AAC re-encode — proven for both `surround51_480p.mp4` (5.1 AAC) and `pcm_audio_480p.mov` (LPCM).
- `noaudio_720p.mp4` still compresses with no audio track; `uhd_4k60.mp4` compresses in ~6.4s, comfortably inside the 120-second bound.
- `doc/HARDWARE_CHECKLIST.md` created (ahead of its originally-planned 04-05 creation — this plan's own task 2 action text required documenting the finding there) with the full HDR tone-map limitation writeup and a runnable physical-device verification recipe.
- `corpus/README.md`'s `hdrProbe` section extended with what the floors mean (0-255 scale) and how to re-derive them once real tone-mapped output exists.

## Task Commits

Each task was committed atomically, except tasks 2 and 3 which were consolidated (see Deviations):

1. **Task 1 (tracer): Composition wrapping, honest toneMapped/hevcFallback, HDR test case** — `3ed6a8f` (feat)
2. **Tasks 2+3 (consolidated): OpenGL→MediaCodec fallback chain, fidelity helper, forced audio downmix, 5.1 ChannelMixingMatrix fix, PCM audioReencoded fix** — `89c7ae6` (feat)
3. **Docs fixup: literal `audioChannelCount` naming in its own KDoc** — `6463047` (docs)

_No SUMMARY-metadata commit yet — see below._

## Files Created/Modified

- `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt` — Composition wrapping, `resolveHdrMode`, `attemptExport`/fallback chain, `hdrFallbackExhaustedError`, `audioForcedReencode`, `channelMixingMatrixFor`/`fiveDotOneToStereoMixingMatrix`, `audioEncodeForced`-aware `audioReencoded`
- `android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt` — `InputInfo.audioChannelCount`, extended `wouldTransmux`
- `android/src/test/kotlin/com/danjjohnson/compress_video/SizeGuardTest.kt` — 4 new `wouldTransmux` channel-count cases
- `example/integration_test/hard_inputs_test.dart` — `_decodeImage`/`_samplePixelRgb`/`_expectHdrFidelity`, MP4-box `_readMp4AudioChannelCount` (own copy per no-shared-helpers convention), HDR dual-outcome test group, 4 new audio/4K60 cases
- `doc/HARDWARE_CHECKLIST.md` — new
- `corpus/README.md` — `hdrProbe` rationale extension

## Decisions Made

See `key-decisions` in frontmatter for the full list. Highlights: `resolveHdrMode`'s KEEP_HDR branch (a real bug fix, not a literal reading of the plan text), the dual-outcome HDR test idiom, the manual 5.1→stereo `ChannelMixingMatrix`, and trusting `audioEncodeForced` over `ExportResult.audioConversionProcess` for the PCM case.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Unconditional non-zero HdrMode silently broke the transmux fast path**
- **Found during:** Task 1, first emulator run of the existing suite after adding `Composition` wrapping
- **Issue:** Setting `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL` unconditionally (even for non-HDR sources) made `small_480p.mp4`'s previously-passing transmux case fail — `TransformerUtil.shouldTranscodeVideo` (confirmed via `javap` against the installed media3-transformer-1.11.1 AAR) forces a transcode whenever `TransformationRequest.hdrMode` is non-zero, independent of whether the input is HDR
- **Fix:** `resolveHdrMode` returns `HDR_MODE_KEEP_HDR` (0) for a non-HDR input, the tone-map mode only for a genuinely HDR one
- **Verified:** Full `example/integration_test` suite (92/92) re-run green, including both transmux cases
- **Committed in:** `3ed6a8f`

**2. [Rule 1 - Bug] `ChannelMixingMatrix.createForConstantGain(6, 2)` throws `UnsupportedOperationException`**
- **Found during:** Task 3, first emulator run of the new `surround51_480p.mp4` case
- **Issue:** `UnsupportedOperationException: Default channel mixing coefficients for 6->2 are not yet implemented.` — contradicts 04-RESEARCH.md's "Don't Hand-Roll" citation, which assumed general `(int, int)` coverage
- **Fix:** Added `channelMixingMatrixFor`/`fiveDotOneToStereoMixingMatrix`, a manual ITU-R BS.775-inspired 6-channel-to-stereo `ChannelMixingMatrix` (front channels pass straight through, centre and surrounds contribute at -3dB to both outputs, LFE not folded in), special-cased only for the 6→2 pair; every other pair this plugin requests still uses the library default
- **Verified:** `surround51_480p.mp4` case passes, esds channel count reads 2
- **Committed in:** `89c7ae6`

**3. [Rule 1 - Bug] `audioReencoded` false for a genuinely re-encoded PCM source**
- **Found during:** Task 3, first emulator run of the new `pcm_audio_480p.mov` case
- **Issue:** `ExportResult.audioConversionProcess` reported `CONVERSION_PROCESS_TRANSMUXED` (2), not `TRANSCODED` (1), even though the output re-probed as genuine AAC (confirmed via `readAudioCodec` on the destination file) — a raw PCM source's trivial decode step appears to drive Media3's own conversion-process classification rather than the real encode step
- **Fix:** `audioReencoded`'s computation also trusts this engine's own `audioEncodeForced` decision (`request.audioMode == REENCODE || audioForcedReencode`), which mirrors `TransformerUtil.shouldTranscodeAudio`'s own `audioNeedsEncoding()` check (javap-verified) — this is the SAME decision Media3 itself used to decide whether to transcode, not a guess
- **Verified:** `pcm_audio_480p.mov` case passes, `audioReencoded: true`, `audioCodec: aac`
- **Committed in:** `89c7ae6`

**4. [Pre-authorised contingency, applied] Both HDR clips assert the exhausted-chain error, not tone-map success**
- **Found during:** Task 1's first emulator run of the new HDR case, confirmed again after task 2's fallback chain landed
- **Issue:** 04-02-PLAN.md task 1's own acceptance criteria explicitly anticipated this: "If the emulator cannot decode the Main10 stream... the case is rewritten to assert that typed reason rather than deleted." The observed failure is a real Transformer pipeline limitation (not a metadata-read failure, which 04-01 already proved works), but the same principle applies: a real, typed, documented failure is what this hardware can prove.
- **Fix:** Both HDR test cases assert exactly one of two legitimate outcomes (success+fidelity, or exhausted-chain `unsupportedInput`) rather than a single hard assumption, matching the codebase's own established dual-outcome idiom
- **Verified:** Both cases pass on this emulator via the exhausted-chain branch; the success branch is real code, unexercised pending hardware
- **Committed in:** `3ed6a8f` (task 1's assertion), refined in `89c7ae6` (task 2's dual-outcome form)

**5. [Rule 2 - Missing critical / plan-authoring gap] `doc/HARDWARE_CHECKLIST.md` created ahead of schedule**
- **Issue:** This file is not in 04-02-PLAN.md's `files_modified` frontmatter (ROADMAP.md assigns its creation to 04-05), but task 2's own action text explicitly instructs recording the HDR decode/tone-map limitation there
- **Fix:** Created the file now with the HDR section fully written, plus placeholder sections for the other hardware-only checks 04-03/04-04/04-05 will need
- **Impact:** 04-05 should extend this file, not assume it needs creating from scratch
- **Committed in:** `89c7ae6`

---

**Total deviations:** 3 genuine bugs auto-fixed, 1 pre-authorised contingency applied, 1 plan-authoring gap filled (Rule 2). **Impact on plan:** All auto-fixes were necessary for correctness (two silently produced wrong results — a broken transmux fast path and a false `audioReencoded: false` — the kind of bug this project's "prove what actually happened" philosophy exists to catch). No scope creep beyond the explicitly-instructed `doc/HARDWARE_CHECKLIST.md` file.

## Issues Encountered

- The local Android emulator (`compress_video_api35`) crashed/disappeared twice during this plan's verification runs (once mid-full-suite, once again after a subsequent restart), consistent with this project's documented danserver memory-pressure pattern (`swap: 8.0Gi/8.0Gi used` observed at the time of the second crash) rather than a code-triggered crash. Restarted both times with the documented `sg kvm -c` recipe; all runs after each restart passed cleanly. Not treated as a code issue.
- The plan's own "teeth demonstration" acceptance criterion for `_expectHdrFidelity` (temporarily raising `minSaturation` in a scratch sidecar copy to prove the assertion actually fails) was **not executed** — there is no real successful tone-mapped output on this hardware to run it against. This is carried forward as an honest gap, not fabricated: `_expectHdrFidelity`'s logic was reviewed carefully (patch-coordinate scaling, saturation formula, dominance/luma checks) but has zero live executions of its assertion body. A future plan with hardware access (or once CI's own Android/iOS legs are confirmed to have the same limitation or not) should run this demonstration for real.

## User Setup Required

None — no external service configuration required.

## What 04-03 Needs to Know

- **`resolveHdrMode`'s branch on `inputIsHdr` is load-bearing, not cosmetic.** Any future HdrMode-related change (04-03's HEVC opt-in, keep-HDR) must preserve the KEEP_HDR-for-non-HDR behavior, or the transmux fast path breaks again for every ordinary clip. `TransformerUtil.shouldTranscodeVideo`'s bytecode is the authoritative reference (04-RESEARCH.md doesn't document this).
- **`attemptExport`'s per-attempt-fresh-state shape is reusable.** 04-03's own capability-probing work doesn't need a retry chain, but if a future plan needs one, this is the established local-suspend-function pattern (closes over job-scoped state, never reuses a `Transformer`/temp file).
- **The HDR tone-map success path is fully implemented but unproven on this danserver emulator.** 04-03/04-04/04-05 should NOT assume this emulator will ever demonstrate a successful HDR tone-map — plan CI/hardware-checklist expectations accordingly. The macOS CI host's Apple Silicon Media Engine (04-RESEARCH.md) is a DIFFERENT pipeline (Apple's own AVFoundation reader tone-maps automatically, Phase 3 D-08) and is not affected by this Android-specific finding.
- **`doc/HARDWARE_CHECKLIST.md` already exists** with the HDR section fully written and placeholder sections for HEVC/keep-HDR (04-03/04-04) and `targetSizeMb`/estimate tolerances (already known from Phase 2). 04-05 should extend, not recreate.
- **`SizeGuard.InputInfo.audioChannelCount` exists only on the Kotlin side** — `SizeGuard.swift` does not have it yet (04-04's job, per 04-CONTEXT.md's own "deliberate, scheduled divergence" note).
- **`channelMixingMatrixFor`'s 6→2 special case is the ONLY non-library-default pair this plugin currently needs.** If a future plan needs another unsupported pair from `ChannelMixingMatrix.createForConstantGain`, check via `javap` first rather than assuming coverage.

## Next Phase Readiness

- Ready for 04-03 (HEVC opt-in, keep-HDR): the HdrMode resolution and Composition-wrapping infrastructure this plan built is exactly what 04-03 extends.
- CDEC-02 and AUDO-03 are NOT marked complete in `REQUIREMENTS.md` — both are also declared by 04-04-PLAN.md and 04-05-PLAN.md (shared-ID gate, #2388); they stay `Pending` until the last declaring plan (04-05) finishes.
- No blockers carried forward beyond the documented hardware-only gaps above (all recorded in `doc/HARDWARE_CHECKLIST.md` and `QUESTIONS.md`).

## Self-Check: PASSED

- `doc/HARDWARE_CHECKLIST.md` verified present on disk.
- All 3 commits (`3ed6a8f`, `89c7ae6`, `6463047`) verified present in `git log`.
- `flutter analyze --fatal-infos --fatal-warnings`, `flutter test` (84/84 Dart unit tests), Android native unit tests (all `SizeGuardTest`/`ArgumentsTest`/etc. green including 4 new cases), and the full `example/integration_test` suite (92/92) all re-run green as of the final commit.
- Every `<acceptance_criteria>` re-run and passing, except the two explicitly documented in Deviations #4 (HDR fidelity success path unproven on this hardware) and the "teeth demonstration" gap noted under Issues Encountered — both are honest, carried-forward gaps tied to the same confirmed hardware limitation, not silently skipped.

---
*Phase: 04-codecs-hdr-and-hard-inputs*
*Completed: 2026-09-26*
