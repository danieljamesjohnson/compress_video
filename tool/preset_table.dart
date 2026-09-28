// Pure parsing and rendering behind the README's generated preset table (RELS-02, D-05, D-12).
//
// Nothing here touches the filesystem: `tool/generate_preset_table.dart` does the reading and
// writing, and `test/preset_table_test.dart` exercises these functions with hand-built inputs.
//
// This library imports `package:compress_video/compress_video.dart` for the `CompressPreset` and
// `PresetSpec` types. That package needs `dart:ui`, so both callers run under `flutter test`.
import 'package:compress_video/compress_video.dart';

/// Opens the generated block in README.md. Only the generator writes after this line.
const String presetTableStart = '<!-- PRESET_TABLE_START -->';

/// Closes the generated block in README.md. Only the generator writes before this line.
const String presetTableEnd = '<!-- PRESET_TABLE_END -->';

/// The corpus clip whose measured rows the README quotes: a portrait 1080p clip at 60 fps,
/// which every preset has to re-encode.
const String measuredSourceClip = 'portrait_hibitrate_1080p60';

/// The frame rate every `PresetSpec.videoBitrateBps` is stated at.
const int presetNominalFps = 30;

/// The platforms the README table has a column for, in column order.
const List<String> measuredPlatforms = <String>['android', 'ios', 'macos'];

/// What one preset produced from [measuredSourceClip] on one platform.
typedef MeasuredRow = ({String widthByHeight, int videoBitrateBps});

/// Measured rows by platform (one of [measuredPlatforms]), then by preset name.
typedef MeasuredRows = Map<String, Map<String, MeasuredRow>>;

const String _presetColumn = 'Preset';
const String _sourceClipColumn = 'Source clip';
const String _sizeColumn = 'Width×Height';
const String _bitrateColumn = 'Video bitrate (bps)';

final RegExp _sizePattern = RegExp(r'^\d+×\d+$');
final RegExp _bitratePattern = RegExp(r'^\d{1,3}(,\d{3})*$|^\d+$');

/// Reads the [measuredSourceClip] rows of doc/PRESETS.md's three measured tables.
///
/// The Android table is the first `### Measured table` line under `## Android`. The Apple tables
/// are the lines starting `### Measured table — iOS Simulator` and
/// `### Measured table — macOS host`.
///
/// Throws [StateError] when a heading or a column is absent, when a cell cannot be read, and
/// when any platform lacks a row for any [CompressPreset]. The error names the platform and the
/// preset. A partial table is never returned.
MeasuredRows parseMeasuredRows(String presetsMd) {
  final List<String> lines = presetsMd.split('\n');
  final MeasuredRows measured = <String, Map<String, MeasuredRow>>{};
  for (final String platform in measuredPlatforms) {
    final int heading = _headingLine(lines, platform);
    final Map<String, MeasuredRow> rows = _parseTable(lines, heading, platform);
    for (final CompressPreset preset in CompressPreset.values) {
      if (!rows.containsKey(preset.name)) {
        throw StateError(
          'doc/PRESETS.md has no $measuredSourceClip row for preset '
          '${preset.name} in the $platform measured table',
        );
      }
    }
    measured[platform] = rows;
  }
  return measured;
}

/// The index of the line holding [platform]'s table heading.
int _headingLine(List<String> lines, String platform) {
  int found = -1;
  switch (platform) {
    case 'android':
      final int section = lines.indexWhere(
        (String line) => line.trim() == '## Android',
      );
      if (section >= 0) {
        for (int i = section + 1; i < lines.length; i++) {
          final String line = lines[i].trim();
          if (line.startsWith('## ')) {
            break;
          }
          if (line == '### Measured table') {
            found = i;
            break;
          }
        }
      }
    case 'ios':
      found = lines.indexWhere(
        (String line) =>
            line.trim().startsWith('### Measured table — iOS Simulator'),
      );
    case 'macos':
      found = lines.indexWhere(
        (String line) =>
            line.trim().startsWith('### Measured table — macOS host'),
      );
    default:
      throw StateError('Unknown platform $platform');
  }
  if (found < 0) {
    throw StateError(
      'doc/PRESETS.md has no measured table heading for $platform',
    );
  }
  return found;
}

/// The cells of one Markdown pipe row, trimmed, without the outer empty cells.
List<String> _cells(String line) {
  final List<String> cells = line
      .trim()
      .split('|')
      .map((String cell) => cell.trim())
      .toList();
  return cells.sublist(1, cells.length - 1);
}

/// Parses the pipe table that follows the heading at [heading].
Map<String, MeasuredRow> _parseTable(
  List<String> lines,
  int heading,
  String platform,
) {
  int start = heading + 1;
  while (start < lines.length && lines[start].trim().isEmpty) {
    start++;
  }
  final List<String> table = <String>[];
  for (int i = start; i < lines.length; i++) {
    final String line = lines[i].trim();
    if (!line.startsWith('|') || !line.endsWith('|') || line.length < 2) {
      break;
    }
    table.add(line);
  }
  if (table.length < 2) {
    throw StateError(
      'doc/PRESETS.md has no table under the $platform measured table heading',
    );
  }

  final List<String> header = _cells(table.first);
  int column(String name) {
    final int index = header.indexOf(name);
    if (index < 0) {
      throw StateError(
        'doc/PRESETS.md: the $platform measured table has no "$name" column',
      );
    }
    return index;
  }

  final int presetIndex = column(_presetColumn);
  final int clipIndex = column(_sourceClipColumn);
  final int sizeIndex = column(_sizeColumn);
  final int bitrateIndex = column(_bitrateColumn);

  final Map<String, MeasuredRow> rows = <String, MeasuredRow>{};
  // table[1] is the |---|---| separator row.
  for (final String line in table.skip(2)) {
    final List<String> cells = _cells(line);
    if (cells.length != header.length) {
      throw StateError(
        'doc/PRESETS.md: a row of the $platform measured table has '
        '${cells.length} cells, expected ${header.length}: $line',
      );
    }
    if (cells[clipIndex] != measuredSourceClip) {
      continue;
    }
    final String preset = cells[presetIndex];
    final String size = cells[sizeIndex];
    final String bitrate = cells[bitrateIndex];
    if (!_sizePattern.hasMatch(size)) {
      throw StateError(
        'doc/PRESETS.md: cannot read the size "$size" of preset $preset in '
        'the $platform measured table',
      );
    }
    if (!_bitratePattern.hasMatch(bitrate)) {
      throw StateError(
        'doc/PRESETS.md: cannot read the bitrate "$bitrate" of preset $preset '
        'in the $platform measured table',
      );
    }
    if (rows.containsKey(preset)) {
      throw StateError(
        'doc/PRESETS.md: preset $preset has two $measuredSourceClip rows in '
        'the $platform measured table',
      );
    }
    rows[preset] = (
      widthByHeight: size,
      videoBitrateBps: int.parse(bitrate.replaceAll(',', '')),
    );
  }
  return rows;
}

/// A bitrate target in megabits per second with no padding: `2.5 Mbps`, `5 Mbps`.
String _targetMbps(int bps) {
  String text = (bps / 1000000).toStringAsFixed(3);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  text = text.replaceFirst(RegExp(r'\.$'), '');
  return '$text Mbps';
}

/// A measured bitrate in megabits per second to two decimals: `1.48 Mbps`.
String _measuredMbps(int bps) => '${(bps / 1000000).toStringAsFixed(2)} Mbps';

/// Renders the README's preset table and the three sentences under it as Markdown.
///
/// There is one row per [CompressPreset], in declaration order. [specs] gives each preset's
/// longest side and bitrate target, [maxFps] is the default frame rate cap, and [measured] is
/// what [parseMeasuredRows] returned.
///
/// The same input always gives the same string. The result has no trailing newline.
///
/// Throws [StateError] when [specs] or [measured] lacks an entry the table needs.
String renderPresetTable({
  required Map<CompressPreset, PresetSpec> specs,
  required int maxFps,
  required MeasuredRows measured,
}) {
  final StringBuffer out = StringBuffer()
    ..writeln(
      '| Preset | Longest side (px) | Video bitrate target | Frame rate cap | '
      'From the 1080p60 test clip: Android emulator | '
      'From the 1080p60 test clip: iOS Simulator | '
      'From the 1080p60 test clip: macOS |',
    )
    ..writeln('|---|---|---|---|---|---|---|');

  for (final CompressPreset preset in CompressPreset.values) {
    final PresetSpec? spec = specs[preset];
    if (spec == null) {
      throw StateError('No PresetSpec for preset ${preset.name}');
    }
    final List<String> cells = <String>[
      preset.name,
      '${spec.maxLongSidePx}',
      '${_targetMbps(spec.videoBitrateBps)} (at $presetNominalFps fps)',
      '$maxFps fps (never raised)',
    ];
    for (final String platform in measuredPlatforms) {
      final MeasuredRow? row = measured[platform]?[preset.name];
      if (row == null) {
        throw StateError(
          'No measurement for preset ${preset.name} on $platform',
        );
      }
      cells.add('${row.widthByHeight}, ${_measuredMbps(row.videoBitrateBps)}');
    }
    out.writeln('| ${cells.join(' | ')} |');
  }

  out
    ..writeln()
    ..writeln(
      'The bitrate target is what the encoder is asked for, and an encoder '
      'lands near it, not on it. The target scales down with the output '
      'resolution and frame rate, and a video is never upscaled and never '
      'given a higher frame rate than it came with.',
    )
    ..writeln()
    ..writeln(
      'The clip is a generated test pattern, not camera footage. The Android '
      'and iOS numbers come from software encoders, on an emulator and on a '
      "simulator. A phone's hardware encoder and a real recording will give "
      'different numbers.',
    )
    ..writeln()
    ..write('The full measurements are in [doc/PRESETS.md](doc/PRESETS.md).');
  return out.toString();
}

/// Returns [readme] with the text between [presetTableStart] and [presetTableEnd] replaced by
/// [generated]. Both markers stay, each on its own line, and nothing outside them changes.
///
/// Throws [StateError] when either marker is missing, appears more than once, or when the end
/// marker comes before the start marker.
String replaceBetweenMarkers(String readme, String generated) {
  final int start = readme.indexOf(presetTableStart);
  final int end = readme.indexOf(presetTableEnd);
  if (start < 0) {
    throw StateError('README.md has no $presetTableStart marker');
  }
  if (end < 0) {
    throw StateError('README.md has no $presetTableEnd marker');
  }
  if (readme.indexOf(presetTableStart, start + 1) >= 0 ||
      readme.indexOf(presetTableEnd, end + 1) >= 0) {
    throw StateError('README.md has a preset table marker more than once');
  }
  if (end < start) {
    throw StateError('README.md has $presetTableEnd before $presetTableStart');
  }
  final String before = readme.substring(0, start + presetTableStart.length);
  final String after = readme.substring(end);
  return '$before\n$generated\n$after';
}
