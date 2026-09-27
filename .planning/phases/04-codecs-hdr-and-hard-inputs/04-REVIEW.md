---
phase: 04-codecs-hdr-and-hard-inputs
reviewed: 2026-09-27T12:00:00Z
depth: standard
files_reviewed: 25
files_reviewed_list:
  - .github/workflows/ci.yml
  - android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/CodecCapabilities.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/ArgumentsTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/CodecCapabilitiesTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/SizeGuardTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/HevcOutputDecisionTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/FiveDotOneToStereoMixingMatrixTest.kt
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
  critical: 0
  warning: 0
  info: 1
  total: 1
status: clean
---

# Phase 04: Code Review Report (iteration 2 — fix verification)

**Reviewed:** 2026-09-27T12:00:00Z
**Depth:** standard
**Files Reviewed:** 25
**Status:** clean

## Summary

This is iteration 2 of the auto-fix loop. Iteration 1 (`04-REVIEW.md`, superseded, see git
history) found CR-01, CR-02, WR-01, WR-02, and IN-01. Fix commits `80d8ef7` (CR-01/CR-02),
`1d87b0b` (WR-01), and `b8e9f0e` (WR-02) are on `main`. This pass re-derives the pre-fix bug from
first principles on both platforms, traces the new coupled-decision logic line by line against
every reachable input combination, checks the new/changed tests actually exercise the fixed rules,
and re-scans the untouched files for regressions or previously-missed issues. IN-01 was left
explicitly out of scope for the fix pass per instructions and is not re-raised above Info here, per
this iteration's own instructions.

**CR-01/CR-02 verification (both platforms).** `TransformerEngine.resolveHevcOutputDecision`
(Android, new pure companion function, called identically from both `compress()` and the
`resolvePlan()` overload) and the inlined `keepHdrFallbackActive` gate in
`CompressionEngine.compress()`/`resolvePlan()` (Apple) now compute `outputIsHevc` and
`hevcFallback` as one coupled unit instead of two independent booleans. I hand-traced all eight
reachable combinations of `(requestedHevc, hasHardwareHevc, requestedKeepHdr, inputIsHdr,
keepHdrAchievable)` relevant to the two findings, including the exact CR-01 scenario (explicit
`codec: hevc` + generic hardware HEVC present + `hdr: keepHdr` against a genuinely HDR source whose
HDR-editing capability check fails) and the exact CR-02 scenario (`hdr: keepHdr` against an
already-SDR source). In every traced case `outputIsHevc` and `hevcFallback` now agree with the
class contract (`hevcFallback: true` implies H.264 output; `hevcFallback` is `false` whenever
nothing was attempted). The Kotlin and Swift implementations are line-for-line equivalent —
`keepHdrFallbackActive = requestedKeepHdr && inputIsHdr && !keepHdrAchievable`, then `outputIsHevc =
keepHdrFallbackActive ? false : (hasHardwareHevc || keepHdrAchievable)`, then `hevcFallback =
(requestedHevc && !hasHardwareHevc) || keepHdrFallbackActive` — on both files. The Swift change is
type-sound: all operands are `Bool`, the ternary is a pre-existing idiom already used elsewhere in
this function (e.g. the pixel-format ternary a few lines above), and `outputIsHevc`/`hevcFallback`
remain `var` exactly as before so the existing post-`canApply` fallback branch (lines 364–381,
untouched by this fix, already correctly reverts `videoReaderSettings` to 8-bit BGRA and rebuilds
`videoOutputSettings` when the writer disagrees with the probe) continues to work unchanged. The
`resolvePlan` overload on both platforms independently recomputes the same coupled decision from
the same primitives rather than threading a value in from `compress()`, so the `SizeGuard`
estimate-vs-real-compress agreement invariant this codebase relies on elsewhere still holds.

Regression check requested by this iteration's brief:
- **Transmux fast path for the default request:** unaffected. `wouldTransmux` is gated by
  `SizeGuard.Options.outputCodecIsHevc` (fed by the same coupled decision via the `resolvePlan`
  overload) already disqualifying transmux whenever the resolved output would be HEVC; for the
  default request (`requestedHevc=false, requestedKeepHdr=false`) the coupled decision reduces to
  the pre-fix formula exactly (`keepHdrFallbackActive` is always `false` when `requestedKeepHdr` is
  `false`), so no behavioural change for the common path.
- **Never-larger unconditional:** `finishSuccess`'s `usedOriginal = tempBytes >= inputBytes` check
  (Android) and the equivalent Apple copy-original path are untouched by either fix commit and sit
  downstream of the coupled decision, not gated by it.
- **Flags gated by `!usedOriginal`:** confirmed unchanged on Android — `hevcFallback =
  !usedOriginal && hevcFallbackFromRequest` (line 722) still wraps the new `hevcDecision.hevcFallback`
  value exactly as it wrapped the old inline formula, and the `wouldUseOriginal` fast path at the
  top of `compress()` still forces `toneMapped`/`hevcFallback` to `NO_TRANSFORM_ATTEMPTED` before
  any Transformer is built, unaffected by the new coupling. Apple's `buildResult`'s own
  `!usedOriginal` guard (line ~833, `resolvedHevcFallback = !usedOriginal && hevcFallback`) is
  likewise untouched.

**New tests verified to exercise the fixed rules, not just re-assert the old (buggy) behaviour.**
`HevcOutputDecisionTest.kt`'s 7 cases include the exact CR-01 combination
(`explicitHevcRequest_hardwareAvailable_plusUnachievableKeepHdrOnHdrSource_forcesH264Fallback`,
asserting `outputIsHevc == false` where the pre-fix formula would have produced `true`) and the
exact CR-02 combination (`keepHdrRequest_sdrSource_isHarmlessNoOpNeverReportedAsFallback`,
asserting `hevcFallback == false` where the pre-fix formula would have produced `true`) — both
assertions would fail against the pre-fix formula, confirming these are genuine regression tests
rather than restatements. `hard_inputs_test.dart`'s two new groups reuse the pre-existing
`_expectCodecFallbackInvariant` cross-cutting assertion (which itself asserts the class contract:
`hevcFallback` implies H.264, never-fallback implies the requested codec) against
`hdr_hlg10.mp4` with `codec: hevc, hdr: keepHdr` (CR-01's reachable scenario) and against
`small_480p.mp4` with `hdr: keepHdr` alone (CR-02's reachable scenario, additionally asserting
`hevcFallback: false` and `toneMapped: false` directly).

**WR-01 verification.** `fiveDotOneToStereoMixingMatrix` moved from a private instance method to
an `internal`, argument-free companion function with no behavioural change to its coefficients
(confirmed by diff — the coefficient table itself is byte-identical, only its location and
visibility changed). `FiveDotOneToStereoMixingMatrixTest.kt` asserts every one of the six input
channels' coefficients directly, including the two regressions the review specifically named
(`backLeft_foldsIntoLeftOnlyNeverRight`, `backRight_foldsIntoRightOnlyNeverLeft`) — a BL/BR
transposition bug would flip exactly these two assertions. `corpus/generate_corpus.sh`'s
regenerated `surround51_480p.mp4` now merges six independently-generated sine sources
(100/200/300/400/500/600Hz) via `amerge` + `pan=5.1|c0=c0|...|c5=c5` (explicit identity mapping,
not the old `c0=c0|c1=c0|...` all-channels-to-c0 collapse), giving every one of the six channels
distinguishable content — the structural precondition the finding required. The commit stat shows
only `surround51_480p.mp4`/`.expected.json` changed size (byte count), consistent with a real
audio-content regeneration rather than an accidental full-corpus rewrite, and the fix report
records a clean `verify_corpus.sh` re-run after `sync_to_example.sh`.

**WR-02 verification.** `CompressOptions.codec`'s dartdoc now cross-references the `HdrMode.keepHdr`
override directly (added text states the override, the resulting `hevcFallback: false` /
`videoCodec: 'hevc'` combination, and the `HdrMode.toneMapToSdr` escape hatch) rather than leaving
it discoverable only from `HdrMode.keepHdr`'s own doc. This is a documentation-only change, matches
the review's own accepted alternative (document rather than reject the combination, since the
override is pre-existing, intentional, load-bearing behaviour), and does not touch the native
decision logic already re-verified above.

**Re-scan of untouched files.** `CodecCapabilities.kt`/`.swift`, `SizeGuard.kt`/`.swift`,
`Arguments.kt`/`.swift`, `ci.yml`, and the `tool/*.sh` scripts are byte-identical to iteration 1 (no
commits since touched them) and were already reviewed clean at standard depth in iteration 1; no
new issues found on re-read of the sections most load-bearing to this iteration's focus (the
`SizeGuard.Options.outputCodecIsHevc` consumer and `CodecCapabilities.hasHardwareHevcEncoder`/
`supportsHdrEditing` producers the coupled decision depends on). No hardcoded secrets, dangerous
function usage, or empty catch blocks were introduced by any of the three fix commits.

All four in-scope findings (CR-01, CR-02, WR-01, WR-02) from iteration 1 are verified fixed,
correctly, on both platforms, with regression coverage that would fail against the pre-fix code.
No new Critical or Warning issues were found in this iteration. Per this iteration's instructions,
IN-01 (the `SURROUND_DOWNMIX_GAIN` comment) remains open at Info only and the documented decisions
in `corpus/README.md` are not treated as defects.

## Info

### IN-01: `SURROUND_DOWNMIX_GAIN`'s doc comment misdescribes the constant's derivation (carried over, unfixed, out of scope by design)

**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt:1144-1149`
**Issue:** Unchanged since iteration 1. The comment states the `-3dB` gain constant is `10^(-3/20)
rounded to 7 significant figures` and gives `0.7071068f`; `10^(-3/20) ≈ 0.7079458`, while
`0.7071068` is actually `1/√2` (`-3.0103dB`, the standard equal-power constant). The functional
difference (~0.12% in linear gain) is inaudible and not a behavioural bug — this is a comment-only
inaccuracy.
**Fix:** Correct the comment to describe `1/√2` (`-3.0103dB`), or change the literal to
`0.7079458f` if `10^(-3/20)` was the intended reference value. (Explicitly out of scope for the
prior fix pass and this review; not escalated per this iteration's instructions.)

---

_Reviewed: 2026-09-27T12:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
