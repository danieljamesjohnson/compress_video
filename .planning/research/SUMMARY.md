# Project Research Summary

**Project:** compress_video
**Domain:** Flutter plugin, on-device video transcoding (Android Media3 / Apple AVFoundation)
**Researched:** 2026-09-11 → 2026-09-14 (scan + brief), distilled 2026-09-15
**Confidence:** HIGH

## Executive Summary

This is a native-plugin product with one verb: turn a phone video into a smaller MP4 that plays
everywhere. The incumbent (`video_compress`, 170k downloads/30d) is abandoned with 176 open
issues; reading all of them shows that demand is overwhelmingly about *breakage* (toolchain rot,
silent `null`, crashes on ordinary inputs) plus one missing knob (output size). Experts build
this today on Media3 Transformer (Android) and AVAssetReader/AVAssetWriter (Apple), with typed
platform channels, a per-job model, and a real-clip test corpus. The two native challengers are
one-person projects that each shipped a visible correctness gap; the FFmpeg route is out by size
and licence.

Recommended approach: rebuild from scratch (do not fork), fix the contract first (Pigeon typed
messages, one unit per quantity, typed results and errors, never-larger, never-null), then build
the Android engine, then Apple to parity, then the differentiators (HDR tone-mapping, HEVC
fallback, jobs/background), then a release that is explicitly a drop-in migration from the
incumbent. Key risks: toolchain drift (mitigated by CI on current stable and a recurring chore),
HDR/rotation correctness (mitigated by a committed corpus of real iPhone/Pixel clips and device
tests), and Apple verification depending on a Mac reachable from danserver (currently blocked;
see `QUESTIONS.md`).

## Key Findings

### Recommended Stack

Media3 Transformer 1.11 on Android (pure JVM, ~4 MB, no 16 KB exposure; bitrate, resize, trim,
transmux, rotation, HDR tone-map, progress, cancel built in). AVAssetReader/AVAssetWriter on iOS
13+/macOS 11+ for encode with real bitrate/HEVC/HDR control, `AVAssetExportSession` passthrough
for remux. Pigeon for the channel contract. CocoaPods and SPM. GitHub Actions on Linux + macOS
runners. Details: `STACK.md`.

**Core technologies:**
- androidx.media3 transformer/effect/muxer: the transcoder — Google-maintained replacement for the dead Transcoder library
- AVFoundation reader/writer: encoder control Apple's export presets do not expose
- Pigeon: typed channels — kills the incumbent's unit-mismatch and swallowed-error bug classes

### Expected Features

**Must have (table stakes):** one-call compress on three platforms; builds on today's toolchain
(CocoaPods + SPM); typed results, never `null`; never larger than input; output-size control
(preset / max side / bitrate / target MB) with documented presets; working progress and cancel;
media info and rotation-correct thumbnails; upright portrait output; exact trim; audio kept by
default, strippable.

**Should have (competitive):** transmux fast path; HDR tone-map default with keep-HDR opt-in;
HEVC opt-in with hardware-only encode and reported fallback; per-job queue with concurrency
limit; background-isolate support; Android `mediaProcessing` foreground service; pre-flight
estimate; `video_compress`-compatible shim and migration table.

**Defer (v2+):** web (WebCodecs), Windows/Linux, GIF→MP4, pause/resume, AV1. Details: `FEATURES.md`.

### Architecture Approach

Thin Dart API over a Pigeon contract; a per-job registry on each platform; a `Probe` →
`SizeGuard` (transmux / encode / reject) → engine pipeline; results re-probed and the
never-larger rule applied before returning. One engine instance per job on its own thread.
Details: `ARCHITECTURE.md`.

**Major components:**
1. Dart API + JobQueue + compat shim — options, typed results, per-job streams
2. Android TransformerEngine + Probe + SizeGuard + Thumbnails + optional FGS
3. Apple WriterEngine + PassthroughEngine + Probe + SizeGuard + Thumbnails (shared Swift core for iOS/macOS)

### Critical Pitfalls

1. **Toolchain rot** — CI on current stable Flutter/AGP/Xcode, SPM + CocoaPods, recurring chore.
2. **Swallowed errors / `null`** — typed errors through Pigeon; every failure path tested.
3. **Output bigger than input, blocky "Highest"** — presets as (maxLongSide, bitrate) pairs; byte check with `usedOriginal`.
4. **Rotation and HDR** — engine-correct defaults (Media3 landscape+metadata, Apple `transform`; tone-map modes) verified on a committed corpus of real portrait, Dolby Vision and HLG clips, on devices not just simulators.
5. **Global singleton job state** — per-job registry and streams from day one.
Full list of 24: `PITFALLS.md`.

## Implications for Roadmap

Based on research, suggested phase structure (granularity: standard):

### Phase 1: Contract and skeleton
**Rationale:** The incumbent's bug classes are contract bugs; fixing the contract first makes every later phase testable. Also establishes the toolchains (Android SDK + emulator on danserver, Mac over SSH, CI) that everything depends on.
**Delivers:** Pigeon messages with units in field names; Dart API with typed options/results/errors and per-job streams; three platform stubs that build; example app; CI green on Linux + macOS; corpus directory with the first clips.
**Addresses:** BULD-01..05 groundwork, JOBS-01 shape, CORE-03/04 types
**Avoids:** pitfalls 1, 2, 3, 7, 14, 15

### Phase 2: Probe, media info and thumbnails
**Rationale:** Small end-to-end slice through the channel on both platforms; the compressor needs Probe anyway; thumbnails are 29 open issues on the incumbent.
**Delivers:** INFO-01/02/03 on Android, iOS, macOS, rotation-correct, one unit.
**Avoids:** 7, 21, 24

### Phase 3: Android compression on Media3
**Rationale:** Android is where the incumbent's pain is worst and where danserver can verify autonomously (emulator) while the Mac path is being unblocked.
**Delivers:** CORE-01..09, ORNT-01, AUDO-01/02, JOBS-02 on Android; integration tests on emulator against the corpus.
**Uses:** Transformer, `VideoEncoderSettings`, `Presentation`, `ClippingConfiguration`
**Avoids:** 5, 6, 8, 9, 13, 19

### Phase 4: Apple compression to parity (iOS + macOS)
**Rationale:** Same contract, second engine; needs the Mac.
**Delivers:** CORE-01..09, ORNT-01, AUDO-01/02, JOBS-02 on iOS and macOS; XCTest on simulator; SPM + CocoaPods verified.
**Uses:** AVAssetReader/Writer, passthrough export session
**Avoids:** 4, 8, 9, 11, 24

### Phase 5: Codecs, HDR and hard inputs
**Rationale:** The differentiators, and the cases every competitor got wrong; needs both engines and the corpus.
**Delivers:** CDEC-01/02/03, AUDO-03, 4K60 handling; corpus expanded (Dolby Vision, HLG, 5.1, PCM, 4K60); hardware checklist.
**Avoids:** 10, 12, 20

### Phase 6: Jobs, isolates and background
**Rationale:** Sits on the per-job model; independent of codec work.
**Delivers:** JOBS-03/04/05: queue + concurrency, background isolate, Android `mediaProcessing` FGS, iOS interruption semantics.
**Avoids:** 15, 16, 17, 18, 19

### Phase 7: Release and migration
**Rationale:** The adoption lever is "drop-in"; docs and the shim map the finished API.
**Delivers:** RELS-01/02/03: README preset tables, MIGRATION.md, compat shim, pub.dev publish at 160/160, TEST-01 release checklist run.
**Avoids:** 22, 23

### Phase Ordering Rationale

- Contract before engines: every incumbent bug class lives in the contract.
- Android before Apple: autonomous verification exists on danserver today; the Mac path is a pending Dan action (QUESTIONS.md #1). If the Mac is unblocked early, Phase 4 can run in parallel with Phase 3 because they share only the Pigeon contract.
- Differentiators (HDR/HEVC) after parity: they need both engines and a mature corpus.
- Release last, but README/preset constants are written from Phase 3 onward so docs are generated, not authored late.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1:** current AGP/Kotlin/Pigeon/SPM template versions; Android SDK + emulator install on a headless Linux box with an AMD GPU (KVM acceleration); GitHub Actions emulator runners.
- **Phase 4:** AVAssetWriter HDR/8-bit reader output settings, `sourceFormatHint` details, progress derivation; macOS-specific differences.
- **Phase 5:** Media3 `HdrMode` behaviour per API level and device; Apple keep-HDR settings; HEVC capability probing on both platforms.
- **Phase 6:** `mediaProcessing` FGS lifecycle on Android 15/16; iOS background-task limits.

Phases with standard patterns (skip research-phase):
- **Phase 2:** MediaMetadataRetriever / AVAssetImageGenerator are well documented.
- **Phase 7:** pub.dev publishing and scoring are well documented.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Official docs and source read 2026-09-14; versions must be re-checked at Phase 1 |
| Features | HIGH | 233 issues + 32 PRs read in full; dependents and SO surveyed |
| Architecture | HIGH | Derived from two working competitors and the engines' documented constraints |
| Pitfalls | HIGH | Each one was shipped by someone; sources cited |

**Overall confidence:** HIGH

### Gaps to Address

- Apple verification path: MacBook SSH key not yet authorized (QUESTIONS.md #1). Plan Phase 4 to start with a Mac-readiness check.
- Android emulator on danserver: not yet installed; HDR/HEVC hardware paths need a physical phone (QUESTIONS.md #3).
- pub.dev publisher: none yet (QUESTIONS.md #2). Needed by Phase 7.
- Exact preset table (maxLongSide × bitrate pairs): choose in Phase 3 from measured output sizes on the corpus, not from the incumbent's numbers.

## Sources

### Primary (HIGH confidence)
- `sources/VIDEO_COMPRESS_BRIEF.md` — the research brief (2026-09-14) with links to every claim
- `sources/issues-and-prs.md` — issue clusters and all 32 open PRs of jonataslaw/VideoCompress
- `sources/who-uses-it.md` — dependents, SDKs, StackOverflow, FluffyChat migration
- `sources/competitors-and-native-apis.md` — competitor source reads; Media3 and AVFoundation docs with URLs
- Android: developer.android.com Media3 Transformer pages, media3 release notes, page-sizes guide, FGS service types
- Apple: AVAssetExportSession / export presets / AVAssetWriter / AVAssetReader / AVAssetWriterInput docs, WWDC20 10010, forum thread 672056

### Secondary (MEDIUM confidence)
- `light_compressor_v2`, `v_video_compressor`, `flutter_compress` source (cloned 2026-09-14) — what works and what doesn't in practice
- StackOverflow threads and the FlutterFlow community thread — user intent and numbers

### Tertiary (LOW confidence)
- Third-party iPhone MB/minute figures (MacRumors, hevcut) — approximate

---
*Research completed: 2026-09-15*
*Ready for roadmap: yes*
