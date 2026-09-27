/// Public API for the `compress_video` Flutter plugin.
///
/// This phase ships the typed error taxonomy every later call throws and maps into, and the
/// `CompressVideo` entry point for media info. Thumbnails and compression are added by later
/// plans in this phase and in phases 2-6.
library;

import 'dart:async';
import 'dart:collection';

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
///
/// [compress] jobs submitted through one instance run through that instance's own FIFO queue,
/// gated by [maxConcurrentJobs]; two instances queue completely independently, so one instance
/// is the normal choice for an app (D-04). Because that queue is per-instance mutable state,
/// this constructor is not `const` -- see CHANGELOG.md for the migration note if an existing
/// call site declared `const CompressVideo()`.
class CompressVideo {
  /// Creates a [CompressVideo]. [binaryMessenger] is normally left `null`, which routes calls
  /// to the default host platform messenger. [maxConcurrentJobs] must be at least 1 (the
  /// default); it throws a [CompressVideoException] with reason
  /// [CompressVideoErrorReason.unsupportedInput] otherwise, matching how every other invalid
  /// argument in this package is rejected.
  CompressVideo({BinaryMessenger? binaryMessenger, this.maxConcurrentJobs = 1})
    // The public parameter name `binaryMessenger` is the documented API shape;
    // `this._binaryMessenger` would make the private field name the public parameter
    // name instead, so an initializing formal is deliberately not used here.
    // ignore: prefer_initializing_formals
    : _binaryMessenger = binaryMessenger {
    if (maxConcurrentJobs < 1) {
      throw const CompressVideoException(
        reason: CompressVideoErrorReason.unsupportedInput,
        message: 'maxConcurrentJobs must be at least 1',
      );
    }
  }

  final BinaryMessenger? _binaryMessenger;

  /// The maximum number of [compress] jobs this instance runs at once (default 1, strictly
  /// sequential). Extra submissions beyond this limit wait in FIFO submission order until a
  /// running job's [CompressJob.result] settles -- successfully, with a failure, or by
  /// cancellation -- freeing a slot for the next queued job (D-02).
  final int maxConcurrentJobs;

  /// This instance's own FIFO queue of jobs admitted but not yet started, paired with the
  /// closure that starts each one. Two [CompressVideo] instances never share a queue (D-04).
  final Queue<({CompressJob job, void Function() admit})> _pending =
      Queue<({CompressJob job, void Function() admit})>();

  /// The number of jobs from this instance currently running (admitted, not yet settled).
  /// Never exceeds [maxConcurrentJobs]. Only [_onJobSettled] decrements it, and only
  /// [_pumpQueue] increments it -- the cancel-while-queued path in [CompressJob.cancel] never
  /// touches this count, since it never incremented it either (05-RESEARCH.md Pitfall 1).
  int _activeJobCount = 0;

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
    } catch (e) {
      throw _wrapUnexpected(e, 'getMediaInfo');
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
    } catch (e) {
      throw _wrapUnexpected(e, 'getThumbnail');
    }
  }

  /// Compresses the video at [path] per [options], returning a [CompressJob] synchronously,
  /// with no `Future` wrapping it (D-01), whether it starts immediately or waits behind other
  /// jobs from this same instance.
  ///
  /// [path] and [options] are validated before anything crosses the platform channel: a blank
  /// [path] and any invalid [options] combination both throw a [CompressVideoException] with
  /// reason [CompressVideoErrorReason.unsupportedInput] synchronously, from this call itself,
  /// not from the returned job's [CompressJob.result]. [options]'s preset is resolved to
  /// concrete `maxLongSidePx`/`videoBitrateBps` values here -- no preset enum crosses the
  /// channel.
  ///
  /// The job may be queued behind earlier jobs submitted to this same instance: with the
  /// default [maxConcurrentJobs] of 1, jobs run strictly one at a time in submission order; a
  /// higher limit runs that many at once. [CompressJob.isQueued] reports whether a job is still
  /// waiting, and its [CompressJob.progress] stream emits only once it actually starts. Every
  /// job's [CompressJob.progress] and [CompressJob.result] are fully independent of every other
  /// job regardless of queue position; there is no global progress stream and no "is
  /// compressing" singleton anywhere in this package. Two [CompressVideo] instances queue
  /// completely independently (D-04).
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

    late final ({CompressJob job, void Function() admit}) entry;
    entry = createQueuedCompressJob(
      api: api,
      binaryMessenger: _binaryMessenger,
      path: path,
      request: _buildRequestMessage(options),
      wrapPlatformException: _wrapPlatformException,
      wrapMissingPlugin: _wrapMissingPlugin,
      onCancelWhileQueued: () => _pending.remove(entry),
    );
    _pending.add(entry);
    _pumpQueue();
    return entry.job;
  }

  /// Starts entries from the front of [_pending] while [_activeJobCount] is below
  /// [maxConcurrentJobs], in FIFO submission order. The only call site that increments
  /// [_activeJobCount]; [_onJobSettled] is the only one that decrements it and is what calls
  /// back in here once a running job frees its slot.
  void _pumpQueue() {
    while (_activeJobCount < maxConcurrentJobs && _pending.isNotEmpty) {
      final ({CompressJob job, void Function() admit}) entry = _pending
          .removeFirst();
      _activeJobCount++;
      entry.admit();
      unawaited(
        entry.job.result.then(
          (_) => _onJobSettled(),
          onError: (Object _, StackTrace _) => _onJobSettled(),
        ),
      );
    }
  }

  /// Frees the slot a completed, failed, or cancelled running job held, then pumps the queue
  /// again so the next waiting job (if any) can start.
  void _onJobSettled() {
    _activeJobCount--;
    _pumpQueue();
  }

  /// Makes every call in this package usable from a background isolate (one spawned with
  /// `Isolate.run`, `compute`, or any other non-root-isolate mechanism).
  ///
  /// This must be the FIRST statement inside any such isolate's callback that will use this
  /// plugin, before constructing a [CompressVideo] or calling any of its methods. [token] is
  /// obtained on the ROOT isolate with `RootIsolateToken.instance` -- that property is `null`
  /// off the root isolate, so it must be captured before spawning and passed into the
  /// closure, not looked up from inside it.
  ///
  /// Safe to call more than once per isolate. Unnecessary (and a no-op you never need to
  /// write) on the root isolate itself -- the root isolate's platform messenger is already
  /// bound. Skipping this call on a background isolate does not silently succeed: the first
  /// platform call that isolate makes through this plugin fails with a typed
  /// [CompressVideoException] rather than completing, so a caller who forgot it gets a
  /// diagnosable error rather than a hang or a `null` (see this package's background-isolate
  /// section in README.md for the observed failure shape).
  ///
  /// Example:
  /// ```dart
  /// final RootIsolateToken token = RootIsolateToken.instance!;
  /// final CompressResult result = await Isolate.run(() async {
  ///   CompressVideo.ensureInitializedInBackgroundIsolate(token);
  ///   final CompressVideo compressVideo = CompressVideo();
  ///   return compressVideo.compress(path, options: options).result;
  /// });
  /// ```
  static void ensureInitializedInBackgroundIsolate(RootIsolateToken token) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
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
    } catch (e) {
      throw _wrapUnexpected(e, 'estimate');
    }
  }

  /// Deletes every file this plugin has written to its own cache directory -- compression
  /// outputs and thumbnails alike, since both are written through the same shared cache-
  /// directory helper natively.
  ///
  /// Never touches anything outside that one directory: a file placed directly in the app's
  /// own wider cache directory, or in any other subdirectory of it, is left alone. A file a
  /// still-running [compress] job is currently writing to is also left alone -- calling this
  /// while a job is in flight never corrupts it; the job still completes normally and its
  /// reported [CompressResult.outputPath] is still readable afterwards. Succeeds as a no-op
  /// when the cache directory is empty or does not exist yet -- never an error for "nothing to
  /// delete".
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
    } catch (e) {
      throw _wrapUnexpected(e, 'clearCache');
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
    } catch (e) {
      throw _wrapUnexpected(e, 'getThumbnailFile');
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

  /// Last-resort wrap for any exception that is neither a [PlatformException] nor a
  /// [MissingPluginException] -- mirrors [CompressJob._run]'s own WR-03 catch-all. Added in
  /// 05-02 after empirically confirming a background isolate's omitted-initialisation case
  /// throws a raw `StateError` (from `BackgroundIsolateBinaryMessenger.instance` itself, before
  /// ever reaching a platform channel) that neither of the two `on` clauses above matches; every
  /// future-returning public call in this class must still resolve to a typed
  /// [CompressVideoException] rather than let that (or any other unanticipated exception type)
  /// escape untyped.
  CompressVideoException _wrapUnexpected(Object e, String callName) {
    return CompressVideoException(
      reason: CompressVideoErrorReason.unknown,
      message: 'Unexpected error during $callName',
      platformDetail: '${e.runtimeType}: $e',
    );
  }
}
