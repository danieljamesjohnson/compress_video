// Platform-free unit coverage of CompressJob and its Dart-side registry (02-06-PLAN.md task 1).
//
// No emulator and no real platform channel round trip: `startCompress` is mocked directly on
// the generated CompressHostApi channel (same pattern as test/media_info_mapping_test.dart), and
// progress events are delivered by calling `CompressVideoFlutterApiImpl.onProgress` directly --
// it is a public class over a shared, package-private job registry, so a fresh instance still
// routes into the same jobs `CompressVideo.compress` created. Nothing here reaches a Transformer
// or a Looper; every case is provable with the Dart VM alone.
import 'dart:async';

import 'package:compress_video/compress_video.dart';
import 'package:compress_video/src/compress_job.dart';
import 'package:compress_video/src/messages.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _startCompressChannelName =
    'dev.flutter.pigeon.compress_video.CompressHostApi.startCompress';
const MessageCodec<Object?> _codec = CompressHostApi.pigeonChannelCodec;

/// Installs a mock handler on the generated `startCompress` channel that never replies --
/// enough to observe a [CompressJob]'s synchronously-assigned `id` and to route progress events
/// to it, without ever resolving `result`.
void _installHangingStartCompressHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(_startCompressChannelName, (
        ByteData? message,
      ) async {
        return Completer<ByteData?>().future; // never completes
      });
}

/// Installs a mock handler that replies with [response] as soon as it is called.
void _installSucceedingStartCompressHandler(CompressResultMessage response) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(_startCompressChannelName, (
        ByteData? message,
      ) async {
        return _codec.encodeMessage(<Object?>[response]);
      });
}

/// Installs a mock handler that replies with a platform error carrying [reasonName].
void _installFailingStartCompressHandler(String reasonName) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(_startCompressChannelName, (
        ByteData? message,
      ) async {
        return _codec.encodeMessage(<Object?>[
          reasonName,
          'simulated platform error',
          null,
        ]);
      });
}

CompressResultMessage _fakeResultMessage() => CompressResultMessage(
  outputPath: '/tmp/fake-output.mp4',
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const CompressVideo compressVideo = CompressVideo();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_startCompressChannelName, null);
  });

  group('CompressJob identity', () {
    test(
      'two jobs created back to back have different ids, both matching the documented pattern',
      () {
        _installHangingStartCompressHandler();
        final CompressJob jobA = compressVideo.compress('/tmp/a.mp4');
        final CompressJob jobB = compressVideo.compress('/tmp/b.mp4');

        expect(jobA.id, isNot(jobB.id));
        final RegExp idPattern = RegExp(r'^[0-9]+-[0-9a-f]{16}$');
        expect(jobA.id, matches(idPattern));
        expect(jobB.id, matches(idPattern));
      },
    );
  });

  group('CompressVideoFlutterApiImpl progress routing', () {
    test(
      'a progress event addressed to an unknown id is dropped without throwing',
      () {
        _installHangingStartCompressHandler();
        compressVideo.compress('/tmp/a.mp4');

        expect(
          () =>
              CompressVideoFlutterApiImpl().onProgress('no-such-job-id', 42.0),
          returnsNormally,
        );
      },
    );

    test(
      "an event addressed to a known id reaches only that job's stream, never a second job's",
      () async {
        _installHangingStartCompressHandler();
        final CompressJob jobA = compressVideo.compress('/tmp/a.mp4');
        final CompressJob jobB = compressVideo.compress('/tmp/b.mp4');

        final List<double> aValues = <double>[];
        final List<double> bValues = <double>[];
        jobA.progress.listen(aValues.add);
        jobB.progress.listen(bValues.add);

        CompressVideoFlutterApiImpl().onProgress(jobA.id, 17.0);
        // Broadcast stream events are delivered asynchronously; let the microtask queue drain.
        await Future<void>.delayed(Duration.zero);

        expect(aValues, <double>[17.0]);
        expect(
          bValues,
          isEmpty,
          reason: "job B's stream must never see job A's progress events",
        );
      },
    );

    test(
      'a late progress event for an already-finished job is dropped, not added to a closed '
      'stream',
      () async {
        _installSucceedingStartCompressHandler(_fakeResultMessage());
        final CompressJob job = compressVideo.compress('/tmp/a.mp4');
        await job.result;

        expect(
          () => CompressVideoFlutterApiImpl().onProgress(job.id, 99.0),
          returnsNormally,
        );
      },
    );
  });

  group('CompressJob usable with no listener', () {
    test(
      'a job that completes successfully with no listener attached resolves its result and '
      'raises nothing',
      () async {
        _installSucceedingStartCompressHandler(_fakeResultMessage());
        final CompressJob job = compressVideo.compress('/tmp/a.mp4');

        // Deliberately never subscribe to job.progress.
        final CompressResult result = await job.result;
        expect(result.outputPath, '/tmp/fake-output.mp4');
      },
    );

    test(
      'a job that fails with no listener attached still fails result, raising nothing else',
      () async {
        _installFailingStartCompressHandler('io');
        final CompressJob job = compressVideo.compress('/tmp/a.mp4');

        await expectLater(
          () => job.result,
          throwsA(isA<CompressVideoException>()),
        );
      },
    );
  });

  group('CompressJob late subscription', () {
    test(
      "subscribing to a job's progress after it has already finished yields a stream that "
      'closes immediately rather than hanging',
      () async {
        _installSucceedingStartCompressHandler(_fakeResultMessage());
        final CompressJob job = compressVideo.compress('/tmp/a.mp4');
        await job.result;

        await expectLater(job.progress, emitsDone);
      },
    );
  });

  group('CompressJob controller closed exactly once per terminal path', () {
    test(
      'success: the progress stream closes exactly once and stays closed',
      () async {
        _installSucceedingStartCompressHandler(_fakeResultMessage());
        final CompressJob job = compressVideo.compress('/tmp/a.mp4');
        await job.result;

        // Two independent late listeners must both observe an already-closed stream -- proof
        // there is exactly one controller and it was closed once, not left half-open.
        await expectLater(job.progress, emitsDone);
        await expectLater(job.progress, emitsDone);
      },
    );

    test(
      'failure: the progress stream closes exactly once and stays closed',
      () async {
        _installFailingStartCompressHandler('unsupportedInput');
        final CompressJob job = compressVideo.compress('/tmp/a.mp4');
        await expectLater(
          () => job.result,
          throwsA(isA<CompressVideoException>()),
        );

        await expectLater(job.progress, emitsDone);
        await expectLater(job.progress, emitsDone);
      },
    );

    test(
      'cancellation: the progress stream closes exactly once and result fails as cancelled',
      () async {
        const String cancelChannelName =
            'dev.flutter.pigeon.compress_video.CompressHostApi.cancel';
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMessageHandler(cancelChannelName, (
              ByteData? message,
            ) async {
              return _codec.encodeMessage(<Object?>[null]);
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMessageHandler(cancelChannelName, null);
        });

        // The mocked startCompress reply is held open until this test decides the "native" side
        // has finished cancelling -- exactly mirroring how the real platform call stays
        // in-flight until JobRegistry.cancel resolves it.
        final Completer<ByteData?> pendingStartCompressReply =
            Completer<ByteData?>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMessageHandler(_startCompressChannelName, (
              ByteData? message,
            ) async {
              return pendingStartCompressReply.future;
            });

        final CompressJob job = compressVideo.compress('/tmp/a.mp4');
        await job.cancel();
        expect(job.isCancelled, isTrue);

        // Simulate native's own cancellation reply arriving on the still-pending startCompress
        // call, exactly as TransformerEngine.compress does when JobRegistry.cancel resolves it.
        pendingStartCompressReply.complete(
          _codec.encodeMessage(<Object?>[
            'cancelled',
            'The compression job was cancelled',
            null,
          ]),
        );

        await expectLater(
          () => job.result,
          throwsA(
            isA<CompressVideoException>().having(
              (CompressVideoException e) => e.reason,
              'reason',
              CompressVideoErrorReason.cancelled,
            ),
          ),
        );

        await expectLater(job.progress, emitsDone);
        await expectLater(job.progress, emitsDone);
      },
    );
  });
}
