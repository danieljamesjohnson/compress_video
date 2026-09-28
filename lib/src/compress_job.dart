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
///
/// On a background isolate, registration itself is impossible, one of two ways depending on
/// whether `ensureInitializedInBackgroundIsolate` was called first:
///
/// - Called, but `BinaryMessenger.setMessageHandler` (what `messages.CompressVideoFlutterApi
///   .setUp` calls internally to receive the unsolicited `onProgress` push from native) throws
///   `UnsupportedError` on `BackgroundIsolateBinaryMessenger` unconditionally -- "Messages from
///   the host platform always go to the root isolate" (confirmed against the Flutter SDK
///   source, `_background_isolate_binary_messenger_io.dart`, during 05-02 execution).
/// - Never called at all: resolving the default messenger itself throws `StateError` first --
///   `BackgroundIsolateBinaryMessenger.instance`'s own guard for "not initialised yet" -- before
///   `setMessageHandler` is ever reached (confirmed live: the omitted-initialisation case threw
///   this, untyped, until this method also caught it).
///
/// Both are structural engine limitations, not a bug in this package, and not something a
/// `SendPort`/`ReceivePort` relay should paper over (05-RESEARCH.md's "Don't Hand-Roll" table
/// explicitly rules that out). Catching either here and continuing lets `compress()`'s actual
/// platform call proceed -- on the root isolate unaffected; on a background isolate, resolved
/// instead through `awaitCompressResult` (05-02) rather than `startCompress`'s own stranded
/// reply. The job started this way simply never receives progress events, which
/// [createQueuedCompressJob]'s caller-facing contract (see `CompressVideo.compress` dartdoc and
/// this package's README) documents rather than hides.
void _ensureFlutterApiRegistered(BinaryMessenger? binaryMessenger) {
  if (_flutterApiRegistry.containsKey(binaryMessenger)) {
    return;
  }
  final CompressVideoFlutterApiImpl impl = CompressVideoFlutterApiImpl();
  try {
    messages.CompressVideoFlutterApi.setUp(
      impl,
      binaryMessenger: binaryMessenger,
    );
  } on UnsupportedError {
    // Background isolate, initialised: no progress channel can be registered here.
  } on StateError {
    // Background isolate, never initialised: the default messenger itself is unusable. See
    // dartdoc above.
  }
  _flutterApiRegistry[binaryMessenger] = impl;
}

/// No-op default for [CompressJob._onCancelWhileQueued] -- a job created via [CompressJob.start]
/// is never in a queued state by the time a caller could observe it, so its cancel-while-queued
/// hook is never actually invoked, but the field still needs a non-null default.
void _noOpCancelWhileQueued() {}

/// Creates a [CompressJob] in a queued state -- registered in the job registry immediately (so
/// progress routing and the registry-cleanup path behave identically whether or not the job
/// ever waits) but with its platform call deferred -- and returns it together with a closure
/// that issues that deferred call.
///
/// The returned `admit` closure is deliberately NOT a member of [CompressJob]: this plan's own
/// discretion section limits the class to exactly one new public member, [CompressJob.isQueued].
/// Returning the admission capability as a plain closure lets `CompressVideo`'s queue start a
/// job it created without [CompressJob] exposing a public "start now" method any caller could
/// invoke directly on a job they merely hold a reference to.
({CompressJob job, void Function() admit}) createQueuedCompressJob({
  required messages.CompressHostApi api,
  required BinaryMessenger? binaryMessenger,
  required String path,
  required messages.CompressRequestMessage request,
  required CompressVideoException Function(PlatformException, String)
  wrapPlatformException,
  required CompressVideoException Function(MissingPluginException, String)
  wrapMissingPlugin,
  required void Function() onCancelWhileQueued,
}) {
  _ensureFlutterApiRegistered(binaryMessenger);
  final CompressJob job = CompressJob._(generateJobId(), api)
    .._onCancelWhileQueued = onCancelWhileQueued;
  _jobRegistry[job.id] = job;
  return (
    job: job,
    admit: () => job._startPlatformCall(
      path,
      request,
      wrapPlatformException,
      wrapMissingPlugin,
    ),
  );
}

/// A running or finished compression job, returned synchronously by `CompressVideo.compress`
/// (D-01) while the platform call it wraps proceeds asynchronously.
///
/// There is no global progress stream and no "is compressing" singleton anywhere in the main
/// library (both exist only in the deprecated `video_compress_compat.dart` import) -- every
/// [CompressJob] is fully independent, and two jobs started together never
/// share state. A job may sit briefly in a queued state (see [isQueued]) before its platform
/// call is issued, when `CompressVideo`'s own concurrency limit is holding it back; a job's
/// [progress] and [result] behave identically regardless of whether it started immediately or
/// waited.
class CompressJob {
  CompressJob._(this.id, this._api)
    : _progressController = StreamController<double>.broadcast();

  /// Starts a new compression job for [path] with [request] against [api] on [binaryMessenger],
  /// returning the [CompressJob] immediately -- not a `Future<CompressJob>` -- while the
  /// platform call proceeds in the background. [wrapPlatformException] and [wrapMissingPlugin]
  /// are `CompressVideo`'s own exception-mapping helpers, reused here rather than forked, so
  /// every call in the package maps a platform failure identically.
  ///
  /// This factory always issues its platform call immediately (it is never queued); it is kept
  /// alongside [createQueuedCompressJob] so this class's own construction contract does not
  /// change shape for this plan.
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
    final ({CompressJob job, void Function() admit}) queued =
        createQueuedCompressJob(
          api: api,
          binaryMessenger: binaryMessenger,
          path: path,
          request: request,
          wrapPlatformException: wrapPlatformException,
          wrapMissingPlugin: wrapMissingPlugin,
          onCancelWhileQueued: _noOpCancelWhileQueued,
        );
    queued.admit();
    return queued.job;
  }

  /// This job's id, in the format `<monotonic counter>-<16 lowercase hex characters>`.
  final String id;

  final messages.CompressHostApi _api;
  final StreamController<double> _progressController;
  final Completer<CompressResult> _resultCompleter =
      Completer<CompressResult>();
  bool _isCancelled = false;

  /// True from creation until this job's platform call is issued -- either immediately (a job
  /// created via [CompressJob.start], or one admitted the instant `CompressVideo`'s queue had a
  /// free slot) or later, once an earlier job from the same `CompressVideo` instance completes.
  bool _isQueued = true;

  /// Removes this job from `CompressVideo`'s pending queue when [cancel] is called while
  /// [isQueued] is still true. Set by [createQueuedCompressJob]; never touches the active-job
  /// count, which only the running-job completion path adjusts (05-RESEARCH.md Pitfall 1).
  void Function() _onCancelWhileQueued = _noOpCancelWhileQueued;

  /// Progress, 0 to 100 inclusive, emitted as the job runs. A broadcast stream that closes
  /// when the job ends, whether by success, failure or cancellation. Emits nothing while
  /// [isQueued] is true -- the first event only arrives once the job actually starts.
  ///
  /// For a job created on a background isolate (see
  /// `CompressVideo.ensureInitializedInBackgroundIsolate`), this stream never emits any value
  /// -- it simply closes once the job settles, exactly like a job whose progress arrived too
  /// fast to observe. This is a structural Flutter engine limitation, not a bug: a background
  /// isolate can never register a handler for native's progress push
  /// (`BackgroundIsolateBinaryMessenger.setMessageHandler` throws unconditionally off-root).
  /// [result] is unaffected -- it still resolves with the job's real, typed outcome.
  Stream<double> get progress => _progressController.stream;

  /// Completes with the job's [CompressResult] on success, or fails with a
  /// [CompressVideoException] on any failure (including cancellation, with reason
  /// [CompressVideoErrorReason.cancelled]). Never resolves to `null`.
  Future<CompressResult> get result => _resultCompleter.future;

  /// Whether [cancel] has been called on this job.
  bool get isCancelled => _isCancelled;

  /// Whether this job's platform call has not yet been issued. True from creation until
  /// `CompressVideo`'s queue admits it -- a job may report progress and resolve a result only
  /// after this becomes `false`.
  bool get isQueued => _isQueued;

  /// Requests cancellation of this job. A no-op if the job has already finished (successfully,
  /// with a failure, or by a previous [cancel] call).
  ///
  /// If the job is still [isQueued], it is removed from `CompressVideo`'s pending queue and
  /// resolved with the same typed [CompressVideoErrorReason.cancelled] failure a natively-
  /// cancelled job produces, without ever reaching the platform -- a caller cannot tell from the
  /// exception whether the job had started (D-03). Otherwise, native code deletes the job's
  /// partial output and fails [result] with a cancelled [CompressVideoException]; this call only
  /// requests that and does not itself wait for [result] to complete.
  Future<void> cancel() async {
    if (_isCancelled || _resultCompleter.isCompleted) {
      return;
    }
    _isCancelled = true;
    if (_isQueued) {
      _isQueued = false;
      _onCancelWhileQueued();
      _jobRegistry.remove(id);
      if (!_progressController.isClosed) {
        await _progressController.close();
      }
      _failWith(
        const CompressVideoException(
          reason: CompressVideoErrorReason.cancelled,
          message: 'The compression job was cancelled',
        ),
      );
      return;
    }
    try {
      await _api.cancel(id);
    } on PlatformException {
      // Best-effort: `result` is the authority on the eventual outcome once the in-flight
      // startCompress call itself unwinds.
    } on MissingPluginException {
      // No native implementation registered; nothing more this call can do.
    }
  }

  /// Issues this job's deferred platform call. A no-op if already admitted or if the job was
  /// already resolved (for example, cancelled while queued) before being admitted -- the latter
  /// should not normally happen since `CompressVideo` removes a cancelled entry from its pending
  /// queue before it can be admitted, but this guard keeps admission idempotent regardless.
  void _startPlatformCall(
    String path,
    messages.CompressRequestMessage request,
    CompressVideoException Function(PlatformException, String)
    wrapPlatformException,
    CompressVideoException Function(MissingPluginException, String)
    wrapMissingPlugin,
  ) {
    if (!_isQueued) {
      return;
    }
    _isQueued = false;
    unawaited(_run(path, request, wrapPlatformException, wrapMissingPlugin));
  }

  Future<void> _run(
    String path,
    messages.CompressRequestMessage request,
    CompressVideoException Function(PlatformException, String)
    wrapPlatformException,
    CompressVideoException Function(MissingPluginException, String)
    wrapMissingPlugin,
  ) async {
    // The eventual outcome is captured in a local rather than completing `_resultCompleter`
    // immediately on each branch, so the progress stream can be closed BEFORE `result` resolves
    // -- not merely "at some point around the same time" -- on every terminal path (02-06-PLAN.md
    // task 1's "closes before or as the result completes"). `Completer.complete` schedules its
    // listeners onto a later microtask rather than running them synchronously, so completing it
    // first and closing the stream afterwards in a `finally` block does not actually guarantee
    // an observer of `result` sees an already-closed stream; closing first and completing after
    // does.
    CompressResult? success;
    CompressVideoException? failure;
    try {
      final messages.CompressResultMessage message;
      // RootIsolateToken.instance is non-null ONLY on the root isolate (a cheap, synchronous,
      // per-isolate constant) -- the reliable way to detect this call is running off-root,
      // independent of whether ensureInitializedInBackgroundIsolate was actually called (05-02).
      if (RootIsolateToken.instance == null) {
        // startCompress's own reply is not what this branch reads: its native implementation
        // delays returning until it has attempted to deliver CompressVideoFlutterApi's progress
        // push, which no background isolate can ever register a handler for
        // (BackgroundIsolateBinaryMessenger.setMessageHandler throws unconditionally off-root).
        // This branch reads the actual outcome from the dedicated escape hatch below instead,
        // which resolves independently of that push and of startCompress's own reply.
        //
        // Native's progress push stays a direct, awaited call there (not fire-and-forget -- that
        // was tried and reverted) so a ROOT-isolate caller keeps 02-06-PLAN.md's "progress
        // reaches exactly 100 before or as result completes" guarantee; a fire-and-forget push
        // cannot promise that ordering (confirmed live: it broke compress_jobs_test.dart's
        // root-isolate cases). Off-root, that push can never be acknowledged at all, so native
        // bounds its own wait for it (TransformerEngine.PROGRESS_ACK_TIMEOUT_MS, 3s) and proceeds
        // regardless once that elapses.
        final Future<messages.CompressResultMessage> startCompressFuture = _api
            .startCompress(path, id, request);
        // Attached immediately, before anything below can throw first: a Future's error is
        // reported as "unhandled" the moment nothing has observed it, not only once its value is
        // read, so this must run even if awaitCompressResult throws before the explicit wait a
        // few lines down ever executes (Futures support multiple independent listeners, so this
        // does not interfere with that separate wait).
        unawaited(
          startCompressFuture.then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          ),
        );
        message = await _api.awaitCompressResult(id);
        // Genuinely waited for (bounded, comfortably longer than native's own
        // PROGRESS_ACK_TIMEOUT_MS bound above), not just marked handled above -- confirmed
        // empirically (05-02) that letting this isolate exit while startCompress's own reply is
        // still in flight crashes the WHOLE process natively: `[FATAL:flutter/lib/ui/window/
        // platform_message_response_dart_port.cc] Check failed: did_send.`, once Isolate.run
        // tears the isolate down before that reply can be delivered to it. The bound here is a
        // backstop, not the primary defence -- native's own bound above is what actually keeps
        // this short; this margin only protects against IPC/dispatch overhead on top of it. The
        // awaited value/error is discarded either way -- awaitCompressResult above is
        // authoritative for the result.
        try {
          await startCompressFuture.timeout(const Duration(seconds: 15));
        } catch (_) {
          // Ignore: this wait exists only to delay isolate teardown, not to source the result.
        }
      } else {
        message = await _api.startCompress(path, id, request);
      }
      success = CompressResult(
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
    } on PlatformException catch (e) {
      failure = wrapPlatformException(e, 'compress');
    } on MissingPluginException catch (e) {
      failure = wrapMissingPlugin(e, 'compress');
    } catch (e) {
      // WR-03: any other exception (for example a TypeError from a malformed Pigeon codec
      // reply) must still resolve `result` with a typed error rather than leaving it -- and
      // every caller awaiting it -- hanging forever. This is the last resort, not the normal
      // path: every documented native failure is one of the two typed exceptions above.
      failure = CompressVideoException(
        reason: CompressVideoErrorReason.unknown,
        message: 'Unexpected error during compress',
        platformDetail: '${e.runtimeType}: $e',
      );
    } finally {
      _jobRegistry.remove(id);
      if (!_progressController.isClosed) {
        await _progressController.close();
      }
    }
    if (success != null && !_resultCompleter.isCompleted) {
      _resultCompleter.complete(success);
    } else if (failure != null) {
      _failWith(failure);
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
