/// Compatibility library for apps moving from `video_compress` 3.1.4 to `compress_video`.
///
/// Replace
///
/// ```dart
/// import 'package:video_compress/video_compress.dart';
/// ```
///
/// with
///
/// ```dart
/// import 'package:compress_video/video_compress_compat.dart';
/// ```
///
/// and the incumbent's documented calls keep compiling: `VideoCompress.compressVideo`,
/// `getMediaInfo`, `getFileThumbnail`, `getByteThumbnail`, `cancelCompression`,
/// `deleteAllCache`, `compressProgress$`, `isCompressing`, `setLogLevel`, `dispose` and every
/// [VideoQuality] value. Every call runs on this package's own engine ([CompressVideo]).
/// `MIGRATION.md` is the guide: it lists each old call next to its replacement.
///
/// What changes even though the code compiles unchanged:
///
/// - **Nothing returns `null`.** The incumbent swallowed a platform failure, printed it, and
///   returned `null`. Here every failure throws a typed [CompressVideoException], and the
///   return types are non-nullable. An existing `?.` or `!` on a result becomes an analyzer
///   warning, not an error.
/// - **A cancelled compression** resolves to a [MediaInfo] whose [MediaInfo.isCancel] is `true`
///   and whose [MediaInfo.path] is `null`.
/// - **The output is never larger than the input**, and trimming works on every platform.
///
/// Everything here is deprecated on purpose. It exists so a migration can be done in two
/// steps (switch the import, then move call by call to [CompressVideo]), not as a second API
/// to stay on.
///
/// This library declares its own [MediaInfo], shaped like the incumbent's. Do not import it
/// together with `package:compress_video/compress_video.dart` unless one of the two imports
/// carries `hide MediaInfo` or a prefix, because both declare that name.
library;

// The incumbent's own names (`VideoCompress`, `VideoQuality.DefaultQuality`, ...) are the
// contract this library exists to keep, so they cannot follow the lowerCamelCase lints.
// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:compress_video/compress_video.dart' hide MediaInfo;
import 'package:compress_video/compress_video.dart' as cv;
import 'package:flutter/foundation.dart' show VoidCallback;

/// The incumbent's quality names, in the incumbent's order.
///
/// Each value resolves to exactly one [CompressOptions] through
/// [VideoQualityCompressOptions.compressOptions]; that getter's documentation is the mapping
/// table.
@Deprecated(
  'Use CompressOptions(preset: CompressPreset.p720) and friends -- see MIGRATION.md',
)
enum VideoQuality {
  /// Long side capped at 1280 ([CompressPreset.p720]).
  DefaultQuality,

  /// Long side capped at 640 ([CompressPreset.p360]).
  LowQuality,

  /// Long side capped at 854 ([CompressPreset.p480]).
  MediumQuality,

  /// Long side capped at 1920 ([CompressPreset.p1080]).
  HighestQuality,

  /// Long side capped at 640 ([CompressPreset.p360]).
  Res640x480Quality,

  /// Long side capped at 960 ([CompressPreset.p720] with `maxLongSidePx: 960`).
  Res960x540Quality,

  /// Long side capped at 1280 ([CompressPreset.p720]).
  Res1280x720Quality,

  /// Long side capped at 1920 ([CompressPreset.p1080]).
  Res1920x1080Quality,
}

/// Resolves a [VideoQuality] to the [CompressOptions] the compatibility library runs it with.
@Deprecated('Construct CompressOptions directly -- see MIGRATION.md')
extension VideoQualityCompressOptions on VideoQuality {
  /// The [CompressOptions] this quality runs with. The same value `MIGRATION.md` documents and
  /// the unit tests assert, so the three cannot drift apart.
  ///
  /// | `VideoQuality` | `CompressOptions` | Why |
  /// |---|---|---|
  /// | `DefaultQuality` | `preset: p720` | The incumbent's Android default was short side 720 (1280x720). |
  /// | `LowQuality` | `preset: p360` | The incumbent used short side 360. |
  /// | `MediumQuality` | `preset: p480` | The incumbent gave 1136x640 on Android and Apple's Medium preset (about 480p) on iOS; p480 sits between them. |
  /// | `HighestQuality` | `preset: p1080` | The incumbent did not resize and used a fixed 3.7 Mbps, which made 4K blocky. A 1920 cap never upscales, so a source at or below 1080p is still not resized. |
  /// | `Res640x480Quality` | `preset: p360` | A long side of 640 is p360's own cap. |
  /// | `Res960x540Quality` | `preset: p720, maxLongSidePx: 960` | No preset caps at 960. The bitrate is scaled down from p720's by the engine, by area. |
  /// | `Res1280x720Quality` | `preset: p720` | Exact match. |
  /// | `Res1920x1080Quality` | `preset: p1080` | Exact match. |
  ///
  /// The caps are on the long side and never upscale, and the aspect ratio of the input is
  /// kept. `Res640x480Quality` therefore does not force a 4:3 frame.
  CompressOptions get compressOptions => switch (this) {
    VideoQuality.DefaultQuality => const CompressOptions(
      preset: CompressPreset.p720,
    ),
    VideoQuality.LowQuality => const CompressOptions(
      preset: CompressPreset.p360,
    ),
    VideoQuality.MediumQuality => const CompressOptions(
      preset: CompressPreset.p480,
    ),
    VideoQuality.HighestQuality => const CompressOptions(
      preset: CompressPreset.p1080,
    ),
    VideoQuality.Res640x480Quality => const CompressOptions(
      preset: CompressPreset.p360,
    ),
    VideoQuality.Res960x540Quality => const CompressOptions(
      preset: CompressPreset.p720,
      maxLongSidePx: 960,
    ),
    VideoQuality.Res1280x720Quality => const CompressOptions(
      preset: CompressPreset.p720,
    ),
    VideoQuality.Res1920x1080Quality => const CompressOptions(
      preset: CompressPreset.p1080,
    ),
  };
}

/// The incumbent's media info shape: mutable, every field nullable.
///
/// Returned by [IVideoCompress.getMediaInfo] and [IVideoCompress.compressVideo]. The typed,
/// immutable replacement is `MediaInfo` in `package:compress_video/compress_video.dart` (for
/// media info) and [CompressResult] (for a compression's outcome).
///
/// There is no constructor that reads a map: the incumbent parsed an untyped map it received
/// from the platform, which is the class of bug this package exists to remove. [toJson] is
/// kept because the incumbent's own documentation calls it, and it only writes.
@Deprecated(
  'Use MediaInfo from package:compress_video/compress_video.dart, or '
  'CompressResult for a compression -- see MIGRATION.md',
)
class MediaInfo {
  /// Creates a [MediaInfo]. Only [path] is required, and it may be `null`.
  MediaInfo({
    required this.path,
    this.title,
    this.author,
    this.width,
    this.height,
    this.orientation,
    this.filesize,
    this.duration,
    this.isCancel,
    this.file,
  });

  /// Path of the file this describes. `null` only for a cancelled compression.
  String? path;

  /// Always `null`: the engine does not read container title metadata.
  String? title;

  /// Always `null`: the engine does not read container author metadata.
  String? author;

  /// Displayed (rotation-corrected) width, in pixels.
  int? width;

  /// Displayed (rotation-corrected) height, in pixels.
  int? height;

  /// Clockwise rotation, in degrees, the container declares. Set by
  /// [IVideoCompress.getMediaInfo]; `null` on a compression result.
  int? orientation;

  /// Size of the file, in bytes.
  int? filesize;

  /// Duration, in milliseconds.
  double? duration;

  /// Whether the compression that produced this was cancelled. `false` for a finished
  /// compression, `true` for a cancelled one, `null` from [IVideoCompress.getMediaInfo].
  bool? isCancel;

  /// [path] as a [File], or `null` when [path] is `null`.
  File? file;

  /// Writes the incumbent's key set. Output only; nothing in this library reads it back.
  ///
  /// `orientation` and `isCancel` are left out when `null`, as the incumbent did. Unlike the
  /// incumbent, a `null` [path] does not throw here: `file` is written as `null`.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['path'] = path;
    data['title'] = title;
    data['author'] = author;
    data['width'] = width;
    data['height'] = height;
    if (orientation != null) {
      data['orientation'] = orientation;
    }
    data['filesize'] = filesize;
    data['duration'] = duration;
    if (isCancel != null) {
      data['isCancel'] = isCancel;
    }
    final String? currentPath = path;
    data['file'] = currentPath == null ? null : File(currentPath).toString();
    return data;
  }
}

/// A handle returned by [ObservableBuilder.subscribe]. Call [unsubscribe] to stop receiving
/// values.
@Deprecated(
  'Listen to CompressJob.progress and cancel the StreamSubscription -- see '
  'MIGRATION.md',
)
class Subscription {
  /// Creates a [Subscription] whose [unsubscribe] runs the given callback.
  const Subscription(this.unsubscribe);

  /// Stops this subscriber, and only this subscriber, from receiving further values.
  final VoidCallback unsubscribe;
}

/// The incumbent's minimal observable, used for [IVideoCompress.compressProgress$].
///
/// Two differences from the incumbent, both supersets of its behaviour: any number of
/// subscribers may [subscribe] at once (the incumbent threw on the second), and
/// [Subscription.unsubscribe] stops only its own subscriber (the incumbent closed the stream
/// under every subscriber).
@Deprecated(
  'Listen to CompressJob.progress, a Stream<double> -- see MIGRATION.md',
)
class ObservableBuilder<T> {
  final StreamController<T> _observable = StreamController<T>.broadcast();

  /// `true` until the first [subscribe] call, and `false` from then on.
  bool notSubscribed = true;

  /// Delivers [value] to every current subscriber.
  void next(T value) {
    _observable.add(value);
  }

  /// Subscribes to values, with the same parameters as `Stream.listen`.
  Subscription subscribe(
    void Function(T event) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    notSubscribed = false;
    final StreamSubscription<T> subscription = _observable.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    return Subscription(() {
      unawaited(subscription.cancel());
    });
  }
}

IVideoCompress? _instance;

/// The incumbent's entry point: one shared [IVideoCompress], created on first use and
/// replaced after [IVideoCompress.dispose].
@Deprecated('Construct a CompressVideo() where you need it -- see MIGRATION.md')
IVideoCompress get VideoCompress => _instance ??= IVideoCompress._();

/// The incumbent's verbs, implemented on [CompressVideo].
///
/// Obtained from the top-level `VideoCompress` getter. It keeps the incumbent's contract of
/// one compression at a time with one shared progress stream: [isCompressing] is `true`
/// exactly while a compression started here is in flight, and [compressProgress$] carries
/// that compression's progress.
@Deprecated('Use CompressVideo -- see MIGRATION.md')
class IVideoCompress {
  IVideoCompress._() : _engine = CompressVideo(maxConcurrentJobs: 1);

  final CompressVideo _engine;

  /// Progress of the compression in flight, 0 to 100, delivered to every subscriber.
  ///
  /// Replaced by [CompressJob.progress], which is per job.
  @Deprecated('Use CompressJob.progress -- see MIGRATION.md')
  final ObservableBuilder<double> compressProgress$ =
      ObservableBuilder<double>();

  bool _isCompressing = false;

  /// The compression in flight, or `null`. Set and cleared together with [_isCompressing].
  CompressJob? _currentJob;

  /// Whether a compression started through this object is in flight.
  ///
  /// The engine itself has no such global: each [CompressJob] is independent.
  @Deprecated(
    'Hold the CompressJob and await its result instead -- see MIGRATION.md',
  )
  bool get isCompressing => _isCompressing;

  /// Returns media info for the video at [path].
  ///
  /// Runs [CompressVideo.getMediaInfo] and copies its typed fields: [MediaInfo.width] and
  /// [MediaInfo.height] are the displayed size in pixels, [MediaInfo.orientation] the rotation
  /// in degrees, [MediaInfo.filesize] bytes, [MediaInfo.duration] milliseconds.
  /// [MediaInfo.title] and [MediaInfo.author] are always `null`.
  ///
  /// Throws a [CompressVideoException] on any failure. Never resolves to `null`.
  @Deprecated('Use CompressVideo().getMediaInfo(path) -- see MIGRATION.md')
  Future<MediaInfo> getMediaInfo(String path) async {
    final cv.MediaInfo info = await _engine.getMediaInfo(path);
    return MediaInfo(
      path: path,
      width: info.widthPx,
      height: info.heightPx,
      orientation: info.rotationDegrees,
      filesize: info.sizeBytes,
      duration: info.durationMs.toDouble(),
      file: File(path),
    );
  }

  /// Compresses the video at [path] and returns the output as a [MediaInfo].
  ///
  /// Runs [CompressVideo.compress] with the options [quality] resolves to (see
  /// [VideoQualityCompressOptions.compressOptions]) and these parameters applied on top:
  ///
  /// - [startTime] and [duration] are in **seconds**, as in the incumbent, and [duration] is
  ///   the length of the span to keep. They become `trimStartMs = startTime * 1000` and
  ///   `trimEndMs = (startTime + duration) * 1000`.
  /// - [includeAudio] `false` removes the audio track; `true` or `null` keeps it.
  /// - [frameRate] is a cap (`maxFps`), never a target: a slower source is not sped up.
  /// - [deleteOrigin] deletes the input after a successful compression, and only when the
  ///   output is a different file from the input.
  ///
  /// What differs from the incumbent:
  ///
  /// - A failure throws a typed [CompressVideoException]. It is never swallowed into `null`.
  /// - A cancelled compression resolves to a [MediaInfo] with [MediaInfo.isCancel] `true` and
  ///   a `null` [MediaInfo.path].
  /// - Trimming works on every platform.
  /// - The output is never larger than the input. When compressing would not make the file
  ///   smaller, the output is a copy of the input.
  /// - [VideoQuality.HighestQuality] caps the long side at 1920 instead of not resizing.
  ///
  /// What is kept: only one compression runs at a time. Calling this while [isCompressing] is
  /// `true` fails with a [StateError], before anything reaches the platform. Like every
  /// other failure of this call, it is delivered through the returned `Future`.
  @Deprecated(
    'Use CompressVideo().compress(path, options: ...).result -- see '
    'MIGRATION.md',
  )
  Future<MediaInfo> compressVideo(
    String path, {
    VideoQuality quality = VideoQuality.DefaultQuality,
    bool deleteOrigin = false,
    int? startTime,
    int? duration,
    bool? includeAudio,
    int frameRate = 30,
  }) async {
    if (_isCompressing) {
      throw StateError(
        '''VideoCompress Error: 
      Method: compressVideo
      Already have a compression process, you need to wait for the process to finish or stop it''',
      );
    }

    // CompressOptions has no copyWith, so the base options are copied field by field.
    final CompressOptions base = quality.compressOptions;
    final CompressOptions options = CompressOptions(
      preset: base.preset,
      maxLongSidePx: base.maxLongSidePx,
      videoBitrateBps: base.videoBitrateBps,
      targetSizeMb: base.targetSizeMb,
      maxFps: frameRate,
      audio: includeAudio == false
          ? const AudioStrip()
          : const AudioPassthrough(),
      trimStartMs: startTime == null ? null : startTime * 1000,
      trimEndMs: duration == null ? null : ((startTime ?? 0) + duration) * 1000,
      outputPath: base.outputPath,
      codec: base.codec,
      hdr: base.hdr,
      androidForegroundService: base.androidForegroundService,
    );

    // Throws for an invalid argument before the state below is touched, so a rejected call
    // can never leave isCompressing stuck at true.
    final CompressJob job = _engine.compress(path, options: options);
    _currentJob = job;
    _isCompressing = true;
    final StreamSubscription<double> forwarding = job.progress.listen(
      compressProgress$.next,
    );

    try {
      final CompressResult result = await job.result;
      if (deleteOrigin) {
        await _deleteOrigin(path, result.outputPath);
      }
      return MediaInfo(
        path: result.outputPath,
        width: result.widthPx,
        height: result.heightPx,
        filesize: result.outputBytes,
        duration: result.durationMs.toDouble(),
        isCancel: false,
        file: File(result.outputPath),
      );
    } on CompressVideoException catch (e) {
      if (e.reason == CompressVideoErrorReason.cancelled) {
        return MediaInfo(path: null, isCancel: true);
      }
      rethrow;
    } finally {
      _currentJob = null;
      _isCompressing = false;
      await forwarding.cancel();
    }
  }

  /// Deletes the input at [path], unless [outputPath] is that same file.
  ///
  /// The two are compared as files, not as strings, so a second name for the input (a
  /// symbolic link, or a differently spelled path) is recognised. When that comparison cannot
  /// be made, the input is kept: keeping a file the caller asked to delete is recoverable,
  /// deleting their only copy is not.
  Future<void> _deleteOrigin(String path, String outputPath) async {
    if (outputPath == path) {
      return;
    }
    try {
      // Resolved first: FileSystemEntity.identical does not follow a symbolic link, so on its
      // own it reports a link and its target as two different files.
      final String resolvedInput = await File(path).resolveSymbolicLinks();
      final String resolvedOutput = await File(
        outputPath,
      ).resolveSymbolicLinks();
      if (resolvedInput == resolvedOutput ||
          await FileSystemEntity.identical(resolvedInput, resolvedOutput)) {
        return;
      }
      await File(path).delete();
    } on FileSystemException {
      // The input is already gone, or cannot be compared or deleted. The compression itself
      // succeeded, so its result is still returned.
    }
  }

  /// Stops the compression in flight. Does nothing when there is none.
  ///
  /// The pending [compressVideo] call then resolves to a [MediaInfo] with
  /// [MediaInfo.isCancel] `true`.
  @Deprecated('Use CompressJob.cancel() -- see MIGRATION.md')
  Future<void> cancelCompression() async {
    await _currentJob?.cancel();
  }

  /// Returns a JPEG thumbnail of the video at [path], as bytes.
  ///
  /// [quality] is JPEG quality, 1 to 100. [position] is in milliseconds; a negative value
  /// (the incumbent's default of -1, "let the platform choose") means the first frame.
  ///
  /// Throws a [CompressVideoException] on any failure, including a [quality] outside 1 to
  /// 100. Never resolves to `null`.
  @Deprecated(
    'Use CompressVideo().getThumbnail(path, positionMs: ..., quality: ...) '
    '-- see MIGRATION.md',
  )
  Future<Uint8List> getByteThumbnail(
    String path, {
    int quality = 100,
    int position = -1,
  }) {
    return _engine.getThumbnail(
      path,
      positionMs: position < 0 ? 0 : position,
      quality: quality,
    );
  }

  /// Writes a JPEG thumbnail of the video at [path] to a file in the plugin's cache directory
  /// and returns it.
  ///
  /// [quality] and [position] behave as in [getByteThumbnail].
  ///
  /// Throws a [CompressVideoException] on any failure.
  @Deprecated(
    'Use CompressVideo().getThumbnailFile(path, positionMs: ..., quality: '
    '...) -- see MIGRATION.md',
  )
  Future<File> getFileThumbnail(
    String path, {
    int quality = 100,
    int position = -1,
  }) async {
    final String thumbnailPath = await _engine.getThumbnailFile(
      path,
      positionMs: position < 0 ? 0 : position,
      quality: quality,
    );
    return File(thumbnailPath);
  }

  /// Deletes every file this plugin wrote to its own cache directory, compression outputs
  /// and thumbnails alike, and returns `true`.
  ///
  /// Throws a [CompressVideoException] when the platform fails to clear the directory; it
  /// never returns `false` or `null` for a failure.
  @Deprecated('Use CompressVideo().clearCache() -- see MIGRATION.md')
  Future<bool> deleteAllCache() async {
    await _engine.clearCache();
    return true;
  }

  /// Does nothing. Kept so existing calls compile; the engine has no log level to set.
  @Deprecated('Remove the call; it has no effect -- see MIGRATION.md')
  Future<void> setLogLevel(int logLevel) async {}

  /// Drops the shared instance, so the next read of `VideoCompress` creates a new one.
  ///
  /// As with the incumbent, this does not cancel a compression that is still in flight, and
  /// subscribers of this object's [compressProgress$] are not moved to the new instance.
  @Deprecated(
    'Nothing to dispose: CompressVideo holds no global state -- see '
    'MIGRATION.md',
  )
  void dispose() {
    if (identical(_instance, this)) {
      _instance = null;
    }
  }
}
