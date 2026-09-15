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

/// How the audio track is handled during compression. Wire-level counterpart of the public
/// `AudioMode` enum in `lib/src/compress_options.dart`.
enum AudioModeMessage {
  /// Keep the source audio track's encoding when it is already MP4-compatible AAC; re-encode
  /// otherwise. This is the default.
  passthrough,

  /// Always re-encode the audio track to AAC, honouring the requested bitrate and channels.
  reencode,

  /// Remove the audio track entirely. The result's `audioCodec` is `null`.
  strip,
}

/// A compression request, sent once per job via [CompressHostApi.startCompress] and also used
/// (identically) by [CompressHostApi.estimate] to predict what that request would produce.
///
/// The preset named by the caller's `CompressOptions.preset` (see
/// `lib/src/compress_options.dart`) is resolved to a concrete [maxLongSidePx] plus
/// [videoBitrateBps] entirely on the Dart side before this message is built — no preset enum
/// crosses the channel, so a reader will not find one here.
class CompressRequestMessage {
  CompressRequestMessage({
    this.maxLongSidePx,
    this.videoBitrateBps,
    this.targetSizeMb,
    required this.presetMaxLongSidePx,
    required this.presetVideoBitrateBps,
    required this.maxFps,
    required this.audioMode,
    this.audioBitrateBps,
    this.audioChannels,
    this.trimStartMs,
    this.trimEndMs,
    this.outputPath,
    required this.videoCodec,
    required this.hdrMode,
  });

  /// Explicit cap on the output's longer displayed side, in pixels, or `null` when the caller
  /// did not set `CompressOptions.maxLongSidePx` -- in which case `SizeGuard` falls back to
  /// [presetMaxLongSidePx]. Never the preset's own value pre-resolved into this field (that
  /// was 02-02's tracer-only shape); this field is `null` unless the caller explicitly set it,
  /// which is what lets the native side tell "explicit override" apart from "use the preset".
  final int? maxLongSidePx;

  /// Explicit target video bitrate, in bits per second, or `null` when the caller did not set
  /// `CompressOptions.videoBitrateBps` -- in which case `SizeGuard` resolves it from
  /// [targetSizeMb] if set, else scales [presetVideoBitrateBps] by the actual output
  /// resolution and frame rate (SizeGuard.kt rule 6; this is the fix for the incumbent's
  /// fixed-bitrate-regardless-of-resolution defect, PITFALLS.md row 13).
  final int? videoBitrateBps;

  /// Target output file size, in megabytes, or `null` when no target size was requested.
  final double? targetSizeMb;

  /// The selected `CompressPreset`'s own nominal long-side cap, in pixels, always sent
  /// regardless of any [maxLongSidePx] override -- the reference value SizeGuard's bitrate
  /// scaling formula divides by. The preset enum itself never crosses the channel (02-02
  /// decision, unchanged); only its two resolved numbers do.
  final int presetMaxLongSidePx;

  /// The selected `CompressPreset`'s own nominal video bitrate, in bits per second, always
  /// sent regardless of any [videoBitrateBps] override -- the reference value SizeGuard scales
  /// when neither an explicit bitrate nor a [targetSizeMb] was requested.
  final int presetVideoBitrateBps;

  /// Cap on the output's frame rate, in frames per second. Never upscales the input's own
  /// frame rate — the effective cap is `min(maxFps, input fps)`.
  final int maxFps;

  /// How the audio track is handled. See [AudioModeMessage].
  final AudioModeMessage audioMode;

  /// Target audio bitrate, in bits per second, when [audioMode] is
  /// [AudioModeMessage.reencode]. `null` otherwise.
  final int? audioBitrateBps;

  /// Target audio channel count, when [audioMode] is [AudioModeMessage.reencode]. `null`
  /// otherwise.
  final int? audioChannels;

  /// Start of the trim range, in milliseconds from the start of the input, or `null` for no
  /// trim start.
  final int? trimStartMs;

  /// End of the trim range, in milliseconds from the start of the input, or `null` for no
  /// trim end.
  final int? trimEndMs;

  /// Destination path for the compressed output, or `null` to use the plugin's own cache
  /// directory with a name derived from the job id.
  final String? outputPath;

  /// Requested output video codec. Only `"h264"` is accepted in this phase; HEVC opt-in is
  /// Phase 4.
  final String videoCodec;

  /// Requested HDR handling. Only `"toneMapToSdr"` is accepted in this phase; keep-HDR opt-in
  /// is Phase 4.
  final String hdrMode;
}

/// The typed result of a completed compression job. Every field is populated from a re-probe
/// of the finished output file, never from the export engine's own approximate fields — see
/// 02-RESEARCH.md Pitfall 4.
class CompressResultMessage {
  CompressResultMessage({
    required this.outputPath,
    required this.inputBytes,
    required this.outputBytes,
    required this.widthPx,
    required this.heightPx,
    required this.durationMs,
    required this.videoCodec,
    this.audioCodec,
    required this.transmuxed,
    required this.usedOriginal,
    required this.toneMapped,
    required this.hevcFallback,
    required this.audioReencoded,
    required this.elapsedMs,
  });

  /// Absolute path to the compressed output file.
  final String outputPath;

  /// Size of the input file, in bytes.
  final int inputBytes;

  /// Size of the output file, in bytes.
  final int outputBytes;

  /// Displayed (rotation-corrected) width of the output, in pixels.
  final int widthPx;

  /// Displayed (rotation-corrected) height of the output, in pixels.
  final int heightPx;

  /// Duration of the output, in milliseconds, from a re-probe of the finished file.
  final int durationMs;

  /// Normalised video codec of the output (for example `h264`).
  final String videoCodec;

  /// Normalised audio codec of the output, or `null` when the audio track was stripped or the
  /// source had none.
  final String? audioCodec;

  /// Whether the job ran as a transmux (container remux with no video re-encode) rather than
  /// a full encode.
  final bool transmuxed;

  /// Whether the original input bytes were copied to [outputPath] because compressing would
  /// have produced an equal-or-larger file. `outputPath` always names a file the plugin owns
  /// (never the caller's original input path) when this is `true`.
  final bool usedOriginal;

  /// Reserved for Phase 4's HDR tone-mapping. Always `false` in this phase.
  final bool toneMapped;

  /// Reserved for Phase 4's HEVC hardware-fallback handling. Always `false` in this phase.
  final bool hevcFallback;

  /// Whether the audio track was re-encoded (as opposed to passed through or stripped).
  final bool audioReencoded;

  /// Wall-clock time the compression took, in milliseconds.
  final int elapsedMs;
}

/// The typed, pre-flight prediction of what a [CompressRequestMessage] would produce, without
/// running an actual encode.
class EstimateMessage {
  EstimateMessage({
    required this.outputBytes,
    required this.durationMs,
    required this.widthPx,
    required this.heightPx,
    required this.wouldTransmux,
    required this.wouldUseOriginal,
  });

  /// Predicted size of the output, in bytes.
  final int outputBytes;

  /// Predicted duration of the output, in milliseconds.
  final int durationMs;

  /// Predicted displayed width of the output, in pixels.
  final int widthPx;

  /// Predicted displayed height of the output, in pixels.
  final int heightPx;

  /// Whether the request would run as a transmux rather than a full encode.
  final bool wouldTransmux;

  /// Whether the request would fall back to copying the original input rather than encoding.
  final bool wouldUseOriginal;
}

/// Runs and manages compression jobs. Implemented per-platform; this phase implements Android
/// only.
@HostApi()
abstract class CompressHostApi {
  /// Starts a compression job for the media at [path], identified by the caller-generated
  /// [jobId], with the given [request]. [jobId] is generated by the caller (Dart) so two jobs
  /// started back to back never race on native-side id generation.
  @async
  CompressResultMessage startCompress(
    String path,
    String jobId,
    CompressRequestMessage request,
  );

  /// Cancels the job identified by [jobId]. A no-op if the job has already finished.
  @async
  void cancel(String jobId);

  /// Returns a pre-flight [EstimateMessage] for compressing the media at [path] with
  /// [request], without running an actual encode.
  @async
  EstimateMessage estimate(String path, CompressRequestMessage request);

  /// Deletes every file the plugin has written to its own cache directory.
  @async
  void clearCache();
}

/// Progress notifications from native code back to Dart, keyed by job id. Fire-and-forget:
/// Dart does not reply to this call.
@FlutterApi()
abstract class CompressVideoFlutterApi {
  /// Reports that the job identified by [jobId] has reached [percent] (0 to 100) complete.
  void onProgress(String jobId, double percent);
}
