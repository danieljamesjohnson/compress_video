// Integration test for the "hard input" corpus clips Phase 4 adds: HDR (HLG, PQ), unusual
// audio (LPCM, 5.1) and a 4K60 source. All of these cases live in ONE suite (D-13) rather than
// spread across the existing ones, because they share the same media-info-only shape (no
// compression happens here yet) and the phase's own decision text calls for a single new file.
// Every expected value is read from the corpus sidecar rather than hard-coded, exactly like
// media_info_test.dart, so this file and the sidecar can never silently drift apart.
//
// This plan (04-01) does NOT emit a cross-platform parity record: the Apple engine cannot yet
// produce matching values for these clips, and the parity gate treats a case present on one
// platform only as a failure. Emission is added in 04-05, once both engines agree.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:compress_video/compress_video.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Copies a bundled corpus asset out of [rootBundle] into a fresh temporary file and returns
/// its filesystem path, since the platform probe reads from a real file path, not asset bytes.
/// This file keeps its own copy rather than sharing one with media_info_test.dart or
/// compress_audio_test.dart, per this repository's no-shared-test-helpers convention.
Future<String> _copyAssetToTempFile(String assetPath, String fileName) async {
  final ByteData data = await rootBundle.load(assetPath);
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'compress_video_hard_inputs_test_',
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

  group('HDR clips report isHdr from a real platform media-info call', () {
    testWidgets('hdr_hlg10.mp4 (HEVC Main10, HLG) reports isHdr, dimensions and codec', (
      WidgetTester tester,
    ) async {
      const String clipName = 'hdr_hlg10';
      final String path = await _copyAssetToTempFile(
        'assets/corpus/$clipName.mp4',
        '$clipName.mp4',
      );
      final Map<String, dynamic> sidecar = await _loadSidecar(clipName);
      final Map<String, dynamic> expected =
          sidecar['crossPlatform'] as Map<String, dynamic>;

      final MediaInfo info = await compressVideo.getMediaInfo(path);

      // A metadata read does not decode: a pass here proves MediaMetadataRetriever reports the
      // HDR transfer characteristic correctly, not that the goldfish HEVC decoder can actually
      // decode a Main10 stream (04-RESEARCH.md Open Question 1) -- that is a separate, unproven
      // risk this test does not exercise.
      expect(info.isHdr, expected['isHdr']);
      expect(info.widthPx, expected['widthPx']);
      expect(info.heightPx, expected['heightPx']);
      expect(info.videoCodec, expected['videoCodec']);
      expect(
        info.durationMs.toDouble(),
        closeTo(
          (expected['durationMs'] as int).toDouble(),
          (expected['durationToleranceMs'] as int).toDouble(),
        ),
      );
    });
  });
}
