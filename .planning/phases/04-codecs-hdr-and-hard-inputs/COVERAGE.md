# Phase 4 — API Coverage Declaration

**No external API integration:** this phase integrates on-device platform media frameworks
(Media3 Transformer, AVFoundation, VideoToolbox) behind the existing Pigeon contract. No
third-party service, network endpoint, hosted SDK, or registry package is consumed, and no new
pub.dev / CocoaPods / SPM / Gradle dependency is added (04-RESEARCH.md → "Package Legitimacy
Audit": not applicable, every class used already ships inside the pins Phases 1–3 established).

The surface that *is* worth an explicit matrix here is the **codec-capability surface** the phase
newly depends on: four platform capability questions whose answers change what the plugin emits.
Each is declared INTEGRATE (wired and asserted this phase) or OPT-OUT (deliberately not wired,
with the reason).

## Codec / HDR capability matrix

| # | Capability question | Android mechanism | Apple mechanism | Disposition | Note |
|---|---------------------|-------------------|-----------------|-------------|------|
| 1 | Does this device have a **hardware HEVC encoder**? | `EncoderUtil.getSupportedEncoders(MimeTypes.VIDEO_H265)` + `EncoderUtil.isHardwareAccelerated(..)` | `VTCopySupportedPropertyDictionaryForEncoder` with `kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder` | **INTEGRATE** | Gates the H.264-vs-H.265 MIME/codec choice (CDEC-01). Emulator and iOS simulator answer "no" (verified); the Apple Silicon macOS CI host answers "yes". |
| 2 | Can this device **keep HDR** for this transfer function? | `EncoderUtil.getSupportedEncodersForHdrEditing(VIDEO_H265, ColorInfo)` | the same hardware-HEVC probe plus `AVAssetWriter.canApply(outputSettings:forMediaType:)` on the Main10 + BT.2020 dictionary | **INTEGRATE** | Gates `HdrMode.keepHdr` (CDEC-03); a "no" falls back to tone-mapped SDR **H.264** and reports it. |
| 3 | Will **OpenGL tone-mapping** succeed on this device? | no synchronous query exists — sequential attempt `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL` → `..._USING_MEDIACODEC` → typed error | not applicable: the 8-bit BGRA reader path makes the system tone-map (Phase 3 D-08) | **INTEGRATE** (as a retry chain, not a probe) | 04-RESEARCH.md Pitfall 3: a plan that says "check support, then encode once" is describing an API that does not exist for this decision. |
| 4 | Does this device support **AV1 / VP9 output**? | `EncoderUtil` could answer it | VideoToolbox could answer it | **OPT-OUT** | AV1 is v2 (`FEAT-04` in REQUIREMENTS.md); no v1 requirement asks for it and `VideoCodec` has no such value. |
| 5 | Does this device support **Dolby Vision RPU passthrough**? | — | — | **OPT-OUT** | ffmpeg cannot author a DV profile-8 RPU, so no fixture exists; the DV case is real-clip-only (QUESTIONS.md #4) and lives in `doc/HARDWARE_CHECKLIST.md` until Dan supplies the clip. |
| 6 | Does this device expose a **software HEVC encoder** as a middle case? | `EncoderUtil.getSupportedEncoders` returns an empty list on this AVD (verified live) | simulator has no video encoder at all (cited) | **OPT-OUT** | 04-RESEARCH.md Pitfall 6: there is no software HEVC encoder on either CI environment to exercise, and CDEC-01 asks for hardware-only HEVC anyway. |

**Callers never see capabilities directly.** The plugin exposes no capability-query API in this
phase; the observable contract stays the three existing `CompressResult` fields (`toneMapped`,
`hevcFallback`, `audioReencoded`) plus `videoCodec`. Adding a public probe API would be a Pigeon
contract change, which 04-CONTEXT.md explicitly says is not needed ("No new result field").
