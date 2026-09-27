---
phase: 04-codecs-hdr-and-hard-inputs
reviewed: 2026-09-27T00:00:00Z
depth: standard
files_reviewed: 22
files_reviewed_list:
  - .github/workflows/ci.yml
  - android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/CodecCapabilities.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/ArgumentsTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/CodecCapabilitiesTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/SizeGuardTest.kt
  - corpus/generate_corpus.sh
  - corpus/sync_to_example.sh
  - corpus/verify_corpus.sh
  - darwin/compress_video/Sources/compress_video/Arguments.swift
  - darwin/compress_video/Sources/compress_video/CodecCapabilities.swift
  - darwin/compress_video/Sources/compress_video/CompressionEngine.swift
  - darwin/compress_video/Sources/compress_video/SizeGuard.swift
  - example/integration_test/hard_inputs_test.dart
  - example/ios/RunnerTests/RunnerTests.swift
  - example/macos/RunnerTests/RunnerTests.swift
  - lib/src/compress_options.dart
  - lib/src/compress_result.dart
  - test/compress_options_test.dart
  - tool/check_parity.sh
  - tool/check_parity_test.sh
  - tool/run_ios_integration_suites.sh
findings:
  critical: 2
  warning: 2
  info: 1
  total: 5
status: issues_found
---

# Phase 04: Code Review Report

**Reviewed:** 2026-09-27T00:00:00Z
**Depth:** standard
**Files Reviewed:** 22 (of 24 listed; `tool/run_ios_integration_suites.sh` and `.github/workflows/ci.yml` reviewed as CI/shell tooling, not native/Dart logic)
**Status:** issues_found

## Summary

Phase 4 adds HDR tone-mapping, HEVC opt-in, keep-HDR opt-in, forced stereo AAC downmix, and the
hard-inputs corpus/parity gate, ported in parallel across `TransformerEngine.kt` (Android) and
`CompressionEngine.swift` (Apple). The two engines are impressively kept in lockstep — `SizeGuard`'s
resolution rules, the `wouldTransmux`/`wouldUseOriginal` predicates, and the audio-channel-count/
HEVC gating conditions are numerically identical across the Kotlin and Swift ports, and both are
backed by a large, well-structured JVM/XCTest suite.

However, tracing the interaction between the HEVC opt-in gate (`hasHardwareHevc`) and the keep-HDR
gate (`keepHdrAchievable`) in both `compress()` entry points turned up **two real, reachable
contract violations that exist identically on both platforms** — the same bug was ported faithfully
in both directions, so the cross-platform parity gate cannot catch it (both sides agree on the wrong
answer). Both violate invariants this project's own dartdoc states as guarantees
(`CompressResult.hevcFallback`/`toneMapped`, `HdrMode.keepHdr`'s "falls back to tone-mapped SDR
H.264" contract) and are outside the corpus/CI test matrix's current coverage (no test combines
`VideoCodec.hevc` with `HdrMode.keepHdr`, and no test requests `HdrMode.keepHdr` against a non-HDR
clip). See CR-01 and CR-02 below.

A secondary quality gap was found in the 5.1-to-stereo downmix test fixture: the corpus clip that
exercises `fiveDotOneToStereoMixingMatrix`/the Apple `AVAssetReaderAudioMixOutput` downmix carries
identical audio content on all six channels, which makes it structurally incapable of catching a
channel-mapping error (see WR-01).

## Critical Issues

### CR-01: HEVC opt-in and keep-HDR-fallback gates are computed independently, allowing "HEVC-SDR" output the class contract forbids

**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt:106-112` (also `:923-926`, the `resolvePlan` overload)
**File:** `darwin/compress_video/Sources/compress_video/CompressionEngine.swift:132-157` (also `:726-734`, the `resolvePlan` overload)

**Issue:** `outputIsHevc` (Android) / `outputIsHevc` (Apple) is computed as a plain OR of two
independent booleans:

```kotlin
val hasHardwareHevc = requestedHevc && hasHardwareHevcEncoder()
val keepHdrAchievable = resolveKeepHdrAchievable(inputFile, inputInfo.isHdr, requestedKeepHdr)
val outputIsHevc = hasHardwareHevc || keepHdrAchievable
```

`resolveHdrMode(inputInfo.isHdr, keepHdrAchievable)` (Android, called separately at line 473) and
the reader/writer HDR pixel-format branch (Apple, `keepHdrAchievable ? 10-bit : 8-bit BGRA`) decide
*independently* whether the export actually keeps HDR or tone-maps to SDR — based on
`keepHdrAchievable` alone, ignoring `hasHardwareHevc`.

These two decisions can disagree. Consider a request with **both** `codec: VideoCodec.hevc` and
`hdr: HdrMode.keepHdr` against a genuinely HDR source, on a device that has a generic hardware HEVC
encoder (`hasHardwareHevcEncoder()` → true) but whose HDR-editing capability check fails for this
specific `ColorInfo` (`CodecCapabilities.supportsHdrEditing`/`VTCopyVideoEncoderList`'s
HDR-editing enumeration → empty — a realistic split, since generic HEVC encode support is far more
common than HDR-editing-capable HEVC encode support):

- `hasHardwareHevc = true` (plain HEVC request honoured)
- `keepHdrAchievable = false` (keep-HDR specifically not achievable)
- `outputIsHevc = true || false = true` → the Transformer/AVAssetWriter is configured for HEVC output
- `resolveHdrMode`/the reader pixel format independently choose the **tone-map-to-SDR** path (Android: `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL`; Apple: 8-bit BGRA reader settings, and — because `keepHdrAchievable` is false — the HEVC output dictionary never gets its `AVVideoColorPropertiesKey` block at all, line 324 of `CompressionEngine.swift`)

The result is an **HEVC-encoded, tone-mapped SDR file with no explicit colour tagging at all** —
exactly the outcome `HdrMode.keepHdr`'s own dartdoc rules out ("the engine falls back to tone-mapped
SDR H.264") and exactly what `hard_inputs_test.dart`'s own `_expectCodecFallbackInvariant` helper
asserts can never happen ("a fallback always produces H.264 -- never HEVC 8-bit or any other
codec"). It also means the tone-mapped output never gets the required explicit BT.709 tagging,
because that tagging lives only in `h264OutputSettings` (Apple), which is skipped whenever
`outputIsHevc` is true.

No test exercises this combination: `hard_inputs_test.dart`'s `expectKeepHdrOrFallback` always uses
the default `codec: VideoCodec.h264`, and the HEVC opt-in test (`portrait_hibitrate_1080p60.mp4`)
uses a non-HDR clip. Because the exact same faulty formula was ported to both platforms, the
cross-platform parity gate (`tool/check_parity.sh`) cannot detect it either — both platforms agree
on the wrong answer.

**Fix:** Force H.264 whenever a keep-HDR request could not be honoured, regardless of the
independent plain-HEVC capability:

```kotlin
// Android, TransformerEngine.compress (and the resolvePlan overload's outputCodecIsHevc)
val keepHdrFallbackActive = requestedKeepHdr && !keepHdrAchievable
val outputIsHevc = if (keepHdrFallbackActive) false else hasHardwareHevc || keepHdrAchievable
```

```swift
// Apple, CompressionEngine.compress (and the resolvePlan(inputURL:inputInfo:request:) overload)
let keepHdrFallbackActive = requestedKeepHdr && !keepHdrAchievable
var outputIsHevc = keepHdrFallbackActive ? false : (hasHardwareHevc || keepHdrAchievable)
```

Add a regression case to `hard_inputs_test.dart` that requests `CompressOptions(codec:
VideoCodec.hevc, hdr: HdrMode.keepHdr)` against an HDR clip and asserts (via
`_expectCodecFallbackInvariant`) that a fallback always yields `videoCodec: 'h264'`.

---

### CR-02: `hevcFallback` reports `true` for every `HdrMode.keepHdr` request against a non-HDR source, even though nothing was attempted or fell back

**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt:121-122`
**File:** `darwin/compress_video/Sources/compress_video/CompressionEngine.swift:157`

**Issue:**

```kotlin
val hevcFallback =
    (requestedHevc && !hasHardwareHevc) || (requestedKeepHdr && !keepHdrAchievable)
```

`keepHdrAchievable` is `false` whenever `!inputInfo.isHdr` (see `resolveKeepHdrAchievable`'s own
first guard, `if (!requestedKeepHdr || !inputIsHdr) return false`) — **regardless of hardware
capability**. So for *any* SDR (non-HDR) input compressed with `hdr: HdrMode.keepHdr` (a
reasonable defensive pattern: "always ask to keep HDR if there is any"), `keepHdrAchievable` is
always `false`, and the second disjunct `requestedKeepHdr && !keepHdrAchievable` is always `true` —
so `hevcFallback` is reported `true` even though:

- the source was never HDR, so there was nothing to "keep" and nothing to fall back from,
- the encode ran as an ordinary H.264 SDR encode (identical to what `hdr: toneMapToSdr` would have
  produced), and
- `toneMapped` correctly stays `false` (guarded by `inputWasHdr`), since nothing was tone-mapped.

This produces the exact combination `CompressResult.toneMapped`'s own dartdoc says can never
happen: *"a genuine keep-HDR fallback reports both flags `true` together (tone-mapped SDR H.264),
never one without the other."* Here `hevcFallback: true` arrives with `toneMapped: false` for a
completely unremarkable SDR compression, misleading a caller who checks `hevcFallback` to detect a
real hardware limitation.

No test exercises `HdrMode.keepHdr` against a non-HDR corpus clip — `hard_inputs_test.dart`'s
keep-HDR group only runs against `hdr_hlg10.mp4`/`hdr_pq10.mp4`.

**Fix:** Gate the keep-HDR disjunct on the source actually being HDR:

```kotlin
val hevcFallback =
    (requestedHevc && !hasHardwareHevc) ||
        (requestedKeepHdr && inputInfo.isHdr && !keepHdrAchievable)
```

```swift
var hevcFallback =
  (requestedHevc && !hasHardwareHevc) || (requestedKeepHdr && inputInfo.isHdr && !keepHdrAchievable)
```

Add a case to `hard_inputs_test.dart` (or the existing SDR-corpus compression suite) that requests
`hdr: HdrMode.keepHdr` against a non-HDR clip (e.g. `small_480p.mp4`) and asserts `hevcFallback:
false`, `toneMapped: false`.

## Warnings

### WR-01: The 5.1 downmix corpus fixture cannot detect a channel-mapping error

**File:** `corpus/generate_corpus.sh:578-604` (surround51_480p.mp4 generation)
**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt:598-650` (`fiveDotOneToStereoMixingMatrix`)

**Issue:** `surround51_480p.mp4`'s 5.1 audio is built with
`pan=5.1|c0=c0|c1=c0|c2=c0|c3=c0|c4=c0|c5=c0` — every one of the six channels (FL, FR, FC, LFE, BL,
BR) carries the **identical** mono sine-wave signal. Because `fiveDotOneToStereoMixingMatrix`'s
matrix is symmetric per output side (`FL→L=1, FC→L=g, BL→L=g` and `FR→R=1, FC→R=g, BR→R=g`), feeding
identical content into every input channel makes `L_out == R_out` regardless of which physical
channel is wired to which coefficient slot. A regression that swapped `BL`/`BR` (front-left/right
already can't swap without an audible balance change, but the two rear channels can), or
accidentally folded `LFE` into the mix, would produce a numerically different but *symmetrically
identical* L/R result and would not be caught by `hard_inputs_test.dart`'s existing
`surround51_480p.mp4` assertions (`audioReencoded`, channel count via `_readMp4AudioChannelCount`,
`audioCodec`) — none of which inspect the actual downmixed sample values.

The Apple engine has no equivalent hand-written matrix (it delegates to
`AVAssetReaderAudioMixOutput`'s own Core Audio downmix), so this fixture also can't prove the two
platforms' downmix coefficients produce comparable audio — only that both produce *some* 2-channel
AAC output of a similar byte size (the documented `+/-50%` `outputBytes` envelope).

**Fix:** Add a second, low-cost fixture (or extend this one) where each of the six channels carries
a **distinct** tone/frequency (e.g. `pan=5.1|c0=0.5|c1=1.0|c2=1.5|...` via `sine` sources per
channel, or six discrete frequencies mixed in), then assert the downmixed L/R channels' relative
energy is consistent with the documented BS.775-style weighting (front channels dominant, centre
and one rear channel folded into each side at the sub-integer weight, LFE absent) — at least enough
to catch a channel-index transposition. A pure-JVM unit test directly against
`fiveDotOneToStereoMixingMatrix`'s output coefficients (it is currently `private` and untested even
at the unit level) would be a cheaper first step.

### WR-02: `CompressOptions.codec` can be silently overridden to HEVC by a successful `HdrMode.keepHdr` request, with no field distinguishing the two ways `videoCodec: 'hevc'` can happen

**File:** `lib/src/compress_options.dart:251-261` (`codec`/`hdr` dartdoc)
**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt:111` / `darwin/compress_video/Sources/compress_video/CompressionEngine.swift:150`

**Issue:** When `hdr: HdrMode.keepHdr` succeeds (`keepHdrAchievable == true`), `outputIsHevc` is
forced `true` **regardless of the caller's own `codec` field** — a caller who explicitly set
`codec: VideoCodec.h264` together with `hdr: HdrMode.keepHdr` still gets an HEVC output, with
`hevcFallback: false` (nothing "fell back"; the codec field was simply not honoured). This is
implied by `HdrMode.keepHdr`'s own dartdoc ("Keep the input's HDR characteristics (HEVC 10-bit...)")
but is not cross-referenced from `VideoCodec`/`codec`'s own dartdoc, and `CompressResult` has no
field that distinguishes "HEVC because the caller asked for HEVC" from "HEVC because keep-HDR
required it despite an explicit H.264 request."

**Fix:** Either reject the combination `codec: VideoCodec.h264` + `hdr: HdrMode.keepHdr` in
`CompressOptions.validate()`/`Arguments.requireValidCompressRequest` as contradictory (a caller who
explicitly asked for H.264 almost certainly did not intend HDR-keep to override it), or at minimum
cross-reference this override explicitly in `codec`'s own dartdoc so it isn't only discoverable by
reading `HdrMode.keepHdr`'s doc.

## Info

### IN-01: `SURROUND_DOWNMIX_GAIN`'s doc comment misdescribes the constant's derivation

**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt:1144-1149`

**Issue:** The comment states the `-3dB` gain constant is `10^(-3/20) rounded to 7 significant
figures`, and gives the value `0.7071068f`. `10^(-3/20) ≈ 0.7079458` (true `-3.0dB`); `0.7071068` is
actually `1/√2` (`-3.0103dB`) — a different, very well-known constant (the "-3dB pan law"/equal-power
constant) that happens to be numerically close but is not what the comment describes deriving. The
functional difference (≈0.12% in linear gain) is inaudible and not a behavioural bug, but the
comment's math is wrong and could mislead a future reader trying to verify or adjust the constant.

**Fix:** Either correct the comment to say `1/√2` (`0.70710678...`, `-3.0103dB`, the standard
equal-power constant many consumer downmix implementations actually use), or change the literal to
`0.7079458f` if `10^(-3/20)` was the actually-intended reference value.

---

_Reviewed: 2026-09-27T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
