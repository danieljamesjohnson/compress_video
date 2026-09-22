import 'package:compress_video/compress_video.dart';

/// A handle for a single in-flight (or finished) compression started through
/// [CompressionRunner.compress].
///
/// Mirrors the observable shape of a [CompressJob] -- a progress stream, a result future and a
/// cancel callback -- so [MainScreen] (in `main_screen.dart`) can depend on this small
/// interface instead of [CompressJob] directly.
class CompressionHandle {
  /// Creates a [CompressionHandle].
  const CompressionHandle({
    required this.progress,
    required this.result,
    required this.cancel,
  });

  /// Progress, 0 to 100 inclusive, emitted as the job runs. A broadcast stream that closes when
  /// the job ends, whether by success, failure or cancellation.
  final Stream<double> progress;

  /// Completes with the job's [CompressResult] on success, or fails with a
  /// [CompressVideoException] on any failure (including cancellation, with reason
  /// [CompressVideoErrorReason.cancelled]).
  final Future<CompressResult> result;

  /// Requests cancellation of this job. A no-op if the job has already finished.
  final Future<void> Function() cancel;
}

/// The one seam `MainScreen` uses to reach the compression engine.
///
/// [CompressJob]'s constructor is private and its factory needs a real `CompressHostApi`
/// platform channel, so a widget test cannot construct one directly. This abstraction is what
/// lets `main_screen_test.dart` substitute a fake that is fully test-controlled, with no
/// platform channel at all -- D-27's "fake `CompressVideo`" in practice.
abstract class CompressionRunner {
  /// Starts a compression of the video at [path] per [options], returning a
  /// [CompressionHandle] immediately -- not a `Future` -- while the underlying work proceeds in
  /// the background.
  CompressionHandle compress(String path, {required CompressOptions options});

  /// Returns a pre-flight estimate for compressing the video at [path] per [options].
  Future<CompressEstimate> estimate(
    String path, {
    required CompressOptions options,
  });

  /// Deletes every file the plugin has written to its own cache directory.
  Future<void> clearCache();
}

/// The real [CompressionRunner]. Delegates straight to [CompressVideo] and adds no logic of
/// its own.
class RealCompressionRunner implements CompressionRunner {
  /// Creates a [RealCompressionRunner].
  const RealCompressionRunner();

  static const CompressVideo _compressVideo = CompressVideo();

  @override
  CompressionHandle compress(String path, {required CompressOptions options}) {
    final CompressJob job = _compressVideo.compress(path, options: options);
    return CompressionHandle(
      progress: job.progress,
      result: job.result,
      cancel: job.cancel,
    );
  }

  @override
  Future<CompressEstimate> estimate(
    String path, {
    required CompressOptions options,
  }) {
    return _compressVideo.estimate(path, options: options);
  }

  @override
  Future<void> clearCache() => _compressVideo.clearCache();
}
