import 'dart:async';
import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:compress_video/compress_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:video_player/video_player.dart';

import 'compression_runner.dart';

/// The `compress_video` example app's single screen (BULD-04).
///
/// This is the thin end-to-end tracer (03-03-PLAN.md task 1): pick the bundled sample clip,
/// compress it at the library's own default [CompressOptions], watch live progress from the
/// real [CompressionRunner], and play the result inline. Task 2 expands this into the full
/// seven-state flow `03-UI-SPEC.md` describes (Idle/Picking/Estimating/Cancelled/Failed states,
/// the real picker, the full options surface and the responsive layout).
class MainScreen extends StatefulWidget {
  /// Creates the screen. [runner] defaults to [RealCompressionRunner]; a widget test injects a
  /// fake here instead.
  const MainScreen({super.key, this.runner = const RealCompressionRunner()});

  /// The seam through which this screen reaches the compression engine.
  final CompressionRunner runner;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const String _bundledAssetPath =
      'assets/corpus/portrait_hibitrate_1080p60.mp4';

  File? _pickedFile;
  String? _pickedFileName;
  int? _pickedFileSizeBytes;
  bool _isPicking = false;

  final CompressOptions _options = const CompressOptions();

  CompressionHandle? _activeJob;
  double _progressPercent = 0;
  StreamSubscription<double>? _progressSubscription;

  CompressResult? _result;

  VideoPlayerController? _playerController;
  bool _playerInitFailed = false;

  @override
  void dispose() {
    unawaited(_progressSubscription?.cancel());
    _playerController?.dispose();
    super.dispose();
  }

  Future<void> _useBundledClip() async {
    setState(() => _isPicking = true);
    try {
      final ByteData data = await rootBundle.load(_bundledAssetPath);
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'compress_video_example_',
      );
      final File file = File('${tempDir.path}/portrait_hibitrate_1080p60.mp4');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      final int size = await file.length();
      if (!mounted) return;
      setState(() {
        _pickedFile = file;
        // Only the basename is ever rendered -- never the full temp path (T-03-10).
        _pickedFileName = file.uri.pathSegments.last;
        _pickedFileSizeBytes = size;
        _result = null;
      });
      _playerController?.dispose();
      _playerController = null;
      _playerInitFailed = false;
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _startCompress() async {
    final File? file = _pickedFile;
    if (file == null) return;

    final CompressionHandle handle = widget.runner.compress(
      file.path,
      options: _options,
    );

    setState(() {
      _activeJob = handle;
      _progressPercent = 0;
      _result = null;
    });
    _playerController?.dispose();
    _playerController = null;
    _playerInitFailed = false;

    unawaited(_progressSubscription?.cancel());
    _progressSubscription = handle.progress.listen((double percent) {
      if (mounted) setState(() => _progressPercent = percent);
    });

    try {
      final CompressResult result = await handle.result;
      if (!mounted) return;
      setState(() {
        _activeJob = null;
        _result = result;
      });
      unawaited(_initializePlayer(result));
    } on CompressVideoException {
      if (!mounted) return;
      setState(() {
        _activeJob = null;
        _progressPercent = 0;
      });
    }
  }

  Future<void> _cancel() async {
    await _activeJob?.cancel();
  }

  Future<void> _initializePlayer(CompressResult result) async {
    final VideoPlayerController controller = VideoPlayerController.file(
      File(result.outputPath),
    );
    setState(() => _playerController = controller);
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() => _playerInitFailed = true);
    }
  }

  Widget _buildPlayer(CompressResult result) {
    if (_playerInitFailed) {
      return const Text(
        'Playback unavailable — the compressed file was still written.',
      );
    }
    final VideoPlayerController? controller = _playerController;
    if (controller == null || !controller.value.isInitialized) {
      return AspectRatio(
        aspectRatio: result.widthPx / result.heightPx,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return AspectRatio(
      aspectRatio: result.widthPx / result.heightPx,
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (controller.value.isPlaying) {
              controller.pause();
            } else {
              controller.play();
            }
          });
        },
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            VideoPlayer(controller),
            Icon(
              controller.value.isPlaying
                  ? Icons.pause_circle
                  : Icons.play_circle,
              size: 64,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CompressResult? result = _result;
    final bool isCompressing = _activeJob != null;
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('compress_video example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_pickedFile == null) ...<Widget>[
            Text(
              'Pick a video from your library, or use the bundled sample clip to try '
              'compression without one.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _isPicking ? null : _useBundledClip,
              child: const Text('Use bundled sample clip →'),
            ),
          ] else ...<Widget>[
            Text(
              _pickedFileName ?? '',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: theme.textTheme.bodyLarge,
            ),
            Text('${_pickedFileSizeBytes ?? 0} bytes'),
            const SizedBox(height: 16),
            Text(
              'Preset: ${_options.preset.name}',
              style: theme.textTheme.bodyLarge,
            ),
            Text(
              'Max FPS: ${_options.maxFps}',
              style: theme.textTheme.bodyLarge,
            ),
            Text(
              'Audio: ${_options.audio.mode.name}',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            if (!isCompressing)
              ElevatedButton(
                onPressed: _startCompress,
                child: const Text('Compress video'),
              ),
            if (isCompressing) ...<Widget>[
              LinearProgressIndicator(value: _progressPercent / 100),
              const SizedBox(height: 8),
              Text(
                '${_progressPercent.clamp(0, 100).round()}%',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _cancel, child: const Text('Cancel')),
            ],
            if (result != null) ...<Widget>[
              const SizedBox(height: 24),
              Text(
                '-${(100 - result.outputBytes / result.inputBytes * 100).toStringAsFixed(0)}% '
                'smaller',
                style: theme.textTheme.headlineSmall,
              ),
              Text('${result.inputBytes} bytes -> ${result.outputBytes} bytes'),
              Text('${result.widthPx} x ${result.heightPx} px'),
              Text('Codec: ${result.videoCodec}'),
              Text('Elapsed: ${result.elapsedMs} ms'),
              const SizedBox(height: 16),
              _buildPlayer(result),
            ],
          ],
        ],
      ),
    );
  }
}
