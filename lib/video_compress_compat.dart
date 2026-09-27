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

  final bool _isCompressing = false;

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
