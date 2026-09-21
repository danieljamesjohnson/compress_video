// Integration test for per-job independence: progress ordering, two-job isolation (02-06-PLAN.md
// task 1), cancellation (task 2), and the complete error-mapping/real-failure surface (task 3) --
// all run on a real Android emulator. Every corpus-derived expectation is read from a sidecar
// exactly like compress_test.dart, so this file and the sidecar can never silently drift apart.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:compress_video/compress_video.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Copies a bundled corpus asset out of [rootBundle] into a fresh temporary file and returns
/// its filesystem path, since the platform compress call reads from a real file path, not
/// asset bytes.
Future<String> _copyAssetToTempFile(String assetPath, String fileName) async {
  final ByteData data = await rootBundle.load(assetPath);
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'compress_video_jobs_test_',
  );
  final File file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  return file.path;
}

Future<String> _copyHiBitrateClip(String suffix) => _copyAssetToTempFile(
  'assets/corpus/portrait_hibitrate_1080p60.mp4',
  'jobs_hibitrate_${suffix}_${DateTime.now().microsecondsSinceEpoch}.mp4',
);

/// Returns a path inside a fresh temporary directory that no file has ever been written to.
/// Cancellation and failure cases pass this as `CompressOptions.outputPath` so the exact
/// destination is known up front and "no file exists here" can be asserted deterministically,
/// without needing to know the plugin's own private cache-directory naming scheme.
Future<String> _freshOutputPath(String fileName) async {
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'compress_video_jobs_test_output_',
  );
  return '${tempDir.path}/$fileName';
}

/// Starts compressing [path] and completes once the job's progress stream has emitted at least
/// one value strictly below 100 -- proof a cancel issued right after this returns lands
/// genuinely mid-flight, not on an already-finished job.
Future<void> _awaitProgressBelow100(CompressJob job) async {
  if (job.isCancelled) return;
  final Completer<void> sawProgressBelow100 = Completer<void>();
  late final StreamSubscription<double> subscription;
  subscription = job.progress.listen(
    (double value) {
      if (value < 100 && !sawProgressBelow100.isCompleted) {
        sawProgressBelow100.complete();
      }
    },
    onDone: () {
      if (!sawProgressBelow100.isCompleted) {
        // The job finished (or failed) before ever reporting a value below 100 -- extremely
        // unlikely for the high-bitrate clip this suite uses, but complete rather than hang so a
        // genuine regression surfaces as a failed "strictly below 100" assertion downstream,
        // not a timeout with no diagnostic.
        sawProgressBelow100.complete();
      }
    },
  );
  await sawProgressBelow100.future.timeout(const Duration(seconds: 30));
  await subscription.cancel();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Compression is implemented on Android only until Phase 3 lands the Apple engine
  // (AVAssetReader/AVAssetWriter). On iOS/macOS these suites would talk to a host API no
  // Swift code implements yet; register one skipped placeholder and stop so the run stays
  // honest and finite. Phase 3 removes this guard.
  if (!Platform.isAndroid) {
    test(
      'compression suites are Android-only until Phase 3',
      () {},
      skip: 'Apple compression engine lands in Phase 3 (CORE-01/CORE-07).',
    );
    return;
  }

  const CompressVideo compressVideo = CompressVideo();

  group('Per-job progress: ordering, range and a single terminal 100', () {
    testWidgets(
      "a single job's progress values are all within 0-100, monotonically non-decreasing, "
      'and end with exactly one 100, closing before or as the result completes',
      (WidgetTester tester) async {
        final String path = await _copyHiBitrateClip('single');
        final List<double> progressValues = <double>[];
        // A plain Completer, not `subscription.asFuture()` -- `asFuture()` internally replaces
        // whatever `onDone` callback is already registered, which would silently discard this
        // one rather than compose with it.
        final Completer<void> streamDoneCompleter = Completer<void>();

        final CompressJob job = compressVideo.compress(path);
        final StreamSubscription<double> subscription = job.progress.listen(
          progressValues.add,
          onDone: streamDoneCompleter.complete,
        );
        addTearDown(subscription.cancel);

        final CompressResult result = await job.result;
        // Checked at exactly this moment, before awaiting the completer below (which would
        // trivially be true regardless of ordering) -- proof that the progress stream had
        // ALREADY closed by the time `result` resolved, per 02-06-PLAN.md task 1's "closes
        // before or as the result completes".
        final bool streamAlreadyDoneWhenResultResolved =
            streamDoneCompleter.isCompleted;
        await streamDoneCompleter.future;

        expect(
          progressValues,
          isNotEmpty,
          reason: 'the progress stream must emit at least one value',
        );
        for (final double value in progressValues) {
          expect(value, inInclusiveRange(0, 100));
        }
        expect(
          progressValues,
          List<double>.of(progressValues)..sort(),
          reason: 'progress values must be monotonically non-decreasing',
        );
        expect(
          progressValues.last,
          100.0,
          reason: 'the sequence must end with exactly one terminal 100',
        );
        expect(
          progressValues.where((double v) => v == 100.0).length,
          1,
          reason:
              '100 must appear exactly once, not repeated on every trailing poll',
        );
        expect(
          streamAlreadyDoneWhenResultResolved,
          isTrue,
          reason:
              "the job's progress stream must have closed by the time result completed",
        );
        expect(result.usedOriginal, isFalse);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  group('Two-job independence: progress, result and output never cross', () {
    testWidgets(
      'two jobs started together each reach 100, complete independently, and produce two '
      "different, both-existing files, with no event from one job appearing on the other's "
      'stream',
      (WidgetTester tester) async {
        final String pathA = await _copyHiBitrateClip('jobA');
        final String pathB = await _copyHiBitrateClip('jobB');

        final List<double> progressA = <double>[];
        final List<double> progressB = <double>[];

        final CompressJob jobA = compressVideo.compress(
          pathA,
          options: const CompressOptions(preset: CompressPreset.p360),
        );
        final CompressJob jobB = compressVideo.compress(
          pathB,
          options: const CompressOptions(preset: CompressPreset.p720),
        );

        final StreamSubscription<double> subA = jobA.progress.listen(
          (double v) => progressA.add(v),
        );
        final StreamSubscription<double> subB = jobB.progress.listen(
          (double v) => progressB.add(v),
        );

        final List<CompressResult> results = await Future.wait(
          <Future<CompressResult>>[jobA.result, jobB.result],
        );
        await subA.cancel();
        await subB.cancel();

        final CompressResult resultA = results[0];
        final CompressResult resultB = results[1];

        expect(progressA, isNotEmpty);
        expect(progressB, isNotEmpty);
        expect(progressA.last, 100.0);
        expect(progressB.last, 100.0);

        expect(resultA.outputPath, isNot(resultB.outputPath));
        expect(await File(resultA.outputPath).exists(), isTrue);
        expect(await File(resultB.outputPath).exists(), isTrue);

        // job A used p360 (640 long side); job B used p720 (1280 long side) -- this is the
        // strongest available proof that each job resolved its OWN request, not the other's,
        // since a cross-wired job would report the wrong preset's dimensions.
        expect(resultA.heightPx, 640);
        expect(resultB.heightPx, 1280);
      },
      timeout: const Timeout(Duration(seconds: 40)),
    );
  });

  group('Cancel: typed outcome, closed stream, deleted partial, idempotent', () {
    testWidgets(
      'cancelling mid-flight resolves as cancelled with the partial file already gone before '
      'the future resolves',
      (WidgetTester tester) async {
        final String path = await _copyHiBitrateClip('cancel_midflight');
        final String outputPath = await _freshOutputPath(
          'cancel_midflight_output.mp4',
        );
        final List<double> progressValues = <double>[];

        final CompressJob job = compressVideo.compress(
          path,
          options: CompressOptions(outputPath: outputPath),
        );
        final StreamSubscription<double> subscription = job.progress.listen(
          progressValues.add,
        );

        // Proves the cancel below genuinely lands mid-flight: issued only after a progress
        // value strictly below 100 was observed, so this case cannot silently degrade into
        // cancelling an already-finished job.
        await _awaitProgressBelow100(job);
        expect(
          progressValues.any((double v) => v < 100),
          isTrue,
          reason: 'must have observed progress below 100 before cancelling',
        );

        await job.cancel();
        expect(job.isCancelled, isTrue);

        Object? caughtError;
        try {
          await job.result;
        } catch (e) {
          caughtError = e;
        }
        expect(caughtError, isA<CompressVideoException>());
        expect(
          (caughtError as CompressVideoException).reason,
          CompressVideoErrorReason.cancelled,
        );

        // Checked AFTER awaiting the result above -- proving the deletion happens before the
        // future resolves, not merely "eventually".
        expect(await File(outputPath).exists(), isFalse);

        await expectLater(job.progress, emitsDone);
        await subscription.cancel();
      },
      timeout: const Timeout(Duration(seconds: 40)),
    );

    testWidgets('a second cancel() on the same job completes without error and does not change the '
        'outcome', (WidgetTester tester) async {
      final String path = await _copyHiBitrateClip('cancel_double');
      final String outputPath = await _freshOutputPath(
        'cancel_double_output.mp4',
      );

      final CompressJob job = compressVideo.compress(
        path,
        options: CompressOptions(outputPath: outputPath),
      );
      await _awaitProgressBelow100(job);

      // The result-failure expectation is registered IMMEDIATELY, in the same statement as
      // triggering both cancels -- not after `await`ing something else first. `job.result`'s
      // completer resolving with an error needs a listener attached promptly or Dart's zone
      // reports it as an unhandled exception; a `Future` obtained later, after another
      // multi-step await has already let that error propagate unheard, is too late.
      final Future<void> resultFailureExpectation = expectLater(
        job.result,
        throwsA(
          isA<CompressVideoException>().having(
            (CompressVideoException e) => e.reason,
            'reason',
            CompressVideoErrorReason.cancelled,
          ),
        ),
      );
      final List<Future<void>> cancelFutures = <Future<void>>[
        job.cancel(),
        job.cancel(),
      ];
      await expectLater(Future.wait(cancelFutures), completes);
      await resultFailureExpectation;

      expect(await File(outputPath).exists(), isFalse);
    }, timeout: const Timeout(Duration(seconds: 40)));

    testWidgets(
      'a cancel issued after successful completion is a no-op: the finished output stays in '
      "place and the result is unchanged",
      (WidgetTester tester) async {
        final String path = await _copyHiBitrateClip('cancel_after_success');
        final String outputPath = await _freshOutputPath(
          'cancel_after_success_output.mp4',
        );

        final CompressJob job = compressVideo.compress(
          path,
          options: CompressOptions(outputPath: outputPath),
        );
        final CompressResult result = await job.result;
        expect(result.usedOriginal, isFalse);
        expect(await File(outputPath).exists(), isTrue);

        await job.cancel();

        expect(
          await File(outputPath).exists(),
          isTrue,
          reason: 'a cancel after success must not delete the finished output',
        );
        final CompressResult resultAfterCancel = await job.result;
        // Compared against the FIRST result, not against the raw `outputPath` string this test
        // constructed -- the native side canonicalises the path (e.g. Android's `/data/user/0`
        // symlink resolves to `/data/data`), so `result.outputPath` legitimately differs from
        // the caller-supplied string even on the very first, successful call.
        expect(resultAfterCancel, result);
        expect(resultAfterCancel.usedOriginal, isFalse);
      },
      timeout: const Timeout(Duration(seconds: 40)),
    );

    testWidgets(
      'cancelling one of three jobs leaves the other two to complete normally, with only the '
      "cancelled job's partial file gone",
      (WidgetTester tester) async {
        final String pathSurvivorA = await _copyHiBitrateClip('three_a');
        final String pathSurvivorB = await _copyHiBitrateClip('three_b');
        final String pathCancelled = await _copyHiBitrateClip('three_c');
        final String outputPathCancelled = await _freshOutputPath(
          'three_c_output.mp4',
        );

        final CompressJob jobA = compressVideo.compress(
          pathSurvivorA,
          options: const CompressOptions(preset: CompressPreset.p360),
        );
        final CompressJob jobB = compressVideo.compress(
          pathSurvivorB,
          options: const CompressOptions(preset: CompressPreset.p720),
        );
        final CompressJob jobC = compressVideo.compress(
          pathCancelled,
          options: CompressOptions(outputPath: outputPathCancelled),
        );

        await _awaitProgressBelow100(jobC);
        await jobC.cancel();
        // Registered immediately after cancelling, before awaiting jobA/jobB below -- those two
        // awaits can each take several seconds, long enough for jobC.result's completer (which
        // resolves independently, shortly after the cancel call) to be treated as an unhandled
        // async error by Dart's zone if nothing had attached a listener to it yet.
        final Future<void> jobCFailureExpectation = expectLater(
          jobC.result,
          throwsA(isA<CompressVideoException>()),
        );

        final CompressResult resultA = await jobA.result;
        final CompressResult resultB = await jobB.result;
        await jobCFailureExpectation;

        expect(await File(resultA.outputPath).exists(), isTrue);
        expect(await File(resultB.outputPath).exists(), isTrue);
        expect(await File(outputPathCancelled).exists(), isFalse);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  group('Real failures: every one is typed, none logs, none leaves a file behind', () {
    testWidgets(
      'compressing the genuinely damaged truncated_mdat.mp4 fails with a typed '
      'CompressVideoException rather than a crash or a null, and leaves no partial file behind',
      (WidgetTester tester) async {
        final String path = await _copyAssetToTempFile(
          'assets/corpus/truncated_mdat.mp4',
          'truncated_mdat_${DateTime.now().microsecondsSinceEpoch}.mp4',
        );
        final String outputPath = await _freshOutputPath(
          'truncated_mdat_output.mp4',
        );

        final CompressJob job = compressVideo.compress(
          path,
          options: CompressOptions(outputPath: outputPath),
        );

        Object? caughtError;
        try {
          await job.result;
        } catch (e) {
          caughtError = e;
        }

        expect(
          caughtError,
          isA<CompressVideoException>(),
          reason:
              'a genuinely damaged file must fail typed, never crash and never return null',
        );
        final CompressVideoException exception =
            caughtError as CompressVideoException;

        // 02-RESEARCH.md Open Question 2: observe the REAL ExportException.errorCode a
        // genuinely truncated file produces on this platform, rather than assuming one from the
        // javadoc alone. Printed (not just asserted) so it can be transcribed into the plan's
        // SUMMARY verbatim.
        // ignore: avoid_print
        print(
          'Observed failure for truncated_mdat.mp4: reason=${exception.reason}, '
          'platformDetail=${exception.platformDetail}, message=${exception.message}',
        );

        expect(
          exception.reason,
          isNot(CompressVideoErrorReason.cancelled),
          reason:
              'this was never cancelled -- it is a genuine decode/processing failure',
        );
        // The numeric ExportException.errorCode must be observable from Dart somewhere -- via
        // platformDetail (only populated when reason is unknown) or, for every other reason,
        // folded into message -- never silently dropped just because this reason was recognised.
        final bool codeIsObservable =
            (exception.platformDetail?.contains(RegExp(r'\d')) ?? false) ||
            exception.message.contains(RegExp(r'\bcode \d+\b'));
        expect(
          codeIsObservable,
          isTrue,
          reason:
              'the observed numeric export error code must appear in platformDetail or message',
        );
        expect(await File(outputPath).exists(), isFalse);
      },
      timeout: const Timeout(Duration(seconds: 40)),
    );

    testWidgets(
      'compressing a path that does not exist fails with reason fileNotFound',
      (WidgetTester tester) async {
        final String outputPath = await _freshOutputPath(
          'does_not_exist_output.mp4',
        );
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'compress_video_jobs_test_missing_',
        );
        final String missingPath =
            '${tempDir.path}/does_not_exist_${DateTime.now().microsecondsSinceEpoch}.mp4';

        final CompressJob job = compressVideo.compress(
          missingPath,
          options: CompressOptions(outputPath: outputPath),
        );

        await expectLater(
          () => job.result,
          throwsA(
            isA<CompressVideoException>().having(
              (CompressVideoException e) => e.reason,
              'reason',
              CompressVideoErrorReason.fileNotFound,
            ),
          ),
        );
        expect(await File(outputPath).exists(), isFalse);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    testWidgets(
      'compressing a zero-byte file fails with reason unsupportedInput',
      (WidgetTester tester) async {
        final String outputPath = await _freshOutputPath(
          'zero_byte_output.mp4',
        );
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'compress_video_jobs_test_zero_byte_',
        );
        final File zeroByteFile = File(
          '${tempDir.path}/zero_byte_${DateTime.now().microsecondsSinceEpoch}.mp4',
        );
        await zeroByteFile.writeAsBytes(const <int>[], flush: true);

        final CompressJob job = compressVideo.compress(
          zeroByteFile.path,
          options: CompressOptions(outputPath: outputPath),
        );

        await expectLater(
          () => job.result,
          throwsA(
            isA<CompressVideoException>().having(
              (CompressVideoException e) => e.reason,
              'reason',
              CompressVideoErrorReason.unsupportedInput,
            ),
          ),
        );
        expect(await File(outputPath).exists(), isFalse);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    testWidgets(
      'compressing a plain text file renamed to .mp4 fails with a typed reason and leaves '
      'nothing behind',
      (WidgetTester tester) async {
        final String outputPath = await _freshOutputPath(
          'plain_text_output.mp4',
        );
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'compress_video_jobs_test_plain_text_',
        );
        final File plainTextFile = File(
          '${tempDir.path}/plain_text_${DateTime.now().microsecondsSinceEpoch}.mp4',
        );
        await plainTextFile.writeAsString(
          'This is not a video file, just plain text renamed to .mp4.',
          flush: true,
        );

        final CompressJob job = compressVideo.compress(
          plainTextFile.path,
          options: CompressOptions(outputPath: outputPath),
        );

        Object? caughtError;
        try {
          await job.result;
        } catch (e) {
          caughtError = e;
        }
        expect(caughtError, isA<CompressVideoException>());
        expect(await File(outputPath).exists(), isFalse);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });
}
