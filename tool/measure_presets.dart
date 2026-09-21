// Measurement harness for `doc/PRESETS.md` -- NOT part of the assertion suite (plan
// 02-04-PLAN.md task 3). It runs every `CompressPreset` against both `small_480p.mp4` and
// `portrait_hibitrate_1080p60.mp4` on a real emulator/device and prints one machine-readable
// `MEASURE ...` line per run, carrying every column `doc/PRESETS.md`'s table publishes. A
// measurement run must never fail an assertion -- a failed run produces no numbers -- so this
// file contains no `expect(...)` calls at all, only prints.
//
// This file lives in `tool/`, not `example/integration_test/`, because it is a reproducible
// measurement script, not a correctness test -- keeping it out of `integration_test/` means
// `flutter test integration_test` (the assertion suite CI and developers run routinely) never
// picks it up by directory convention. The `integration_test` package still requires a real
// Flutter app to host the binding, so running it means copying it in beside the real tests
// exactly like `corpus/sync_to_example.sh` copies corpus fixtures into `example/assets/corpus/`.
//
// To reproduce the table in doc/PRESETS.md:
//
//   cp tool/measure_presets.dart example/integration_test/measure_presets_test.dart
//   cd example
//   flutter test integration_test/measure_presets_test.dart -d <device-id>
//   rm integration_test/measure_presets_test.dart
//
// (Substitute `-d emulator-5554`, or a physical device id from `flutter devices`, for
// `<device-id>`.) Parse the `MEASURE ...` lines from stdout to rebuild the table.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:compress_video/compress_video.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<String> _copyAssetToTempFile(String assetPath, String fileName) async {
  final ByteData data = await rootBundle.load(assetPath);
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'compress_video_measure_presets_',
  );
  final File file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  return file.path;
}

Future<int> _sourceBytes(String clipName) async {
  final String raw = await rootBundle.loadString(
    'assets/corpus/$clipName.expected.json',
  );
  final Map<String, dynamic> sidecar = jsonDecode(raw) as Map<String, dynamic>;
  final Map<String, dynamic> crossPlatform =
      sidecar['crossPlatform'] as Map<String, dynamic>;
  return crossPlatform['sizeBytes'] as int;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const CompressVideo compressVideo = CompressVideo();

  const List<String> clips = <String>[
    'small_480p',
    'portrait_hibitrate_1080p60',
  ];
  const List<CompressPreset> presets = <CompressPreset>[
    CompressPreset.p360,
    CompressPreset.p480,
    CompressPreset.p720,
    CompressPreset.p1080,
  ];

  testWidgets('measure every preset on the corpus', (
    WidgetTester tester,
  ) async {
    for (final String clip in clips) {
      final int sourceBytes = await _sourceBytes(clip);
      for (final CompressPreset preset in presets) {
        final String path = await _copyAssetToTempFile(
          'assets/corpus/$clip.mp4',
          '${clip}_${preset.name}_${DateTime.now().microsecondsSinceEpoch}.mp4',
        );
        final CompressJob job = compressVideo.compress(
          path,
          options: CompressOptions(preset: preset),
        );
        final CompressResult result = await job.result;
        final MediaInfo outputInfo = await compressVideo.getMediaInfo(
          result.outputPath,
        );

        final double durationMinutes = result.durationMs / 1000.0 / 60.0;
        final double mbPerMin = durationMinutes > 0
            ? (result.outputBytes / 1000000.0) / durationMinutes
            : double.nan;

        // ignore: avoid_print
        print(
          'MEASURE preset=${preset.name} clip=$clip '
          'sourceBytes=$sourceBytes outputBytes=${result.outputBytes} '
          'widthPx=${result.widthPx} heightPx=${result.heightPx} '
          'frameRateFps=${outputInfo.frameRateFps} '
          'videoBitrateBps=${outputInfo.videoBitrateBps} '
          'elapsedMs=${result.elapsedMs} usedOriginal=${result.usedOriginal} '
          'transmuxed=${result.transmuxed} '
          'mbPerMin=${mbPerMin.toStringAsFixed(3)}',
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
