// Integration test for CompressVideo.getMediaInfo, run on a real Android emulator (and, once
// Apple CI/device access exists, the iOS simulator). One real clip's media info travels Dart to
// Kotlin to MediaMetadataRetriever and back; every expected value is read from the corpus
// sidecar rather than hard-coded here, so this file and the sidecar can never silently drift
// apart.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:compress_video/compress_video.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const CompressVideo compressVideo = CompressVideo();

  testWidgets(
    'getMediaInfo returns rotation-corrected dimensions and duration for portrait_rot90',
    (WidgetTester tester) async {
      final String path = await _copyAssetToTempFile(
        'assets/corpus/portrait_rot90.mp4',
        'portrait_rot90.mp4',
      );
      final Map<String, dynamic> sidecar = await _loadSidecar('portrait_rot90');
      final Map<String, dynamic> expected =
          sidecar['crossPlatform'] as Map<String, dynamic>;

      final MediaInfo info = await compressVideo.getMediaInfo(path);

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
    },
  );
}
