// Platform-free unit coverage of CompressVideo's Dart-side FIFO job queue and concurrency gate
// (05-01-PLAN.md task 2): default sequential ordering, a concurrency limit of 2, constructor
// validation, cancel-while-queued (05-RESEARCH.md Pitfall 1), and per-instance independence.
//
// No emulator and no real platform channel round trip: `startCompress`/`cancel` are mocked
// directly on the generated CompressHostApi channels, exactly like test/compress_job_test.dart,
// and every call is held open on a per-job Completer this file resolves by hand -- concurrency is
// asserted from the fake's own recorded call list, never from a wall-clock sleep.
import 'dart:async';

import 'package:compress_video/compress_video.dart';
import 'package:compress_video/src/compress_job.dart'
    show CompressVideoFlutterApiImpl;
import 'package:compress_video/src/messages.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _startCompressChannelName =
    'dev.flutter.pigeon.compress_video.CompressHostApi.startCompress';
const String _cancelChannelName =
    'dev.flutter.pigeon.compress_video.CompressHostApi.cancel';
const MessageCodec<Object?> _codec = CompressHostApi.pigeonChannelCodec;

CompressResultMessage _fakeResultMessage(String jobId) => CompressResultMessage(
  outputPath: '/tmp/fake-output-$jobId.mp4',
  inputBytes: 1000,
  outputBytes: 500,
  widthPx: 640,
  heightPx: 360,
  durationMs: 4000,
  videoCodec: 'h264',
  audioCodec: 'aac',
  transmuxed: false,
  usedOriginal: false,
  toneMapped: false,
  hevcFallback: false,
  audioReencoded: false,
  elapsedMs: 100,
);

/// Fakes the native side of `CompressHostApi.startCompress`/`cancel` for a whole test: records
/// the ordered sequence of job ids `startCompress` was called for, holds every call open on a
/// per-job [Completer] this file resolves by hand (with a success reply or a
/// `PlatformException`-shaped failure), and records every job id `cancel` was called for.
class _FakeCompressHost {
  final List<String> startedJobIds = <String>[];
  final List<String> cancelledJobIds = <String>[];
  final Map<String, Completer<ByteData?>> _pendingReplies =
      <String, Completer<ByteData?>>{};

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_startCompressChannelName, (
          ByteData? message,
        ) async {
          final List<Object?> args =
              _codec.decodeMessage(message)! as List<Object?>;
          final String jobId = args[1]! as String;
          startedJobIds.add(jobId);
          final Completer<ByteData?> completer = Completer<ByteData?>();
          _pendingReplies[jobId] = completer;
          return completer.future;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_cancelChannelName, (ByteData? message) async {
          final List<Object?> args =
              _codec.decodeMessage(message)! as List<Object?>;
          cancelledJobIds.add(args[0]! as String);
          return _codec.encodeMessage(<Object?>[null]);
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_startCompressChannelName, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_cancelChannelName, null);
  }

  /// Resolves [jobId]'s in-flight `startCompress` call with a successful result.
  void completeSuccess(String jobId) {
    _pendingReplies
        .remove(jobId)!
        .complete(_codec.encodeMessage(<Object?>[_fakeResultMessage(jobId)]));
  }

  /// Resolves [jobId]'s in-flight `startCompress` call with a typed failure, [reasonName]
  /// matching one of `CompressVideoErrorReason`'s value names (native code's own error-code
  /// contract).
  void completeFailure(String jobId, String reasonName) {
    _pendingReplies
        .remove(jobId)!
        .complete(
          _codec.encodeMessage(<Object?>[
            reasonName,
            'simulated platform error',
            null,
          ]),
        );
  }
}

/// Tracks one job's progress values from the moment it is created (so events emitted the instant
/// it starts, regardless of how long it waited first, are never missed) and asserts, once the job
/// settles, that this plan's queue-position invariant held: every value in 0-100, non-decreasing,
/// and the progress stream already closed by the time [CompressJob.result] settled.
class _JobInvariantTracker {
  _JobInvariantTracker(this.job) {
    _subscription = job.progress.listen(
      values.add,
      onDone: _streamDone.complete,
    );
  }

  final CompressJob job;
  final List<double> values = <double>[];
  final Completer<void> _streamDone = Completer<void>();
  late final StreamSubscription<double> _subscription;

  /// Awaits [job]'s outcome (success or failure -- both are valid terminal states for this
  /// invariant) and asserts the invariant. Returns the job's [CompressResult] on success, or
  /// `null` if the job failed/was cancelled.
  Future<CompressResult?> assertInvariant() async {
    CompressResult? result;
    try {
      result = await job.result;
    } catch (_) {
      // A failed or cancelled job still must satisfy the same progress/stream invariant.
    }
    final bool streamAlreadyDone = _streamDone.isCompleted;
    await _streamDone.future;
    await _subscription.cancel();

    for (final double value in values) {
      expect(value, inInclusiveRange(0, 100));
    }
    expect(
      values,
      List<double>.of(values)..sort(),
      reason: "job ${job.id}'s progress values must be non-decreasing",
    );
    expect(
      streamAlreadyDone,
      isTrue,
      reason:
          "job ${job.id}'s progress stream must close before or as result "
          'settles',
    );
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Matcher throwsUnsupportedInput() => throwsA(
    isA<CompressVideoException>().having(
      (CompressVideoException e) => e.reason,
      'reason',
      CompressVideoErrorReason.unsupportedInput,
    ),
  );

  group('Default limit (1): strictly one startCompress call at a time', () {
    test(
      'three submissions produce exactly one startCompress call until the first completes, '
      'then the second, then the third',
      () async {
        final _FakeCompressHost fake = _FakeCompressHost()..install();
        addTearDown(fake.uninstall);
        final CompressVideo cv = CompressVideo();

        final CompressJob jobA = cv.compress('/tmp/a.mp4');
        final CompressJob jobB = cv.compress('/tmp/b.mp4');
        final CompressJob jobC = cv.compress('/tmp/c.mp4');

        expect(jobA.isQueued, isFalse);
        expect(jobB.isQueued, isTrue);
        expect(jobC.isQueued, isTrue);
        expect(fake.startedJobIds, <String>[jobA.id]);

        fake.completeSuccess(jobA.id);
        await jobA.result;
        expect(fake.startedJobIds, <String>[jobA.id, jobB.id]);
        expect(jobB.isQueued, isFalse);

        fake.completeSuccess(jobB.id);
        await jobB.result;
        expect(fake.startedJobIds, <String>[jobA.id, jobB.id, jobC.id]);
        expect(jobC.isQueued, isFalse);

        fake.completeSuccess(jobC.id);
        await jobC.result;
      },
    );
  });

  group('Limit 2: exactly two concurrent, never three', () {
    test(
      'three submissions produce exactly two startCompress calls before any completes, and '
      'the third only after one of the first two settles',
      () async {
        final _FakeCompressHost fake = _FakeCompressHost()..install();
        addTearDown(fake.uninstall);
        final CompressVideo cv = CompressVideo(maxConcurrentJobs: 2);

        final CompressJob jobA = cv.compress('/tmp/a.mp4');
        final CompressJob jobB = cv.compress('/tmp/b.mp4');
        final CompressJob jobC = cv.compress('/tmp/c.mp4');

        expect(jobA.isQueued, isFalse);
        expect(jobB.isQueued, isFalse);
        expect(jobC.isQueued, isTrue);
        expect(fake.startedJobIds, <String>[jobA.id, jobB.id]);

        fake.completeSuccess(jobA.id);
        await jobA.result;
        expect(fake.startedJobIds, <String>[jobA.id, jobB.id, jobC.id]);
        expect(jobC.isQueued, isFalse);

        fake.completeSuccess(jobB.id);
        await jobB.result;
        fake.completeSuccess(jobC.id);
        await jobC.result;
      },
    );
  });

  group('Constructor validation', () {
    test(
      'maxConcurrentJobs of 0 or negative is rejected with reason unsupportedInput; 1 and 2 '
      'construct cleanly',
      () {
        expect(
          () => CompressVideo(maxConcurrentJobs: 0),
          throwsUnsupportedInput(),
        );
        expect(
          () => CompressVideo(maxConcurrentJobs: -1),
          throwsUnsupportedInput(),
        );
        expect(() => CompressVideo(maxConcurrentJobs: 1), returnsNormally);
        expect(() => CompressVideo(maxConcurrentJobs: 2), returnsNormally);
      },
    );
  });

  group('Cancel while queued', () {
    test(
      "a queued job's cancel() completes result as cancelled, closes its progress stream, and "
      'the fake records no startCompress and no cancel call for that job',
      () async {
        final _FakeCompressHost fake = _FakeCompressHost()..install();
        addTearDown(fake.uninstall);
        final CompressVideo cv = CompressVideo();

        final CompressJob jobA = cv.compress('/tmp/a.mp4');
        final CompressJob jobB = cv.compress('/tmp/b.mp4');
        expect(jobB.isQueued, isTrue);

        await jobB.cancel();

        await expectLater(
          () => jobB.result,
          throwsA(
            isA<CompressVideoException>().having(
              (CompressVideoException e) => e.reason,
              'reason',
              CompressVideoErrorReason.cancelled,
            ),
          ),
        );
        await expectLater(jobB.progress, emitsDone);
        expect(fake.startedJobIds, <String>[jobA.id]);
        expect(fake.cancelledJobIds, isEmpty);

        fake.completeSuccess(jobA.id);
        await jobA.result;
      },
    );

    test(
      'frees nothing it did not take: with limit 1, one running job and two queued jobs, '
      'cancelling the first queued job still lets the second queued job start the instant the '
      'running job settles -- not two at once, and not never',
      () async {
        final _FakeCompressHost fake = _FakeCompressHost()..install();
        addTearDown(fake.uninstall);
        final CompressVideo cv = CompressVideo();

        final CompressJob jobA = cv.compress('/tmp/a.mp4');
        final CompressJob jobB = cv.compress('/tmp/b.mp4');
        final CompressJob jobC = cv.compress('/tmp/c.mp4');
        expect(fake.startedJobIds, <String>[jobA.id]);
        expect(jobB.isQueued, isTrue);
        expect(jobC.isQueued, isTrue);

        await jobB.cancel();
        await expectLater(
          () => jobB.result,
          throwsA(isA<CompressVideoException>()),
        );
        // Cancelling jobB must not itself start jobC -- only jobA settling does.
        expect(fake.startedJobIds, <String>[jobA.id]);
        expect(jobC.isQueued, isTrue);

        fake.completeSuccess(jobA.id);
        await jobA.result;

        // jobC starts -- exactly one more startCompress call, never two, never none.
        expect(fake.startedJobIds, <String>[jobA.id, jobC.id]);
        expect(jobC.isQueued, isFalse);

        fake.completeSuccess(jobC.id);
        await jobC.result;
      },
    );
  });

  group('Failure and cancellation both advance the queue', () {
    test(
      'a job whose startCompress fails still lets the next queued job start',
      () async {
        final _FakeCompressHost fake = _FakeCompressHost()..install();
        addTearDown(fake.uninstall);
        final CompressVideo cv = CompressVideo();

        final CompressJob jobA = cv.compress('/tmp/a.mp4');
        final CompressJob jobB = cv.compress('/tmp/b.mp4');
        expect(fake.startedJobIds, <String>[jobA.id]);

        fake.completeFailure(jobA.id, 'io');
        await expectLater(
          () => jobA.result,
          throwsA(isA<CompressVideoException>()),
        );

        expect(fake.startedJobIds, <String>[jobA.id, jobB.id]);
        fake.completeSuccess(jobB.id);
        await jobB.result;
      },
    );

    test(
      'cancelling a running job still lets the next queued job start once it settles',
      () async {
        final _FakeCompressHost fake = _FakeCompressHost()..install();
        addTearDown(fake.uninstall);
        final CompressVideo cv = CompressVideo();

        final CompressJob jobA = cv.compress('/tmp/a.mp4');
        final CompressJob jobB = cv.compress('/tmp/b.mp4');
        expect(fake.startedJobIds, <String>[jobA.id]);

        await jobA.cancel();
        expect(fake.cancelledJobIds, <String>[jobA.id]);
        // Mirrors how native resolves the in-flight startCompress call once JobRegistry.cancel
        // completes it, exactly like test/compress_job_test.dart's own cancellation case.
        fake.completeFailure(jobA.id, 'cancelled');
        await expectLater(
          () => jobA.result,
          throwsA(
            isA<CompressVideoException>().having(
              (CompressVideoException e) => e.reason,
              'reason',
              CompressVideoErrorReason.cancelled,
            ),
          ),
        );

        expect(fake.startedJobIds, <String>[jobA.id, jobB.id]);
        fake.completeSuccess(jobB.id);
        await jobB.result;
      },
    );
  });

  group('Per-instance independence', () {
    test(
      'two CompressVideo instances each with limit 1 run one job each concurrently -- two '
      'startCompress calls in flight at once, one per instance',
      () async {
        final _FakeCompressHost fake = _FakeCompressHost()..install();
        addTearDown(fake.uninstall);
        final CompressVideo cv1 = CompressVideo();
        final CompressVideo cv2 = CompressVideo();

        final CompressJob job1 = cv1.compress('/tmp/1.mp4');
        final CompressJob job2 = cv2.compress('/tmp/2.mp4');

        expect(job1.isQueued, isFalse);
        expect(job2.isQueued, isFalse);
        expect(fake.startedJobIds, <String>[job1.id, job2.id]);

        // A second job on cv1 queues behind job1 -- cv2's own queue is untouched by it.
        final CompressJob job1b = cv1.compress('/tmp/1b.mp4');
        expect(job1b.isQueued, isTrue);
        expect(fake.startedJobIds, <String>[job1.id, job2.id]);

        fake.completeSuccess(job1.id);
        await job1.result;
        expect(fake.startedJobIds, <String>[job1.id, job2.id, job1b.id]);

        fake.completeSuccess(job2.id);
        await job2.result;
        fake.completeSuccess(job1b.id);
        await job1b.result;
      },
    );
  });

  group('Invariant across queue position', () {
    test('progress and result stay independent and well-formed for every job in a submitted set, '
        'whether it started immediately or waited', () async {
      final _FakeCompressHost fake = _FakeCompressHost()..install();
      addTearDown(fake.uninstall);
      final CompressVideo cv = CompressVideo();

      final CompressJob jobA = cv.compress('/tmp/a.mp4');
      final CompressJob jobB = cv.compress('/tmp/b.mp4');
      final _JobInvariantTracker trackerA = _JobInvariantTracker(jobA);
      final _JobInvariantTracker trackerB = _JobInvariantTracker(jobB);

      // jobA already started (front of an otherwise-empty queue); jobB has not, so no event
      // is sent for it yet -- native has no way to reference a job id it was never given a
      // platform call for.
      CompressVideoFlutterApiImpl().onProgress(jobA.id, 50.0);
      CompressVideoFlutterApiImpl().onProgress(jobA.id, 100.0);

      fake.completeSuccess(jobA.id);
      final CompressResult? resultA = await trackerA.assertInvariant();
      expect(resultA, isNotNull);

      // jobB now started; its own progress events must land on its own tracker.
      CompressVideoFlutterApiImpl().onProgress(jobB.id, 100.0);
      fake.completeSuccess(jobB.id);
      final CompressResult? resultB = await trackerB.assertInvariant();
      expect(resultB, isNotNull);

      expect(trackerA.values, <double>[50.0, 100.0]);
      expect(trackerB.values, <double>[100.0]);
      expect(resultA!.outputPath, isNot(resultB!.outputPath));
    });
  });
}
