---
phase: 04-codecs-hdr-and-hard-inputs
fixed_at: 2026-09-27T06:23:06Z
review_path: .planning/phases/04-codecs-hdr-and-hard-inputs/04-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 04: Code Review Fix Report

**Fixed at:** 2026-09-27T06:23:06Z
**Source review:** .planning/phases/04-codecs-hdr-and-hard-inputs/04-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope (critical + warning): 4
- Fixed: 4
- Skipped: 0
- Out of scope (info, not fixed by this pass): IN-01

## Fixed Issues

### CR-01: HEVC opt-in and keep-HDR-fallback gates computed independently, allowing "HEVC-SDR" output

**Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt`, `darwin/compress_video/Sources/compress_video/CompressionEngine.swift`, `example/integration_test/hard_inputs_test.dart`, `android/src/test/kotlin/com/danjjohnson/compress_video/HevcOutputDecisionTest.kt`
**Commit:** `80d8ef7`
**Applied fix:** Adopted the coherent rule from the review's own Fix code block (option: force
H.264 unconditionally whenever a keep-HDR request against a genuinely HDR source could not be
honoured, regardless of an independently-available plain hardware HEVC encoder) rather than the
prompt's alternative "honour explicit HEVC for the SDR output" variant, because the latter would
contradict `hard_inputs_test.dart`'s own pre-existing `_expectCodecFallbackInvariant` rule ("a
fallback always produces H.264 -- never HEVC 8-bit or any other codec"), which is exercised by
every other codec/HDR case in the suite and by `HdrMode.keepHdr`'s own dartdoc contract.

On Android, extracted the coupled decision into a new pure companion function
`TransformerEngine.resolveHevcOutputDecision(requestedHevc, hasHardwareHevc, requestedKeepHdr,
inputIsHdr, keepHdrAchievable)` returning `HevcOutputDecision(outputIsHevc, hevcFallback)`, called
identically from both `compress()` and the `resolvePlan()` overload (previously two independently
maintained inline formulas) — this also structurally guarantees the two call sites can never
drift apart again. On Apple, the same `keepHdrFallbackActive` gate is inlined identically in
`CompressionEngine.compress()` and its `resolvePlan()` overload (no Swift toolchain available on
this machine to extract a shared helper safely; kept the change minimal and mirrored line-for-line
against the Kotlin logic).

Added `HevcOutputDecision` unit tests (7 cases, including the exact CR-01 reachable scenario:
explicit HEVC request + hardware HEVC present + keep-HDR requested against a genuinely HDR source
whose HDR-editing capability check fails) and a new `hard_inputs_test.dart` case
(`codec: VideoCodec.hevc, hdr: HdrMode.keepHdr` against `hdr_hlg10.mp4`) asserting via the
existing `_expectCodecFallbackInvariant` that the combination always resolves coherently.

**Verification:** `./gradlew :compress_video:testDebugUnitTest` — full suite green, including the
new `HevcOutputDecisionTest` (7/7 passed). `dart format`/`dart analyze` clean on the modified Dart
test file. Swift change verified by Tier-1 re-read only (no Swift toolchain on this machine, per
project CLAUDE.md) — **requires human verification** on the MacBook Air / CI before this phase is
considered fully verified on Apple.

### CR-02: `hevcFallback` reports `true` for every `HdrMode.keepHdr` request against a non-HDR source

**Files modified:** same as CR-01 (fixed by the same commit — the two findings share the exact
same lines/variables in both engines, and fixing CR-01 without also gating on `inputIsHdr` would
have introduced a NEW bug: a `codec: hevc` + `hdr: keepHdr` request against a non-HDR source would
wrongly downgrade to H.264 even though there is nothing to keep).
**Commit:** `80d8ef7`
**Applied fix:** `resolveHevcOutputDecision`'s `keepHdrFallbackActive` gates on `inputIsHdr`
(Android) / `inputInfo.isHdr` (Apple), so a keep-HDR request against an already-SDR source is
correctly treated as a harmless no-op: `hevcFallback: false`, `toneMapped: false`. Added
`hard_inputs_test.dart` case: `small_480p.mp4` (SDR) with `hdr: HdrMode.keepHdr` asserts
`hevcFallback: false`, `toneMapped: false`, `videoCodec: 'h264'`.

**Verification:** Same JVM run as CR-01 (`keepHdrRequest_sdrSource_isHarmlessNoOpNeverReportedAsFallback`
passed). `dart analyze`/`dart format` clean.

### WR-01: The 5.1 downmix corpus fixture cannot detect a channel-mapping error

**Files modified:** `corpus/generate_corpus.sh`, `corpus/surround51_480p.mp4`,
`corpus/surround51_480p.expected.json`, `example/assets/corpus/surround51_480p.mp4`,
`example/assets/corpus/surround51_480p.expected.json`,
`android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt`,
`android/src/test/kotlin/com/danjjohnson/compress_video/FiveDotOneToStereoMixingMatrixTest.kt`
**Commit:** `1d87b0b`
**Applied fix:**
1. Regenerated `surround51_480p.mp4`'s 5.1 audio with six distinct sine tones
   (100/200/300/400/500/600Hz for FL/FR/FC/LFE/BL/BR respectively, via six `lavfi sine` sources
   merged with `amerge` and explicitly labelled into the `5.1` layout with `pan`), replacing the
   old fixture where every channel carried the identical mono tone. Regenerated via
   `bash corpus/generate_corpus.sh`, re-wrote the sidecar with `bash corpus/verify_corpus.sh
   --write` (only `surround51_480p.expected.json`'s `sizeBytes` changed — every other clip
   regenerated byte-identical), re-verified with a plain `bash corpus/verify_corpus.sh` (no
   drift), and synced with `bash corpus/sync_to_example.sh` (sha256-verified).
2. Moved `fiveDotOneToStereoMixingMatrix` from a `private` instance method to a pure,
   argument-free companion function (mirroring the existing `buildVideoEffects` pattern), and
   added `FiveDotOneToStereoMixingMatrixTest` — a plain JVM unit test asserting every input
   channel's coefficients directly, including two regression cases pinned specifically on the
   review's own named risk ("back-left/back-right already can't swap without an audible balance
   change... but the two rear channels can"): `backLeft_foldsIntoLeftOnlyNeverRight` and
   `backRight_foldsIntoRightOnlyNeverLeft`.

**Scope decision:** The review's Fix section suggested two remedies: (a) a pure-JVM unit test
against the matrix coefficients, explicitly called "a cheaper first step", and (b) an on-device
assertion in `hard_inputs_test.dart` inspecting the downmixed sample values' relative energy. (a)
is fully implemented above. (b) was assessed and **not** implemented in this pass: this plugin
exposes no API for reading decoded PCM sample values from Dart (only metadata/byte-size/codec
fields), and no `ffmpeg`/`ffprobe` binary is available inside the Android emulator or iOS
simulator the integration suite runs in, so a genuine on-device spectral-energy assertion would
require new infrastructure beyond a fix pass's scope. The regenerated fixture now CARRIES
distinguishable content on all six channels (the structural precondition WR-01 identified as
missing), and the Apple engine's `AVAssetReaderAudioMixOutput` downmix is exercised against the
same new fixture by the existing `hard_inputs_test.dart` assertions (`audioReencoded`, channel
count via `_readMp4AudioChannelCount`, `audioCodec`) — unchanged, since none of those assertions
depend on channel content. This residual gap (an on-device or host-side sample-level assertion) is
recorded here as a legitimate follow-up rather than silently dropped.

**Verification:** `./gradlew :compress_video:testDebugUnitTest` — full suite green, including new
`FiveDotOneToStereoMixingMatrixTest` (6/6 passed). `bash corpus/verify_corpus.sh` — no drift.

### WR-02: `CompressOptions.codec` can be silently overridden to HEVC by a successful `HdrMode.keepHdr` request

**Files modified:** `lib/src/compress_options.dart`
**Commit:** `b8e9f0e`
**Applied fix:** Chose the review's second option (document the override) over rejecting the
`codec: h264` + `hdr: keepHdr` combination at validation time, since the override is intentional,
pre-existing, load-bearing behaviour (`HdrMode.keepHdr`'s own dartdoc already states it: "Keep the
input's HDR characteristics (HEVC 10-bit...)"), and adding a new validation rejection would be a
breaking behavioural change to an already-shipped-in-this-phase contract, not merely a
documentation gap fix. Added a cross-reference directly to `CompressOptions.codec`'s own dartdoc
stating the override explicitly, why it happens (HDR cannot be represented in this plugin's H.264
output), what the result reports in that case (`hevcFallback: false`, `videoCodec: 'hevc'`), and
the escape hatch for a caller that must never receive HEVC (`hdr: HdrMode.toneMapToSdr`
explicitly). This is a single shared Dart-level contract read by both native implementations, so
no native-side change was needed to "apply it on both platforms" — the platforms already implement
the now-documented behaviour identically (confirmed by the CR-01/CR-02 fix above, which touched
the exact lines this override lives on in both engines).

**Verification:** `dart format`/`dart analyze` clean. `flutter test` — full suite green (83/83),
including `compress_options_test.dart`'s existing codec/hdr acceptance cases (unaffected —
documentation-only change).

## Skipped Issues

None — all in-scope findings were fixed.

## Notes for the human reviewer

- **CR-01/CR-02's Apple-side fix (`CompressionEngine.swift`) was verified by Tier-1 re-read only.**
  No Swift toolchain exists on this machine (danserver); per project CLAUDE.md this is expected,
  and the change was kept minimal, mirrored line-for-line against the already-verified Kotlin
  logic, and type-shaped conservatively (`let`/`var` mirrored exactly, no new control flow beyond
  an `if`/`else` ternary already used elsewhere in the same function). **Confirm on the MacBook Air
  or CI (XCTest / the `apple` GitHub Actions job) before treating this phase as fully re-verified.**
- **WR-01's residual scope** (an on-device sample-level downmix assertion) is a legitimate,
  documented follow-up, not a dropped requirement — see the Scope decision above.
- Local verification run for this fix pass: `flutter analyze --fatal-infos --fatal-warnings`
  (clean), `flutter test` (83/83), `./gradlew :compress_video:testDebugUnitTest` (full suite green
  including 13 new JVM tests), `bash corpus/verify_corpus.sh` (no drift), `bash
  tool/check_parity_test.sh` (13/13 self-test cases pass). All ran in the main checkout (this repo
  has `workflow.use_worktrees: false`, so no isolated worktree was created for this fix pass —
  these numbers are reproducible directly from `main` at commit `b8e9f0e`). The hard-inputs suite
  itself was **not** run on the local Android emulator by this fixer (out of scope for a
  code-review-fix pass per its own instructions; recommended before shipping this phase).
- `flutter analyze`/`flutter test` both mutate `analysis_options.yaml` as an unrelated first-run
  side effect ("Upgrading analysis_options.yaml to exclude build and platform directories") — this
  was reverted with `git checkout -- analysis_options.yaml` after each run and is not part of any
  commit above; a future run of either command will re-trigger it and should be reverted the same
  way if not intentionally adopted.

---

_Fixed: 2026-09-27T06:23:06Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
