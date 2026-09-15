// Integration test for CompressVideo.getThumbnail and getThumbnailFile, run on a real Android
// emulator (and, once Apple simulator/device access exists, the same suite on iOS/macOS).
// Every expected value is read from the corpus sidecar's `thumbnailProbe` block, never
// hard-coded here, so this file and the sidecar can never silently drift apart.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:compress_video/compress_video.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Copies a bundled corpus asset out of [rootBundle] into a fresh temporary file and returns
/// its filesystem path, since the platform thumbnail call reads from a real file path, not
/// asset bytes.
Future<String> _copyAssetToTempFile(String assetPath, String fileName) async {
  final ByteData data = await rootBundle.load(assetPath);
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'compress_video_thumbnail_test_',
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

/// Decodes [bytes] (JPEG, in this suite) into a [ui.Image].
Future<ui.Image> _decodeImage(Uint8List bytes) async {
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  return frame.image;
}

/// Samples the RGB value at ([x], [y]) in [image] from its raw, straight-alpha RGBA bytes.
Future<List<int>> _samplePixelRgb(ui.Image image, int x, int y) async {
  final ByteData? byteData = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (byteData == null) {
    fail('Could not read raw pixel data from the decoded thumbnail');
  }
  final int offset = (y * image.width + x) * 4;
  return <int>[
    byteData.getUint8(offset),
    byteData.getUint8(offset + 1),
    byteData.getUint8(offset + 2),
  ];
}

/// Asserts that [actualRgb] matches [expectedRgb] within [tolerance] in every channel.
void _expectRgbCloseTo(
  List<int> actualRgb,
  List<dynamic> expectedRgb,
  int tolerance, {
  String? reason,
}) {
  for (int channel = 0; channel < 3; channel++) {
    expect(
      actualRgb[channel],
      closeTo((expectedRgb[channel] as num).toDouble(), tolerance.toDouble()),
      reason: reason,
    );
  }
}

/// Returns `true` if [a] and [b] differ by more than [tolerance] in at least one channel.
bool _rgbDiffersBy(List<int> a, List<int> b, int tolerance) {
  for (int channel = 0; channel < 3; channel++) {
    if ((a[channel] - b[channel]).abs() > tolerance) {
      return true;
    }
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const CompressVideo compressVideo = CompressVideo();

  testWidgets(
    'getThumbnail of the portrait clip at the sidecar position is upright, at the '
    'sidecar moment',
    (WidgetTester tester) async {
      final String path = await _copyAssetToTempFile(
        'assets/corpus/portrait_rot90.mp4',
        'portrait_rot90.mp4',
      );
      final Map<String, dynamic> sidecar = await _loadSidecar('portrait_rot90');
      final Map<String, dynamic> crossPlatform =
          sidecar['crossPlatform'] as Map<String, dynamic>;
      final Map<String, dynamic> thumbnailProbe =
          sidecar['thumbnailProbe'] as Map<String, dynamic>;

      final int positionMs = thumbnailProbe['positionMs'] as int;
      final int patchXPx = thumbnailProbe['patchXPx'] as int;
      final int patchYPx = thumbnailProbe['patchYPx'] as int;
      final List<dynamic> expectedRgb =
          thumbnailProbe['expectedRgb'] as List<dynamic>;
      final int rgbTolerance = thumbnailProbe['rgbTolerance'] as int;

      final Uint8List bytes = await compressVideo.getThumbnail(
        path,
        positionMs: positionMs,
      );
      expect(bytes, isNotEmpty);

      final ui.Image image = await _decodeImage(bytes);
      expect(
        image.height,
        greaterThan(image.width),
        reason: 'a portrait thumbnail must be taller than it is wide',
      );
      expect(image.width, crossPlatform['widthPx']);
      expect(image.height, crossPlatform['heightPx']);

      final List<int> sampledRgb = await _samplePixelRgb(
        image,
        patchXPx,
        patchYPx,
      );
      _expectRgbCloseTo(
        sampledRgb,
        expectedRgb,
        rgbTolerance,
        reason: 'sampled patch colour must match the sidecar at $positionMs ms',
      );
    },
  );

  testWidgets(
    'getThumbnail at a different moment samples a different colour than the sidecar '
    'moment',
    (WidgetTester tester) async {
      final String path = await _copyAssetToTempFile(
        'assets/corpus/portrait_rot90.mp4',
        'portrait_rot90_moment.mp4',
      );
      final Map<String, dynamic> sidecar = await _loadSidecar('portrait_rot90');
      final Map<String, dynamic> thumbnailProbe =
          sidecar['thumbnailProbe'] as Map<String, dynamic>;

      final int positionMs = thumbnailProbe['positionMs'] as int;
      final int patchXPx = thumbnailProbe['patchXPx'] as int;
      final int patchYPx = thumbnailProbe['patchYPx'] as int;
      final int rgbTolerance = thumbnailProbe['rgbTolerance'] as int;

      final Uint8List atProbeMoment = await compressVideo.getThumbnail(
        path,
        positionMs: positionMs,
      );
      final Uint8List atOtherMoment = await compressVideo.getThumbnail(
        path,
        positionMs: 1000,
      );

      final ui.Image probeImage = await _decodeImage(atProbeMoment);
      final ui.Image otherImage = await _decodeImage(atOtherMoment);

      final List<int> probeRgb = await _samplePixelRgb(
        probeImage,
        patchXPx,
        patchYPx,
      );
      final List<int> otherRgb = await _samplePixelRgb(
        otherImage,
        patchXPx,
        patchYPx,
      );

      expect(
        _rgbDiffersBy(probeRgb, otherRgb, rgbTolerance),
        isTrue,
        reason:
            'a thumbnail at 1000 ms must sample a different colour bucket than '
            'the one at $positionMs ms',
      );
    },
  );
}
