import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import 'compress_result.dart';
import 'compress_video_exception.dart';
import 'messages.g.dart' as messages;

/// Generates a compression job id, one per call, monotonically increasing and never reused
/// within a process's lifetime.
int _jobIdCounter = 0;
final Random _jobIdRandom = Random.secure();

/// Every [CompressJob] currently awaiting its platform reply, keyed by [CompressJob.id], so
/// [CompressVideoFlutterApiImpl.onProgress] can route an incoming progress event to the right
/// job without a global progress stream.
final Map<String, CompressJob> _jobRegistry = <String, CompressJob>{};

/// One [CompressVideoFlutterApiImpl] per distinct [BinaryMessenger], registered lazily the
/// first time a job starts on that messenger, so `messages.CompressVideoFlutterApi.setUp` is
/// called exactly once per messenger rather than once per job.
final Map<BinaryMessenger?, CompressVideoFlutterApiImpl> _flutterApiRegistry =
    <BinaryMessenger?, CompressVideoFlutterApiImpl>{};

/// Generates a job id in the format `<monotonic counter>-<16 lowercase hex characters>`.
///
/// This exact format is part of the contract, not an implementation detail: native code
/// validates an incoming job id against it before ever using the id as a filename stem.
String generateJobId() {
  final int counter = _jobIdCounter++;
  final StringBuffer hex = StringBuffer();
  for (int i = 0; i < 16; i++) {
    hex.write(_jobIdRandom.nextInt(16).toRadixString(16));
  }
  return '$counter-$hex';
}

/// Ensures a [CompressVideoFlutterApiImpl] is registered on [binaryMessenger] (the default
/// platform messenger when `null`), registering one the first time this is called for a given
/// messenger.
void _ensureFlutterApiRegistered(BinaryMessenger? binaryMessenger) {
  if (_flutterApiRegistry.containsKey(binaryMessenger)) {
    return;
  }
  final CompressVideoFlutterApiImpl impl = CompressVideoFlutterApiImpl();
  messages.CompressVideoFlutterApi.setUp(
    impl,
    binaryMessenger: binaryMessenger,
  );
  _flutterApiRegistry[binaryMessenger] = impl;
}

/// A running or finished compression job, returned synchronously by `CompressVideo.compress`
/// (D-01) while the platform call it wraps proceeds asynchronously.
///
/// There is no global progress stream and no "is compressing" singleton anywhere in this
/// package -- every [CompressJob] is fully independent, and two jobs started together never
/// share state.
class CompressJob {
  CompressJob._(this.id, this._api)
    : _progressController = StreamController<double>.broadcast();

  /// Starts a new compression job for [path] with [request] against [api] on [binaryMessenger],
  /// returning the [CompressJob] immediately -- not a `Future<CompressJob>` -- while the
  /// platform call proceeds in the background. [wrapPlatformException] and [wrapMissingPlugin]
  /// are `CompressVideo`'s own exception-mapping helpers, reused here rather than forked, so
  /// every call in the package maps a platform failure identically.
  factory CompressJob.start({
    required messages.CompressHostApi api,
    required BinaryMessenger? binaryMessenger,
    required String path,
    required messages.CompressRequestMessage request,
    required CompressVideoException Function(PlatformException, String)
    wrapPlatformException,
    required CompressVideoException Function(MissingPluginException, String)
    wrapMissingPlugin,
  }) {
    _ensureFlutterApiRegistered(binaryMessenger);
    final CompressJob job = CompressJob._(generateJobId(), api);
    _jobRegistry[job.id] = job;
    unawaited(
      job._run(path, request, wrapPlatformException, wrapMissingPlugin),
    );
    return job;
  }

  /// This job's id, in the format `<monotonic counter>-<16 lowercase hex characters>`.
  final String id;

  final messages.CompressHostApi _api;
  final StreamController<double> _progressController;
  final Completer<CompressResult> _resultCompleter =
      Completer<CompressResult>();
  bool _isCancelled = false;

  /// Progress, 0 to 100 inclusive, emitted as the job runs. A broadcast stream that closes
  /// when the job ends, whether by success, failure or cancellation.
  Stream<double> get progress => _progressController.stream;

  /// Completes with the job's [CompressResult] on success, or fails with a
  /// [CompressVideoException] on any failure (including cancellation, with reason
  /// [CompressVideoErrorReason.cancelled]). Never resolves to `null`.
  Future<CompressResult> get result => _resultCompleter.future;

  /// Whether [cancel] has been called on this job.
  bool get isCancelled => _isCancelled;

  /// Requests cancellation of this job. A no-op if the job has already finished (successfully,
  /// with a failure, or by a previous [cancel] call). Native code deletes the job's partial
  /// output and fails [result] with a cancelled [CompressVideoException]; this call only
  /// requests that and does not itself wait for [result] to complete.
  Future<void> cancel() async {
    if (_isCancelled || _resultCompleter.isCompleted) {
      return;
    }
    _isCancelled = true;
    try {
      await _api.cancel(id);
    } on PlatformException {
      // Best-effort: `result` is the authority on the eventual outcome once the in-flight
      // startCompress call itself unwinds.
    } on MissingPluginException {
      // No native implementation registered; nothing more this call can do.
    }
  }

  Future<void> _run(
    String path,
    messages.CompressRequestMessage request,
    CompressVideoException Function(PlatformException, String)
    wrapPlatformException,
    CompressVideoException Function(MissingPluginException, String)
    wrapMissingPlugin,
  ) async {
    try {
      final messages.CompressResultMessage message = await _api.startCompress(
        path,
        id,
        request,
      );
      final CompressResult compressResult = CompressResult(
        outputPath: message.outputPath,
        inputBytes: message.inputBytes,
        outputBytes: message.outputBytes,
        widthPx: message.widthPx,
        heightPx: message.heightPx,
        durationMs: message.durationMs,
        videoCodec: message.videoCodec,
        audioCodec: message.audioCodec,
        transmuxed: message.transmuxed,
        usedOriginal: message.usedOriginal,
        toneMapped: message.toneMapped,
        hevcFallback: message.hevcFallback,
        audioReencoded: message.audioReencoded,
        elapsedMs: message.elapsedMs,
      );
      if (!_resultCompleter.isCompleted) {
        _resultCompleter.complete(compressResult);
      }
    } on PlatformException catch (e) {
      _failWith(wrapPlatformException(e, 'compress'));
    } on MissingPluginException catch (e) {
      _failWith(wrapMissingPlugin(e, 'compress'));
    } finally {
      _jobRegistry.remove(id);
      if (!_progressController.isClosed) {
        await _progressController.close();
      }
    }
  }

  void _failWith(CompressVideoException exception) {
    if (!_resultCompleter.isCompleted) {
      _resultCompleter.completeError(exception);
    }
  }

  void _emitProgress(double percent) {
    if (!_progressController.isClosed) {
      _progressController.add(percent);
    }
  }
}

/// Routes `messages.CompressVideoFlutterApi.onProgress` calls to the matching [CompressJob]'s
/// progress stream, keyed by job id, dropping events for ids it does not know rather than
/// throwing -- a progress event can arrive after its job's stream already closed.
class CompressVideoFlutterApiImpl implements messages.CompressVideoFlutterApi {
  @override
  void onProgress(String jobId, double percent) {
    _jobRegistry[jobId]?._emitProgress(percent);
  }
}
