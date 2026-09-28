// Unit tests for tool/preset_table.dart: the pure parser, renderer and marker replacement behind
// the README's generated preset table (RELS-02, D-05).
//
// `flutter test` runs with the package root as its working directory, so `doc/PRESETS.md` is read
// from disk by its relative path.
import 'dart:io';

import 'package:compress_video/compress_video.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/preset_table.dart';

/// A table heading row and separator row in doc/PRESETS.md's own column order.
const String _tableHeader =
    '| Preset | Source clip | Source bytes | Output bytes | Width×Height | '
    'Frame rate (fps) | Video bitrate (bps) | Elapsed (ms) | `usedOriginal` | '
    '`transmuxed` | MB/min |\n'
    '|---|---|---|---|---|---|---|---|---|---|---|\n';

/// One measured row for [preset] on [clip].
String _row(
  String preset, {
  String clip = measuredSourceClip,
  String size = '720×1280',
  String bitrate = '1,479,121',
}) =>
    '| $preset | $clip | 4,454,349 | 814,822 | $size | 30.0 | $bitrate | 5,283 '
    '| false | false | 12.125 |\n';

/// Four rows, one per preset, leaving out any preset named in [omit].
String _rows({Set<String> omit = const <String>{}}) {
  final StringBuffer buffer = StringBuffer();
  for (final CompressPreset preset in CompressPreset.values) {
    if (!omit.contains(preset.name)) {
      buffer.write(_row(preset.name));
    }
  }
  return buffer.toString();
}

/// A minimal doc/PRESETS.md with all three tables.
String _presetsMd({
  String androidHeading = '### Measured table',
  String iosHeading = '### Measured table — iOS Simulator (software encoder)',
  String macosHeading =
      '### Measured table — macOS host (real Video Toolbox hardware encode, '
      'Apple Silicon)',
  Set<String> omitAndroid = const <String>{},
  Set<String> omitIos = const <String>{},
  Set<String> omitMacos = const <String>{},
}) =>
    '# Preset measurements\n\n'
    '## Android\n\n'
    'Some prose.\n\n'
    '$androidHeading\n\n'
    '$_tableHeader'
    '${_row('p720', clip: 'small_480p', size: '854×480', bitrate: '128,623')}'
    '${_rows(omit: omitAndroid)}\n'
    'More prose.\n\n'
    '## Apple\n\n'
    '$iosHeading\n\n'
    '$_tableHeader'
    '${_rows(omit: omitIos)}\n'
    '$macosHeading\n\n'
    '$_tableHeader'
    '${_rows(omit: omitMacos)}\n'
    'Closing prose.\n';

MeasuredRows _measured() => parseMeasuredRows(_presetsMd());

void main() {
  group('parseMeasuredRows', () {
    test(
      'reads the 1080p60 rows of all three platforms from doc/PRESETS.md',
      () {
        final MeasuredRows measured = parseMeasuredRows(
          File('doc/PRESETS.md').readAsStringSync(),
        );

        expect(measured.keys, <String>['android', 'ios', 'macos']);
        for (final String platform in measuredPlatforms) {
          expect(
            measured[platform]!.keys,
            CompressPreset.values.map((CompressPreset p) => p.name),
            reason: platform,
          );
        }

        expect(measured['android']!['p720']!.widthByHeight, '720×1280');
        expect(measured['android']!['p720']!.videoBitrateBps, 1479121);
        expect(measured['android']!['p1080']!.videoBitrateBps, 3546188);
        expect(measured['ios']!['p720']!.videoBitrateBps, 2671018);
        expect(measured['ios']!['p360']!.widthByHeight, '360×640');
        expect(measured['macos']!['p720']!.videoBitrateBps, 2586442);
        expect(measured['macos']!['p1080']!.widthByHeight, '1080×1920');
      },
    );

    test('ignores rows measured on any other source clip', () {
      final MeasuredRows measured = _measured();

      // The Android table's small_480p row says 854×480 at 128,623 bps for p720.
      expect(measured['android']!['p720']!.widthByHeight, '720×1280');
      expect(measured['android']!['p720']!.videoBitrateBps, 1479121);
    });

    test(
      'throws StateError naming the platform and preset of a missing row',
      () {
        expect(
          () => parseMeasuredRows(_presetsMd(omitIos: <String>{'p480'})),
          throwsA(
            isA<StateError>().having(
              (StateError e) => e.message,
              'message',
              allOf(contains('ios'), contains('p480')),
            ),
          ),
        );
        expect(
          () => parseMeasuredRows(_presetsMd(omitAndroid: <String>{'p1080'})),
          throwsA(
            isA<StateError>().having(
              (StateError e) => e.message,
              'message',
              allOf(contains('android'), contains('p1080')),
            ),
          ),
        );
        expect(
          () => parseMeasuredRows(_presetsMd(omitMacos: <String>{'p360'})),
          throwsA(
            isA<StateError>().having(
              (StateError e) => e.message,
              'message',
              allOf(contains('macos'), contains('p360')),
            ),
          ),
        );
      },
    );

    test('throws StateError when a heading it anchors on is absent', () {
      expect(
        () => parseMeasuredRows(_presetsMd(androidHeading: '### Numbers')),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('android'),
          ),
        ),
      );
      expect(
        () => parseMeasuredRows(
          _presetsMd(iosHeading: '### Measured table — iPhone'),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('ios'),
          ),
        ),
      );
      expect(
        () => parseMeasuredRows(
          _presetsMd(macosHeading: '### Measured table — a Mac'),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('macos'),
          ),
        ),
      );
      expect(
        () => parseMeasuredRows('# Nothing here\n'),
        throwsA(isA<StateError>()),
      );
    });

    test('does not take the Apple tables for the Android one', () {
      // With no "## Android" section the plain heading must not be looked for elsewhere.
      final String withoutAndroid = _presetsMd().replaceFirst(
        '## Android',
        '## Something else',
      );

      expect(
        () => parseMeasuredRows(withoutAndroid),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('android'),
          ),
        ),
      );
    });

    test('throws StateError on a bitrate or size cell it cannot read', () {
      final String badBitrate = _presetsMd().replaceFirst(
        '1,479,121',
        'about 1.5M',
      );
      expect(() => parseMeasuredRows(badBitrate), throwsA(isA<StateError>()));

      final String badSize = _presetsMd().replaceFirst('720×1280', '720p');
      expect(() => parseMeasuredRows(badSize), throwsA(isA<StateError>()));
    });

    test('throws StateError when a column it needs is missing', () {
      final String renamed = _presetsMd().replaceAll(
        'Video bitrate (bps)',
        'Bitrate',
      );

      expect(
        () => parseMeasuredRows(renamed),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('Video bitrate (bps)'),
          ),
        ),
      );
    });

    test('throws StateError when a preset is measured twice in one table', () {
      final String twice = _presetsMd().replaceFirst(
        _row('p360'),
        '${_row('p360')}${_row('p360')}',
      );

      expect(() => parseMeasuredRows(twice), throwsA(isA<StateError>()));
    });
  });

  group('renderPresetTable', () {
    String render({int maxFps = 30}) => renderPresetTable(
      specs: kPresetSpecs,
      maxFps: maxFps,
      measured: parseMeasuredRows(File('doc/PRESETS.md').readAsStringSync()),
    );

    test('has exactly the documented header row', () {
      expect(
        render().split('\n').first,
        '| Preset | Longest side (px) | Video bitrate target | Frame rate cap | '
        'From the 1080p60 test clip: Android emulator | '
        'From the 1080p60 test clip: iOS Simulator | '
        'From the 1080p60 test clip: macOS |',
      );
    });

    test('has one row per preset, in declaration order', () {
      final List<String> rows = render()
          .split('\n')
          .where((String line) => line.startsWith('| p'))
          .toList();

      expect(rows, hasLength(CompressPreset.values.length));
      for (int i = 0; i < rows.length; i++) {
        expect(rows[i], startsWith('| ${CompressPreset.values[i].name} |'));
      }
    });

    test('the p720 row carries the constants and the measurements', () {
      final String row = render()
          .split('\n')
          .firstWhere((String line) => line.startsWith('| p720 |'));

      expect(
        row,
        '| p720 | 1280 | 2.5 Mbps (at 30 fps) | 30 fps (never raised) | '
        '720×1280, 1.48 Mbps | 720×1280, 2.67 Mbps | 720×1280, 2.59 Mbps |',
      );
    });

    test('formats whole and fractional megabit targets without padding', () {
      final String table = render();

      expect(table, contains('| p360 | 640 | 0.8 Mbps (at 30 fps) |'));
      expect(table, contains('| p480 | 854 | 1.2 Mbps (at 30 fps) |'));
      expect(table, contains('| p1080 | 1920 | 5 Mbps (at 30 fps) |'));
    });

    test('the frame rate cap follows maxFps', () {
      expect(render(maxFps: 24), contains('| 24 fps (never raised) |'));
      expect(render(maxFps: 24), isNot(contains('| 30 fps (never raised) |')));
    });

    test('is followed by the three plain-English sentences', () {
      final String table = render();

      expect(table, contains('never upscaled'));
      expect(table, contains('generated test pattern, not camera footage'));
      expect(table, contains('software encoders, on an emulator and on a'));
      expect(table, contains('doc/PRESETS.md'));
    });

    test('is deterministic', () {
      expect(render(), render());
    });

    test('ends without a trailing newline and never contains a marker', () {
      final String table = render();

      expect(table.endsWith('\n'), isFalse);
      expect(table, isNot(contains(presetTableStart)));
      expect(table, isNot(contains(presetTableEnd)));
    });

    test('throws StateError when a preset has no spec', () {
      final Map<CompressPreset, PresetSpec> partial =
          Map<CompressPreset, PresetSpec>.of(kPresetSpecs)
            ..remove(CompressPreset.p480);

      expect(
        () => renderPresetTable(
          specs: partial,
          maxFps: 30,
          measured: _measured(),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('p480'),
          ),
        ),
      );
    });

    test('throws StateError when a measurement is missing', () {
      final MeasuredRows measured = _measured();
      final MeasuredRows withoutMacos = <String, Map<String, MeasuredRow>>{
        'android': measured['android']!,
        'ios': measured['ios']!,
      };

      expect(
        () => renderPresetTable(
          specs: kPresetSpecs,
          maxFps: 30,
          measured: withoutMacos,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('macos'),
          ),
        ),
      );
    });
  });

  group('replaceBetweenMarkers', () {
    const String readme =
        '# Title\n\nBefore.\n\n'
        '$presetTableStart\nold table\n$presetTableEnd\n\n'
        'After.\n';

    test('replaces only the text between the markers and keeps both', () {
      expect(
        replaceBetweenMarkers(readme, 'new table'),
        '# Title\n\nBefore.\n\n'
        '$presetTableStart\nnew table\n$presetTableEnd\n\n'
        'After.\n',
      );
    });

    test('fills an empty marker block', () {
      const String empty = 'A\n$presetTableStart\n$presetTableEnd\nB\n';

      expect(
        replaceBetweenMarkers(empty, 'table'),
        'A\n$presetTableStart\ntable\n$presetTableEnd\nB\n',
      );
    });

    test('is idempotent', () {
      final String once = replaceBetweenMarkers(readme, 'new table');

      expect(replaceBetweenMarkers(once, 'new table'), once);
    });

    test('throws StateError when the start marker is missing', () {
      expect(
        () => replaceBetweenMarkers('text\n$presetTableEnd\n', 'table'),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when the end marker is missing', () {
      expect(
        () => replaceBetweenMarkers('$presetTableStart\ntext\n', 'table'),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when the markers are out of order', () {
      expect(
        () => replaceBetweenMarkers(
          '$presetTableEnd\ntext\n$presetTableStart\n',
          'table',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when a marker appears twice', () {
      expect(
        () => replaceBetweenMarkers(
          '$presetTableStart\na\n$presetTableEnd\n'
              '$presetTableStart\nb\n$presetTableEnd\n',
          'table',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
