import 'dart:async';
import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:compress_video/compress_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'compression_runner.dart';

/// The desktop/phone layout breakpoint, in logical pixels (03-UI-SPEC.md Layout) -- Material's
/// own `600` layout-size boundary. At exactly 600 the constrained desktop layout applies; below
/// it, the full-bleed phone layout applies. There is no third breakpoint.
const double _kDesktopBreakpoint = 600;

/// The desktop layout's maximum content width, in logical pixels (03-UI-SPEC.md Layout).
const double _kDesktopMaxContentWidth = 640;

/// The bundled corpus clip the "Use bundled sample clip" fallback copies out of the asset
/// bundle -- lets a simulator/emulator/CI run with no photo library (D-25).
const String _kBundledAssetPath =
    'assets/corpus/portrait_hibitrate_1080p60.mp4';

/// The debounce applied before an options change triggers a fresh `estimate()` call
/// (03-UI-SPEC.md Screen States, auto-selected).
const Duration _kEstimateDebounce = Duration(milliseconds: 300);

/// Sentinel used by [_MainScreenState._updateOptions] to distinguish "this field was not
/// passed" from "this field was explicitly set to null" (clearing an optional value).
const Object _unset = Object();

/// The `compress_video` example app's single screen (BULD-04).
///
/// One shared Dart widget tree, driving all seven states described by `03-UI-SPEC.md`: Idle,
/// Picking, Estimating, Compressing, Cancelled, Failed and Done. No Cupertino widgets, no
/// confirmation dialogs, no platform branching beyond `image_picker`'s own federated routing.
class MainScreen extends StatefulWidget {
  /// Creates the screen. [runner] defaults to [RealCompressionRunner]; a widget test injects a
  /// fake [CompressionRunner] here instead, with no platform channel.
  const MainScreen({super.key, this.runner = const RealCompressionRunner()});

  /// The seam through which this screen reaches the compression engine.
  final CompressionRunner runner;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  File? _pickedFile;
  String? _pickedFileName;
  int? _pickedFileSizeBytes;
  bool _isPicking = false;

  CompressOptions _options = const CompressOptions();

  CompressEstimate? _estimate;
  bool _isEstimating = false;
  bool _estimateFailed = false;
  Timer? _estimateDebounceTimer;
  int _estimateRequestId = 0;

  CompressionHandle? _activeJob;
  double _progressPercent = 0;
  StreamSubscription<double>? _progressSubscription;

  CompressResult? _result;
  CompressVideoErrorReason? _failureReason;

  VideoPlayerController? _playerController;
  bool _playerInitFailed = false;

  late final TextEditingController _maxLongSideController =
      TextEditingController(text: _options.maxLongSidePx?.toString() ?? '');
  late final TextEditingController _videoBitrateController =
      TextEditingController(text: _options.videoBitrateBps?.toString() ?? '');
  late final TextEditingController _targetSizeController =
      TextEditingController(text: _options.targetSizeMb?.toString() ?? '');
  late final TextEditingController _maxFpsController = TextEditingController(
    text: _options.maxFps.toString(),
  );
  late final TextEditingController _trimStartController = TextEditingController(
    text: _options.trimStartMs?.toString() ?? '',
  );
  late final TextEditingController _trimEndController = TextEditingController(
    text: _options.trimEndMs?.toString() ?? '',
  );
  final TextEditingController _audioBitrateController = TextEditingController(
    text: '128000',
  );
  final TextEditingController _audioChannelsController = TextEditingController(
    text: '2',
  );

  bool get _hasClip => _pickedFile != null;
  bool get _isCompressing => _activeJob != null;
  bool get _isDone => _result != null && !_isCompressing;
  bool get _isFailed => _failureReason != null && !_isCompressing;

  @override
  void dispose() {
    _estimateDebounceTimer?.cancel();
    unawaited(_progressSubscription?.cancel());
    _disposePlayer();
    _maxLongSideController.dispose();
    _videoBitrateController.dispose();
    _targetSizeController.dispose();
    _maxFpsController.dispose();
    _trimStartController.dispose();
    _trimEndController.dispose();
    _audioBitrateController.dispose();
    _audioChannelsController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------------------
  // Picking
  // ---------------------------------------------------------------------------------------

  Future<void> _pickVideo() async {
    setState(() => _isPicking = true);
    XFile? picked;
    try {
      picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    } catch (_) {
      // A picker that throws (permission denied, etc.) leaves the screen in Idle with no
      // error card and no snackbar (03-UI-SPEC.md picker-button/error).
      picked = null;
    }
    if (!mounted) return;
    setState(() => _isPicking = false);
    if (picked == null) {
      return;
    }
    await _setPickedFile(File(picked.path));
  }

  Future<void> _useBundledClip() async {
    setState(() => _isPicking = true);
    try {
      final ByteData data = await rootBundle.load(_kBundledAssetPath);
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'compress_video_example_',
      );
      final File file = File('${tempDir.path}/portrait_hibitrate_1080p60.mp4');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      if (!mounted) return;
      await _setPickedFile(file);
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _setPickedFile(File file) async {
    final int size = await file.length();
    if (!mounted) return;
    setState(() {
      _pickedFile = file;
      // Only the basename is ever rendered -- never the full temp/library path (T-03-10).
      _pickedFileName = file.uri.pathSegments.last;
      _pickedFileSizeBytes = size;
      _result = null;
      _failureReason = null;
      _estimate = null;
    });
    _disposePlayer();
    _scheduleEstimate();
  }

  // ---------------------------------------------------------------------------------------
  // Options + estimate
  // ---------------------------------------------------------------------------------------

  void _updateOptions({
    CompressPreset? preset,
    Object? maxLongSidePx = _unset,
    Object? videoBitrateBps = _unset,
    Object? targetSizeMb = _unset,
    int? maxFps,
    AudioOptions? audio,
    Object? trimStartMs = _unset,
    Object? trimEndMs = _unset,
  }) {
    final CompressOptions updated = CompressOptions(
      preset: preset ?? _options.preset,
      maxLongSidePx: identical(maxLongSidePx, _unset)
          ? _options.maxLongSidePx
          : maxLongSidePx as int?,
      videoBitrateBps: identical(videoBitrateBps, _unset)
          ? _options.videoBitrateBps
          : videoBitrateBps as int?,
      targetSizeMb: identical(targetSizeMb, _unset)
          ? _options.targetSizeMb
          : targetSizeMb as double?,
      maxFps: maxFps ?? _options.maxFps,
      audio: audio ?? _options.audio,
      trimStartMs: identical(trimStartMs, _unset)
          ? _options.trimStartMs
          : trimStartMs as int?,
      trimEndMs: identical(trimEndMs, _unset)
          ? _options.trimEndMs
          : trimEndMs as int?,
    );
    setState(() => _options = updated);
    _scheduleEstimate();
  }

  void _onAudioModeChanged(AudioMode mode) {
    final AudioOptions audio = switch (mode) {
      AudioMode.passthrough => const AudioPassthrough(),
      AudioMode.reencode => AudioReencode(
        bitrateBps: int.tryParse(_audioBitrateController.text) ?? 128000,
        channels: int.tryParse(_audioChannelsController.text) ?? 2,
      ),
      AudioMode.strip => const AudioStrip(),
    };
    _updateOptions(audio: audio);
  }

  void _onAudioReencodeChanged({int? bitrateBps, int? channels}) {
    final AudioOptions current = _options.audio;
    if (current is! AudioReencode) return;
    _updateOptions(
      audio: AudioReencode(
        bitrateBps: bitrateBps ?? current.bitrateBps,
        channels: channels ?? current.channels,
      ),
    );
  }

  void _scheduleEstimate() {
    _estimateDebounceTimer?.cancel();
    final File? file = _pickedFile;
    if (file == null) return;
    setState(() {
      _isEstimating = true;
      _estimateFailed = false;
    });
    _estimateDebounceTimer = Timer(
      _kEstimateDebounce,
      () => _runEstimate(file),
    );
  }

  Future<void> _runEstimate(File file) async {
    final int requestId = ++_estimateRequestId;
    try {
      final CompressEstimate estimate = await widget.runner.estimate(
        file.path,
        options: _options,
      );
      if (!mounted || requestId != _estimateRequestId) return;
      setState(() {
        _estimate = estimate;
        _isEstimating = false;
        _estimateFailed = false;
      });
    } catch (_) {
      if (!mounted || requestId != _estimateRequestId) return;
      setState(() {
        _isEstimating = false;
        _estimateFailed = true;
      });
    }
  }

  // ---------------------------------------------------------------------------------------
  // Compress / cancel
  // ---------------------------------------------------------------------------------------

  Future<void> _startCompress() async {
    final File? file = _pickedFile;
    if (file == null) return;

    final CompressionHandle handle;
    try {
      handle = widget.runner.compress(file.path, options: _options);
    } on CompressVideoException catch (e) {
      // A synchronous validation failure (e.g. targetSizeMb + videoBitrateBps together) never
      // enters Compressing -- shown as a SnackBar carrying the exception's own message, with
      // no state change (03-UI-SPEC.md options-panel/error, backstop "contradictory targets").
      _showSnackBar(e.message);
      return;
    }

    setState(() {
      _activeJob = handle;
      _progressPercent = 0;
      _result = null;
      _failureReason = null;
    });
    _disposePlayer();

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
    } on CompressVideoException catch (e) {
      if (!mounted) return;
      setState(() {
        _activeJob = null;
        _progressPercent = 0;
      });
      if (e.reason == CompressVideoErrorReason.cancelled) {
        // Cancelled routes to the Cancelled state, never Failed -- a transient SnackBar, no
        // result card, no confirmation dialog (03-UI-SPEC.md Copywriting Contract).
        _showSnackBar('Compression cancelled.');
      } else {
        setState(() => _failureReason = e.reason);
      }
    }
  }

  Future<void> _cancel() async {
    await _activeJob?.cancel();
  }

  Future<void> _initializePlayer(CompressResult result) async {
    final VideoPlayerController controller = VideoPlayerController.file(
      File(result.outputPath),
    );
    setState(() {
      _playerController = controller;
      _playerInitFailed = false;
    });
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() => _playerInitFailed = true);
    }
  }

  void _disposePlayer() {
    _playerController?.dispose();
    _playerController = null;
    _playerInitFailed = false;
  }

  void _showSnackBar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _failureBody(CompressVideoErrorReason reason) {
    switch (reason) {
      case CompressVideoErrorReason.unsupportedInput:
        return "This file or option combination isn't supported — try a different clip or preset.";
      case CompressVideoErrorReason.decoderUnavailable:
        return "This device can't decode that file's video track — try a different clip.";
      case CompressVideoErrorReason.encoderUnavailable:
        return "The encoder isn't available right now — try again in a moment.";
      case CompressVideoErrorReason.outOfSpace:
        return 'Not enough free storage to finish — free up space and try again.';
      case CompressVideoErrorReason.io:
        return 'Something went wrong writing the file — try again.';
      default:
        return 'Something went wrong — try again.';
    }
  }

  // ---------------------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool isDesktop = width >= _kDesktopBreakpoint;
    final List<Widget> sections = _buildSections(context, isDesktop);

    Widget body = ListView(
      padding: const EdgeInsets.all(16),
      children: sections,
    );
    if (isDesktop) {
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kDesktopMaxContentWidth),
          child: body,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('compress_video example')),
      body: body,
    );
  }

  List<Widget> _buildSections(BuildContext context, bool isDesktop) {
    final List<Widget> sections = <Widget>[
      _buildPickerSection(context, isDesktop),
    ];
    if (_hasClip) {
      sections
        ..add(const SizedBox(height: 32))
        ..add(_buildOptionsSection(context, isDesktop))
        ..add(const SizedBox(height: 32))
        ..add(_buildEstimateSection(context));
      final Widget? progressOrResult = _buildProgressOrResultSection(context);
      if (progressOrResult != null) {
        sections
          ..add(const SizedBox(height: 32))
          ..add(progressOrResult);
      }
      final Widget? player = _buildPlayerSection(context);
      if (player != null) {
        sections
          ..add(const SizedBox(height: 32))
          ..add(player);
      }
    }
    return sections;
  }

  // ---------------------------------------------------------------------------------------
  // Picker section: Idle / Picking (no clip) or the picked-clip tile
  // ---------------------------------------------------------------------------------------

  Widget _buildPickerSection(BuildContext context, bool isDesktop) {
    if (!_hasClip) {
      return _buildEmptyState(context, isDesktop);
    }
    return _buildPickedClipTile(context);
  }

  Widget _buildEmptyState(BuildContext context, bool isDesktop) {
    final ThemeData theme = Theme.of(context);
    final Widget pickButton = ElevatedButton.icon(
      onPressed: _isPicking ? null : _pickVideo,
      icon: _isPicking
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.video_library_outlined),
      label: const Text('Pick video'),
    );
    final Widget bundledLink = TextButton(
      onPressed: _isPicking ? null : _useBundledClip,
      child: const Text('Use bundled sample clip →'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 64),
        Text('No video selected', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        Text(
          'Pick a video from your library, or use the bundled sample clip to try '
          'compression without one.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        if (isDesktop)
          Row(children: <Widget>[pickButton])
        else
          SizedBox(width: double.infinity, child: pickButton),
        const SizedBox(height: 8),
        bundledLink,
      ],
    );
  }

  Widget _buildPickedClipTile(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            const Icon(Icons.movie_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _pickedFileName ?? '',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: theme.textTheme.bodyLarge,
                  ),
                  Text(
                    '${_pickedFileSizeBytes ?? 0} bytes',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------------------
  // Options section
  // ---------------------------------------------------------------------------------------

  Widget _buildOptionsSection(BuildContext context, bool isDesktop) {
    final bool enabled = !_isCompressing;
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Options', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            SegmentedButton<CompressPreset>(
              segments: const <ButtonSegment<CompressPreset>>[
                ButtonSegment<CompressPreset>(
                  value: CompressPreset.p360,
                  label: Text('360p'),
                ),
                ButtonSegment<CompressPreset>(
                  value: CompressPreset.p480,
                  label: Text('480p'),
                ),
                ButtonSegment<CompressPreset>(
                  value: CompressPreset.p720,
                  label: Text('720p'),
                ),
                ButtonSegment<CompressPreset>(
                  value: CompressPreset.p1080,
                  label: Text('1080p'),
                ),
              ],
              selected: <CompressPreset>{_options.preset},
              onSelectionChanged: enabled
                  ? (Set<CompressPreset> selection) =>
                        _updateOptions(preset: selection.first)
                  : null,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _maxLongSideController,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Max long side (px, optional)',
              ),
              onChanged: (String value) =>
                  _updateOptions(maxLongSidePx: int.tryParse(value)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _videoBitrateController,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Video bitrate (bps, optional)',
              ),
              onChanged: (String value) =>
                  _updateOptions(videoBitrateBps: int.tryParse(value)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _targetSizeController,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Target size (MB, optional)',
              ),
              onChanged: (String value) =>
                  _updateOptions(targetSizeMb: double.tryParse(value)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _maxFpsController,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Max frame rate (fps)',
              ),
              onChanged: (String value) => _updateOptions(
                maxFps: int.tryParse(value) ?? _options.maxFps,
              ),
            ),
            const SizedBox(height: 16),
            Text('Audio', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            SegmentedButton<AudioMode>(
              segments: const <ButtonSegment<AudioMode>>[
                ButtonSegment<AudioMode>(
                  value: AudioMode.passthrough,
                  label: Text('Passthrough'),
                ),
                ButtonSegment<AudioMode>(
                  value: AudioMode.reencode,
                  label: Text('Re-encode'),
                ),
                ButtonSegment<AudioMode>(
                  value: AudioMode.strip,
                  label: Text('Strip'),
                ),
              ],
              selected: <AudioMode>{_options.audio.mode},
              onSelectionChanged: enabled
                  ? (Set<AudioMode> selection) =>
                        _onAudioModeChanged(selection.first)
                  : null,
            ),
            if (_options.audio is AudioReencode) ...<Widget>[
              const SizedBox(height: 8),
              TextField(
                controller: _audioBitrateController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Audio bitrate (bps)',
                ),
                onChanged: (String value) =>
                    _onAudioReencodeChanged(bitrateBps: int.tryParse(value)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _audioChannelsController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Audio channels (1 or 2)',
                ),
                onChanged: (String value) =>
                    _onAudioReencodeChanged(channels: int.tryParse(value)),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _trimStartController,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Trim start (ms, optional)',
                    ),
                    onChanged: (String value) =>
                        _updateOptions(trimStartMs: int.tryParse(value)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _trimEndController,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Trim end (ms, optional)',
                    ),
                    onChanged: (String value) =>
                        _updateOptions(trimEndMs: int.tryParse(value)),
                  ),
                ),
              ],
            ),
            if (!_isCompressing) ...<Widget>[
              const SizedBox(height: 16),
              _buildCompressButton(isDesktop),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompressButton(bool isDesktop) {
    final Widget button = ElevatedButton(
      onPressed: _startCompress,
      child: const Text('Compress video'),
    );
    if (isDesktop) {
      return Row(children: <Widget>[button]);
    }
    return SizedBox(width: double.infinity, child: button);
  }

  // ---------------------------------------------------------------------------------------
  // Estimate line
  // ---------------------------------------------------------------------------------------

  Widget _buildEstimateSection(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    String text;
    Widget? spinner;
    if (_isEstimating) {
      text = 'Estimating…';
      spinner = const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (_estimateFailed) {
      text = 'Estimate unavailable — Compress still works.';
    } else if (_estimate != null) {
      final CompressEstimate estimate = _estimate!;
      final double mb = estimate.outputBytes / 1000000;
      text =
          '≈ ${mb.toStringAsFixed(1)} MB · ${estimate.widthPx}×${estimate.heightPx} · '
          '${(estimate.durationMs / 1000).toStringAsFixed(1)} s';
    } else {
      text = '';
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        if (spinner != null) ...<Widget>[const SizedBox(width: 8), spinner],
      ],
    );
  }

  // ---------------------------------------------------------------------------------------
  // Progress / Failed / Done
  // ---------------------------------------------------------------------------------------

  Widget? _buildProgressOrResultSection(BuildContext context) {
    if (_isCompressing) return _buildProgressSection(context);
    if (_isFailed) return _buildFailedCard(context);
    if (_isDone) return _buildResultCard(context);
    return null;
  }

  Widget _buildProgressSection(BuildContext context) {
    final int percent = _progressPercent.clamp(0, 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        LinearProgressIndicator(value: _progressPercent / 100),
        const SizedBox(height: 8),
        Text('$percent%', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _cancel, child: const Text('Cancel')),
      ],
    );
  }

  Widget _buildFailedCard(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final CompressVideoErrorReason reason = _failureReason!;
    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Compression failed.',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.onErrorContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _failureBody(reason),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onErrorContainer,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _startCompress,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(BuildContext context) {
    final CompressResult result = _result!;
    final ThemeData theme = Theme.of(context);
    final double savingsPercent = result.inputBytes > 0
        ? (1 - result.outputBytes / result.inputBytes) * 100
        : 0;
    final List<Widget> badges = <Widget>[
      if (result.transmuxed) const Chip(label: Text('transmuxed')),
      if (result.usedOriginal) const Chip(label: Text('usedOriginal')),
      if (result.audioReencoded) const Chip(label: Text('audioReencoded')),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${savingsPercent >= 0 ? '-' : '+'}${savingsPercent.abs().toStringAsFixed(0)}% '
              'smaller',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(
              '${result.inputBytes} bytes → ${result.outputBytes} bytes',
              style: theme.textTheme.bodyLarge,
            ),
            Text(
              '${result.widthPx} × ${result.heightPx} px',
              style: theme.textTheme.bodyLarge,
            ),
            Text(
              'Codec: ${result.videoCodec}',
              style: theme.textTheme.bodyLarge,
            ),
            Text(
              'Elapsed: ${result.elapsedMs} ms',
              style: theme.textTheme.bodyLarge,
            ),
            if (badges.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: badges),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------------------
  // Player
  // ---------------------------------------------------------------------------------------

  Widget? _buildPlayerSection(BuildContext context) {
    if (!_isDone) return null;
    return _buildPlayerWidget(context);
  }

  Widget _buildPlayerWidget(BuildContext context) {
    final CompressResult result = _result!;
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
}
