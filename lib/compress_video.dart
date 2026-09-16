/// Public API for the `compress_video` Flutter plugin.
///
/// This phase ships the typed error taxonomy every later call throws and maps into, and the
/// `CompressVideo` entry point for media info. Thumbnails and compression are added by later
/// plans in this phase and in phases 2-6.
library;

import 'package:flutter/services.dart';

import 'src/compress_job.dart';
import 'src/compress_options.dart';
import 'src/compress_result.dart';
import 'src/compress_video_exception.dart';
import 'src/media_info.dart';
import 'src/messages.g.dart' as messages;
import 'src/presets.dart';

export 'src/compress_job.dart' show CompressJob;
export 'src/compress_options.dart';
export 'src/compress_result.dart';
export 'src/compress_video_exception.dart';
export 'src/media_info.dart';
export 'src/presets.dart';

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
      throw _wrapPlatformException(e, 'getMediaInfo');
    } on MissingPluginException catch (e) {
      throw _wrapMissingPlugin(e, 'getMediaInfo');
    }
  }

  /// Returns JPEG-encoded thumbnail bytes for the frame at [positionMs] milliseconds from the
  /// start of the clip at [path], on every platform -- this is the only unit `positionMs` is
  /// ever expressed in, in Dart or in native code.
  ///
  /// [quality] is JPEG quality, 1 (lowest) to 100 (highest). [maxDimensionPx] caps the longer
  /// side of the returned, displayed (rotation-corrected) frame; the frame is never upscaled,
  /// and `null` means no cap. A [positionMs] beyond the clip's duration is clamped to the last
  /// frame rather than rejected.
  ///
  /// Throws a [CompressVideoException] for every failure. A blank [path], a negative
  /// [positionMs], a [quality] outside 1 to 100, or a non-positive [maxDimensionPx] all throw
  /// with reason [CompressVideoErrorReason.unsupportedInput] before ever crossing the
  /// platform channel. This call never resolves to `null`.
  Future<Uint8List> getThumbnail(
    String path, {
    int positionMs = 0,
    int quality = 80,
    int? maxDimensionPx,
  }) async {
    _validateThumbnailArgs(
      path: path,
      positionMs: positionMs,
      quality: quality,
      maxDimensionPx: maxDimensionPx,
      outputPath: null,
    );

    final messages.ThumbnailHostApi api = messages.ThumbnailHostApi(
      binaryMessenger: _binaryMessenger,
    );

    try {
      return await api.getThumbnail(path, positionMs, quality, maxDimensionPx);
    } on PlatformException catch (e) {
      throw _wrapPlatformException(e, 'getThumbnail');
    } on MissingPluginException catch (e) {
      throw _wrapMissingPlugin(e, 'getThumbnail');
    }
  }

  /// Compresses the video at [path] per [options], returning a [CompressJob] synchronously,
  /// with no `Future` wrapping it (D-01), while the platform call proceeds in the background.
  ///
  /// [path] and [options] are validated before anything crosses the platform channel: a blank
  /// [path] and any invalid [options] combination both throw a [CompressVideoException] with
  /// reason [CompressVideoErrorReason.unsupportedInput] synchronously, from this call itself,
  /// not from the returned job's [CompressJob.result]. [options]'s preset is resolved to
  /// concrete `maxLongSidePx`/`videoBitrateBps` values here -- no preset enum crosses the
  /// channel. The returned job's [CompressJob.progress] stream and
  /// [CompressJob.result] are both fully independent of any other job; there is no global
  /// progress stream and no "is compressing" singleton anywhere in this package.
  CompressJob compress(
    String path, {
    CompressOptions options = const CompressOptions(),
  }) {
    if (path.trim().isEmpty) {
      throw const CompressVideoException(
        reason: CompressVideoErrorReason.unsupportedInput,
        message: 'path must not be empty or whitespace-only',
      );
    }
    options.validate();

    final messages.CompressHostApi api = messages.CompressHostApi(
      binaryMessenger: _binaryMessenger,
    );

    return CompressJob.start(
      api: api,
      binaryMessenger: _binaryMessenger,
      path: path,
      request: _buildRequestMessage(options),
      wrapPlatformException: _wrapPlatformException,
      wrapMissingPlugin: _wrapMissingPlugin,
    );
  }

  /// Returns a pre-flight [CompressEstimate] for compressing the video at [path] per
  /// [options], without running an actual encode, decoding a single frame, or building a
  /// native transcoder.
  ///
  /// [path] and [options] are validated exactly as they are for [compress] -- a blank [path]
  /// or an invalid [options] combination throws synchronously, before crossing the platform
  /// channel. The native side resolves [CompressEstimate] through the SAME pure resolution
  /// function [compress] itself uses, so this call and a subsequent [compress] call with the
  /// same [path]/[options] can never predict a different outcome (D-19, INFO-03).
  Future<CompressEstimate> estimate(
    String path, {
    CompressOptions options = const CompressOptions(),
  }) async {
    if (path.trim().isEmpty) {
      throw const CompressVideoException(
        reason: CompressVideoErrorReason.unsupportedInput,
        message: 'path must not be empty or whitespace-only',
      );
    }
    options.validate();

    final messages.CompressHostApi api = messages.CompressHostApi(
      binaryMessenger: _binaryMessenger,
    );

    try {
      final messages.EstimateMessage message = await api.estimate(
        path,
        _buildRequestMessage(options),
      );
      return CompressEstimate(
        outputBytes: message.outputBytes,
        durationMs: message.durationMs,
        widthPx: message.widthPx,
        heightPx: message.heightPx,
        wouldTransmux: message.wouldTransmux,
        wouldUseOriginal: message.wouldUseOriginal,
      );
    } on PlatformException catch (e) {
      throw _wrapPlatformException(e, 'estimate');
    } on MissingPluginException catch (e) {
      throw _wrapMissingPlugin(e, 'estimate');
    }
  }

  /// Deletes every file this plugin has written to its own cache directory.
  ///
  /// Not yet implemented natively on Android -- lands later in plan 02-07; until then this
  /// throws a [CompressVideoException] with reason [CompressVideoErrorReason.unsupportedInput]
  /// naming that plan, rather than being absent from the Dart API.
  Future<void> clearCache() async {
    final messages.CompressHostApi api = messages.CompressHostApi(
      binaryMessenger: _binaryMessenger,
    );

    try {
      await api.clearCache();
    } on PlatformException catch (e) {
      throw _wrapPlatformException(e, 'clearCache');
    } on MissingPluginException catch (e) {
      throw _wrapMissingPlugin(e, 'clearCache');
    }
  }

  /// Resolves [options] into the wire-level [messages.CompressRequestMessage], applying the
  /// preset (via [kPresetSpecs]) whenever the caller did not give an explicit
  /// `maxLongSidePx`/`videoBitrateBps` -- shared by [compress] and [estimate] so the two calls
  /// can never resolve the same options differently.
  messages.CompressRequestMessage _buildRequestMessage(
    CompressOptions options,
  ) {
    final PresetSpec presetSpec = kPresetSpecs[options.preset]!;

    final AudioOptions audio = options.audio;
    int? audioBitrateBps;
    int? audioChannels;
    if (audio is AudioReencode) {
      audioBitrateBps = audio.bitrateBps;
      audioChannels = audio.channels;
    }

    return messages.CompressRequestMessage(
      // Explicit-override-or-null, unlike 02-02's tracer-only shape: `SizeGuard` (native)
      // needs to tell "the caller set this" apart from "resolve it from the preset", which a
      // pre-flattened value could not express. See `presetMaxLongSidePx`/
      // `presetVideoBitrateBps` below for the preset's own reference values.
      maxLongSidePx: options.maxLongSidePx,
      videoBitrateBps: options.videoBitrateBps,
      targetSizeMb: options.targetSizeMb,
      presetMaxLongSidePx: presetSpec.maxLongSidePx,
      presetVideoBitrateBps: presetSpec.videoBitrateBps,
      maxFps: options.maxFps,
      audioMode: switch (audio.mode) {
        AudioMode.passthrough => messages.AudioModeMessage.passthrough,
        AudioMode.reencode => messages.AudioModeMessage.reencode,
        AudioMode.strip => messages.AudioModeMessage.strip,
      },
      audioBitrateBps: audioBitrateBps,
      audioChannels: audioChannels,
      trimStartMs: options.trimStartMs,
      trimEndMs: options.trimEndMs,
      outputPath: options.outputPath,
      videoCodec: options.codec.name,
      hdrMode: options.hdr.name,
    );
  }

  /// Same as [getThumbnail], but writes the JPEG to a file and returns its absolute path
  /// instead of returning bytes.
  ///
  /// With no [outputPath], the file is given a unique name inside the app's own cache
  /// directory; a call never overwrites the file a previous call wrote. With [outputPath],
  /// the file is written exactly there.
  ///
  /// Throws a [CompressVideoException] for every failure. In addition to [getThumbnail]'s
  /// validation, a blank (but non-null) [outputPath] throws
  /// [CompressVideoErrorReason.unsupportedInput] before crossing the channel; an [outputPath]
  /// whose parent directory does not exist or is not writable throws with reason
  /// [CompressVideoErrorReason.io] from the platform side, and no file is written in that
  /// case.
  Future<String> getThumbnailFile(
    String path, {
    int positionMs = 0,
    int quality = 80,
    int? maxDimensionPx,
    String? outputPath,
  }) async {
    _validateThumbnailArgs(
      path: path,
      positionMs: positionMs,
      quality: quality,
      maxDimensionPx: maxDimensionPx,
      outputPath: outputPath,
    );

    final messages.ThumbnailHostApi api = messages.ThumbnailHostApi(
      binaryMessenger: _binaryMessenger,
    );

    try {
      return await api.getThumbnailFile(
        path,
        positionMs,
        quality,
        maxDimensionPx,
        outputPath,
      );
    } on PlatformException catch (e) {
      throw _wrapPlatformException(e, 'getThumbnailFile');
    } on MissingPluginException catch (e) {
      throw _wrapMissingPlugin(e, 'getThumbnailFile');
    }
  }

  /// Validates arguments shared by [getThumbnail] and [getThumbnailFile] before either ever
  /// touches the platform channel. Mirrored on the native side (`Arguments.kt`) as the
  /// authority for any caller that reaches the channel another way.
  void _validateThumbnailArgs({
    required String path,
    required int positionMs,
    required int quality,
    required int? maxDimensionPx,
    required String? outputPath,
  }) {
    if (path.trim().isEmpty) {
      throw const CompressVideoException(
        reason: CompressVideoErrorReason.unsupportedInput,
        message: 'path must not be empty or whitespace-only',
      );
    }
    if (positionMs < 0) {
      throw const CompressVideoException(
        reason: CompressVideoErrorReason.unsupportedInput,
        message: 'positionMs must not be negative',
      );
    }
    if (quality < 1 || quality > 100) {
      throw const CompressVideoException(
        reason: CompressVideoErrorReason.unsupportedInput,
        message: 'quality must be between 1 and 100 inclusive',
      );
    }
    if (maxDimensionPx != null && maxDimensionPx <= 0) {
      throw const CompressVideoException(
        reason: CompressVideoErrorReason.unsupportedInput,
        message: 'maxDimensionPx must be positive when given',
      );
    }
    if (outputPath != null && outputPath.trim().isEmpty) {
      throw const CompressVideoException(
        reason: CompressVideoErrorReason.unsupportedInput,
        message: 'outputPath must not be blank when given',
      );
    }
  }

  /// Maps a [PlatformException] from any call into a [CompressVideoException], preserving the
  /// original platform code as [CompressVideoException.platformDetail] whenever the reason is
  /// [CompressVideoErrorReason.unknown].
  CompressVideoException _wrapPlatformException(
    PlatformException e,
    String callName,
  ) {
    final CompressVideoErrorReason reason = reasonFromPlatformCode(e.code);
    return CompressVideoException(
      reason: reason,
      message: e.message ?? 'Platform error during $callName',
      platformDetail: reason == CompressVideoErrorReason.unknown
          ? e.code
          : null,
    );
  }

  /// Maps a [MissingPluginException] (no native implementation registered) into a
  /// [CompressVideoException] with reason [CompressVideoErrorReason.unknown].
  CompressVideoException _wrapMissingPlugin(
    MissingPluginException e,
    String callName,
  ) {
    return CompressVideoException(
      reason: CompressVideoErrorReason.unknown,
      message: 'No platform implementation found for $callName',
      platformDetail: e.runtimeType.toString(),
    );
  }
}
