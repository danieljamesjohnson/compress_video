import 'package:flutter/foundation.dart' show immutable;

import 'compress_video_exception.dart';

/// Named output resolutions a [CompressOptions.preset] can select.
///
/// Each name is the resolution it targets; see `lib/src/presets.dart` for the resolved
/// (maxLongSidePx, videoBitrateBps) pair each one maps to.
enum CompressPreset {
  /// Targets a long side of 640px.
  p360,

  /// Targets a long side of 854px.
  p480,

  /// Targets a long side of 1280px. The default preset.
  p720,

  /// Targets a long side of 1920px.
  p1080,
}

/// Output video codec. Reserved field: only [h264] is accepted until Phase 4 adds HEVC opt-in
/// with a hardware-only encode and automatic fallback.
enum VideoCodec {
  /// H.264/AVC. The only accepted value in this phase.
  h264,

  /// H.265/HEVC. Reserved; not yet accepted -- Phase 4 implements this.
  hevc,
}

/// Output HDR handling. Reserved field: only [toneMapToSdr] is accepted until Phase 4 adds
/// keep-HDR opt-in.
enum HdrMode {
  /// Tone-map HDR input down to SDR. The only accepted value in this phase, and the default.
  toneMapToSdr,

  /// Keep the input's HDR characteristics in the output. Reserved; not yet accepted -- Phase 4
  /// implements this.
  keepHdr,
}

/// The wire-level shape of how the audio track is handled. See [AudioOptions] for the
/// public, richer API this flattens to.
enum AudioMode {
  /// Keep the source audio track's encoding when it is already MP4-compatible AAC; re-encode
  /// otherwise.
  passthrough,

  /// Always re-encode the audio track to AAC.
  reencode,

  /// Remove the audio track entirely.
  strip,
}

/// How the audio track is handled during compression.
///
/// A sealed class with three `const` subclasses rather than an enum, because [AudioReencode]
/// carries its own required parameters ([AudioReencode.bitrateBps], [AudioReencode.channels])
/// that an enum value cannot hold. Every subclass exposes the [AudioMode] it flattens to at the
/// platform channel boundary.
@immutable
sealed class AudioOptions {
  const AudioOptions();

  /// The wire-level [AudioMode] this option flattens to.
  AudioMode get mode;
}

/// Keep the source audio track's encoding when it is already MP4-compatible AAC; re-encode
/// otherwise. The default [CompressOptions.audio] value.
@immutable
class AudioPassthrough extends AudioOptions {
  /// Creates an [AudioPassthrough].
  const AudioPassthrough();

  @override
  AudioMode get mode => AudioMode.passthrough;

  @override
  bool operator ==(Object other) => other is AudioPassthrough;

  @override
  int get hashCode => (AudioPassthrough).hashCode;
}

/// Always re-encode the audio track to AAC at [bitrateBps] with [channels] channels.
@immutable
class AudioReencode extends AudioOptions {
  /// Creates an [AudioReencode]. [bitrateBps] must be positive and [channels] must be 1 or 2;
  /// [CompressOptions.validate] enforces both before the request crosses the platform channel.
  const AudioReencode({required this.bitrateBps, required this.channels});

  /// Target audio bitrate, in bits per second.
  final int bitrateBps;

  /// Target audio channel count. 1 (mono) or 2 (stereo).
  final int channels;

  @override
  AudioMode get mode => AudioMode.reencode;

  @override
  bool operator ==(Object other) =>
      other is AudioReencode &&
      other.bitrateBps == bitrateBps &&
      other.channels == channels;

  @override
  int get hashCode => Object.hash(AudioReencode, bitrateBps, channels);
}

/// Remove the audio track entirely. The result's `audioCodec` is `null`.
@immutable
class AudioStrip extends AudioOptions {
  /// Creates an [AudioStrip].
  const AudioStrip();

  @override
  AudioMode get mode => AudioMode.strip;

  @override
  bool operator ==(Object other) => other is AudioStrip;

  @override
  int get hashCode => (AudioStrip).hashCode;
}

/// Options controlling how [CompressVideo.compress] transforms its input.
///
/// Every field is documented with its unit and its behaviour when left at the default. The
/// precedence rule between [preset] and the explicit targets: [maxLongSidePx],
/// [videoBitrateBps] and [targetSizeMb] each override the preset's own value when set, and the
/// effective long side and frame rate are never above the input's own (never upscale, D-08).
@immutable
class CompressOptions {
  /// Creates a [CompressOptions]. Call [validate] before use to raise
  /// [CompressVideoErrorReason.unsupportedInput] for an invalid combination -- `compress`
  /// always does this before crossing the platform channel.
  const CompressOptions({
    this.preset = CompressPreset.p720,
    this.maxLongSidePx,
    this.videoBitrateBps,
    this.targetSizeMb,
    this.maxFps = 30,
    this.audio = const AudioPassthrough(),
    this.trimStartMs,
    this.trimEndMs,
    this.outputPath,
    this.codec = VideoCodec.h264,
    this.hdr = HdrMode.toneMapToSdr,
  });

  /// The named preset to resolve [maxLongSidePx]/[videoBitrateBps] from when either is not
  /// explicitly set. Defaults to [CompressPreset.p720].
  final CompressPreset preset;

  /// Explicit cap on the output's longer displayed side, in pixels, overriding [preset] when
  /// set. `null` means "use the preset's own value". Never upscales: the effective long side is
  /// `min(this value, the input's own displayed long side)`.
  final int? maxLongSidePx;

  /// Explicit target video bitrate, in bits per second, overriding [preset] when set. `null`
  /// means "use the preset's own value". Mutually exclusive with [targetSizeMb] -- setting
  /// both throws in [validate].
  final int? videoBitrateBps;

  /// Explicit target output file size, in megabytes, overriding [preset]'s implied size when
  /// set. `null` means "no target size requested". Mutually exclusive with [videoBitrateBps].
  final double? targetSizeMb;

  /// Cap on the output's frame rate, in frames per second. Defaults to 30. Never upscales: the
  /// effective frame rate is `min(this value, the input's own frame rate)`.
  final int maxFps;

  /// How the audio track is handled. Defaults to [AudioPassthrough].
  final AudioOptions audio;

  /// Start of the trim range, in milliseconds from the start of the input, or `null` for no
  /// trim start.
  final int? trimStartMs;

  /// End of the trim range, in milliseconds from the start of the input, or `null` for no trim
  /// end.
  final int? trimEndMs;

  /// Destination path for the compressed output, or `null` to use the plugin's own cache
  /// directory with a name derived from the job id.
  final String? outputPath;

  /// Requested output video codec. Reserved: only [VideoCodec.h264] is accepted in this phase;
  /// HEVC opt-in is Phase 4.
  final VideoCodec codec;

  /// Requested HDR handling. Reserved: only [HdrMode.toneMapToSdr] is accepted in this phase;
  /// keep-HDR opt-in is Phase 4.
  final HdrMode hdr;

  /// Throws a [CompressVideoException] with reason
  /// [CompressVideoErrorReason.unsupportedInput] for any combination of fields the engine
  /// cannot honour. Called by `CompressVideo.compress`/`estimate` before either crosses the
  /// platform channel.
  void validate() {
    void reject(String message) {
      throw CompressVideoException(
        reason: CompressVideoErrorReason.unsupportedInput,
        message: message,
      );
    }

    if (maxFps <= 0) {
      reject('maxFps must be positive');
    }
    if (maxLongSidePx != null && maxLongSidePx! < 16) {
      reject('maxLongSidePx must be at least 16 when given');
    }
    if (videoBitrateBps != null && videoBitrateBps! <= 0) {
      reject('videoBitrateBps must be positive when given');
    }
    if (targetSizeMb != null &&
        (!targetSizeMb!.isFinite || targetSizeMb! <= 0)) {
      reject('targetSizeMb must be a finite, positive number when given');
    }
    if (trimStartMs != null && trimStartMs! < 0) {
      reject('trimStartMs must not be negative when given');
    }
    if (trimEndMs != null && trimEndMs! <= (trimStartMs ?? 0)) {
      reject('trimEndMs must be strictly greater than trimStartMs when given');
    }
    if (outputPath != null && outputPath!.trim().isEmpty) {
      reject('outputPath must not be blank when given');
    }
    if (codec != VideoCodec.h264) {
      reject('codec: only VideoCodec.h264 is accepted in this phase');
    }
    if (hdr != HdrMode.toneMapToSdr) {
      reject('hdr: only HdrMode.toneMapToSdr is accepted in this phase');
    }
    final AudioOptions audioValue = audio;
    if (audioValue is AudioReencode) {
      if (audioValue.bitrateBps <= 0) {
        reject('audio: AudioReencode.bitrateBps must be positive');
      }
      if (audioValue.channels < 1 || audioValue.channels > 2) {
        reject('audio: AudioReencode.channels must be 1 or 2');
      }
    }
    if (targetSizeMb != null && videoBitrateBps != null) {
      reject(
        'videoBitrateBps and targetSizeMb are contradictory targets for the same '
        'output size; set at most one',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CompressOptions &&
          other.preset == preset &&
          other.maxLongSidePx == maxLongSidePx &&
          other.videoBitrateBps == videoBitrateBps &&
          other.targetSizeMb == targetSizeMb &&
          other.maxFps == maxFps &&
          other.audio == audio &&
          other.trimStartMs == trimStartMs &&
          other.trimEndMs == trimEndMs &&
          other.outputPath == outputPath &&
          other.codec == codec &&
          other.hdr == hdr);

  @override
  int get hashCode => Object.hash(
    preset,
    maxLongSidePx,
    videoBitrateBps,
    targetSizeMb,
    maxFps,
    audio,
    trimStartMs,
    trimEndMs,
    outputPath,
    codec,
    hdr,
  );

  @override
  String toString() =>
      'CompressOptions(preset: $preset, maxLongSidePx: $maxLongSidePx, '
      'videoBitrateBps: $videoBitrateBps, targetSizeMb: $targetSizeMb, maxFps: $maxFps, '
      'audio: $audio, trimStartMs: $trimStartMs, trimEndMs: $trimEndMs, '
      'outputPath: $outputPath, codec: $codec, hdr: $hdr)';
}
