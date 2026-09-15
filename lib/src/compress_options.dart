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
  /// set. `null` (the default) means "use [preset]'s own long side". A minimum of `16` is
  /// enforced -- the emulator's own H.264 encoder's advertised minimum frame dimension -- and
  /// `16` itself is accepted. Never upscales: the effective long side actually used is
  /// `min(this value, the input's own displayed long side)`, so a value above the input's own
  /// long side has no visible effect other than "don't shrink below this".
  final int? maxLongSidePx;

  /// Explicit target video bitrate, in bits per second, overriding [preset]'s own bitrate when
  /// set. `null` (the default) means "resolve the bitrate from [targetSizeMb] if set, else
  /// scale [preset]'s own bitrate by the actual output resolution and frame rate" -- an
  /// unscaled preset bitrate applied to a smaller-than-preset source is exactly the defect
  /// that made the incumbent's highest preset re-encode 4K at a fixed 3.7 Mbps. Mutually
  /// exclusive with [targetSizeMb] -- setting both throws in [validate].
  final int? videoBitrateBps;

  /// Explicit target output file size, in megabytes, overriding [preset]'s implied size when
  /// set. `null` (the default) means "no target size requested". Mutually exclusive with
  /// [videoBitrateBps] -- setting both throws in [validate].
  ///
  /// A megabyte here is exactly `1,000,000` bytes (decimal, matching how every upload limit
  /// and carrier data allowance is stated) -- never `2^20` (`1,048,576`) bytes.
  ///
  /// The real output lands within plus or minus 15 percent of the requested size, for a real
  /// encode of a genuinely compressible source; a source that is already smaller than the
  /// requested size, or already incompressible, is governed by the never-larger guarantee
  /// instead and may not reach anywhere near the target. The video bitrate that produces the
  /// target size is computed as `(targetSizeMb * 1,000,000 * 8 / outputDurationSeconds) *
  /// 0.97`, minus the resolved audio bitrate -- the `0.97` reserves 3 percent of the requested
  /// size for container and muxing overhead before the rest is split between video and audio.
  ///
  /// This tolerance is the formula's designed target, verified as exact arithmetic in
  /// `SizeGuardTest.kt`. A software encoder's *actual* rate control can still diverge from a
  /// requested bitrate by more than 15 percent on very short, already-downscaled clips --
  /// measured live on this project's danserver emulator (02-03-SUMMARY.md, QUESTIONS.md);
  /// re-verification against a physical device's hardware encoder is tracked separately.
  final double? targetSizeMb;

  /// Cap on the output's frame rate, in frames per second. Defaults to `30`. This is always a
  /// cap, never a target: the effective frame rate actually used is `min(this value, the
  /// input's own frame rate)`, so a slower source is never sped up to reach this value, and a
  /// value above the input's own frame rate has no effect.
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
