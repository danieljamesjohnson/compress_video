// Generates the preset table in README.md (RELS-02, D-05).
//
// The table sits between `<!-- PRESET_TABLE_START -->` and `<!-- PRESET_TABLE_END -->` and is
// never typed by hand. It is built from three sources:
//
//   * `kPresetSpecs` (lib/src/presets.dart): each preset's longest side and bitrate target;
//   * `CompressOptions().maxFps`: the default frame rate cap;
//   * doc/PRESETS.md: what each preset produced from the 1080p60 corpus clip on Android, iOS
//     and macOS, as measured by tool/measure_presets.dart.
//
// To regenerate, from the package root:
//
//   flutter test tool/generate_preset_table.dart
//
// CI runs the same command and then `git diff --exit-code README.md`, so a preset constant or a
// measurement that changes without a regenerated README turns the build red.
//
// This runs under `flutter test` and not `dart run` because
// `package:compress_video/compress_video.dart` imports Flutter, which needs `dart:ui`. The
// rendering itself is in tool/preset_table.dart and is unit-tested by
// test/preset_table_test.dart.
import 'dart:io';

import 'package:compress_video/compress_video.dart';
import 'package:flutter_test/flutter_test.dart';

import 'preset_table.dart';

void main() {
  test('regenerate README preset table', () {
    // `flutter test` runs with the package root as its working directory.
    final File presetsMd = File('doc/PRESETS.md');
    final File readme = File('README.md');

    final MeasuredRows measured = parseMeasuredRows(
      presetsMd.readAsStringSync(),
    );
    final String table = renderPresetTable(
      specs: kPresetSpecs,
      maxFps: const CompressOptions().maxFps,
      measured: measured,
    );

    final String before = readme.readAsStringSync();
    final String after = replaceBetweenMarkers(before, table);
    if (after != before) {
      readme.writeAsStringSync(after, flush: true);
    }

    expect(readme.readAsStringSync(), after);
  });
}
