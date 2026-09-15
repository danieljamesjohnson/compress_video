import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:compress_video/compress_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() {
  runApp(const CompressVideoExampleApp());
}

/// The `compress_video` example app.
///
/// Lists the corpus clips bundled as assets (mirrored from `corpus/` by
/// `corpus/sync_to_example.sh`) along with their byte sizes, read through `rootBundle`, and
/// shows the decoded [MediaInfo] for the bundled portrait clip beneath the list -- a live,
/// on-device demonstration of the same `getMediaInfo` call the integration test exercises.
class CompressVideoExampleApp extends StatelessWidget {
  /// Creates the example app.
  const CompressVideoExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('compress_video example')),
        body: const Column(
          children: <Widget>[
            Expanded(child: _CorpusAssetList()),
            Divider(height: 1),
            Expanded(child: _PortraitMediaInfo()),
          ],
        ),
      ),
    );
  }
}

/// A list of the bundled corpus assets and their byte sizes.
class _CorpusAssetList extends StatefulWidget {
  const _CorpusAssetList();

  @override
  State<_CorpusAssetList> createState() => _CorpusAssetListState();
}

class _CorpusAssetListState extends State<_CorpusAssetList> {
  static const List<String> _assetPaths = <String>[
    'assets/corpus/portrait_rot90.mp4',
    'assets/corpus/small_480p.mp4',
    'assets/corpus/noaudio_720p.mp4',
  ];

  late final Future<Map<String, int>> _sizesByPath = _loadSizes();

  Future<Map<String, int>> _loadSizes() async {
    final Map<String, int> sizes = <String, int>{};
    for (final String path in _assetPaths) {
      final ByteData data = await rootBundle.load(path);
      sizes[path] = data.lengthInBytes;
    }
    return sizes;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _sizesByPath,
      builder:
          (BuildContext context, AsyncSnapshot<Map<String, int>> snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text('Failed to load corpus assets: ${snapshot.error}'),
              );
            }
            final Map<String, int>? sizes = snapshot.data;
            if (sizes == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              children: <Widget>[
                for (final MapEntry<String, int> entry in sizes.entries)
                  ListTile(
                    leading: const Icon(Icons.movie_outlined),
                    title: Text(entry.key.split('/').last),
                    subtitle: Text('${entry.value} bytes'),
                  ),
              ],
            );
          },
    );
  }
}

/// Decodes and displays [MediaInfo] for the bundled `portrait_rot90.mp4` corpus clip.
class _PortraitMediaInfo extends StatefulWidget {
  const _PortraitMediaInfo();

  @override
  State<_PortraitMediaInfo> createState() => _PortraitMediaInfoState();
}

class _PortraitMediaInfoState extends State<_PortraitMediaInfo> {
  static const String _assetPath = 'assets/corpus/portrait_rot90.mp4';
  static const CompressVideo _compressVideo = CompressVideo();

  late final Future<MediaInfo> _mediaInfo = _loadMediaInfo();

  Future<MediaInfo> _loadMediaInfo() async {
    final ByteData data = await rootBundle.load(_assetPath);
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'compress_video_example_',
    );
    final File file = File('${tempDir.path}/portrait_rot90.mp4');
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return _compressVideo.getMediaInfo(file.path);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MediaInfo>(
      future: _mediaInfo,
      builder: (BuildContext context, AsyncSnapshot<MediaInfo> snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Failed to read media info: ${snapshot.error}'),
          );
        }
        final MediaInfo? info = snapshot.data;
        if (info == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const Text(
              'Media info: portrait_rot90.mp4',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('${info.widthPx} x ${info.heightPx} px (displayed)'),
            Text('Rotation: ${info.rotationDegrees}°'),
            Text('Duration: ${info.durationMs} ms'),
            Text('Size: ${info.sizeBytes} bytes'),
            Text('Codec: ${info.videoCodec ?? 'unknown'}'),
            Text('Bitrate: ${info.videoBitrateBps ?? 'unknown'} bps'),
            Text('Frame rate: ${info.frameRateFps ?? 'unknown'} fps'),
            Text('Has audio: ${info.hasAudio}'),
            Text('HDR: ${info.isHdr}'),
          ],
        );
      },
    );
  }
}
