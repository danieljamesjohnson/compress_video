# compress_video

A Flutter plugin that takes a video the user just recorded or picked, makes it much smaller, and
hands back the new file, on Android, iOS and macOS. It also reads media info and makes
poster-frame thumbnails. It is the drop-in successor to
[`video_compress`](https://pub.dev/packages/video_compress) (abandoned since 2025-02), built on
Google's and Apple's current media APIs — Media3 Transformer on Android,
AVAssetReader/AVAssetWriter on iOS and macOS — instead of a dead third-party transcoder and
preset-only export sessions.

## Core value

One call turns a phone video into a smaller MP4 that plays everywhere, and it **never makes the
file bigger, never returns null, and builds on today's Flutter toolchain**.

## What this phase ships

This early version wires up the typed platform-channel contract (via
[Pigeon](https://pub.dev/packages/pigeon)) and two calls:

* **Media info** — duration, dimensions, rotation, codec, HDR-ness and more, read without
  decoding the whole file.
* **Thumbnails** — a rotation-correct poster frame at any timestamp, as JPEG bytes or written to
  a file.

Compression itself, presets, jobs, progress and cancellation land in later versions.

## Unit convention

Every quantity that crosses the Dart/native boundary carries its unit in its name —
`durationMs`, `positionMs`, `sizeBytes`, `widthPx`, `heightPx`, `videoBitrateBps`,
`frameRateFps`, `rotationDegrees`. There is no ambiguous bare `duration` or `position` anywhere
in the public API.

## Usage

```dart
const compressVideo = CompressVideo();

// Media info: duration, dimensions, rotation, codec, HDR-ness — read without decoding the
// whole file.
final MediaInfo info = await compressVideo.getMediaInfo(path);
print('${info.widthPx}x${info.heightPx}, ${info.durationMs}ms, ${info.videoCodec}');

// A rotation-correct poster frame as JPEG bytes, at an exact millisecond.
final Uint8List jpegBytes = await compressVideo.getThumbnail(
  path,
  positionMs: 1500,
  quality: 80,
  maxDimensionPx: 512,
);

// The same frame, written to a file instead — either a unique name inside the app's own
// cache directory, or exactly at a caller-chosen outputPath.
final String cachedThumbPath = await compressVideo.getThumbnailFile(path, positionMs: 1500);
final String exactThumbPath = await compressVideo.getThumbnailFile(
  path,
  positionMs: 1500,
  outputPath: '/some/writable/dir/poster.jpg',
);
```

### `MediaInfo` fields

| Field | Unit | Unknown sentinel |
|---|---|---|
| `durationMs` | milliseconds | always present (never unknown) |
| `widthPx` / `heightPx` | pixels, **displayed** (rotation-corrected), never coded | always present |
| `rotationDegrees` | unsigned clockwise degrees, as reported before the correction above | always present; `0` for an unrotated clip |
| `sizeBytes` | bytes | always present |
| `videoCodec` | normalised token (`h264`, `hevc`, `av1`, `vp9`, `unknown`) | `null` when the platform can't determine it; **always `unknown` on iOS 13–15 / macOS 11–12** — see note below |
| `videoBitrateBps` | bits per second, platform-reported (tolerant, may vary slightly between platforms) | `null`, never `0` |
| `frameRateFps` | frames per second, `double`, platform-reported (tolerant) | `null`, never `0` |
| `hasAudio` | `bool` | always present |
| `isHdr` | `bool` (PQ or HLG transfer characteristic) | `false` when undetermined — never an exception |

> **Known limitation:** `videoCodec` is always `"unknown"` on iOS 13–15 and macOS 11–12. On
> those OS versions the plugin falls back to the synchronous `AVAssetTrack.formatDescriptions`
> API, whose untyped `[Any]` elements cannot be downcast to `CMFormatDescription` without either
> a forced cast (outside this project's threat model) or a conditional cast the compiler flags
> as "always succeeds" (an error under this build's warnings-as-errors). From iOS 16 / macOS 13
> onward, the modern `async` loading API is used and reports the real codec normally.

### `getThumbnail` / `getThumbnailFile` semantics

* **`positionMs`** — milliseconds from the start of the clip. Negative values throw
  [`CompressVideoErrorReason.unsupportedInput`] synchronously (no frame before the start of a
  clip is ever returned). A value beyond the clip's duration is **clamped to the last frame**
  rather than rejected — duration reporting is approximate and both platforms' own frame APIs
  already clamp this way.
* **`quality`** — JPEG quality, `1` (lowest) to `100` (highest) inclusive; anything outside that
  range throws `unsupportedInput` before crossing the platform channel.
* **`maxDimensionPx`** — caps the longer side of the returned, displayed (rotation-corrected)
  frame. The frame is **never upscaled**: a value at or above the native longer side returns the
  native size unchanged. Must be positive when given; `null` (the default) means no cap.
* **`outputPath`** (file variant only) — with no `outputPath`, the file is written to a
  uniquely-named JPEG inside the app's own cache directory; a call never overwrites a previous
  call's file. With an explicit `outputPath`, the file is written exactly there; a parent
  directory that doesn't exist or isn't writable throws `io` and leaves no file behind.

### `CompressVideoErrorReason` values

Every public call throws a [`CompressVideoException`] instead of returning `null` or letting a
raw platform exception escape. `reason` is one of:

| Reason | Meaning |
|---|---|
| `fileNotFound` | The given path did not resolve to a readable file. |
| `unsupportedInput` | The file exists but its container/codec isn't supported (or an argument, like a blank path or an out-of-range `quality`, was rejected before crossing the channel). |
| `decoderUnavailable` | The platform could not obtain a decoder for the input. |
| `io` | A platform I/O error not covered by a more specific reason above. |
| `cancelled` | The operation was cancelled before it completed. |
| `unknown` | The platform reported an error code this plugin version doesn't recognise; the original code is preserved in [`CompressVideoException.platformDetail`]. |
| `encoderUnavailable` | The device could not obtain/configure an encoder for the requested output (compression, later versions). |
| `outOfSpace` | The destination filesystem has no room for the output (compression, later versions). |
| `interrupted` | The operation was interrupted by the system before completing and can be retried (Apple engine, later versions). |

## Supported platforms

| Platform | Minimum version |
|---|---|
| Android | API 23 (Android 6.0) |
| iOS | 13.0 |
| macOS | 11.0 |

## What "the same on every platform" means

Android, iOS and macOS run on genuinely different encoders (Media3 Transformer vs.
AVAssetReader/AVAssetWriter), so this package is precise about what it guarantees to be the same
across platforms and what it does not.

**The same on every platform, for a given input and `CompressOptions`:**

* the output's displayed `widthPx` / `heightPx`
* the output's `videoCodec` and `audioCodec`
* the `transmuxed`, `usedOriginal` and `audioReencoded` flags
* `durationMs`, within one output frame

**Deliberately NOT the same — different by design, not by bug:**

* `outputBytes` — different encoders spend bits differently at the same nominal target; a
  cross-platform parity gate in this project's own CI treats a wide byte-count spread as
  expected and only fails on an order-of-magnitude regression
* `elapsedMs` — wall-clock encode time depends on the host's own encoder (hardware vs. software,
  device vs. simulator) and is never compared across platforms

This is not a promise of byte-for-byte or elapsed-time parity anywhere in this package's surface
— see the `outputBytes` and `elapsedMs` dartdoc on [`CompressResult`] for the same statement at
the point a caller reads those fields, and `doc/PRESETS.md` for the actual per-platform measured
tables (including a real, measured Apple-overshoots/Android-undershoots bitrate divergence) that
substantiate this section rather than assert it.

## What this plugin deliberately does not do

* **Bundle FFmpeg.** No GPL dependency, no ~100 MB binary blob, no software-only encode path.
  Everything goes through the platform's own hardware-accelerated media APIs.
* **Filters, watermarks or stitching.** This is a compression and inspection tool, not a video
  editor.
* **Upload or manage network transfer.** This plugin produces a local file; getting it somewhere
  else is the app's job.

## Development

Planning for this project lives in `.planning/` (GSD). Research that led here:
`.planning/research/sources/VIDEO_COMPRESS_BRIEF.md`.
