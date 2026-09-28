# Migrating from `video_compress` to `compress_video`

This guide is for an app that uses `video_compress` 3.1.4. It has two steps, and the first one
is a one-line change:

1. Switch the import. Your existing calls keep compiling and run on the new engine.
2. Move each call to the new API when it suits you. The tables below put every old name next to
   its new call.

## 1. Switch in one line

In `pubspec.yaml`, replace `video_compress` with `compress_video`. Then change the import.

Before:

```dart
import 'package:video_compress/video_compress.dart';
```

After:

```dart
import 'package:compress_video/video_compress_compat.dart';
```

The code from the `video_compress` README then compiles as it is:

```dart
MediaInfo mediaInfo = await VideoCompress.compressVideo(
  path,
  quality: VideoQuality.DefaultQuality,
  deleteOrigin: false, // It's false by default
);
```

Everything compiles. Two kinds of analyzer message appear, and neither is an error:

- **Deprecation notices.** Every name in the compat import is marked deprecated and says which
  new call replaces it. This is your to-do list for step 2.
- **Warnings on `?.` and `!`.** The results are no longer nullable, so a `mediaInfo?.path` or a
  `mediaInfo!.path` on a result is now unnecessary. The analyzer says so with a warning. The code
  still builds and runs.

Do not import the compat library and `package:compress_video/compress_video.dart` in the same
file without a prefix or a `hide MediaInfo`. Both declare a class called `MediaInfo`.

## 2. What behaves differently after the switch

The code compiles unchanged, but the engine under it is new. These are the differences.

| What | `video_compress` | After the switch |
|---|---|---|
| A failure | Printed with `debugPrint` and returned as `null` | Throws a typed `CompressVideoException`. Its `reason` says what went wrong. Nothing returns `null`. |
| Output size | Could be larger than the input | Never larger than the input. When compressing would not make the file smaller, the output is a copy of the input. |
| Trim on Android | `duration` was read as "how much to cut from the end", so the wrong part was kept | `startTime` and `duration` keep exactly the span you asked for, on every platform. |
| Trim on iOS | Only applied when `includeAudio` was `false` | Always applied. |
| `width` and `height` on Android | Swapped for the wrong rotations | The size as displayed, after rotation, on every platform. |
| `VideoQuality.HighestQuality` | No resize, fixed 3.7 Mbps. A 4K video stayed 4K and looked blocky. | The long side is capped at 1920. A video at or below 1080p is still not resized. |
| `compressProgress$` | One subscriber. A second `subscribe` threw. `unsubscribe` closed the stream for everyone. | Any number of subscribers. `unsubscribe` stops only its own subscriber. |
| `deleteAllCache` | Deleted the whole plugin folder and crashed on Android | Deletes only the files this plugin wrote, and returns `true`. |
| `setLogLevel` | Set the native log level | Does nothing. The call is kept so that your code compiles. |
| A cancelled `compressVideo` | Returned `null` or a `MediaInfo` with `isCancel` set, depending on the platform | Returns `MediaInfo(isCancel: true)` with a `null` `path`. |
| `MediaInfo.fromJson` | Parsed an untyped map from the platform | Not provided. The new engine never sends an untyped map. `toJson` is kept. |
| `title` and `author` | Read from the container | Always `null`. |
| `orientation` on a compression result | Set | `null`. It is set on the result of `getMediaInfo`. |
| Audio | Always re-encoded to AAC on Android | Passed through unchanged when the output can carry it. |

### One compression at a time is kept

`video_compress` ran one compression at a time and threw a `StateError` if you started a second
one. The compat import keeps this. While `isCompressing` is `true`, a second `compressVideo`
call fails with the same `StateError`, before anything reaches the platform.

The error arrives through the returned `Future`, as it did in `video_compress`. Catch it with
`try`/`catch` around the `await`, or with `.catchError`.

The new API has no such limit. `CompressVideo` has a queue, every job has its own progress and
its own result, and `maxConcurrentJobs` sets how many run at once. Queueing and running several
jobs at once live there, not in the compat import.

## 3. Every old API and its new call

"Compat import" is what the name does after step 1. "New API" is what to write in step 2.

| `video_compress` | Compat import | New API |
|---|---|---|
| `VideoCompress` | The shared instance, created on first use | `CompressVideo()`. Construct one where you need it. One shared instance per app is the normal choice. |
| `IVideoCompress` | The type of `VideoCompress`. It cannot be constructed or extended. | `CompressVideo` |
| `Compress` | Not provided. The methods of this extension are members of `IVideoCompress`. | `CompressVideo` |
| `compressVideo` | Same call. Returns a non-null `MediaInfo`. | `CompressVideo().compress(path, options: ...)` returns a `CompressJob`. Await `job.result` for a `CompressResult`. |
| `quality` | Same parameter, of type `VideoQuality` | `CompressOptions(preset: ...)`. See the `VideoQuality` table below. |
| `deleteOrigin` | Same. Deletes the input only after success, and only when the output is a different file. | Not provided. Delete the input yourself after `job.result` succeeds: `File(path).delete()`. |
| `startTime` | Same, in **seconds** | `CompressOptions(trimStartMs: ...)`, in **milliseconds**. `startTime: 2` becomes `trimStartMs: 2000`. |
| `duration` | Same, in **seconds**, the length of the span to keep | `CompressOptions(trimEndMs: ...)`, in **milliseconds**, the end of the span. `startTime: 2, duration: 5` becomes `trimStartMs: 2000, trimEndMs: 7000`. |
| `includeAudio` | Same. `false` removes the audio. | `CompressOptions(audio: AudioStrip())` to remove it, `AudioPassthrough()` (the default) to keep it, `AudioReencode(...)` to re-encode it. |
| `frameRate` | Same. A cap, never a target. | `CompressOptions(maxFps: ...)` |
| `compressProgress$` | Same. Carries the progress of the compression in flight, 0 to 100. | `CompressJob.progress`, a `Stream<double>` from 0 to 100, one per job |
| `ObservableBuilder` | Same class | `Stream<double>` |
| `subscribe` | Same | `job.progress.listen(...)` |
| `notSubscribed` | Same. `true` until the first `subscribe`. | Not provided. Nothing needs it. |
| `next` | Same | Not provided. Only the engine sends progress. |
| `Subscription` | Same class | `StreamSubscription<double>` |
| `unsubscribe` | Same | `subscription.cancel()` |
| `isCompressing` | Same | Not provided. Keep the `CompressJob` and await its `result`. `CompressJob.isQueued` says whether it has started. |
| `cancelCompression` | Same. Cancels the compression in flight. | `job.cancel()`. `job.result` then fails with reason `cancelled`. |
| `getMediaInfo` | Same. Returns the old `MediaInfo` shape. | `CompressVideo().getMediaInfo(path)` returns the new typed `MediaInfo`. |
| `getByteThumbnail` | Same. Returns non-null bytes. | `CompressVideo().getThumbnail(path, positionMs: ..., quality: ...)` |
| `getFileThumbnail` | Same. Returns a `File`. | `CompressVideo().getThumbnailFile(path, positionMs: ..., quality: ...)` returns the path as a `String`. |
| `position` | Milliseconds. `-1`, the old default, means the first frame (`0`). | `positionMs`, milliseconds on every platform. A negative value is rejected. |
| `quality` (thumbnails) | JPEG quality, 1 to 100. The default is 100. | `quality`, 1 to 100. The default is 80. |
| `deleteAllCache` | Same. Returns `true`. | `CompressVideo().clearCache()` |
| `setLogLevel` | Does nothing | Remove the call. |
| `dispose` | Drops the shared instance. A compression in flight keeps running, and `isCompressing` and `cancelCompression` still reach it afterwards. | Remove the call. `CompressVideo` has nothing to dispose. |
| `channel` | Not provided. There is no hand-written channel to expose. | Not provided. The platform contract is typed and private. |
| `initProcessCallback` | Not provided. It was a protected member. | Not provided. |
| `setProcessingStatus` | Not provided. It was a protected member. | Not provided. |
| `VideoQuality` | Same enum, same eight values | `CompressPreset` plus the explicit targets of `CompressOptions` |
| `MediaMetadataRetriever` | Not provided. `video_compress` exported these constants and never used them. | The typed fields of the new `MediaInfo`: `durationMs`, `widthPx`, `heightPx`, `rotationDegrees`, `videoBitrateBps`, `frameRateFps`, `hasAudio`, `videoCodec`. |
| `Enum` | Not provided. It was the base class of `MediaMetadataRetriever`. | Not provided. |

## 4. `MediaInfo` fields

The compat import has its own `MediaInfo`, shaped like the old one: mutable, every field
nullable. The new API splits it in two. `MediaInfo` describes a file, and `CompressResult`
describes what a compression produced. In the new API every name carries its unit.

| `video_compress` field | New `MediaInfo` (from `getMediaInfo`) | New `CompressResult` (from `job.result`) | Unit |
|---|---|---|---|
| `path` | The path you passed in | `outputPath` | |
| `title` | Not provided | Not provided | |
| `author` | Not provided | Not provided | |
| `width` | `widthPx` | `widthPx` | Pixels, as displayed |
| `height` | `heightPx` | `heightPx` | Pixels, as displayed |
| `orientation` | `rotationDegrees` | Not provided. The output is upright. | Degrees, clockwise |
| `filesize` | `sizeBytes` | `outputBytes`, with `inputBytes` beside it | Bytes |
| `duration` | `durationMs` | `durationMs` | Milliseconds. An `int`, where the old field was a `double`. |
| `isCancel` | Not provided | Not provided. A cancelled job throws `CompressVideoException` with reason `cancelled`. | |
| `file` | `File(path)` | `File(result.outputPath)` | |
| `toJson` | Not provided. Read the typed fields. | Not provided | |
| `fromJson` | Not provided | Not provided | |

The new types also report what the old one could not: `videoCodec`, `videoBitrateBps`,
`frameRateFps`, `hasAudio` and `isHdr` on `MediaInfo`, and `transmuxed`, `usedOriginal`,
`toneMapped`, `hevcFallback`, `audioReencoded` and `elapsedMs` on `CompressResult`.

## 5. `VideoQuality` and the preset it runs as

Each `VideoQuality` value runs as exactly one `CompressOptions`. The "cap" is on the longer
side of the video. A video is never enlarged and its shape is kept, so
`VideoQuality.Res640x480Quality` does not force a 4:3 frame.

The bitrate target is for 30 frames per second at the cap. The engine scales it down for a
smaller or slower video.

| `VideoQuality` | Runs as | Long-side cap (px) | Bitrate target | `video_compress` on Android | `video_compress` on iOS and macOS | Why this preset |
|---|---|---|---|---|---|---|
| `VideoQuality.DefaultQuality` | `CompressOptions(preset: CompressPreset.p720)` | 1280 | 2.5 Mbps | Short side up to 720, about 3.9 Mbps | Apple's Medium preset, the same as `MediumQuality` | The Android default was 1280x720. |
| `VideoQuality.LowQuality` | `CompressOptions(preset: CompressPreset.p360)` | 640 | 0.8 Mbps | Short side up to 360, about 0.97 Mbps | Apple's Low preset | The old rule was a short side of 360. |
| `VideoQuality.MediumQuality` | `CompressOptions(preset: CompressPreset.p480)` | 854 | 1.2 Mbps | Short side up to 640 (1136x640), about 3.1 Mbps | Apple's Medium preset, about 480p | The two platforms disagreed. `p480` sits between them. |
| `VideoQuality.HighestQuality` | `CompressOptions(preset: CompressPreset.p1080)` | 1920 | 5 Mbps | No resize, fixed 3.7 Mbps | Apple's Highest preset | A fixed 3.7 Mbps made 4K blocky. A cap of 1920 still leaves a 1080p video at its own size. |
| `VideoQuality.Res640x480Quality` | `CompressOptions(preset: CompressPreset.p360)` | 640 | 0.8 Mbps | Up to 640 by 480, about 0.97 Mbps | Apple's 640x480 preset | A long side of 640 is the cap of `p360`. |
| `VideoQuality.Res960x540Quality` | `CompressOptions(preset: CompressPreset.p720, maxLongSidePx: 960)` | 960 | 2.5 Mbps, scaled down for the smaller frame | Up to 960 by 540, about 2.2 Mbps | Apple's 960x540 preset | No preset has a cap of 960, so the cap is set on top of `p720`. |
| `VideoQuality.Res1280x720Quality` | `CompressOptions(preset: CompressPreset.p720)` | 1280 | 2.5 Mbps | Up to 1280 by 720, about 3.9 Mbps | Apple's 1280x720 preset | The same size. |
| `VideoQuality.Res1920x1080Quality` | `CompressOptions(preset: CompressPreset.p1080)` | 1920 | 5 Mbps | Up to 1920 by 1080, about 8.7 Mbps | Apple's 1920x1080 preset | The same size. |

The bitrates in the `video_compress` columns are what its Android library worked out for a
1920x1080 input at 30 frames per second. On iOS and macOS it had no bitrate control: Apple's
export presets do not offer one.

The README has what each preset really produced on each platform:
[Presets at a glance](README.md#presets-at-a-glance).

## 6. Moving off the compat import

Change the import to the main library and move one call at a time.

```dart
import 'package:compress_video/compress_video.dart';
```

### Compress with progress

Before:

```dart
final subscription = VideoCompress.compressProgress$.subscribe((progress) {
  print('$progress%');
});
final MediaInfo? info = await VideoCompress.compressVideo(
  path,
  quality: VideoQuality.MediumQuality,
);
subscription.unsubscribe();
if (info == null) {
  // Something went wrong. There is no way to know what.
}
```

After:

```dart
final compressVideo = CompressVideo();
final CompressJob job = compressVideo.compress(
  path,
  options: const CompressOptions(preset: CompressPreset.p480),
);
job.progress.listen((double percent) => print('$percent%'));
try {
  final CompressResult result = await job.result;
  print('${result.outputPath}: ${result.outputBytes} bytes');
} on CompressVideoException catch (e) {
  print('Failed: ${e.reason}');
}
```

The progress stream closes by itself when the job ends.

### Cancel

Before:

```dart
await VideoCompress.cancelCompression();
```

After:

```dart
await job.cancel();
```

`job.result` then fails with a `CompressVideoException` whose `reason` is
`CompressVideoErrorReason.cancelled`. You cancel the job you hold, so cancelling one job never
stops another.

### Several videos

Before, a second `compressVideo` call threw a `StateError`, so a batch had to be a loop that
awaited each call.

After:

```dart
final compressVideo = CompressVideo(maxConcurrentJobs: 2);
final List<CompressJob> jobs = <CompressJob>[
  for (final String path in paths) compressVideo.compress(path),
];
final List<CompressResult> results = await Future.wait(
  jobs.map((CompressJob job) => job.result),
);
```

Every call returns its job at once. With `maxConcurrentJobs: 2`, two jobs run and the rest wait
in the order you submitted them. The default is 1.
