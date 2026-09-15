# Features Research — compress_video

**Researched:** 2026-09-14 (233 issues and 32 PRs of the incumbent read; competitor APIs read; StackOverflow; dependents survey). Full detail in `sources/issues-and-prs.md` and `sources/who-uses-it.md`.

## Table stakes (users leave without these)

| Feature | Evidence | Complexity | Depends on |
|---|---|---|---|
| One-call compress to MP4 H.264/AAC on Android + iOS (+ macOS) | The entire install base (170k dl/30d); README promise "MP4 + AAC, plays everywhere" | Med | engines |
| Builds on the current Flutter/AGP/Kotlin/Xcode, installs via CocoaPods **and** SPM | Largest complaint clusters: toolchain rot 64 reactions, SPM 21, JCenter artifact 24 | Low–Med, recurring | CI |
| Never returns `null`; errors are typed and explained | "returns null" #193 (18 comments, 2022→2025), iOS nil crashes 19 reactions; the incumbent swallows every error on both platforms | Low | Pigeon |
| Never makes the file bigger | #200 (7 reactions, "52 MB → 82 MB"), SO 67594673 ("36 MB → 60 MB"), Twake guards against it in app code | Low | size check |
| One knob for output size (bitrate / target MB / max long side), plus presets that are documented | #77 (7), #294 (6), #216, #210, #324; SO "20 MB → 2 MB maximum" | Med | engines |
| Progress + cancel that work | 28 issues mention progress; cancel 12 | Med | per-job design |
| Media info + thumbnail | `getMediaInfo` is why OpenIM imports the package at all; 29 thumbnail issues (27 open) | Low | rotation handling |
| Portrait video comes out upright with correct dimensions | 9 rotation issues; FluffyChat carried a workaround for a year | Med | engine defaults |
| Trim by start/end that actually works | 28 issues; both platforms broken in the incumbent (`trimEndUs` semantic on Android, audio-gated on iOS) | Low | engines |
| Audio kept by default, can be stripped | `includeAudio:false` is the incumbent's crash workaround, "a video without audio loses its purpose" | Low | passthrough |

## Differentiators (competitive advantage)

| Feature | Evidence | Complexity | Notes |
|---|---|---|---|
| Passthrough/transmux fast path when input already fits | SO 79757413 "Telegram-level… passthrough/remux if already H.264/AAC ≤ 720p"; Media3 does it automatically | Low on Android, Med on Apple | Report `transmuxed: true` |
| HDR handled correctly (tone-map by default, keep-HDR opt-in) | #298 washed-out; `light_compressor_v2` mislabels, `v_video_compressor` ignores, Transcoder can't; iPhones shoot Dolby Vision by default | High | The clearest technical edge over every competitor |
| HEVC opt-in with hardware-only encode and reported fallback | `light_compressor_v2` and `flutter_compress` do this; ~40–50% smaller files | Med | Nobody asks for HEVC by name; everybody asks for smaller |
| Typed result that says what happened (codec, transmuxed, tone-mapped, passes) | `light_compressor_v2`'s best idea | Low | Makes support questions answerable |
| Per-job progress/cancel, queue, concurrency limit | #317, #307, #227 | Med | Fixes the global-stream design |
| Works from a background isolate | #242 (7), #248 (4) | Low | inject `BinaryMessenger` |
| Android foreground service option | `light_compressor_v2` has one (`dataSync` type); Media3 needs `mediaProcessing` | Med | Opt-in |
| Pre-flight size estimate | `light_compressor_v2`, `v_video_compressor` | Low | Cheap and loved |
| Documented preset table per platform | The incumbent never documented what "Medium" means; #60 Default==Medium on iOS | Low | README |
| `video_compress`-compatible shim + migration table | 1,224 pubspecs and 1,048 call sites of `VideoCompress.compressVideo` | Low | The adoption lever |
| Output path control | #24, #186, #149, #229, #274 (colliding thumbnails) | Low | |

## Anti-features (deliberately not building)

| Anti-feature | Why not |
|---|---|
| FFmpeg-style option surface (`crf`, x264 presets, `bFrames`) | `v_video_compressor` exposes them and neither native engine can honour them; overstated APIs create bug reports |
| Web in v1 | 12 reactions; needs WebCodecs + muxer; Safari complete only from 26; do after the native core is solid |
| Windows/Linux | 5 reactions; no native path without FFmpeg (`xue_hua_media_compression` drops audio to get there) |
| Watermark / stitch / filters | One issue (#30, 6 reactions) in six years |
| Global singleton state | Source of the concurrency bugs |
| A "Highest" preset that keeps 4K at 3.7 Mbps | The incumbent's `HighestQuality` does this; presets must be explained in resolution + bitrate terms |
| Silent fallbacks | If HEVC/HDR/passthrough falls back, the result must say so |

## Feature dependencies

- Typed results/errors (Pigeon) come first; everything else reports through them.
- Never-larger and transmux both need media info (bitrate, codec, dimensions) of the *input*, so info precedes compression internally.
- HDR/HEVC depend on device capability probing (`MediaCodecList` / `AVAssetExportSession.allExportPresets` or `VTIsHardwareDecodeSupported`), which also feeds the estimate.
- Foreground service and isolate support sit on top of the per-job design.
- The compat shim is last: it maps old verbs onto the finished API.
