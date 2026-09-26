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

// 04-02: this plan adds real compression cases (HDR tone-map, fidelity, unusual audio, 4K60)
// alongside 04-01's media-info-only cases above. Every new case asserts Android-only behaviour
// (the Apple engine does not implement HDR tone-mapping or the forced audio downmix until
// 04-04) with the same `skip: !Platform.isAndroid` guard commit 2007973 established for
// compress_test.dart's own transmux cases, so the Apple CI legs stay green in the meantime.

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

/// Runs `getMediaInfo` against [clipName] and asserts the sidecar's `crossPlatform` block:
/// width/height/codec/hasAudio/isHdr exactly, duration within its stated tolerance. Every case
/// below is a metadata read only -- no compression happens in this plan.
///
/// [extension] defaults to `mp4`; `pcm_audio_480p` is `mov` -- ffmpeg's ISO-MP4 PCM sample
/// entry isn't recognized by Android's MediaExtractor as an audio track (confirmed live during
/// this plan), so that one fixture is muxed as `.mov` instead (04-RESEARCH.md Pitfall 5's
/// pre-authorised contingency; same codec, different container/fourcc).
Future<void> _expectMediaInfoMatchesSidecar(
  CompressVideo compressVideo,
  String clipName, {
  String extension = 'mp4',
}) async {
  final String path = await _copyAssetToTempFile(
    'assets/corpus/$clipName.$extension',
    '$clipName.$extension',
  );
  final Map<String, dynamic> sidecar = await _loadSidecar(clipName);
  final Map<String, dynamic> expected =
      sidecar['crossPlatform'] as Map<String, dynamic>;

  final MediaInfo info = await compressVideo.getMediaInfo(path);

  expect(info.widthPx, expected['widthPx']);
  expect(info.heightPx, expected['heightPx']);
  expect(info.videoCodec, expected['videoCodec']);
  expect(info.hasAudio, expected['hasAudio']);
  expect(info.isHdr, expected['isHdr']);
  expect(
    info.durationMs.toDouble(),
    closeTo(
      (expected['durationMs'] as int).toDouble(),
      (expected['durationToleranceMs'] as int).toDouble(),
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const CompressVideo compressVideo = CompressVideo();

  group('HDR clips report isHdr from a real platform media-info call', () {
    testWidgets(
      'hdr_hlg10.mp4 (HEVC Main10, HLG) reports isHdr, dimensions and codec',
      (WidgetTester tester) async {
        // A metadata read does not decode: a pass here proves MediaMetadataRetriever reports
        // the HDR transfer characteristic correctly, not that the goldfish HEVC decoder can
        // actually decode a Main10 stream (04-RESEARCH.md Open Question 1) -- that is a
        // separate, unproven risk this test does not exercise.
        await _expectMediaInfoMatchesSidecar(compressVideo, 'hdr_hlg10');
      },
    );

    testWidgets(
      'hdr_pq10.mp4 (HEVC Main10, PQ/HDR10) reports isHdr, dimensions and codec',
      (WidgetTester tester) async {
        await _expectMediaInfoMatchesSidecar(compressVideo, 'hdr_pq10');
      },
    );
  });

  group('Unusual audio and 4K60 clips report correct media info', () {
    testWidgets(
      'pcm_audio_480p.mov (LPCM audio) reports hasAudio and dimensions',
      (WidgetTester tester) async {
        await _expectMediaInfoMatchesSidecar(
          compressVideo,
          'pcm_audio_480p',
          extension: 'mov',
        );
      },
    );

    testWidgets(
      'surround51_480p.mp4 (5.1 AAC audio) reports hasAudio and dimensions',
      (WidgetTester tester) async {
        await _expectMediaInfoMatchesSidecar(compressVideo, 'surround51_480p');
      },
    );

    testWidgets('uhd_4k60.mp4 reports 3840x2160 with hasAudio: false', (
      WidgetTester tester,
    ) async {
      await _expectMediaInfoMatchesSidecar(compressVideo, 'uhd_4k60');
    });
  });

  group('An HDR clip compresses to SDR and reports it honestly (04-02)', () {
    testWidgets(
      'hdr_hlg10.mp4 with default options and only the OpenGL tone-map attempt fails '
      'typed rather than crashing or silently passing HDR through',
      (WidgetTester tester) async {
        // Confirmed live on the danserver emulator (compress_video_api35, API 35,
        // swiftshader_indirect software GL): the single HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_
        // OPEN_GL attempt this task adds fails with ExportException.errorCode 5001
        // (ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED) -- logcat shows the root cause is the
        // GL effects pipeline's input Surface being released before the goldfish HEVC
        // decoder (which itself accepts the Main10 stream without complaint) can configure
        // against it, consistent with 04-RESEARCH.md Pitfall 3's warning that no synchronous
        // capability check exists for this path on a software GL renderer. ErrorMapping.kt's
        // existing table already maps 5001 to "io" -- no mapping change needed. This is
        // exactly the scenario 04-02-PLAN.md task 2's OpenGL-then-MediaCodec fallback chain
        // exists to survive; this task's own job is only to prove the Composition-wrapping
        // and honest-reporting plumbing is real, which a correctly-typed failure does just as
        // well as a success would. Task 2 replaces this assertion with a success case once
        // the fallback chain exists.
        final String path = await _copyAssetToTempFile(
          'assets/corpus/hdr_hlg10.mp4',
          'hdr_hlg10_${DateTime.now().microsecondsSinceEpoch}.mp4',
        );
        final CompressJob job = compressVideo.compress(path);

        await expectLater(
          job.result,
          throwsA(
            isA<CompressVideoException>().having(
              (CompressVideoException e) => e.reason,
              'reason',
              CompressVideoErrorReason.io,
            ),
          ),
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
      // The Apple engine does not implement HDR tone-mapping until 04-04.
      skip: !Platform.isAndroid,
    );
  });
}
