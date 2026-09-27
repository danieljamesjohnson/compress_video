// Guards that keep MIGRATION.md and the code in agreement (06-02-PLAN.md task 1, RELS-03,
// D-02, D-04).
//
// Three things are checked:
//
// 1. MIGRATION.md has a table row for every public identifier of `video_compress` 3.1.4.
// 2. Each row of its `VideoQuality` table says what `VideoQuality.compressOptions` really
//    returns, and what `kPresetSpecs` really holds.
// 3. Its "switch in one line" example is the code test/video_compress_compat_snippets_test.dart
//    compiles and runs.
//
// `flutter test` runs with the package root as its working directory, so both files are read
// from disk by their relative paths.
// ignore_for_file: deprecated_member_use_from_same_package
import 'dart:io';

import 'package:compress_video/compress_video.dart' hide MediaInfo;
import 'package:compress_video/video_compress_compat.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every public identifier of `video_compress` 3.1.4 outside the `VideoQuality` values and the
/// `MediaInfo` fields.
///
/// Taken by reading .planning/research/sources/video_compress_3.1.4/lib: `video_compress.dart`
/// (the exports), `video_compressor.dart`, `video_quality.dart`, `media_data.dart`,
/// `compress_mixin.dart` and `subscription.dart`. `CompressMixin` itself is not exported, but
/// `IVideoCompress` extends it, so its members are public members of `IVideoCompress`.
const List<String> _incumbentApiIdentifiers = <String>[
  // video_compressor.dart
  'VideoCompress',
  'IVideoCompress',
  'Compress',
  'compressVideo',
  'quality',
  'deleteOrigin',
  'startTime',
  'duration',
  'includeAudio',
  'frameRate',
  'cancelCompression',
  'getMediaInfo',
  'getByteThumbnail',
  'getFileThumbnail',
  'position',
  'deleteAllCache',
  'setLogLevel',
  'dispose',
  // compress_mixin.dart
  r'compressProgress$',
  'isCompressing',
  'channel',
  'initProcessCallback',
  'setProcessingStatus',
  // subscription.dart
  'ObservableBuilder',
  'subscribe',
  'notSubscribed',
  'next',
  'Subscription',
  'unsubscribe',
  // video_quality.dart
  'VideoQuality',
  // media_data.dart
  'MediaMetadataRetriever',
  'Enum',
];

/// Every member of the incumbent's `MediaInfo`, from
/// .planning/research/sources/video_compress_3.1.4/lib/src/media/media_info.dart.
const List<String> _incumbentMediaInfoMembers = <String>[
  'path',
  'title',
  'author',
  'width',
  'height',
  'orientation',
  'filesize',
  'duration',
  'isCancel',
  'file',
  'toJson',
  'fromJson',
];

/// The first line of the incumbent README's compression snippet.
const String _switchExampleFirstLine =
    'MediaInfo mediaInfo = await VideoCompress.compressVideo(';

/// The incumbent README's compression snippet, one trimmed line per entry.
const List<String> _switchExample = <String>[
  _switchExampleFirstLine,
  'path,',
  'quality: VideoQuality.DefaultQuality,',
  "deleteOrigin: false, // It's false by default",
  ');',
];

/// A bitrate in megabits per second with no padding: `2.5 Mbps`, `5 Mbps`.
String _mbps(int bps) {
  final double mbps = bps / 1000000;
  final String text = mbps == mbps.roundToDouble()
      ? mbps.round().toString()
      : mbps.toString();
  return '$text Mbps';
}

/// The Dart expression that constructs [options], as MIGRATION.md prints it.
String _expression(CompressOptions options) {
  final int? maxLongSidePx = options.maxLongSidePx;
  final String cap = maxLongSidePx == null
      ? ''
      : ', maxLongSidePx: $maxLongSidePx';
  return 'CompressOptions(preset: CompressPreset.${options.preset.name}$cap)';
}

/// The cells of a Markdown table row, trimmed, without the empty ones outside the outer pipes.
List<String> _cells(String row) {
  final List<String> cells = row
      .split('|')
      .map((String c) => c.trim())
      .toList();
  return cells.sublist(1, cells.length - 1);
}

/// Whether [lines] holds [wanted] as one unbroken run, comparing trimmed lines.
bool _containsRun(List<String> lines, List<String> wanted) {
  final List<String> trimmed = lines.map((String l) => l.trim()).toList();
  for (int start = 0; start + wanted.length <= trimmed.length; start++) {
    bool matches = true;
    for (int i = 0; i < wanted.length; i++) {
      if (trimmed[start + i] != wanted[i]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return true;
    }
  }
  return false;
}

/// The lines of the level-2 section of [lines] whose heading starts with [headingStart], up to
/// the next level-2 heading. Each table is looked up inside its own section, because the same
/// name (`duration`, `deleteAllCache`, ...) is the first cell of a row in more than one table.
List<String> _section(List<String> lines, String headingStart) {
  final int start = lines.indexWhere((String l) => l.startsWith(headingStart));
  if (start < 0) {
    fail('MIGRATION.md has no section starting with "$headingStart"');
  }
  final int next = lines.indexWhere(
    (String l) => l.startsWith('## '),
    start + 1,
  );
  return lines.sublist(start + 1, next < 0 ? lines.length : next);
}

void main() {
  late List<String> lines;
  late List<String> apiSection;
  late List<String> mediaInfoSection;
  late List<String> qualitySection;

  setUpAll(() {
    lines = File('MIGRATION.md').readAsStringSync().split('\n');
    apiSection = _section(lines, '## 3. ');
    mediaInfoSection = _section(lines, '## 4. ');
    qualitySection = _section(lines, '## 5. ');
  });

  group('MIGRATION.md names every video_compress identifier', () {
    for (final String name in _incumbentApiIdentifiers) {
      test('`$name` has a row in the API table', () {
        expect(
          apiSection.where((String l) => l.startsWith('| `$name` |')),
          hasLength(1),
          reason: 'expected exactly one table row starting with | `$name` |',
        );
      });
    }

    for (final String name in _incumbentMediaInfoMembers) {
      test('MediaInfo `$name` has a row', () {
        expect(
          mediaInfoSection.where((String l) => l.startsWith('| `$name` |')),
          hasLength(1),
        );
      });
    }
  });

  group('MIGRATION.md VideoQuality table matches the code', () {
    test('there are eight values, as in video_compress', () {
      expect(VideoQuality.values, hasLength(8));
    });

    for (final VideoQuality quality in VideoQuality.values) {
      test('${quality.name} row says what compressOptions returns', () {
        final CompressOptions options = quality.compressOptions;
        // The row prints only `preset` and `maxLongSidePx`. If a mapping ever sets another
        // field, this fails and the table has to grow a column for it.
        expect(
          options,
          CompressOptions(
            preset: options.preset,
            maxLongSidePx: options.maxLongSidePx,
          ),
        );

        final List<String> rows = qualitySection
            .where(
              (String l) => l.startsWith('| `VideoQuality.${quality.name}` |'),
            )
            .toList();
        expect(rows, hasLength(1));
        final String row = rows.single;
        final List<String> cells = _cells(row);
        expect(cells, hasLength(7));

        final PresetSpec spec = kPresetSpecs[options.preset]!;
        expect(row, contains('CompressPreset.${options.preset.name}'));
        expect(cells[1], '`${_expression(options)}`');
        expect(cells[2], '${options.maxLongSidePx ?? spec.maxLongSidePx}');
        expect(cells[3], startsWith(_mbps(spec.videoBitrateBps)));
        if (options.maxLongSidePx == null) {
          expect(cells[3], _mbps(spec.videoBitrateBps));
        }
      });
    }
  });

  group('MIGRATION.md switch example', () {
    test('shows the compat import', () {
      expect(
        lines,
        contains("import 'package:compress_video/video_compress_compat.dart';"),
      );
      expect(
        lines,
        contains("import 'package:video_compress/video_compress.dart';"),
      );
    });

    test('has the exact first line of the README snippet, once', () {
      expect(
        lines.where((String l) => l == _switchExampleFirstLine),
        hasLength(1),
      );
    });

    test('is the code the snippet test compiles', () {
      final List<String> snippetTest = File(
        'test/video_compress_compat_snippets_test.dart',
      ).readAsStringSync().split('\n');

      expect(_containsRun(snippetTest, _switchExample), isTrue);
      expect(_containsRun(lines, _switchExample), isTrue);
    });
  });
}
