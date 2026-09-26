---
phase: 04-codecs-hdr-and-hard-inputs
plan: 03
subsystem: api
tags: [media3, hevc, hdr, encoderutil, codec-capabilities, validation]

# Dependency graph
requires:
  - phase: 04-codecs-hdr-and-hard-inputs
    provides: "04-02's Composition/HdrMode wrapping, OpenGL-then-MediaCodec fallback chain, hard_inputs_test.dart's HDR group and dual-outcome idiom, SizeGuard.InputInfo.audioChannelCount"
provides:
  - "CodecCapabilities.kt: a pure/wrapper capability probe over Media3's EncoderUtil (hasHardwareEncoder, supportsHdrEditing), with the pure half (EncoderInfo, hasHardwareEncoderFor, isSoftwareCodecName) unit-testable on plain JVM against a fabricated encoder list"
  - "Arguments.kt/compress_options.dart validators (validateVideoCodec/validateHdrMode, CompressOptions.validate) accepting hevc/keepHdr, with doc comments rewritten to the real hardware-gated contract"
  - "TransformerEngine's shared outputIsHevc decision (hasHardwareHevc || keepHdrAchievable), read identically by the video-MIME gate and resolveHdrMode, with hevcFallback covering both HEVC-opt-in and keep-HDR triggers"
  - "SizeGuard.Options.outputCodecIsHevc, excluding the transmux fast path whenever the resolved output would really be HEVC, resolved identically by resolvePlan for both estimate() and the real job"
  - "readColorTransfer (mirrors Probe.isHdr's own MediaMetadataRetriever/API-30 gate) feeding CodecCapabilities.supportsHdrEditing for the keep-HDR achievability decision"
  - "hard_inputs_test.dart: a shared _expectCodecFallbackInvariant helper applied to every codec/HDR case, a new HEVC opt-in case (fallback branch proven live), and two new keep-HDR cases (exhausted-fallback-chain branch proven live; the keep branch itself unproven pending hardware)"
  - "doc/PRESETS.md's new HEVC and HDR section, stating no HEVC/keep-HDR bitrate has been measured yet"
affects: [04-04, 04-05]

# Actuals (#2632)
actuals:
  tokens: 14780
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Injectable capability probe: a pure decision function (hasHardwareEncoderFor) over a project-owned EncoderInfo list, with a thin wrapper (toEncoderInfo) doing the real EncoderUtil/Build.VERSION.SDK_INT work only at the call site that needs a real device -- the same SizeGuard-style seam CONTEXT.md's own discretion note asked for, but landing on a bespoke EncoderInfo type rather than raw android.media.MediaCodecInfo once live experimentation showed EncoderUtil.getSupportedEncoders (unlike EncoderUtil.isHardwareAccelerated) cannot run in this project's plain-JVM Gradle unit tests at all"
    - "One shared decision value threaded into two independent gates (video MIME, HdrMode) rather than two separately re-derived conditions -- the same anti-pattern 04-RESEARCH.md's Pattern 4 warns against for Media3's own automatic HdrMode step-down, now also the shape this plan's own new code follows so it cannot fall into the same trap"
    - "A cross-cutting Dart invariant helper (_expectCodecFallbackInvariant) applied to every codec/HDR integration case in a suite, old and new, rather than duplicating the same hevcFallback/videoCodec coherence check per case"

key-files:
  created:
    - android/src/main/kotlin/com/danjjohnson/compress_video/CodecCapabilities.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/CodecCapabilitiesTest.kt
  modified:
    - android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/ArgumentsTest.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/SizeGuardTest.kt
    - lib/src/compress_options.dart
    - test/compress_options_test.dart
    - example/integration_test/hard_inputs_test.dart
    - doc/PRESETS.md

key-decisions:
  - "EncoderUtil.getSupportedEncoders cannot run in this project's plain-JVM Gradle unit test environment (MediaCodecList.getCodecInfos throws 'not mocked'), confirmed empirically via a throwaway scratch test before committing to a design -- but EncoderUtil.isHardwareAccelerated against a Mockito-mocked MediaCodecInfo CAN (Build.VERSION.SDK_INT reads 0, taking the below-API-29 fallback path harmlessly). This asymmetry is why CodecCapabilities' pure half takes a project-owned EncoderInfo list rather than a raw MediaCodecInfo list -- the design choice is load-bearing, not stylistic."
  - "outputIsHevc = hasHardwareHevc || keepHdrAchievable is computed once and read by both the video-MIME gate and resolveHdrMode, and resolvePlan recomputes the identical decision (via the same private helpers) for SizeGuard.Options.outputCodecIsHevc -- three call sites, one decision, by construction rather than by discipline."
  - "hevcFallback is guarded by !usedOriginal inside finishSuccess (the same pattern toneMapped/transmuxed/audioReencoded already use), not computed with the guard baked in at the top of compress() -- the raw request-vs-capability value is threaded through as hevcFallbackFromRequest and the guard is applied once, at the point usedOriginal is known."
  - "isHdrToneMapAttempt (which gates the OpenGL-then-MediaCodec retry chain) is now inputInfo.isHdr && !keepHdrAchievable, not tied to the toneMapToSdr string -- an HDR source with an unachievable keepHdr request takes the SAME retry chain the default tone-map path does, which is what let this plan's new keep-HDR fallback cases reuse 04-02's already-proven exhausted-chain behavior instead of needing new fallback-chain code."
  - "The four Dart/Kotlin tests that asserted 'hevc'/'keepHdr' are rejected were rewritten (not merely supplemented) in the same commit that relaxed the validators -- leaving them in place would have made the task's own verification gate fail, and task 3's own instruction to 'extend' these files was already satisfied by that necessary fix."

requirements-completed: []

coverage:
  - id: D1
    description: "CodecCapabilities.kt: a pure/wrapper capability probe over EncoderUtil (hasHardwareEncoder for HEVC opt-in, supportsHdrEditing for keep-HDR), with the decision logic (hasHardwareEncoderFor, isSoftwareCodecName) unit-tested on plain JVM against a fabricated EncoderInfo list -- no emulator required"
    requirement: CDEC-01
    verification:
      - kind: unit
        ref: "android/src/test/kotlin/.../CodecCapabilitiesTest.kt (10 cases: software-only list, hardware-present list, empty list, all 4 D-05 prefixes, a non-matching vendor name, both HDR-editing outcomes)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Arguments.kt's validateVideoCodec/validateHdrMode and CompressOptions.validate() accept hevc/keepHdr; doc comments rewritten to the real hardware-gated contract; a still-unknown string is still rejected by both"
    requirement: CDEC-01
    verification:
      - kind: unit
        ref: "ArgumentsTest.kt: validateVideoCodec_h264OrHevc_isValid, validateVideoCodec_unknownValue_rejectedAsUnsupportedInput, validateHdrMode_toneMapToSdrOrKeepHdr_isValid, validateHdrMode_unknownValue_rejectedAsUnsupportedInput"
        status: pass
      - kind: unit
        ref: "test/compress_options_test.dart: 'h264 and hevc are both accepted codecs', 'toneMapToSdr and keepHdr are both accepted hdr modes'"
        status: pass
    human_judgment: false
  - id: D3
    description: "The video MIME gate resolves H.264-vs-HEVC from CodecCapabilities.hasHardwareEncoder, independent of HdrMode; hevcFallback is a real computed value (guarded by !usedOriginal); SizeGuard.Options.outputCodecIsHevc excludes the transmux fast path for a resolved-HEVC request -- proven live: an HEVC opt-in request on portrait_hibitrate_1080p60.mp4 reports hevcFallback:true, videoCodec:h264, and a smaller output on this hardware-HEVC-less emulator"
    requirement: CDEC-01
    verification:
      - kind: integration
        ref: "example/integration_test/hard_inputs_test.dart: 'portrait_hibitrate_1080p60.mp4 with VideoCodec.hevc ...' (fallback branch, HEVC_BRANCH=fallback)"
        status: pass
      - kind: unit
        ref: "SizeGuardTest.kt: wouldTransmux_outputCodecIsHevc_disqualifies, wouldTransmux_outputCodecIsNotHevc_stillQualifies"
        status: pass
    human_judgment: false
  - id: D4
    description: "Keep-HDR resolves achievable only when the input is HDR, its colour transfer is readable, and CodecCapabilities.supportsHdrEditing finds a hardware encoder for that ColorInfo; resolveHdrMode and the MIME gate read the same decision, so a successful keep-HDR would encode HEVC and a fallback encodes H.264 -- never HEVC-8-bit-SDR"
    requirement: CDEC-03
    verification:
      - kind: integration
        ref: "hard_inputs_test.dart: 'hdr_hlg10.mp4/hdr_pq10.mp4 with HdrMode.keepHdr' -- both resolve keepHdrAchievable:false and take the SAME OpenGL-then-MediaCodec chain 04-02 proved exhausts on this hardware (KEEP_HDR_BRANCH=exhausted)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The keep-HDR SUCCESS branch (genuine HEVC 10-bit HDR output, toneMapped:false, hevcFallback:false, isHdr:true on re-probe) is implemented and wired into both new test cases, but has never executed on any hardware available to this session"
    requirement: CDEC-03
    verification: []
    human_judgment: true
    rationale: "Both the Android emulator and every device this session had access to report zero hardware HEVC encoders (04-RESEARCH.md, re-confirmed live this plan). The success branch's code path is real and reviewed but genuinely unproven -- 04-04's macOS Apple Silicon CI leg or a physical Android phone from doc/HARDWARE_CHECKLIST.md is expected to exercise it for the first time."
  - id: D6
    description: "A shared _expectCodecFallbackInvariant Dart helper (exactly one coherent hevcFallback/videoCodec combination; usedOriginal forces every conversion flag false) is applied to every codec/HDR case in hard_inputs_test.dart, including the pre-existing HDR tone-map cases from 04-02"
    requirement: CDEC-01
    verification:
      - kind: integration
        ref: "hard_inputs_test.dart full HDR/HEVC/keep-HDR group run, all cases passing with the invariant applied"
        status: pass
    human_judgment: false
  - id: D7
    description: "doc/PRESETS.md documents that the H.264 bitrate ladder does not apply to HEVC/keep-HDR output and that no HEVC or keep-HDR bitrate has been measured yet, naming where the real numbers will come from"
    requirement: CDEC-01
    verification:
      - kind: other
        ref: "grep -c 'hevc' doc/PRESETS.md (>=1) and manual read confirming the 'no HEVC bitrate has been measured yet' sentence"
        status: pass
    human_judgment: false

duration: ~2h30m (estimated; includes source/research reading, a live javap+Mockito capability-probe experiment before committing to CodecCapabilities.kt's design, and two full emulator integration runs plus one emulator segfault/restart)
completed: 2026-09-26
status: complete
---

# Phase 4 Plan 3: Hardware-Only HEVC Opt-In and Keep-HDR Summary

**`CodecCapabilities.kt` wraps Media3's `EncoderUtil` behind a pure/wrapper split proven testable without hardware; HEVC opt-in and keep-HDR now share one `outputIsHevc` decision across the MIME gate, `HdrMode` gate and `SizeGuard`'s transmux predicate, with both fallback paths confirmed live on an emulator that has zero HEVC encoders of any kind.**

## Performance

- **Duration:** ~2h30m (estimated)
- **Started:** 2026-09-26 (session start; not formally timestamped)
- **Completed:** 2026-09-26T13:33:00Z
- **Tasks:** 3
- **Files modified:** 11 (2 created, 9 modified)

## Accomplishments

- `CodecCapabilities.kt` (new): a Kotlin `object` with a pure half (`EncoderInfo`, `hasHardwareEncoderFor`, `isSoftwareCodecName`) unit-testable on plain JVM, and a wrapper half (`hasHardwareEncoder`, `supportsHdrEditing`) backed by `EncoderUtil.getSupportedEncoders`/`getSupportedEncodersForHdrEditing`/`isHardwareAccelerated`. Before committing to this shape, ran a live scratch experiment confirming `EncoderUtil.getSupportedEncoders` throws in this project's plain-JVM Gradle test environment (`MediaCodecList.getCodecInfos not mocked`) while `EncoderUtil.isHardwareAccelerated` against a Mockito-mocked `MediaCodecInfo` does not — the asymmetry that shaped the pure/wrapper boundary.
- `Arguments.kt`'s `validateVideoCodec`/`validateHdrMode` and `CompressOptions.validate()` now accept `hevc`/`keepHdr`, with every "reserved" / "only accepted value in this phase" doc comment rewritten to describe the real hardware-gated contract. The four Dart/Kotlin tests that used to assert these values were rejected were rewritten in the same commit (necessary — the old assertions would otherwise now be wrong).
- `TransformerEngine.compress` resolves one shared `outputIsHevc = hasHardwareHevc || keepHdrAchievable` decision, read by both `setVideoMimeType` and `resolveHdrMode`; `hevcFallback` covers both triggers (HEVC opt-in unavailable, keep-HDR unachievable), guarded by `!usedOriginal` inside `finishSuccess` exactly like `toneMapped`/`transmuxed`/`audioReencoded`.
- `SizeGuard.Options` gains `outputCodecIsHevc` (default `false`); `wouldTransmux` now additionally requires it false. `resolvePlan` resolves the identical `outputIsHevc` decision `compress()` does, so `estimate()` and the real job can never disagree about whether a request would remux.
- A new `readColorTransfer` mirrors `Probe.isHdr`'s own `MediaMetadataRetriever.METADATA_KEY_COLOR_TRANSFER` read (API 30 gate) and feeds `CodecCapabilities.supportsHdrEditing` for the keep-HDR achievability decision. `isHdrToneMapAttempt` now reads `!keepHdrAchievable` rather than the `toneMapToSdr` string, so an unachievable `keepHdr` request reuses 04-02's already-proven OpenGL-then-MediaCodec retry chain rather than needing new fallback code.
- **Confirmed live on `compress_video_api35` (zero HEVC encoders of any kind, 04-RESEARCH.md):** the new HEVC opt-in case on `portrait_hibitrate_1080p60.mp4` reports `hevcFallback: true`, `videoCodec: h264`, and an output smaller than the input. Both new keep-HDR cases (`hdr_hlg10`, `hdr_pq10`) resolve `keepHdrAchievable: false` and take the SAME tone-map retry chain 04-02 proved exhausts on this hardware (codes 5001 then 3003), passing via the exhausted-chain branch.
- `hard_inputs_test.dart` gained a shared `_expectCodecFallbackInvariant` helper (exactly one coherent `hevcFallback`/`videoCodec` combination; `usedOriginal` forces every conversion flag false), applied to every codec/HDR case in the suite including 04-02's pre-existing HDR tone-map cases.
- `doc/PRESETS.md` gained an "HEVC and HDR" section stating plainly that the H.264 bitrate ladder does not apply to HEVC/keep-HDR and that no HEVC/keep-HDR bitrate has been measured yet, naming where the real numbers will come from (04-04's macOS leg, `doc/HARDWARE_CHECKLIST.md` on a physical phone).
- `CodecCapabilitiesTest.kt` (new, 10 cases) proves `hasHardwareEncoderFor`/`isSoftwareCodecName` on plain JVM: software-only list, hardware-present list, empty list (what this emulator's own `EncoderUtil.getSupportedEncoders("video/hevc")` actually returns), all four D-05 prefixes, a vendor name that must not match, and both HDR-editing outcomes. Two new `SizeGuardTest.kt` cases prove `outputCodecIsHevc` in both directions.

## Task Commits

1. **Task 1: End-to-end "ask for HEVC, get an honest answer" — probe, gate, report, assert** — `4fc726b` (feat)
2. **Task 2: Keep-HDR where the device can, tone-mapped SDR H.264 where it cannot** — `21c4b23` (feat)
3. **Task 3: Prove the probe without hardware, and document what the two new values really do** — `f91e917` (test)

**Plan metadata:** pending (this commit)

## Files Created/Modified

- `android/src/main/kotlin/com/danjjohnson/compress_video/CodecCapabilities.kt` — new: pure/wrapper HEVC and HDR-editing capability probe
- `android/src/test/kotlin/com/danjjohnson/compress_video/CodecCapabilitiesTest.kt` — new: 10 JVM unit cases
- `android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt` — relaxed `validateVideoCodec`/`validateHdrMode`, doc rewrite
- `android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt` — `Options.outputCodecIsHevc`, extended `wouldTransmux`
- `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt` — shared `outputIsHevc` decision, `resolveKeepHdrAchievable`, `readColorTransfer`, `hasHardwareHdrEditingSupport`, `hasHardwareHevcEncoder`, extended `resolveHdrMode`/`finishSuccess`/`resolvePlan`
- `android/src/test/kotlin/com/danjjohnson/compress_video/ArgumentsTest.kt` — fixed obsolete rejection tests, added accepted/unknown-value cases
- `android/src/test/kotlin/com/danjjohnson/compress_video/SizeGuardTest.kt` — `outputCodecIsHevc` cases
- `lib/src/compress_options.dart` — relaxed `validate()`, rewrote `VideoCodec`/`HdrMode`/`codec`/`hdr` dartdoc
- `test/compress_options_test.dart` — fixed obsolete rejection tests, added accepted-value and default-codec cases
- `example/integration_test/hard_inputs_test.dart` — `_expectCodecFallbackInvariant`, HEVC opt-in case, two keep-HDR cases
- `doc/PRESETS.md` — new "HEVC and HDR" section

## Decisions Made

See `key-decisions` in frontmatter for the full list. Highlights: the empirically-verified `EncoderUtil.getSupportedEncoders`/`isHardwareAccelerated` JVM-testability asymmetry that shaped `CodecCapabilities`' pure/wrapper split; the single shared `outputIsHevc` decision feeding three call sites (video MIME, `HdrMode`, `SizeGuard.Options.outputCodecIsHevc`); reusing 04-02's exhausted-chain path for an unachievable `keepHdr` request rather than writing new fallback code.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug, self-caused by the plan's own relaxation] Four tests asserted the now-wrong "hevc/keepHdr rejected" behaviour**
- **Found during:** Task 1, immediately after relaxing `Arguments.validateVideoCodec`/`validateHdrMode` and `CompressOptions.validate()`
- **Issue:** `ArgumentsTest.validateVideoCodec_notH264_rejectedAsUnsupportedInput`/`validateHdrMode_notToneMapToSdr_rejectedAsUnsupportedInput` and two matching `compress_options_test.dart` cases asserted that `"hevc"`/`"keepHdr"` were rejected — exactly the behaviour this task's own acceptance criteria required to change
- **Fix:** Rewrote all four to test a still-genuinely-unknown value (`"vp9"`, `"dolbyVision"`) instead, and added explicit accepted-value cases for both new tokens
- **Verified:** `flutter test` (83/83) and `./gradlew :compress_video:testDebugUnitTest` both green
- **Committed in:** `4fc726b` (task 1's commit)

---

**Total deviations:** 1 auto-fixed (Rule 1, a direct and expected consequence of the task's own instructed change, not an independent bug). **Impact on plan:** None beyond the necessary fix — no scope creep.

## Issues Encountered

- The local Android emulator (`compress_video_api35`) segfaulted once mid-verification (`Segmentation fault (core dumped)`, `ptrace: No such process` traces) while running the full `example/integration_test` suite after task 3's changes, consistent with this project's documented danserver memory-pressure pattern (`.claude/CLAUDE.md` lane notes; also seen once during 04-02). Restarted with the documented `sg kvm -c` recipe; the full 95-test suite re-ran cleanly afterward. Not treated as a code issue.

## User Setup Required

None — no external service configuration required.

## What 04-04 Needs to Know

- **The shared `outputIsHevc` decision is the pattern to mirror on Apple.** `CodecCapabilities.swift`'s own hardware-HEVC and HDR-editing wrappers should feed one shared decision into both the video-codec choice and the HDR writer-settings choice, exactly like `TransformerEngine.kt`'s `outputIsHevc = hasHardwareHevc || keepHdrAchievable` — the CDEC-03 failure mode (HEVC-8-bit-SDR on an incapable device) is possible on Apple too if the two gates are computed independently.
- **The keep-HDR and HEVC-opt-in SUCCESS branches have not executed anywhere yet.** Both `hard_inputs_test.dart` cases this plan added are written so the SAME test asserts the success path once a capable device runs it — 04-04's macOS Apple Silicon CI leg (04-RESEARCH.md: real hardware HEVC encoder) is the first opportunity. Do not assume the emulator's fallback-only behavior generalizes; branch on what the result reports, not on the platform's name.
- **`SizeGuard.swift` does not have `outputCodecIsHevc` yet** (04-02-SUMMARY.md already flagged the same gap for `audioChannelCount`) — 04-04's own `SizeGuard.swift` port catch-up needs both fields.
- **`Arguments.swift` still rejects `hevc`/`keepHdr`.** 04-04 needs the identical two-line relaxation `Arguments.kt` got this plan, plus the same doc rewrite.

## Next Phase Readiness

- Ready for 04-04 (Apple parity): the Android-side capability-probe shape, shared-decision pattern, and both Dart test cases (Android-only `skip` guards ready to remove) are exactly what 04-04 mirrors.
- CDEC-01 and CDEC-03 are NOT marked complete in `REQUIREMENTS.md` — both are also declared by 04-04-PLAN.md and 04-05-PLAN.md (shared-ID gate, #2388; confirmed 0/2 ready via `requirements.ready-ids`). They stay `Pending` until the last declaring plan (04-05) finishes.
- No blockers carried forward beyond the documented hardware-only gap above (the keep-HDR/HEVC success branches, tracked in `doc/HARDWARE_CHECKLIST.md` and this summary).

## Self-Check: PASSED

- `android/src/main/kotlin/com/danjjohnson/compress_video/CodecCapabilities.kt` and `android/src/test/kotlin/com/danjjohnson/compress_video/CodecCapabilitiesTest.kt` verified present on disk.
- All 3 commits (`4fc726b`, `21c4b23`, `f91e917`) verified present in `git log`.
- `flutter analyze --fatal-infos --fatal-warnings`, `flutter test` (83/83), `dart format` (stable SDK, no changes), `dart pub publish --dry-run` (exit 0 on a clean tree), `corpus/verify_corpus.sh`, Android native unit tests (including 10 new `CodecCapabilitiesTest.kt` cases and 2 new `SizeGuardTest.kt` cases), and the full `example/integration_test` suite (95/95, re-run after an emulator restart) all green as of the final commit.
- `git diff --exit-code pigeons/messages.dart lib/src/messages.g.dart` confirmed clean — no Pigeon contract change.
- Every `<acceptance_criteria>` re-run and passing, except the keep-HDR/HEVC-opt-in SUCCESS branches (D5), which are real, reviewed code with zero live executions on any hardware available to this session — an honest, carried-forward gap tied to the emulator's confirmed hardware limitation, not silently skipped.

---
*Phase: 04-codecs-hdr-and-hard-inputs*
*Completed: 2026-09-26*
