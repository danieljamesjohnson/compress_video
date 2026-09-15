# compress_video

## What This Is

A Flutter plugin that takes a video the user just recorded or picked, makes it much smaller,
and hands back the new file, on Android, iOS and macOS. It also reads media info and makes
poster-frame thumbnails. It is the drop-in successor to `video_compress` (170k downloads/30d,
abandoned since 2025-02 with 176 open issues), built on Google's and Apple's current media
APIs (Media3 Transformer, AVAssetReader/AVAssetWriter) instead of a dead third-party
transcoder and preset-only export sessions. Audience: Flutter apps where a phone video leaves
the phone (chat clients, short-video feeds, KYC selfie videos, inspection and incident
reporting, marketplace listings) and the SDKs they embed.

## Core Value

One call turns a phone video into a smaller MP4 that plays everywhere, and it **never makes the
file bigger, never returns null, and builds on today's Flutter toolchain**.

## Business Context

- **Customer**: Flutter developers shipping upload flows; the 1,200+ repos and 40 pub.dev
  packages currently depending on `video_compress`.
- **Revenue model**: none. Open source (MIT). Portfolio project: product thinking plus native
  engineering, publicly measurable.
- **Success metric**: pub.dev downloads/30d (target 5–15k within six months of publishing,
  where today's challengers sit after 15–19 months), 160/160 pub points, named migrations from
  `video_compress`.
- **Strategy notes**: `~/CodeProjects/pubdev-stale-scan/VIDEO_COMPRESS_BRIEF.md` (the research
  brief; copied into `.planning/research/sources/`), Obsidian `Projects/Pubdev Stale Scan`.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] One-call compression to H.264/AAC MP4 on Android, iOS and macOS, with presets *and*
      explicit targets (max long side, bitrate, target file size)
- [ ] Typed result (sizes, dimensions, codec used, transmuxed?, tone-mapped?) and typed
      errors; never `null`, never a host-process crash
- [ ] Output never larger than input (fall back to the original and say so)
- [ ] Passthrough/transmux fast path when the input already meets the target
- [ ] Trim by start/end milliseconds, honoured exactly on every platform
- [ ] Portrait and rotated input comes out upright with correct dimensions, no black bars
- [ ] H.264 default, HEVC opt-in with hardware-only encode and automatic fallback
- [ ] HDR input (Dolby Vision, HLG, HDR10) tone-mapped to SDR by default; keep-HDR opt-in
- [ ] Audio passthrough by default; AAC re-encode or strip on request; 5.1 sources don't crash
- [ ] Per-job progress stream and cancel; queued jobs; works from a background isolate
- [ ] Android foreground-service option; honest iOS interruption semantics
- [ ] Media info, thumbnails (one time unit everywhere, rotation-correct), pre-flight estimate
- [ ] Media3 Transformer on Android (minSdk 23), AVAssetReader/Writer on Apple (iOS 13+,
      macOS 11+), CocoaPods and Swift Package Manager, 16 KB-page safe, AGP-9 ready
- [ ] Real-clip test corpus (Dolby Vision iPhone, HLG Pixel, portrait, 4K60, PCM, no audio,
      5.1) run in CI on emulator/simulator, with documented hardware checks
- [ ] Published on pub.dev as `compress_video` with 160/160 points, README preset tables,
      migration guide and a compatibility layer mirroring `video_compress`'s verbs

### Out of Scope

- **FFmpeg** as a dependency — 100 MB binaries, GPL, slow software encode; the incumbent's
  "100% native" promise is the reason people chose it
- **Web** (WebCodecs) — one issue with 12 reactions in the incumbent's tracker; Safari support
  only complete from 26; a v2 milestone once the native core is stable
- **Windows / Linux** — no native equivalent without FFmpeg; 5 reactions total
- **Filters, watermarks, stitching, editing** — a different product; one request in six years
- **Upload / networking** — the app's job; we only produce the file
- **AV1** — encoder availability too thin on mobile in 2026

## Context

- Research done 2026-09-11 → 2026-09-14 in `~/CodeProjects/pubdev-stale-scan`: full source read
  of jonataslaw/VideoCompress and the Transcoder library, top-40 issues with comments and all
  32 open PRs read, dependents survey, StackOverflow, competitor source reads
  (`light_compressor_v2`, `v_video_compressor`, `ffmpeg_kit_flutter_new`, `flutter_compress`),
  Media3 Transformer and AVFoundation docs. Distilled into `.planning/research/`.
- What users actually ask for (from 233 issues): builds that don't rot, no silent `null`,
  **one knob for output size**, control of the output path, run off the main isolate. Nobody
  asks for codecs or filters. Breakage dominates demand.
- Every competitor has shipped one of: sideways/letterboxed portrait video, washed-out HDR,
  a crash on `.mov` with audio, a bitrate option that never reaches the encoder. These are the
  test corpus.
- FluffyChat (largest Flutter Matrix client) migrated off `video_compress` on 2026-08-17;
  Twake guards against the incumbent making files bigger in its own send path. The audience is
  large, active and already looking.
- Environment: danserver (Linux) hosts the agents; Android SDK and emulator must be installed
  here; Apple builds require Dan's MacBook Air over SSH (`dans-macbook-air` on the tailnet),
  which currently refuses our key — see `QUESTIONS.md`.
- No pub.dev verified publisher exists yet; publishing needs one (or Dan's Google account).

## Constraints

- **Tech stack**: Dart/Flutter plugin; Kotlin + Media3 Transformer on Android; Swift +
  AVFoundation on iOS/macOS; typed platform channels via Pigeon — because the incumbent's
  worst bugs were untyped-channel unit mismatches and swallowed errors
- **Dependencies**: no native `.so` code and no FFmpeg — 16 KB page-size compliance for free,
  small binary, permissive licence
- **Compatibility**: minSdk 23 (Media3 ≥ 1.9), iOS 13+, macOS 11+; Flutter stable; both
  CocoaPods and SPM — because SPM is the incumbent's newest 21-reaction complaint
- **Toolchain**: must build on the *current* Flutter/AGP/Kotlin/Xcode every quarter; a CI matrix
  is a requirement, not a nicety — toolchain rot is the incumbent's largest complaint cluster
- **Verification**: Android on the danserver emulator plus a physical phone for hardware
  encoder/HDR checks; Apple on the MacBook Air (simulator + device); real clips, not synthetic
- **Timeline**: v1 on pub.dev within ~8 weeks of starting; six-month adoption targets above

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Rebuild from scratch, do not fork `jonataslaw/VideoCompress` | The Transcoder dependency (H.264-only, no HDR, quiet since 2024-11) is the thing to leave behind; forking inherits its shape | — Pending |
| Package name `compress_video` | Free on pub.dev (checked 2026-09-15), plain, matches what people search | — Pending |
| Android engine: Media3 Transformer | Google's maintained transcoder: bitrate, resize, trim, transmux, rotation, HDR tone-map, progress, cancel; pure JVM, ~4 MB, no 16 KB exposure | — Pending |
| Apple engine: AVAssetReader/AVAssetWriter, export session only for passthrough | Export-session presets cannot set a bitrate and their `progress` is deprecated in iOS 27; the writer path gives bitrate, HEVC, HDR, transform | — Pending |
| Pigeon for platform channels | Typed messages kill the "position is ms in Dart, µs on Android, s on iOS" class of bug | — Pending |
| Default output: tone-mapped SDR H.264 + passthrough AAC; HEVC and keep-HDR opt-in | Maximum recipient compatibility; nobody asked for HEVC, everybody asked for smaller files | — Pending |
| Ship a `video_compress`-shaped compatibility layer and migration table | Adoption story is "drop-in"; 1,200+ repos have the old verbs in their code | — Pending |
| v1 platforms: Android + iOS + macOS; web/desktop later | Matches the incumbent's surface; macOS is nearly free once the AVFoundation code exists | — Pending |
| Apple builds via SSH to `dans-macbook-air` | danserver is Linux; autonomous verification needs Xcode | — Pending (key not yet authorized) |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-09-15 after initialization*
