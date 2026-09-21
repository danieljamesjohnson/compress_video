// Integration test for CompressVideo.getMediaInfo, run on a real Android emulator (and, once
// Apple CI/device access exists, the iOS simulator). Media info travels Dart to Kotlin to
// MediaMetadataRetriever/MediaExtractor and back; every expected value is read from the corpus
// sidecar rather than hard-coded here, so this file and the sidecar can never silently drift
// apart.
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:compress_video/compress_video.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Accumulates the `crossPlatform` values THIS platform actually observed for every clip in
/// the suite, so the parity gate diffs a real per-clip record instead of inferring parity from
/// two platforms merely running the same test file (01-07). Keyed by clip name, sorted, so the
/// emitted JSON is byte-comparable between the Android and iOS runs regardless of test order.
final SplayTreeMap<String, dynamic> _parityRecords =
    SplayTreeMap<String, dynamic>();

/// Rounds [durationMs] into the sidecar's own tolerance bucket so a legitimate one-millisecond
/// platform rounding difference never reads as a divergence, while a real mismatch still does.
int _bucketDuration(int durationMs, int toleranceMs) {
  if (toleranceMs <= 0) {
    return durationMs;
  }
  return (durationMs / toleranceMs).round() * toleranceMs;
}

/// Records [info]'s `crossPlatform` field set for [clipName] into [_parityRecords], with keys
/// in a fixed sorted order (via [SplayTreeMap]) so the two platforms' emitted lines are
/// directly comparable as text.
void _recordParity(
  String clipName,
  MediaInfo info,
  Map<String, dynamic> sidecar,
) {
  final int toleranceMs =
      (sidecar['crossPlatform'] as Map<String, dynamic>)['durationToleranceMs']
          as int;
  _parityRecords[clipName] =
      SplayTreeMap<String, dynamic>.from(<String, dynamic>{
        'durationMs': _bucketDuration(info.durationMs, toleranceMs),
        'hasAudio': info.hasAudio,
        'heightPx': info.heightPx,
        'isHdr': info.isHdr,
        'rotationDegrees': info.rotationDegrees,
        'sizeBytes': info.sizeBytes,
        'videoCodec': info.videoCodec,
        'widthPx': info.widthPx,
      });
}

/// Copies a bundled corpus asset out of [rootBundle] into a fresh temporary file and returns
/// its filesystem path, since the platform probe reads from a real file path, not asset bytes.
Future<String> _copyAssetToTempFile(String assetPath, String fileName) async {
  final ByteData data = await rootBundle.load(assetPath);
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'compress_video_media_info_test_',
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

/// Asserts [info] against the sidecar's `crossPlatform` block: fields every platform must
/// report identically (duration within its stated tolerance).
void _expectCrossPlatformMatches(MediaInfo info, Map<String, dynamic> sidecar) {
  final Map<String, dynamic> expected =
      sidecar['crossPlatform'] as Map<String, dynamic>;

  expect(
    info.widthPx,
    expected['widthPx'],
    reason: 'displayed width must be rotation-corrected, not the coded width',
  );
  expect(
    info.heightPx,
    expected['heightPx'],
    reason: 'displayed height must be rotation-corrected, not the coded height',
  );
  expect(info.rotationDegrees, expected['rotationDegrees']);
  expect(
    info.durationMs.toDouble(),
    closeTo(
      (expected['durationMs'] as int).toDouble(),
      (expected['durationToleranceMs'] as int).toDouble(),
    ),
  );
  expect(info.sizeBytes, expected['sizeBytes']);
  expect(info.hasAudio, expected['hasAudio']);
  expect(info.isHdr, expected['isHdr']);
  expect(info.videoCodec, expected['videoCodec']);
}

/// Asserts [info] against the sidecar's `tolerant` block: platforms may disagree on these
/// within the documented tolerance. A `null` sidecar value means "not required to be present";
/// a non-null sidecar value means this platform must also report a non-null value, within
/// tolerance.
void _expectTolerantWithinBounds(MediaInfo info, Map<String, dynamic> sidecar) {
  final Map<String, dynamic> tolerant =
      sidecar['tolerant'] as Map<String, dynamic>;

  final num? expectedBitrate = tolerant['videoBitrateBps'] as num?;
  if (expectedBitrate != null) {
    expect(
      info.videoBitrateBps,
      isNotNull,
      reason:
          'sidecar records a bitrate ground truth; this platform reported null',
    );
    final num tolerancePct = tolerant['videoBitrateTolerancePct'] as num;
    final double delta =
        expectedBitrate.toDouble() * tolerancePct.toDouble() / 100;
    expect(
      info.videoBitrateBps!.toDouble(),
      closeTo(expectedBitrate.toDouble(), delta),
    );
  }

  final num? expectedFps = tolerant['frameRateFps'] as num?;
  if (expectedFps != null) {
    expect(
      info.frameRateFps,
      isNotNull,
      reason:
          'sidecar records a frame-rate ground truth; this platform reported null',
    );
    final num fpsTolerance = tolerant['frameRateToleranceFps'] as num;
    expect(
      info.frameRateFps!,
      closeTo(expectedFps.toDouble(), fpsTolerance.toDouble()),
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const CompressVideo compressVideo = CompressVideo();

  // Emitted once, after every clip's crossPlatform assertions have run, so tool/check_parity.sh
  // (01-07) can diff exactly what this platform observed against the other platform's own
  // PARITY_JSON line from the same suite.
  tearDownAll(() {
    // ignore: avoid_print
    print('PARITY_JSON ${jsonEncode(_parityRecords)}');
  });

  for (final String clipName in <String>[
    'portrait_rot90',
    'small_480p',
    'noaudio_720p',
  ]) {
    testWidgets('getMediaInfo matches the corpus sidecar for $clipName', (
      WidgetTester tester,
    ) async {
      final String path = await _copyAssetToTempFile(
        'assets/corpus/$clipName.mp4',
        '$clipName.mp4',
      );
      final Map<String, dynamic> sidecar = await _loadSidecar(clipName);

      final MediaInfo info = await compressVideo.getMediaInfo(path);

      _expectCrossPlatformMatches(info, sidecar);
      _expectTolerantWithinBounds(info, sidecar);
      _recordParity(clipName, info, sidecar);
    });
  }

  testWidgets('a missing path yields fileNotFound', (
    WidgetTester tester,
  ) async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'compress_video_media_info_test_',
    );
    final String missingPath = '${tempDir.path}/does_not_exist.mp4';

    await expectLater(
      () => compressVideo.getMediaInfo(missingPath),
      throwsA(
        isA<CompressVideoException>().having(
          (CompressVideoException e) => e.reason,
          'reason',
          CompressVideoErrorReason.fileNotFound,
        ),
      ),
    );
  });

  testWidgets('a freshly written zero-byte file yields unsupportedInput', (
    WidgetTester tester,
  ) async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'compress_video_media_info_test_',
    );
    final File zeroByteFile = File('${tempDir.path}/empty.mp4');
    await zeroByteFile.writeAsBytes(const <int>[], flush: true);

    await expectLater(
      () => compressVideo.getMediaInfo(zeroByteFile.path),
      throwsA(
        isA<CompressVideoException>().having(
          (CompressVideoException e) => e.reason,
          'reason',
          CompressVideoErrorReason.unsupportedInput,
        ),
      ),
    );
  });

  testWidgets('a freshly written text file yields unsupportedInput', (
    WidgetTester tester,
  ) async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'compress_video_media_info_test_',
    );
    final File textFile = File('${tempDir.path}/not_a_video.txt');
    await textFile.writeAsString(
      'this is definitely not a video file',
      flush: true,
    );

    await expectLater(
      () => compressVideo.getMediaInfo(textFile.path),
      throwsA(
        isA<CompressVideoException>().having(
          (CompressVideoException e) => e.reason,
          'reason',
          CompressVideoErrorReason.unsupportedInput,
        ),
      ),
    );
  });

  testWidgets('an empty string path yields unsupportedInput', (
    WidgetTester tester,
  ) async {
    await expectLater(
      () => compressVideo.getMediaInfo(''),
      throwsA(
        isA<CompressVideoException>().having(
          (CompressVideoException e) => e.reason,
          'reason',
          CompressVideoErrorReason.unsupportedInput,
        ),
      ),
    );
  });

  testWidgets(
    'two getMediaInfo calls started together on two different clips both '
    'complete with their own correct values',
    (WidgetTester tester) async {
      final String portraitPath = await _copyAssetToTempFile(
        'assets/corpus/portrait_rot90.mp4',
        'concurrent_portrait_rot90.mp4',
      );
      final String noAudioPath = await _copyAssetToTempFile(
        'assets/corpus/noaudio_720p.mp4',
        'concurrent_noaudio_720p.mp4',
      );
      final Map<String, dynamic> portraitSidecar = await _loadSidecar(
        'portrait_rot90',
      );
      final Map<String, dynamic> noAudioSidecar = await _loadSidecar(
        'noaudio_720p',
      );

      final List<MediaInfo> results = await Future.wait(<Future<MediaInfo>>[
        compressVideo.getMediaInfo(portraitPath),
        compressVideo.getMediaInfo(noAudioPath),
      ]);

      _expectCrossPlatformMatches(results[0], portraitSidecar);
      _expectCrossPlatformMatches(results[1], noAudioSidecar);
    },
  );

  testWidgets(
    'a non-ASCII, emoji filename returns media info identical to the ASCII-named copy',
    (WidgetTester tester) async {
      final String asciiPath = await _copyAssetToTempFile(
        'assets/corpus/portrait_rot90.mp4',
        'ascii_portrait_rot90.mp4',
      );
      final String nonAsciiPath = await _copyAssetToTempFile(
        'assets/corpus/portrait_rot90.mp4',
        '日本語_🎥_portrait_rot90.mp4',
      );

      final MediaInfo asciiInfo = await compressVideo.getMediaInfo(asciiPath);
      final MediaInfo nonAsciiInfo = await compressVideo.getMediaInfo(
        nonAsciiPath,
      );

      expect(nonAsciiInfo, asciiInfo);
    },
  );
}
