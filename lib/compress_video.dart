/// Public API for the `compress_video` Flutter plugin.
///
/// This phase ships the typed error taxonomy every later call throws and maps into, and the
/// `CompressVideo` entry point for media info. Thumbnails and compression are added by later
/// plans in this phase and in phases 2-6.
library;

import 'package:flutter/services.dart';

import 'src/compress_video_exception.dart';
import 'src/media_info.dart';
import 'src/messages.g.dart' as messages;

export 'src/compress_video_exception.dart';
export 'src/media_info.dart';

/// Entry point for the `compress_video` plugin.
///
/// No static singleton and no global state: construct an instance where you need it. The
/// optional [binaryMessenger] parameter exists so a later phase can inject a background-isolate
/// messenger without changing this class's shape.
class CompressVideo {
  /// Creates a [CompressVideo]. [binaryMessenger] is normally left `null`, which routes calls
  /// to the default host platform messenger.
  const CompressVideo({BinaryMessenger? binaryMessenger})
    // The public parameter name `binaryMessenger` is the documented API shape;
    // `this._binaryMessenger` would make the private field name the public parameter
    // name instead, so an initializing formal is deliberately not used here.
    // ignore: prefer_initializing_formals
    : _binaryMessenger = binaryMessenger;

  final BinaryMessenger? _binaryMessenger;

  /// Returns media info for the video at [path].
  ///
  /// Throws a [CompressVideoException] for every failure — an empty or whitespace-only
  /// [path] never crosses the platform channel and immediately throws with reason
  /// [CompressVideoErrorReason.unsupportedInput]. This call never resolves to `null` and no
  /// raw platform exception ever escapes it.
  Future<MediaInfo> getMediaInfo(String path) async {
    if (path.trim().isEmpty) {
      throw const CompressVideoException(
        reason: CompressVideoErrorReason.unsupportedInput,
        message: 'path must not be empty or whitespace-only',
      );
    }

    final messages.ProbeHostApi api = messages.ProbeHostApi(
      binaryMessenger: _binaryMessenger,
    );

    try {
      final messages.MediaInfoMessage message = await api.getMediaInfo(path);
      return MediaInfo(
        durationMs: message.durationMs,
        widthPx: message.widthPx,
        heightPx: message.heightPx,
        rotationDegrees: message.rotationDegrees,
        sizeBytes: message.sizeBytes,
        videoCodec: message.videoCodec,
        videoBitrateBps: message.videoBitrateBps,
        frameRateFps: message.frameRateFps,
        hasAudio: message.hasAudio,
        isHdr: message.isHdr,
      );
    } on PlatformException catch (e) {
      final CompressVideoErrorReason reason = reasonFromPlatformCode(e.code);
      throw CompressVideoException(
        reason: reason,
        message: e.message ?? 'Platform error during getMediaInfo',
        platformDetail: reason == CompressVideoErrorReason.unknown
            ? e.code
            : null,
      );
    } on MissingPluginException catch (e) {
      throw CompressVideoException(
        reason: CompressVideoErrorReason.unknown,
        message: 'No platform implementation found for getMediaInfo',
        platformDetail: e.runtimeType.toString(),
      );
    }
  }
}
