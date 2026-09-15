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

## Supported platforms

| Platform | Minimum version |
|---|---|
| Android | API 23 (Android 6.0) |
| iOS | 13.0 |
| macOS | 11.0 |

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
