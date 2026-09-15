// The single source of truth for every message crossing the platform channel.
//
// Every numeric field carries its unit in its name (`durationMs`, `sizeBytes`, `widthPx`,
// `heightPx`, `rotationDegrees`, `videoBitrateBps`) so the "three units for the same
// parameter on three platforms" bug class (PITFALLS.md #7) cannot recur here — the field
// name itself pins the unit at every call site, in every generated language.
//
// Regenerate with `dart run pigeon --input pigeons/messages.dart`. Running it twice in a
// row must leave the working tree unchanged; a CI step enforces that determinism.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    dartPackageName: 'compress_video',
    kotlinOut:
        'android/src/main/kotlin/com/danjjohnson/compress_video/Messages.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.danjjohnson.compress_video',
      errorClassName: 'CompressVideoError',
    ),
    swiftOut: 'darwin/compress_video/Sources/compress_video/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'CompressVideoError'),
  ),
)
/// The wire-format media info message returned by [ProbeHostApi.getMediaInfo].
///
/// This is the generated, private counterpart of the public, hand-written `MediaInfo`
/// class in `lib/src/media_info.dart` — see that file for the documented public API.
class MediaInfoMessage {
  MediaInfoMessage({
    required this.durationMs,
    required this.widthPx,
    required this.heightPx,
    required this.rotationDegrees,
    required this.sizeBytes,
    this.videoCodec,
    this.videoBitrateBps,
    this.frameRateFps,
    required this.hasAudio,
    required this.isHdr,
  });

  /// Duration of the media, in milliseconds.
  final int durationMs;

  /// Displayed (rotation-corrected) width, in pixels. Never the coded, pre-rotation width.
  final int widthPx;

  /// Displayed (rotation-corrected) height, in pixels. Never the coded, pre-rotation height.
  final int heightPx;

  /// Unsigned clockwise rotation, in degrees, as reported by the platform before the
  /// correction that produced [widthPx]/[heightPx] was applied. `0` for an unrotated clip.
  final int rotationDegrees;

  /// Size of the underlying file, in bytes.
  final int sizeBytes;

  /// Normalised video codec token (`h264`, `hevc`, `av1`, `vp9`, `unknown`), or `null` when
  /// the platform could not determine it. `null` is the sentinel for unknown — never an
  /// empty string.
  final String? videoCodec;

  /// Average video-track bitrate, in bits per second, or `null` when the platform could not
  /// determine it. `null` is the sentinel for unknown — never `0`.
  final int? videoBitrateBps;

  /// Video frame rate, in frames per second, or `null` when the platform could not determine
  /// it. `null` is the sentinel for unknown — never `0`. Never rounded to an integer.
  final double? frameRateFps;

  /// Whether the media has at least one audio track.
  final bool hasAudio;

  /// Whether the video is HDR (PQ or HLG transfer characteristic). `false` when the running
  /// platform cannot determine HDR status — never an exception.
  final bool isHdr;
}

/// Reads media info from a file. Implemented on every platform in this phase.
@HostApi()
abstract class ProbeHostApi {
  /// Returns the [MediaInfoMessage] for the media at [path].
  ///
  /// Declared here in full for the whole contract; only the Android implementation lands in
  /// this plan. Failures throw `CompressVideoError` with the [path] never logged or included
  /// in any diagnostic output outside the returned error detail.
  @async
  MediaInfoMessage getMediaInfo(String path);
}

/// Generates poster-frame thumbnails from a file. Declared here for contract completeness;
/// no platform implements this yet — that lands in a later plan in this phase.
@HostApi()
abstract class ThumbnailHostApi {
  /// Returns JPEG-encoded thumbnail bytes for the frame at [positionMs] in the media at
  /// [path], encoded at [quality] (1-100), with the longer side capped at [maxDimensionPx]
  /// when non-null (never upscaled).
  @async
  Uint8List getThumbnail(
    String path,
    int positionMs,
    int quality,
    int? maxDimensionPx,
  );

  /// Same as [getThumbnail], but writes the JPEG to a file and returns its path. Writes to a
  /// unique name in the app cache directory, or to [outputPath] when given.
  @async
  String getThumbnailFile(
    String path,
    int positionMs,
    int quality,
    int? maxDimensionPx,
    String? outputPath,
  );
}
