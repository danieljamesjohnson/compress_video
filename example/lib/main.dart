import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() {
  runApp(const CompressVideoExampleApp());
}

/// The `compress_video` example app.
///
/// This phase's plugin surface is limited to the typed error taxonomy, so this screen only
/// proves the example app is real and buildable: it lists the corpus clips bundled as assets
/// (mirrored from `corpus/` by `corpus/sync_to_example.sh`) along with their byte sizes, read
/// through `rootBundle`. Later plans extend this screen with media info and a thumbnail once
/// the plugin has calls to make.
class CompressVideoExampleApp extends StatelessWidget {
  /// Creates the example app.
  const CompressVideoExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('compress_video example')),
        body: const _CorpusAssetList(),
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
