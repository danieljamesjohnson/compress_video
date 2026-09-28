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

## Migrating from video_compress

Change one import and your existing `VideoCompress` calls keep compiling, on the new engine.
[MIGRATION.md](MIGRATION.md) lists every old call next to its new one, and what each
`VideoQuality` value now does.

```dart
// Before
import 'package:video_compress/video_compress.dart';

// After
import 'package:compress_video/video_compress_compat.dart';
```

## What this package does

Everything below is on a typed platform-channel contract (via
[Pigeon](https://pub.dev/packages/pigeon)) with no hand-written channel map:

* **Compression** — presets or explicit targets, HEVC and HDR opt-ins, trim, audio control,
  never-larger, per-job progress and cancellation, and an optional job queue for batches (see
  "Compressing a video" and "Queueing several compressions" below).
* **Media info** — duration, dimensions, rotation, codec, HDR-ness and more, read without
  decoding the whole file.
* **Thumbnails** — a rotation-correct poster frame at any timestamp, as JPEG bytes or written to
  a file.

## Install

```sh
flutter pub add compress_video
```

Or add it to `pubspec.yaml` under `dependencies:`:

```yaml
dependencies:
  compress_video: ^1.0.0
```

[CHANGELOG.md](CHANGELOG.md) lists what changed in each version.

## Unit convention

Every quantity that crosses the Dart/native boundary carries its unit in its name —
`durationMs`, `positionMs`, `sizeBytes`, `widthPx`, `heightPx`, `videoBitrateBps`,
`frameRateFps`, `rotationDegrees`. There is no ambiguous bare `duration` or `position` anywhere
in the public API.

## Usage

```dart
final compressVideo = CompressVideo();

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

> **`CompressVideo`'s constructor is not `const`.** A `const CompressVideo()` call site from
> before this version needs to drop the `const` (see CHANGELOG.md) — the per-instance job queue
> below is mutable state a `const` instance cannot hold.

### Compressing a video

```dart
final compressVideo = CompressVideo();

// compress() returns a CompressJob synchronously -- never a Future<CompressJob> -- while the
// actual compression runs in the background.
final CompressJob job = compressVideo.compress(
  path,
  options: const CompressOptions(preset: CompressPreset.p720),
);

// Progress, 0 to 100, ending with exactly one 100.
job.progress.listen((double percent) => print('$percent%'));

// Cancel any time before it finishes -- resolves `result` with a typed `cancelled` failure.
// job.cancel();

try {
  final CompressResult result = await job.result;
  print('${result.outputPath}: ${result.outputBytes} bytes (was ${result.inputBytes})');
} on CompressVideoException catch (e) {
  print('Compression failed: ${e.reason}');
}
```

`compress()` never returns `null` and never lets a raw platform exception escape: every failure,
including cancellation, resolves `job.result` with a typed `CompressVideoException`. The
output is never larger than the input — see `doc/PRESETS.md` and the "same on every platform"
section below.

### Presets at a glance

A preset sets three limits, and the table shows each one next to what that preset really
produced from a portrait 1080p phone clip recorded at 60 frames per second.

<!-- PRESET_TABLE_START -->
| Preset | Longest side (px) | Video bitrate target | Frame rate cap | From a 1080p60 phone clip: Android | From a 1080p60 phone clip: iOS | From a 1080p60 phone clip: macOS |
|---|---|---|---|---|---|---|
| p360 | 640 | 0.8 Mbps (at 30 fps) | 30 fps (never raised) | 360×640, 0.75 Mbps | 360×640, 0.86 Mbps | 360×640, 0.84 Mbps |
| p480 | 854 | 1.2 Mbps (at 30 fps) | 30 fps (never raised) | 480×854, 0.88 Mbps | 480×854, 1.32 Mbps | 480×854, 1.27 Mbps |
| p720 | 1280 | 2.5 Mbps (at 30 fps) | 30 fps (never raised) | 720×1280, 1.48 Mbps | 720×1280, 2.67 Mbps | 720×1280, 2.59 Mbps |
| p1080 | 1920 | 5 Mbps (at 30 fps) | 30 fps (never raised) | 1080×1920, 3.55 Mbps | 1080×1920, 5.26 Mbps | 1080×1920, 5.18 Mbps |

The bitrate target is what the encoder is asked for, and an encoder lands near it, not on it. The target scales down with the output resolution and frame rate, and a video is never upscaled and never given a higher frame rate than it came with.

The Android numbers come from the emulator's software encoder. A phone's hardware encoder will give different numbers.

The full measurements are in [doc/PRESETS.md](doc/PRESETS.md).
<!-- PRESET_TABLE_END -->

### Jobs beyond the foreground: queueing, isolates and backgrounding

The four subsections below are one story, in the order a caller runs into them: how to submit
more than one compression and bound how many run at once; how to run any call from a background
isolate rather than the UI isolate; how to opt an Android job into a foreground service so it
survives the app itself going to the background; and what happens to a running job on iOS when
the system suspends the app. None of this changes `compress()`'s basic contract — every job still
has its own `progress` stream and its own typed `result`, still never returns `null`, and the
output is still never larger than the input.

### Queueing several compressions

Every `CompressVideo` instance owns its own FIFO job queue, gated by `maxConcurrentJobs`:

```dart
// Default: maxConcurrentJobs = 1 -- jobs run strictly one at a time, in submission order.
final compressVideo = CompressVideo();
final CompressJob first = compressVideo.compress(pathA);
final CompressJob second = compressVideo.compress(pathB); // waits for `first` to settle

// Or opt into running more than one at once:
final batchCompressVideo = CompressVideo(maxConcurrentJobs: 3);
```

* `compress()` still returns its `CompressJob` synchronously whether the job starts immediately
  or waits — check `CompressJob.isQueued` to tell which. A queued job's `progress` stream emits
  nothing until it actually starts.
* Every job keeps its own `progress` stream and its own `result`, regardless of queue position —
  there is no global progress stream and no "is compressing" flag anywhere in this package (the
  defect class this plugin exists to avoid, `video_compress` issues #317 and #307).
* Cancelling a job that is still queued resolves `result` with the same typed `cancelled`
  failure a cancelled *running* job produces, without ever reaching the platform — a caller
  cannot tell from the exception whether the job had started.
* Two `CompressVideo` instances queue completely independently; one instance's full queue never
  delays another instance's jobs. One shared instance is the normal choice for an app.
* `maxConcurrentJobs` must be at least 1 (the default); anything less throws
  `CompressVideoException` with reason `unsupportedInput` from the constructor.

### Calling from a background isolate

Platform channels are bound per isolate, so calling this plugin from an isolate spawned with
`Isolate.run` (or `compute`) needs one extra call first — otherwise the first platform call fails
with a typed `CompressVideoException`, never a hang or a `null`:

```dart
final RootIsolateToken token = RootIsolateToken.instance!;
final CompressResult result = await Isolate.run(() async {
  CompressVideo.ensureInitializedInBackgroundIsolate(token);
  final compressVideo = CompressVideo();
  final job = compressVideo.compress(path, options: options);
  return job.result;
});
```

* Capture `RootIsolateToken.instance` on the ROOT isolate before spawning — that property is
  `null` everywhere else — and pass it into the closure.
* Call `CompressVideo.ensureInitializedInBackgroundIsolate(token)` as the closure's first
  statement, before constructing a `CompressVideo` or calling any of its methods.
* This works for every call in the package, not only `compress()`.
* A job started on a background isolate is owned by that isolate: `result` resolves normally, but
  `progress` never emits any value on that isolate (it just closes when the job settles) — a
  background isolate can never receive the platform's progress push at all
  (`BackgroundIsolateBinaryMessenger.setMessageHandler` throws unconditionally off-root, a
  permanent Flutter engine constraint, not a bug in this plugin). Observe progress from the root
  isolate if you need it.
* Skipping `ensureInitializedInBackgroundIsolate` entirely: the first call fails with a typed
  `CompressVideoException` (reason `unknown`) — observed as a `StateError` from
  `BackgroundIsolateBinaryMessenger.instance` itself, wrapped rather than left to escape untyped
  or hang.

### Background execution and app suspension

A compression can keep running after the user leaves the app, within limits that differ by
platform and are honestly reported rather than hidden:

* **iOS:** every running job asks the system for extra execution time
  (`beginBackgroundTask`/`UIApplication`) the moment the app is backgrounded, so a short export
  usually finishes anyway. That extra time is limited and not guaranteed — when it runs out, or
  AVFoundation itself reports that the export was interrupted, the job fails with
  `CompressVideoErrorReason.interrupted` and its partial output file is deleted, exactly like any
  other retryable failure: never a hang, never a `null`. The correct response is to catch
  `interrupted` and resubmit the same input and options. This plugin requests **no
  background-processing entitlement** and adds **no `UIBackgroundModes` key** to the host app —
  `beginBackgroundTask` needs neither, so nothing is imposed on an app that never asked for
  background capabilities.
* **Android:** the counterpart is opt-in per job via `CompressOptions.androidForegroundService`
  (`AndroidForegroundServiceOptions`), which runs the job inside a real `mediaProcessing`
  foreground service so it survives the app moving to the background. **This applies only on
  Android 15 (API 35) and above.** Below API 35 the option is accepted but inert: no service
  starts, no permission is exercised, and the job runs exactly as it would without the option —
  the same never-larger, typed-result contract, just without the background survival. Android's
  own six-hour-per-24-hour quota for that service type ends a job the same way iOS suspension
  does: `interrupted`, retryable, partial output deleted. The notification itself may not be
  visible to the user if the host app has never been granted its own `POST_NOTIFICATIONS`
  permission — this plugin never requests that permission (whether to ask the user is the host
  app's decision, not this library's) — but the compression keeps running and completing
  regardless of whether the notification is shown. To make this work, the plugin's own manifest
  declares two permissions (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PROCESSING`) and one
  non-exported `mediaProcessing`-typed `<service>`, all of which merge into the consuming app's
  own manifest through Gradle's standard manifest merger; the service's class name is fully
  namespaced under this plugin's own package, so a name collision with app-level code is not a
  realistic concern.
* **macOS** is never suspended by the system, so none of this applies there — a running job keeps
  running for as long as the app process is alive, exactly as before this plugin ever added it.

See `doc/HARDWARE_CHECKLIST.md` for the real-device walkthrough this behaviour still needs (a
physical iPhone suspension and a physical Android backgrounding run) versus what has already been
proven by this package's own automated test suites.

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
  `CompressVideoErrorReason.unsupportedInput` synchronously (no frame before the start of a
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

Every public call throws a `CompressVideoException` instead of returning `null` or letting a
raw platform exception escape. `reason` is one of:

| Reason | Meaning |
|---|---|
| `fileNotFound` | The given path did not resolve to a readable file. |
| `unsupportedInput` | The file exists but its container/codec isn't supported (or an argument, like a blank path or an out-of-range `quality`, was rejected before crossing the channel). |
| `decoderUnavailable` | The platform could not obtain a decoder for the input. |
| `io` | A platform I/O error not covered by a more specific reason above. |
| `cancelled` | The operation was cancelled before it completed. |
| `unknown` | The platform reported an error code this plugin version doesn't recognise; the original code is preserved in `CompressVideoException.platformDetail`. |
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
— see the `outputBytes` and `elapsedMs` dartdoc on `CompressResult` for the same statement at
the point a caller reads those fields, and `doc/PRESETS.md` for the actual per-platform measured
tables (including a real, measured Apple-overshoots/Android-undershoots bitrate divergence) that
substantiate this section rather than assert it.

## Codecs, HDR and unusual audio

* **Codec:** H.264 is the default output codec on every platform. `CompressOptions.codec` can
  opt into `VideoCodec.hevc`, but HEVC is used **only when the device has a hardware HEVC
  encoder** (Android: `EncoderUtil`/`MediaCodecList`; Apple: `VTCopyVideoEncoderList`). On a
  device with no hardware HEVC encoder, the request falls back to H.264 and
  `CompressResult.hevcFallback` reports `true` — never a silent substitution, and never a
  software HEVC encode (this package does not use one).
* **HDR:** an HDR input (Dolby Vision profile 8, HLG, HDR10/PQ) is **tone-mapped to SDR by
  default**, so the output is never washed out; `CompressResult.toneMapped` reports `true` when
  this happened. `CompressOptions.hdr = HdrMode.keepHdr` opts into keeping the source's HDR
  transfer function as HEVC 10-bit (Main10) with the correct HDR colour properties (HLG or PQ,
  BT.2020) — again, hardware-gated: on a device that cannot keep HDR, the request falls back to
  tone-mapped SDR H.264 and reports it with **both** `toneMapped: true` and
  `hevcFallback: true`. Requesting `keepHdr` and seeing `toneMapped: true` back always means "the
  device could not keep HDR," never a bug.
* **Unusual audio:** a source with 5.1 (or other >2-channel) audio, PCM/uncompressed audio, or no
  audio track at all compresses successfully rather than failing. More-than-stereo or non-AAC
  audio is downmixed/re-encoded to 2-channel AAC at 128 kbps and reported via
  `CompressResult.audioReencoded: true`; a source with no audio track produces an output with no
  audio track and a `null` `audioCodec`, unchanged from the plugin's first release.
* **`usedOriginal: true` forces every conversion flag false.** When the never-larger rule (see
  above) substitutes the original input bytes for the output, no Transformer/AVAssetWriter ever
  ran — so `transmuxed`, `audioReencoded`, `toneMapped` and `hevcFallback` are all `false` on that
  result, even for an HDR source that would otherwise have tone-mapped. This can genuinely happen
  for an HDR clip whose tone-mapped re-encode would come out larger than the original HDR file:
  the caller gets the original HDR bytes back, `usedOriginal: true`, and `toneMapped: false` —
  reported honestly, not silently, because the never-larger guarantee has no exception for HDR.

See `doc/HARDWARE_CHECKLIST.md` for exactly what has and has not been proven on real hardware for
HEVC and HDR, and `doc/PRESETS.md` for measured bitrate/byte tables.

## What this plugin deliberately does not do

* **Bundle FFmpeg.** No GPL dependency, no ~100 MB binary blob, no software-only encode path.
  Everything goes through the platform's own hardware-accelerated media APIs.
* **Filters, overlays, watermarks or stitching.** This is a compression and inspection tool, not
  a video editor. Trimming by start and end time is the one edit it does.
* **Upload or manage network transfer.** This plugin produces a local file; getting it somewhere
  else is the app's job.
* **Run on the web.** The platforms are Android, iOS and macOS. Web may come in a later version
  and is not promised. A web build has to compress on the server or upload the original.
* **Encode HEVC in software.** `VideoCodec.hevc` is used only with a hardware HEVC encoder.
  Without one the output is H.264 and the result reports `hevcFallback: true`.
* **Keep HDR without a hardware HEVC 10-bit encoder.** On a device without one,
  `HdrMode.keepHdr` falls back to tone-mapped SDR H.264 and the result reports both
  `toneMapped: true` and `hevcFallback: true`. The video still plays everywhere, with the right
  colours.
* **Deliver progress to a background isolate.** A job started there resolves its `result` as
  usual, but its `progress` stream emits nothing. This is a limit of the Flutter engine. Start
  the job on the root isolate when the app shows progress.
* **Keep a job alive in the background below Android 15.** `androidForegroundService` uses the
  `mediaProcessing` service type, which exists from Android 15 (API 35). Below that the option
  does nothing, and there is no `dataSync` fallback. The job still runs while the app is in the
  foreground.
* **Run a long job in the background on iOS.** The plugin uses only the short background task
  the system gives every app and asks for no background entitlement. A job the system suspends
  ends with `interrupted`, and the app can submit it again.

## Development

Planning for this project lives in `.planning/` (GSD). Research that led here:
`.planning/research/sources/VIDEO_COMPRESS_BRIEF.md`.
