# Architecture Research — compress_video

**Researched:** 2026-09-14. Derived from the incumbent's source (what not to do), `light_compressor_v2` and `flutter_compress` (what works), and Media3/AVFoundation docs.

## Components

```
 Dart (lib/)
 ├─ compress_video.dart          public API: CompressVideo.compress(), .info(), .thumbnail(), .estimate(), .clearCache()
 ├─ src/options.dart             CompressOptions (preset | maxLongSide | videoBitrate | targetSizeMB, maxFps, codec, hdr, audio, trim, output)
 ├─ src/result.dart              CompressResult / CompressError (sealed), MediaInfo, ThumbnailResult, Estimate
 ├─ src/job.dart                 CompressJob {id, progress: Stream<double>, done: Future<CompressResult>, cancel()}
 ├─ src/queue.dart               JobQueue: sequential by default, optional maxConcurrent
 ├─ src/compat/video_compress.dart   the video_compress-shaped shim (VideoQuality enum → options)
 └─ src/messages.g.dart          Pigeon-generated host API + FlutterApi for progress events
 pigeons/messages.dart           single source of truth for the channel contract (all quantities in ms / bytes / bps / px)

 Android (android/src/main/kotlin/.../)
 ├─ CompressVideoPlugin.kt       Pigeon host impl; wires context, job registry, progress callbacks
 ├─ JobRegistry.kt               id → Transformer; cancel; one Transformer per job on a HandlerThread
 ├─ TransformerEngine.kt         builds EditedMediaItem/Composition from options: Presentation, Clipping, HdrMode, encoder settings, audio strategy
 ├─ Probe.kt                     MediaExtractor/MediaMetadataRetriever → MediaInfo; encoder capability (HEVC hw? level for 4K60?)
 ├─ SizeGuard.kt                 never-larger check + transmux decision (input bitrate/codec/size vs target)
 ├─ Thumbnails.kt                MediaMetadataRetriever + rotation
 └─ MediaProcessingService.kt    optional mediaProcessing FGS (opt-in)

 Apple (ios/Classes + macos/Classes → shared Sources/)
 ├─ CompressVideoPlugin.swift    Pigeon host impl (FlutterPlugin / FlutterMacOS)
 ├─ JobRegistry.swift            id → WriterSession; cancel
 ├─ WriterEngine.swift           AVAssetReader → (optional CI tone-map / scale) → AVAssetWriter; bitrate, codec, transform, audio passthrough w/ sourceFormatHint; progress from sample PTS
 ├─ PassthroughEngine.swift      AVAssetExportSession(AVAssetExportPresetPassthrough) with timeRange for remux/trim-only
 ├─ Probe.swift                  AVAsset load(.tracks/.duration/.preferredTransform), HDR detection, HEVC capability
 ├─ SizeGuard.swift              same contract as Android
 └─ Thumbnails.swift             AVAssetImageGenerator with appliesPreferredTrackTransform
```

## Data flow

1. Dart builds `CompressOptions`, `JobQueue` assigns an id, calls Pigeon `startCompress(id, request)`.
2. Native `Probe` reads input (codec, bitrate, dims, rotation, fps, HDR, audio layout).
3. `SizeGuard` decides: **transmux** (input already within target → remux/trim only), **encode** (compute target dims/bitrate from preset/targets), or **reject** (unsupported).
4. Engine runs; progress events flow native → Dart via Pigeon `FlutterApi.onProgress(id, pct)` on the platform thread; Dart exposes them as the job's stream.
5. On completion native re-probes the output, applies the never-larger rule (if `outBytes ≥ inBytes`: copy original to output path, `usedOriginal: true`), returns a typed `CompressResult`. On failure returns a typed `CompressError` (never throws across the channel unhandled; never `null`). On cancel deletes the partial file and returns `CompressError.cancelled`.
6. Dart completes the job's future; queue starts the next job.

## Threading and lifecycle

- One engine instance per job; Media3 Transformer must be used from a single thread → a dedicated `HandlerThread` per job (or a small pool). AVAssetWriter runs on its own serial queue.
- Progress callbacks marshalled to the main thread before crossing to Dart.
- Plugin holds a `JobRegistry`; `onDetachedFromEngine` cancels everything and deletes partials.
- Background isolate support: the Dart API accepts an optional `BinaryMessenger` (`BackgroundIsolateBinaryMessenger`) and never touches a global singleton.

## Suggested build order (dependencies)

1. **Contract + skeleton**: Pigeon messages, Dart API surface with stub results, three platform stubs that build, example app, CI. Everything compiles; nothing compresses.
2. **Probe + info + thumbnails** on both platforms (small, exercises the channel end to end, and the compressor needs Probe anyway).
3. **Android encode path** (Transformer): presets/targets → dims/bitrate, trim, fps cap, audio passthrough/strip, orientation, progress, cancel, never-larger, transmux.
4. **Apple encode path** (Writer + Passthrough) to parity, then macOS target.
5. **Codecs + HDR**: capability probing, HEVC fallback, tone-map / keep-HDR, 5.1/PCM audio.
6. **Jobs**: queue/concurrency, isolate messenger, Android FGS, iOS interruption error.
7. **Release**: docs, preset tables, migration guide + compat shim, pub.dev.

## Key contracts to fix early (they are the incumbent's bug classes)

- All times in **milliseconds**, all sizes in **bytes**, bitrates in **bits/second**, dimensions in **pixels of the displayed orientation**. Encoded in Pigeon field names (`positionMs`, `sizeBytes`, `videoBitrateBps`).
- Presets are defined as (maxLongSide, targetBitrateBps at 30 fps, fps cap) and produce the same numbers on every platform; the README table is generated from the same constants.
- `CompressResult` always includes: `outputPath, inputBytes, outputBytes, width, height, durationMs, videoCodec, audioCodec, transmuxed, toneMapped, usedOriginal, hevcFallback, elapsedMs`.
