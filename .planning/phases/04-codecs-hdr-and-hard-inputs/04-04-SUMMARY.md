---
phase: 04-codecs-hdr-and-hard-inputs
plan: 04
subsystem: apple-engine
tags: [swift, avfoundation, videotoolbox, hevc, hdr, audio-downmix, ci]
status: complete
requires:
  - 04-01 (corpus fixtures, hard_inputs_test.dart)
  - 04-02 (Android HDR tone-map, forced audio downmix)
  - 04-03 (Android CodecCapabilities, HEVC opt-in, keep-HDR)
provides:
  - CodecCapabilities.swift (Apple hardware-HEVC probe)
  - Apple HEVC/keep-HDR output with BT.2020 colour properties
  - Apple honest toneMapped/hevcFallback/audioReencoded reporting
  - SizeGuard.swift parity with SizeGuard.kt (audioChannelCount, outputCodecIsHevc)
  - hard_inputs_test.dart running unskipped on all three platforms
affects:
  - 04-05 (parity records, doc/HARDWARE_CHECKLIST.md, requirement closure)
tech-stack:
  added:
    - VTCopyVideoEncoderList (VideoToolbox hardware-encoder enumeration)
    - AVAssetReaderAudioMixOutput (real multichannel audio downmix)
  patterns:
    - Pure decision function over an injected closure (CodecCapabilities.hasHardwareEncoder), mirroring SizeGuard/ErrorMapping's own pure-over-explicit-input shape
    - Every conversion flag (toneMapped/hevcFallback/audioReencoded/transmuxed) gated by "!usedOriginal" in buildResult, matching Android's TransformerEngine.finishSuccess exactly
key-files:
  created:
    - darwin/compress_video/Sources/compress_video/CodecCapabilities.swift
  modified:
    - darwin/compress_video/Sources/compress_video/Arguments.swift
    - darwin/compress_video/Sources/compress_video/SizeGuard.swift
    - darwin/compress_video/Sources/compress_video/CompressionEngine.swift
    - example/ios/RunnerTests/RunnerTests.swift
    - example/macos/RunnerTests/RunnerTests.swift
    - example/integration_test/hard_inputs_test.dart
    - .github/workflows/ci.yml
    - corpus/generate_corpus.sh
    - corpus/surround51_480p.mp4
    - corpus/surround51_480p.expected.json
    - example/assets/corpus/surround51_480p.mp4
    - example/assets/corpus/surround51_480p.expected.json
    - corpus/README.md
key-decisions:
  - "Apple's hardware-HEVC probe uses VTCopyVideoEncoderList + kVTVideoEncoderList_IsHardwareAccelerated, not VTCopySupportedPropertyDictionaryForEncoder + kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder (the latter is iOS-17.4-only, well above this plugin's iOS 13 floor -- found via a real CI compile error)."
  - "Every H.264 output now carries explicit BT.709 AVVideoColorPropertiesKey, regardless of source. Without it, AVAssetWriter infers colour properties from the first appended CVPixelBuffer's own attachments, and a decoded HDR source's buffer can still carry its original HLG/PQ transfer-function attachment even after the pixel values are tone-mapped to SDR -- silently mistagging a correctly-tone-mapped SDR file as HDR."
  - "A genuine multichannel downmix on the AVAssetReader side requires AVAssetReaderAudioMixOutput, not AVAssetReaderTrackOutput -- the latter silently ignores a requested channel count smaller than the source's own and decodes at the source's native count regardless, with no error."
  - "audioReencoded must be gated by !usedOriginal in buildResult, matching toneMapped/hevcFallback/transmuxed (and Android's TransformerEngine.finishSuccess) exactly -- it was not, which let a never-larger substitution report audioReencoded:true for a file that was actually the untouched original."
  - "surround51_480p.mp4 regenerated with a high-entropy mandelbrot source at ~3Mbps (was a low-entropy testsrc at crf 30, measuring only ~60kbps) -- the low bitrate let SizeGuard's input-bitrate cap force the resolved encode target down to match, and Apple's real encoder output apparently exceeded that target enough to trip the unconditional never-larger post-check. Same fixture-design fix 04-02 already applied to the HDR fixtures."
requirements-completed: []
coverage:
  - deliverable: "Arguments.swift accepts hevc/keepHdr, mirroring Arguments.kt"
    verification:
      - kind: test
        ref: "RunnerTests.swift (Arguments pure validators section)"
        status: pass
    human_judgment: false
  - deliverable: "SizeGuard.swift regains case-for-case parity with SizeGuard.kt"
    verification:
      - kind: test
        ref: "RunnerTests.swift SizeGuard.resolve section (6 new audioChannelCount/outputCodecIsHevc cases)"
        status: pass
    human_judgment: false
  - deliverable: "Apple reports toneMapped:true for a tone-mapped HDR clip"
    verification:
      - kind: test
        ref: "hard_inputs_test.dart hdr_hlg10/hdr_pq10 default-options cases, CI run 36279264836"
        status: pass
    human_judgment: false
  - deliverable: "CodecCapabilities.swift answers both ways under injected closures"
    verification:
      - kind: test
        ref: "RunnerTests.swift testHasHardwareEncoderReturnsTrueWhenTheInjectedProbeSaysYes/...SaysNo"
        status: pass
    human_judgment: false
  - deliverable: "HEVC and keep-HDR succeed on a capable device and fall back honestly on an incapable one"
    verification:
      - kind: test
        ref: "hard_inputs_test.dart HEVC/keepHdr cases, CI run 36279264836 (macOS: HEVC_BRANCH=success, KEEP_HDR_BRANCH=keep; iOS simulator: both fallback)"
        status: pass
    human_judgment: true
    rationale: "The macOS host's real hardware HEVC success path is a live CI observation on a hosted runner Dan does not control -- worth a human sanity check that the runner didn't change shape (e.g. lost Apple Silicon) in a way that would silently move this back to the fallback branch."
  - deliverable: "5.1, PCM, no-audio and 4K60 all compress on both Apple platforms"
    verification:
      - kind: test
        ref: "hard_inputs_test.dart, CI run 36279264836; HARD_INPUT_RESULT diagnostic line per case"
        status: pass
    human_judgment: false
  - deliverable: "No skip guard remains in hard_inputs_test.dart"
    verification:
      - kind: command
        ref: "grep -c 'skip:' example/integration_test/hard_inputs_test.dart"
        status: pass
    human_judgment: false
estimate:
  tokens: 88000
actuals:
  tokens: 210000
  tasks: 3
  commits: 8
duration: "~6.5 hours (dominated by CI wall-clock across 5 pushed attempts + 2 phase-level retries)"
completed: 2026-09-27
---

# Phase 4 Plan 04: Apple Codecs, HDR and Hard Inputs Parity Summary

Brought the Apple (iOS/macOS) compression engine to full parity with Android on everything Phase 4
added: honest `toneMapped` reporting, a real hardware-HEVC probe, HEVC/keep-HDR Main10 output with
correct HDR colour properties, forced downmix for unusual audio, and every `hard_inputs_test.dart`
case running unskipped on all three platforms — with the macOS CI runner's real Apple Silicon
Media Engine proving the HEVC/keep-HDR success branch nothing else in this project's toolchain can.

## Accomplishments

- **`Arguments.swift`** relaxed to accept `hevc`/`keepHdr`, mirroring `Arguments.kt` exactly.
- **`SizeGuard.swift`** regained case-for-case parity with `SizeGuard.kt`: `audioChannelCount` on
  `InputInfo`, `outputCodecIsHevc` on `Options`, both defaulted for backward compatibility, plus
  the matching `wouldTransmux` conditions and six mirrored XCTest cases.
- **`CodecCapabilities.swift`** (new): a pure `hasHardwareEncoder(isHardwareEncoderAvailable:)`
  decision function over an injected closure, plus a real wrapper using `VTCopyVideoEncoderList`
  to answer whether this device has a hardware-accelerated HEVC encoder.
- **`CompressionEngine.swift`**: resolves the output codec once per job (HEVC when requested and
  hardware-capable, or when keep-HDR is requested and achievable); builds a parallel HEVC output
  dictionary with `AVVideoColorPropertiesKey` carrying the source's own HLG/PQ transfer for
  keep-HDR; pre-flight validates with `writer.canApply` and falls back to H.264 with
  `hevcFallback: true` on a probe/writer disagreement; forces >2-channel or non-AAC audio to a
  2-channel 128kbps AAC re-encode via `AVAssetReaderAudioMixOutput` (a real downmix, unlike
  `AVAssetReaderTrackOutput`); every H.264 output now carries explicit BT.709 colour properties;
  `toneMapped`/`hevcFallback`/`audioReencoded` are all threaded as real values and gated by
  `!usedOriginal` in `buildResult`, matching Android's `TransformerEngine.finishSuccess` exactly.
- **`hard_inputs_test.dart`**: every Android-only skip guard removed (the whole suite now runs on
  the iOS simulator and the macOS host too); a `HARD_INPUT_RESULT` diagnostic line added to every
  case that produces a `CompressResult`, printed before any assertion, so a future CI failure here
  is self-diagnosing.
- **CI** (`.github/workflows/ci.yml`): logs the Apple runner's `uname -m`/CPU brand string before
  the integration steps, so the "macOS runner has a hardware HEVC encoder" claim is an observed
  fact — confirmed `arm64` / Apple M1 (Virtual).
- **`corpus/generate_corpus.sh`**: `surround51_480p.mp4` regenerated with a high-entropy
  `mandelbrot` source at ~3Mbps (was `testsrc` at `crf 30`, measuring only ~60kbps), the same
  fixture-design fix 04-02 applied to the HDR clips.

## CI Evidence

Five pushed CI attempts plus two coordinator-granted phase-level retries (the plan's own 3-attempt
budget was explicitly exceeded with orchestrator authorization, since each attempt fixed a real,
distinct bug — never a flake):

| Run | Result | What it found |
|-----|--------|---------------|
| 36267121646 | fail (compile) | `kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder` is iOS-17.4-only |
| 36267489006 | fail (5 cases) | HDR default/keepHdr `toneMapped` false; 5.1 downmix threw AVFoundation -11800 |
| 36270368399 | fail (1 case) | HDR/keepHdr fixed; 5.1 downmix esds still reported 6 channels |
| 36275676001 | fail (1 case, identical) | Same 6-channel result despite a second independent downmix fix — pointed away from the writer entirely |
| 36279264836 | **success** (all 4 jobs) | Root cause found (never-larger substitution on a too-low-bitrate fixture) and fixed; every case green |

**Run 36279264836's `HARD_INPUT_RESULT`/branch evidence:**
- iOS simulator (no hardware HEVC): `KEEP_HDR_BRANCH=fallback` (HLG, PQ), `HEVC_BRANCH=fallback`.
- macOS host (Apple M1 Virtual, confirmed `arm64` via the new CI step): `KEEP_HDR_BRANCH=keep`
  (HLG, PQ), `HEVC_BRANCH=success` — the real hardware success path, proven live.
- `surround51_480p`: `usedOriginal=false transmuxed=false audioReencoded=true inputBytes=1001466
  outputBytes=~340000 channels=2` on both Apple legs, and `outputBytes=319886` on Android — all
  comfortably inside the never-larger margin the regenerated fixture provides.
- Android's own emulator step stalled ~2.5h with no output on attempt 1 of the final run (the
  documented hosted-emulator stall, not a code issue); the coordinator cancelled and reran it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder` is iOS-17.4-only**
- **Found during:** First pushed CI attempt (compile error, both the initial build and the
  Pods-reset retry)
- **Issue:** The originally-written `CodecCapabilities.swift` probe used a VideoToolbox
  specification key introduced in iOS 17.4, well above this plugin's iOS 13 deployment floor.
- **Fix:** Replaced with `VTCopyVideoEncoderList` + `kVTVideoEncoderList_IsHardwareAccelerated`
  (iOS 8/macOS 10.8+), enumerating every encoder the system reports.
- **Files modified:** `CodecCapabilities.swift`
- **Commit:** `fea5932`

**2. [Rule 1 - Bug] H.264 output not explicitly tagged SDR**
- **Found during:** Second pushed CI attempt (4 real test failures)
- **Issue:** `AVAssetWriter` infers colour properties from the first appended `CVPixelBuffer`'s
  own attachments when none are set explicitly. A decoded HDR source's buffer can still carry its
  original HLG/PQ transfer-function attachment even after the pixel values are tone-mapped to SDR
  by the system (Phase 3's D-08 reader path), so the produced file was genuinely mistagged HDR
  despite holding SDR pixel data — `toneMapped`'s own honest re-probe correctly reported `false`.
- **Fix:** Every H.264 output now carries an explicit BT.709 `AVVideoColorPropertiesKey`.
- **Files modified:** `CompressionEngine.swift`
- **Verification:** All 4 HDR/keepHdr cases pass on the iOS simulator (attempt 3) and macOS host
  (final run).
- **Commit:** `cb843db`

**3. [Rule 1 - Bug] `AVAssetReaderTrackOutput` does not perform a real channel downmix**
- **Found during:** Second and third pushed CI attempts (the 5.1 case)
- **Issue:** Requesting a smaller `AVNumberOfChannelsKey` than the source's own channel count in
  `AVAssetReaderTrackOutput`'s `outputSettings` is silently ignored — the decoded PCM comes back
  at the source's native channel count regardless, with no error.
- **Fix:** Switched the `audioWillReencode` reader path to `AVAssetReaderAudioMixOutput`, which
  performs the downmix for real through Core Audio's mix engine (works with no explicit
  `AVAudioMix` set). Widened the shared `audioOutput` type from `AVAssetReaderTrackOutput` to its
  common superclass `AVAssetReaderOutput` in both `compress()` and `runCopyLoop()`.
- **Files modified:** `CompressionEngine.swift`
- **Commit:** `8bac542`
- **Note:** This fix was necessary and correct, but did NOT resolve the observed failure — the
  real root cause was #5 below. Left in place because it is independently correct behaviour.

**4. [Rule 1 - Bug] `audioReencoded` not gated by `!usedOriginal`**
- **Found during:** Diagnosing the persisting 5.1 failure after two independent downmix fixes
  produced no observable change
- **Issue:** `buildResult`'s `audioReencoded` parameter was passed straight through to the caller,
  unlike `toneMapped`/`hevcFallback`/`transmuxed`, which were already correctly gated by
  `!usedOriginal`. A never-larger substitution therefore reported `audioReencoded: true` for a
  file that was actually the untouched original — masking exactly this failure mode behind a
  dishonest flag, and making it look like a downmix bug when it was a reporting bug plus a fixture
  issue.
- **Fix:** Gated `audioReencoded` by `!usedOriginal` in `buildResult`, matching Android's
  `TransformerEngine.finishSuccess` exactly (confirmed this was already Android's own behaviour by
  reading the Kotlin source, not assumed).
- **Files modified:** `CompressionEngine.swift`
- **Commit:** `4ee89ee`

**5. [Rule 1 - Bug] `surround51_480p.mp4` fixture too low-bitrate for its own audio downmix**
- **Found during:** Fourth pushed attempt / first coordinator-granted retry (identical failure
  despite two independent, correct downmix fixes)
- **Issue:** The original fixture's `testsrc`+`crf 30` video source measured only ~60kbps real
  bitrate. `SizeGuard`'s rule 6 input-bitrate cap forced the resolved encode target down to that
  same ~60kbps — low enough that Apple's real H.264 encoder's actual output apparently exceeded it
  by enough to trip the unconditional never-larger post-check, substituting the untouched
  6-channel original for the downmixed re-encode. Exactly the failure mode 04-02 already fixed for
  the HDR fixtures, not yet applied to this one.
- **Fix:** Regenerated `surround51_480p.mp4` with a high-entropy `mandelbrot` source at ~3Mbps
  (`corpus/generate_corpus.sh`), re-ran `verify_corpus.sh --write`, `verify_corpus.sh` (no drift),
  `sync_to_example.sh`. Confirmed via the new `HARD_INPUT_RESULT` diagnostic: Android
  `outputBytes=319886` vs `inputBytes=1001466` (>3x headroom), matching the hand-computed
  SizeGuard prediction (~319,300 bytes) almost exactly.
- **Files modified:** `corpus/generate_corpus.sh`, `corpus/surround51_480p.{mp4,expected.json}`,
  `example/assets/corpus/surround51_480p.{mp4,expected.json}`, `corpus/README.md`
- **Commit:** `4ee89ee`

### Process deviation

The plan's own budget was 3 pushed CI attempts. The coordinator granted 2 additional phase-level
retries beyond that budget because each attempt found and fixed a genuinely new, distinct bug
(never the same failure recurring for an unknown reason) — documented here per the plan's own
halt protocol rather than silently absorbed.

**Total deviations:** 5 auto-fixed real bugs (4 in the Apple engine, 1 in the test corpus), all
Rule 1. **Impact:** All were genuine correctness gaps this plan's own CI attempts surfaced and
closed; none were pre-existing issues out of scope, and no test assertion was weakened.

## Self-Check: PASSED

- `darwin/compress_video/Sources/compress_video/CodecCapabilities.swift` exists: confirmed.
- All 8 commits (`2db39f6`, `b0b1e61`, `cb4f64f`, `9cbaea5`, `fea5932`, `cb843db`, `8bac542`,
  `4ee89ee`) present in `git log`: confirmed.
- `diff example/ios/RunnerTests/RunnerTests.swift example/macos/RunnerTests/RunnerTests.swift`:
  no output (identical).
- `grep -c 'skip:' example/integration_test/hard_inputs_test.dart`: 0.
- CI run 36279264836: all four jobs (`Android`, `Detect Apple-relevant changes`, `Apple`,
  `Cross-platform parity`) `success`.

## What 04-05 Needs to Know

- **Parity exclusions to document:** `surround51_480p.mp4`'s exact output bytes differ between
  Android (~319,886–342,568) and Apple (~337,123–342,568) by a few percent, well inside any
  reasonable tolerance, but 04-05's parity schema should treat this the same as the
  `videoBitrateBps`/`truncated_mdat.mp4` exclusions already in `corpus/README.md` rather than
  gating on exact bytes.
- **The macOS hardware AAC bitrate flake** (documented in `.claude/CLAUDE.md` lane notes,
  `compress_audio_test.dart`'s 64000bps-vs-128000bps case): did not occur in this plan's final
  green run, but remains a known intermittent hardware-encoder-variance flake on the macOS host —
  04-05 should not be surprised by it and should re-run rather than investigate if it appears.
- **`doc/HARDWARE_CHECKLIST.md`**: the HEVC/keep-HDR success path is no longer purely
  reviewed-but-unproven — it is now CI-proven live on the macOS host's real Apple Silicon Media
  Engine (`HEVC_BRANCH=success`, `KEEP_HDR_BRANCH=keep` for both HLG and PQ). 04-05 should update
  the checklist to reflect this is proven on a CI runner, with a physical-device pass still useful
  for the Dolby Vision case specifically (still a reserved corpus slot, `QUESTIONS.md` #4).
- **CDEC-01, CDEC-02, CDEC-03, AUDO-03** all stay `Pending` in `REQUIREMENTS.md` — 04-05 also
  declares them and is the last plan to finish; they should flip to `Complete` once 04-05's own
  `SUMMARY.md` exists (shared-ID gate, `requirements.ready-ids`).
