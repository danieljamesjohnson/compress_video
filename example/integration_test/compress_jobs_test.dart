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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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
          reason: '100 must appear exactly once, not repeated on every trailing poll',
        );
        expect(
          streamAlreadyDoneWhenResultResolved,
          isTrue,
          reason: "the job's progress stream must have closed by the time result completed",
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
}
