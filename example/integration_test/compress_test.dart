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
}
