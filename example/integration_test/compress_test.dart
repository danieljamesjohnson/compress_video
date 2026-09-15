// Integration test for CompressVideo.compress -- the phase's tracer: one Dart call, through the
// generated CompressHostApi, into Media3 Transformer on the emulator, and back as a typed
// result read from a re-probe of the finished file. Every expected value is read from the
// corpus sidecar rather than hard-coded here, exactly like media_info_test.dart and
// thumbnail_test.dart, so this file and the sidecar can never silently drift apart.
import 'dart:async';
import 'dart:convert';
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
    'compress_video_compress_test_',
  );
  final File file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  return file.path;
}

/// Loads and decodes the `.expected.json` sidecar for [clipName] (without extension).
Future<Map<String, dynamic>> _loadSidecar(String clipName) async {
  final String raw = await rootBundle.loadString(
    'assets/corpus/$clipName.expected.json',
  );
  return jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const CompressVideo compressVideo = CompressVideo();

  testWidgets(
    'compressing the high-bitrate portrait clip with default options produces a '
    'strictly smaller, upright, re-encoded H.264+AAC MP4',
    (WidgetTester tester) async {
      final String path = await _copyAssetToTempFile(
        'assets/corpus/portrait_hibitrate_1080p60.mp4',
        'portrait_hibitrate_1080p60.mp4',
      );
      final Map<String, dynamic> sidecar = await _loadSidecar(
        'portrait_hibitrate_1080p60',
      );
      final Map<String, dynamic> crossPlatform =
          sidecar['crossPlatform'] as Map<String, dynamic>;

      final File inputFile = File(path);
      final int inputLengthBeforeCompress = await inputFile.length();
      final DateTime inputModifiedBeforeCompress = await inputFile
          .lastModified();

      final List<double> progressValues = <double>[];
      final CompressJob job = compressVideo.compress(path);
      final StreamSubscription<double> progressSubscription = job.progress
          .listen(progressValues.add);

      final CompressResult result = await job.result;
      await progressSubscription.asFuture<void>();

      // The never-larger/remux shortcuts must not be why this passed: this is a real encode.
      expect(result.outputBytes, lessThan(result.inputBytes));
      expect(result.usedOriginal, isFalse);
      expect(result.transmuxed, isFalse);

      expect(result.inputBytes, crossPlatform['sizeBytes']);
      expect(
        result.widthPx,
        720,
        reason:
            'default p720 preset caps the long side at 1280, scaling '
            '1080x1920 displayed down to 720x1280',
      );
      expect(result.heightPx, 1280);
      expect(
        result.heightPx,
        greaterThan(result.widthPx),
        reason: 'the source is portrait; the output must stay upright',
      );
      expect(result.videoCodec, 'h264');
      expect(result.audioCodec, isNotNull);

      final int expectedDurationMs = crossPlatform['durationMs'] as int;
      final int durationToleranceMs =
          crossPlatform['durationToleranceMs'] as int;
      expect(
        result.durationMs.toDouble(),
        closeTo(expectedDurationMs.toDouble(), durationToleranceMs.toDouble()),
      );

      expect(result.elapsedMs, greaterThan(0));
      expect(result.toneMapped, isFalse);
      expect(result.hevcFallback, isFalse);

      final File outputFile = File(result.outputPath);
      expect(await outputFile.exists(), isTrue);
      expect(await outputFile.length(), result.outputBytes);

      // The input file must never be touched, including on the success path.
      expect(await inputFile.length(), inputLengthBeforeCompress);
      expect(await inputFile.lastModified(), inputModifiedBeforeCompress);

      expect(
        progressValues,
        isNotEmpty,
        reason: 'the progress stream must emit at least one value',
      );
      for (final double value in progressValues) {
        expect(value, inInclusiveRange(0, 100));
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // SizeGuard coverage (02-03-PLAN.md task 2): all four presets, an explicit long-side
  // override, an explicit bitrate override, and the frame-rate cap, all on the 60fps
  // high-bitrate clip so genuine-encode and real-shrink assertions can never pass through the
  // never-larger/usedOriginal branch by accident.
  group('SizeGuard: presets, explicit targets and the frame-rate cap', () {
    Future<String> copyHiBitrateClip() => _copyAssetToTempFile(
      'assets/corpus/portrait_hibitrate_1080p60.mp4',
      'sizeguard_hibitrate_${DateTime.now().microsecondsSinceEpoch}.mp4',
    );

    Future<void> expectPreset(
      WidgetTester tester,
      CompressPreset preset,
      int expectedWidthPx,
      int expectedHeightPx,
    ) async {
      final String path = await copyHiBitrateClip();
      final CompressJob job = compressVideo.compress(
        path,
        options: CompressOptions(preset: preset),
      );
      final CompressResult result = await job.result;
      expect(result.widthPx, expectedWidthPx, reason: '$preset width');
      expect(result.heightPx, expectedHeightPx, reason: '$preset height');
      expect(
        result.usedOriginal,
        isFalse,
        reason: '$preset must be a real encode, not the never-larger branch',
      );
      expect(
        result.outputBytes,
        lessThan(result.inputBytes),
        reason: '$preset must actually shrink the file',
      );
    }

    testWidgets(
      'p1080 keeps the source long side unchanged (no rescale) because it is exactly 1920',
      (WidgetTester tester) async {
        await expectPreset(tester, CompressPreset.p1080, 1080, 1920);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    testWidgets('p720 scales the long side down to 1280', (
      WidgetTester tester,
    ) async {
      await expectPreset(tester, CompressPreset.p720, 720, 1280);
    }, timeout: const Timeout(Duration(seconds: 20)));

    testWidgets('p480 scales the long side down to 854', (
      WidgetTester tester,
    ) async {
      await expectPreset(tester, CompressPreset.p480, 480, 854);
    }, timeout: const Timeout(Duration(seconds: 20)));

    testWidgets('p360 scales the long side down to 640', (
      WidgetTester tester,
    ) async {
      await expectPreset(tester, CompressPreset.p360, 360, 640);
    }, timeout: const Timeout(Duration(seconds: 20)));

    testWidgets(
      'an explicit maxLongSidePx of 960 produces an output whose displayed long side is '
      '960 and short side is even',
      (WidgetTester tester) async {
        final String path = await copyHiBitrateClip();
        final CompressJob job = compressVideo.compress(
          path,
          options: const CompressOptions(maxLongSidePx: 960),
        );
        final CompressResult result = await job.result;
        expect(result.heightPx, 960);
        expect(result.widthPx.isEven, isTrue);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    testWidgets(
      'an explicit videoBitrateBps of 1200000 reaches the encoder within the sidecar '
      'bitrate tolerance',
      (WidgetTester tester) async {
        final String path = await copyHiBitrateClip();
        final Map<String, dynamic> sidecar = await _loadSidecar(
          'portrait_hibitrate_1080p60',
        );
        final int tolerancePct =
            (sidecar['tolerant'] as Map<String, dynamic>)['videoBitrateTolerancePct']
                as int;

        const int requestedBitrateBps = 1200000;
        final CompressJob job = compressVideo.compress(
          path,
          options: const CompressOptions(videoBitrateBps: requestedBitrateBps),
        );
        final CompressResult result = await job.result;
        final MediaInfo outputInfo = await compressVideo.getMediaInfo(
          result.outputPath,
        );
        expect(outputInfo.videoBitrateBps, isNotNull);
        final int outputBitrateBps = outputInfo.videoBitrateBps!;
        final double deviationPct =
            (outputBitrateBps - requestedBitrateBps).abs() /
            requestedBitrateBps *
            100;
        expect(deviationPct, lessThanOrEqualTo(tolerancePct.toDouble()));
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    testWidgets(
      'default options on the 60fps clip cap the output frame rate at 30, a real '
      'comparison against the sidecar-recorded source rate of 60',
      (WidgetTester tester) async {
        final Map<String, dynamic> sidecar = await _loadSidecar(
          'portrait_hibitrate_1080p60',
        );
        final Map<String, dynamic> tolerant =
            sidecar['tolerant'] as Map<String, dynamic>;
        final double sourceFps = (tolerant['frameRateFps'] as num).toDouble();
        final double fpsToleranceFps = (tolerant['frameRateToleranceFps'] as num)
            .toDouble();
        // Sanity: this test can only prove the cap on a source above the 30fps default.
        expect(sourceFps, 60.0);

        final String path = await copyHiBitrateClip();
        final CompressJob job = compressVideo.compress(path);
        final CompressResult result = await job.result;
        final MediaInfo outputInfo = await compressVideo.getMediaInfo(
          result.outputPath,
        );
        expect(outputInfo.frameRateFps, isNotNull);
        expect(outputInfo.frameRateFps!, closeTo(30.0, fpsToleranceFps));
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    testWidgets(
      'a maxLongSidePx exactly equal to the source long side is accepted and produces '
      'identical output dimensions',
      (WidgetTester tester) async {
        final String path = await copyHiBitrateClip();
        final CompressJob job = compressVideo.compress(
          path,
          options: const CompressOptions(maxLongSidePx: 1920),
        );
        final CompressResult result = await job.result;
        expect(result.widthPx, 1080);
        expect(result.heightPx, 1920);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });

  // SizeGuard's no-upscale rules, proven against a source already smaller than every
  // preset/cap exercised here -- small_480p.mp4 is 854x480 displayed at 30fps
  // (corpus/small_480p.expected.json).
  group('SizeGuard: no-upscale rules on a source smaller than the request', () {
    Future<String> copySmallClip() => _copyAssetToTempFile(
      'assets/corpus/small_480p.mp4',
      'sizeguard_small_${DateTime.now().microsecondsSinceEpoch}.mp4',
    );

    testWidgets(
      'maxFps 60 on a 30fps source stays at 30, never upscaled',
      (WidgetTester tester) async {
        final String path = await copySmallClip();
        final CompressJob job = compressVideo.compress(
          path,
          options: const CompressOptions(maxFps: 60),
        );
        final CompressResult result = await job.result;
        final MediaInfo outputInfo = await compressVideo.getMediaInfo(
          result.outputPath,
        );
        expect(outputInfo.frameRateFps, isNotNull);
        expect(outputInfo.frameRateFps!, closeTo(30.0, 0.5));
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    testWidgets(
      'maxLongSidePx 4000 on an 854-long-side source stays at 854, never upscaled',
      (WidgetTester tester) async {
        final String path = await copySmallClip();
        final CompressJob job = compressVideo.compress(
          path,
          options: const CompressOptions(maxLongSidePx: 4000),
        );
        final CompressResult result = await job.result;
        expect(result.widthPx, 854);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });
}
