// ignore_for_file: deprecated_member_use
// Integration test for the video_compress compatibility import (06-02-PLAN.md task 2, RELS-03,
// ROADMAP Phase 6 criterion 3): an app that switches its import keeps working on the real
// engines. One case per entry point of the compat library, against Media3 Transformer and
// AVFoundation, not a fake host.
//
// This suite runs unmodified on the Android emulator, the iOS simulator and the macOS host. The
// compat library is the only plugin import here, on purpose: this file is written the way an
// app looks the day after it switched its import.
//
// Every corpus-derived expectation is read from the clip's sidecar, as in the sibling suites.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:compress_video/video_compress_compat.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Records for tool/check_parity.sh, under the "compression" top-level key (03-08, D-16), in
/// the same shape compress_test.dart uses.
///
/// Only the LowQuality compression is recorded. Its output size and duration must be the same
/// on every platform. The other cases depend on timing (progress, cancel) or on the file
/// system (thumbnail files, deleteOrigin, deleteAllCache), and have no value that should be
/// identical across platforms.
final SplayTreeMap<String, dynamic> _compressionParity =
    SplayTreeMap<String, dynamic>();

void _recordCompressionParity(
  String caseName, {
  required int widthPx,
  required int heightPx,
  required int durationMs,
  required int durationToleranceMs,
}) {
  _compressionParity[caseName] =
      SplayTreeMap<String, dynamic>.from(<String, dynamic>{
        'widthPx': widthPx,
        'heightPx': heightPx,
        'durationMs': durationMs,
        'durationToleranceMs': durationToleranceMs,
      });
}

/// Copies a bundled corpus asset into a fresh temporary file and returns its path. The plugin
/// reads a real file, not asset bytes. A case that deletes its input works on this copy, never
/// on the asset (threat T-06-08).
Future<String> _copyAssetToTempFile(String assetPath, String fileName) async {
  final ByteData data = await rootBundle.load(assetPath);
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'compress_video_compat_test_',
  );
  final File file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  return file.path;
}

Future<String> _copyClip(String clipFileName, String suffix) {
  final int dot = clipFileName.lastIndexOf('.');
  final String stem = clipFileName.substring(0, dot);
  final String extension = clipFileName.substring(dot);
  return _copyAssetToTempFile(
    'assets/corpus/$clipFileName',
    'compat_${stem}_${suffix}_${DateTime.now().microsecondsSinceEpoch}$extension',
  );
}

/// The `crossPlatform` block of the sidecar for [clipName] (without extension).
Future<Map<String, dynamic>> _loadCrossPlatform(String clipName) async {
  final String raw = await rootBundle.loadString(
    'assets/corpus/$clipName.expected.json',
  );
  final Map<String, dynamic> sidecar = jsonDecode(raw) as Map<String, dynamic>;
  return sidecar['crossPlatform'] as Map<String, dynamic>;
}

/// Whether [bytes] starts with the JPEG start-of-image marker.
bool _startsLikeJpeg(List<int> bytes) =>
    bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Path of the LowQuality case's output. The last case checks that deleteAllCache removed it.
  String? lowQualityOutputPath;

  tearDownAll(() {
    // ignore: avoid_print
    print(
      'PARITY_JSON ${jsonEncode(<String, dynamic>{'compression': _compressionParity})}',
    );
  });

  group('video_compress compat import', () {
    testWidgets('getMediaInfo returns displayed dimensions and rotation', (
      WidgetTester tester,
    ) async {
      final String path = await _copyClip('portrait_rot90.mp4', 'info');
      final Map<String, dynamic> expected = await _loadCrossPlatform(
        'portrait_rot90',
      );

      final MediaInfo info = await VideoCompress.getMediaInfo(path);

      expect(info.path, path);
      expect(info.width, expected['widthPx']);
      expect(info.height, expected['heightPx']);
      expect(info.orientation, expected['rotationDegrees']);
      expect(info.filesize, expected['sizeBytes']);
      expect(
        info.duration,
        closeTo(
          expected['durationMs'] as int,
          expected['durationToleranceMs'] as int,
        ),
      );
      expect(info.file!.path, path);
      expect(info.isCancel, isNull);
    }, timeout: const Timeout(Duration(seconds: 40)));

    testWidgets(
      'compressVideo LowQuality shrinks, reports progress and single-in-flight state',
      (WidgetTester tester) async {
        final String path = await _copyClip(
          'portrait_hibitrate_1080p60.mp4',
          'low',
        );
        final Map<String, dynamic> expected = await _loadCrossPlatform(
          'portrait_hibitrate_1080p60',
        );
        final int inputBytes = await File(path).length();

        final List<double> progressValues = <double>[];
        final Subscription subscription = VideoCompress.compressProgress$
            .subscribe(progressValues.add);
        addTearDown(subscription.unsubscribe);

        expect(VideoCompress.isCompressing, isFalse);
        final Future<MediaInfo> pending = VideoCompress.compressVideo(
          path,
          quality: VideoQuality.LowQuality,
        );
        expect(VideoCompress.isCompressing, isTrue);

        // The error is delivered through the returned Future, as video_compress did.
        await expectLater(
          VideoCompress.compressVideo(path, quality: VideoQuality.LowQuality),
          throwsStateError,
        );
        expect(
          VideoCompress.isCompressing,
          isTrue,
          reason: 'a rejected second call must not end the first one',
        );

        final MediaInfo info = await pending;
        lowQualityOutputPath = info.path;

        // A 1080x1920 portrait clip under a long-side cap of 640.
        expect(info.width, 360);
        expect(info.height, 640);
        expect(info.filesize, lessThan(inputBytes));
        expect(info.filesize, await info.file!.length());
        expect(await info.file!.exists(), isTrue);
        expect(info.path, isNot(path));
        expect(info.isCancel, isFalse);
        expect(
          info.duration,
          closeTo(
            expected['durationMs'] as int,
            expected['durationToleranceMs'] as int,
          ),
        );
        expect(
          await File(path).exists(),
          isTrue,
          reason: 'deleteOrigin is off',
        );

        expect(progressValues, isNotEmpty);
        for (final double value in progressValues) {
          expect(value, inInclusiveRange(0, 100));
        }
        expect(VideoCompress.isCompressing, isFalse);

        _recordCompressionParity(
          'compat_compress_low_quality',
          widthPx: info.width!,
          heightPx: info.height!,
          durationMs: info.duration!.round(),
          durationToleranceMs: expected['durationToleranceMs'] as int,
        );
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    testWidgets('getByteThumbnail and getFileThumbnail return JPEGs', (
      WidgetTester tester,
    ) async {
      final String path = await _copyClip('portrait_rot90.mp4', 'thumb');

      final Uint8List bytes = await VideoCompress.getByteThumbnail(
        path,
        quality: 80,
        position: 1500,
      );
      expect(_startsLikeJpeg(bytes), isTrue);

      final File file = await VideoCompress.getFileThumbnail(
        path,
        quality: 80,
        position: 1500,
      );
      expect(await file.exists(), isTrue);
      expect(_startsLikeJpeg(await file.readAsBytes()), isTrue);

      // The old default, position -1, means the first frame. It must not be rejected.
      final Uint8List firstFrame = await VideoCompress.getByteThumbnail(path);
      expect(_startsLikeJpeg(firstFrame), isTrue);
    }, timeout: const Timeout(Duration(seconds: 40)));

    testWidgets(
      'cancelCompression resolves the running compressVideo as cancelled',
      (WidgetTester tester) async {
        final String path = await _copyClip(
          'portrait_hibitrate_1080p60.mp4',
          'cancel',
        );

        final Completer<void> sawProgress = Completer<void>();
        final Subscription subscription = VideoCompress.compressProgress$
            .subscribe((double value) {
              if (value < 100 && !sawProgress.isCompleted) {
                sawProgress.complete();
              }
            });
        addTearDown(subscription.unsubscribe);

        final Future<MediaInfo> pending = VideoCompress.compressVideo(
          path,
          quality: VideoQuality.HighestQuality,
        );
        expect(VideoCompress.isCompressing, isTrue);

        // Cancel only once the engine is really running, so the cancel lands mid-flight.
        await sawProgress.future.timeout(const Duration(seconds: 30));
        await VideoCompress.cancelCompression();

        final MediaInfo info = await pending;
        expect(info.isCancel, isTrue);
        expect(info.path, isNull);
        expect(info.file, isNull);
        expect(VideoCompress.isCompressing, isFalse);
        expect(
          await File(path).exists(),
          isTrue,
          reason: 'a cancel must never touch the input',
        );

        // With nothing in flight, a cancel does nothing and does not throw.
        await VideoCompress.cancelCompression();
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    testWidgets('deleteOrigin removes the input after success', (
      WidgetTester tester,
    ) async {
      // A fresh temporary copy: the bundled asset itself is never the input.
      final String path = await _copyClip('small_480p.mp4', 'delete_origin');
      expect(await File(path).exists(), isTrue);

      final MediaInfo info = await VideoCompress.compressVideo(
        path,
        quality: VideoQuality.LowQuality,
        deleteOrigin: true,
      );

      expect(info.isCancel, isFalse);
      expect(await info.file!.exists(), isTrue);
      expect(await File(path).exists(), isFalse);
      expect(VideoCompress.isCompressing, isFalse);
    }, timeout: const Timeout(Duration(seconds: 60)));

    // Last, because it clears the cache the cases above wrote to.
    testWidgets('deleteAllCache clears compressVideo outputs', (
      WidgetTester tester,
    ) async {
      final String? outputPath = lowQualityOutputPath;
      expect(
        outputPath,
        isNotNull,
        reason: 'the LowQuality case must have run and passed first',
      );
      expect(await File(outputPath!).exists(), isTrue);

      final bool cleared = await VideoCompress.deleteAllCache();

      expect(cleared, isTrue);
      expect(await File(outputPath).exists(), isFalse);
    }, timeout: const Timeout(Duration(seconds: 40)));
  });
}
