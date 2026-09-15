import 'package:flutter/foundation.dart' show immutable;

/// Media info for a video file: dimensions, duration, codec and format details.
///
/// Every field's unit is documented below. A nullable field is `null` exactly when the
/// running platform could not determine that value — never `0` and never an empty string,
/// which would be indistinguishable from a real (wrong) measurement.
@immutable
class MediaInfo {
  /// Creates a [MediaInfo]. Application code does not normally construct this directly —
  /// instances are returned by [CompressVideo.getMediaInfo].
  const MediaInfo({
    required this.durationMs,
    required this.widthPx,
    required this.heightPx,
    required this.rotationDegrees,
    required this.sizeBytes,
    required this.videoCodec,
    required this.videoBitrateBps,
    required this.frameRateFps,
    required this.hasAudio,
    required this.isHdr,
  });

  /// Duration of the media, in milliseconds. Rounded half-up from whatever unit the
  /// platform reports.
  final int durationMs;

  /// Displayed (rotation-corrected) width, in pixels. This is the orientation a video
  /// player actually shows — never the coded, pre-rotation width.
  final int widthPx;

  /// Displayed (rotation-corrected) height, in pixels. This is the orientation a video
  /// player actually shows — never the coded, pre-rotation height.
  final int heightPx;

  /// Unsigned clockwise rotation, in degrees, as reported by the platform before the
  /// correction that produced [widthPx]/[heightPx] was applied. `0` for an unrotated clip.
  final int rotationDegrees;

  /// Size of the underlying file, in bytes.
  final int sizeBytes;

  /// Normalised video codec token (`h264`, `hevc`, `av1`, `vp9`, `unknown`), or `null` when
  /// the platform could not determine it.
  final String? videoCodec;

  /// Average video-track bitrate, in bits per second, or `null` when the platform could not
  /// determine it. This is a platform-reported, tolerant value — it may differ slightly
  /// between platforms for the same file.
  final int? videoBitrateBps;

  /// Video frame rate, in frames per second, or `null` when the platform could not determine
  /// it. Never rounded to an integer. This is a platform-reported, tolerant value.
  final double? frameRateFps;

  /// Whether the media has at least one audio track.
  final bool hasAudio;

  /// Whether the video is HDR (PQ or HLG transfer characteristic). `false` when the running
  /// platform cannot determine HDR status — never an exception.
  final bool isHdr;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaInfo &&
          other.durationMs == durationMs &&
          other.widthPx == widthPx &&
          other.heightPx == heightPx &&
          other.rotationDegrees == rotationDegrees &&
          other.sizeBytes == sizeBytes &&
          other.videoCodec == videoCodec &&
          other.videoBitrateBps == videoBitrateBps &&
          other.frameRateFps == frameRateFps &&
          other.hasAudio == hasAudio &&
          other.isHdr == isHdr);

  @override
  int get hashCode => Object.hash(
    durationMs,
    widthPx,
    heightPx,
    rotationDegrees,
    sizeBytes,
    videoCodec,
    videoBitrateBps,
    frameRateFps,
    hasAudio,
    isHdr,
  );

  @override
  String toString() =>
      'MediaInfo(durationMs: $durationMs, widthPx: $widthPx, heightPx: $heightPx, '
      'rotationDegrees: $rotationDegrees, sizeBytes: $sizeBytes, videoCodec: $videoCodec, '
      'videoBitrateBps: $videoBitrateBps, frameRateFps: $frameRateFps, hasAudio: $hasAudio, '
      'isHdr: $isHdr)';
}
