import 'package:flutter/foundation.dart' show immutable;

/// The typed result of a completed compression job.
///
/// Every field is populated from a re-probe of the finished output file, never from the
/// native export engine's own approximate fields (02-RESEARCH.md Pitfall 4). A compression
/// call never resolves to `null` -- every failure completes with a `CompressVideoException`
/// instead.
@immutable
class CompressResult {
  /// Creates a [CompressResult]. Application code does not normally construct this directly --
  /// instances are returned by a [CompressJob]'s `result` future.
  const CompressResult({
    required this.outputPath,
    required this.inputBytes,
    required this.outputBytes,
    required this.widthPx,
    required this.heightPx,
    required this.durationMs,
    required this.videoCodec,
    required this.audioCodec,
    required this.transmuxed,
    required this.usedOriginal,
    required this.toneMapped,
    required this.hevcFallback,
    required this.audioReencoded,
    required this.elapsedMs,
  });

  /// Absolute path to the compressed output file. Always a file the plugin owns -- even when
  /// [usedOriginal] is `true`, this never names the caller's own input path.
  final String outputPath;

  /// Size of the input file, in bytes.
  final int inputBytes;

  /// Size of the output file, in bytes.
  final int outputBytes;

  /// Displayed (rotation-corrected) width of the output, in pixels -- the width a player shows,
  /// never the coded, pre-rotation width. This is exactly the field pair the incumbent
  /// (`video_compress`) reported backwards for a rotated source.
  final int widthPx;

  /// Displayed (rotation-corrected) height of the output, in pixels -- the height a player
  /// shows, never the coded, pre-rotation height.
  final int heightPx;

  /// Duration of the output, in milliseconds, from a re-probe of the finished file.
  final int durationMs;

  /// Normalised video codec of the output (for example `h264`).
  final String videoCodec;

  /// Normalised audio codec of the output, or `null` exactly when there is no audio track in
  /// the output -- because it was stripped, or the source had none to begin with. This
  /// describes the file that was produced, not the [AudioOptions] that were requested: reading
  /// this field is reading the file, not the plan.
  final String? audioCodec;

  /// Whether the file at [outputPath] is the result of a transmux (container remux with no
  /// video re-encode) rather than a full encode. Always `false` when [usedOriginal] is `true`:
  /// a remux is re-verified against the input's own byte count exactly like a real encode is,
  /// and one that did not come out smaller than or equal to the input is discarded in favour of
  /// the original -- never larger makes a promise about the file the caller receives, and that
  /// promise does not have an exception for a remux whose container ended up bigger than the
  /// input.
  final bool transmuxed;

  /// Whether the original input bytes were copied to [outputPath] because compressing --
  /// whether by a full encode or by a transmux -- would have produced (or did produce) an
  /// equal-or-larger file. When `true`, [outputPath] is still a file the plugin owns (a copy
  /// under its own cache directory, or the caller's requested `outputPath`) -- never the
  /// caller's original input path, so a caller who deletes [outputPath] never destroys their
  /// original.
  final bool usedOriginal;

  /// Reserved for Phase 4's HDR tone-mapping. Always `false` in this phase.
  final bool toneMapped;

  /// Reserved for Phase 4's HEVC hardware-fallback handling. Always `false` in this phase.
  final bool hevcFallback;

  /// Whether the audio track was re-encoded (as opposed to passed through or stripped). Read
  /// from the platform export's own record of what actually happened to the track, never from
  /// the [AudioOptions] that were requested -- an [AudioPassthrough] request that fell back to
  /// an AAC re-encode (because the source wasn't already MP4-compatible AAC) reports `true`
  /// here, exactly like an explicit [AudioReencode] would, so this field always describes the
  /// file the caller received rather than the option they asked for.
  final bool audioReencoded;

  /// Wall-clock time the compression took, in milliseconds.
  final int elapsedMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CompressResult &&
          other.outputPath == outputPath &&
          other.inputBytes == inputBytes &&
          other.outputBytes == outputBytes &&
          other.widthPx == widthPx &&
          other.heightPx == heightPx &&
          other.durationMs == durationMs &&
          other.videoCodec == videoCodec &&
          other.audioCodec == audioCodec &&
          other.transmuxed == transmuxed &&
          other.usedOriginal == usedOriginal &&
          other.toneMapped == toneMapped &&
          other.hevcFallback == hevcFallback &&
          other.audioReencoded == audioReencoded &&
          other.elapsedMs == elapsedMs);

  @override
  int get hashCode => Object.hash(
    outputPath,
    inputBytes,
    outputBytes,
    widthPx,
    heightPx,
    durationMs,
    videoCodec,
    audioCodec,
    transmuxed,
    usedOriginal,
    Object.hash(toneMapped, hevcFallback, audioReencoded, elapsedMs),
  );

  @override
  String toString() =>
      'CompressResult(outputPath: $outputPath, inputBytes: $inputBytes, '
      'outputBytes: $outputBytes, widthPx: $widthPx, heightPx: $heightPx, '
      'durationMs: $durationMs, videoCodec: $videoCodec, audioCodec: $audioCodec, '
      'transmuxed: $transmuxed, usedOriginal: $usedOriginal, toneMapped: $toneMapped, '
      'hevcFallback: $hevcFallback, audioReencoded: $audioReencoded, elapsedMs: $elapsedMs)';
}

/// The typed, pre-flight prediction of what a `compress` call would produce, without running
/// an actual encode, decoding a single frame, or building a native transcoder at all.
///
/// Every field is computed by probing the input file and running it through the SAME pure
/// resolution function (`SizeGuard.kt` on Android) the real `compress` call itself uses -- so
/// this prediction and the job it predicts can never recommend a different path (D-19,
/// INFO-03): [wouldTransmux] and [wouldUseOriginal] are read from that resolver, not
/// re-derived, and an integration test asserts they agree with [CompressResult.transmuxed]/
/// [CompressResult.usedOriginal] for the same request.
@immutable
class CompressEstimate {
  /// Creates a [CompressEstimate]. Application code does not normally construct this directly
  /// -- instances are returned by `CompressVideo.estimate`.
  const CompressEstimate({
    required this.outputBytes,
    required this.durationMs,
    required this.widthPx,
    required this.heightPx,
    required this.wouldTransmux,
    required this.wouldUseOriginal,
  });

  /// Predicted size of the output, in bytes.
  ///
  /// This is a PREDICTION, not a measurement, computed from the same target bitrate/duration
  /// arithmetic the real encode resolves (`SizeGuardTest.kt` proves that arithmetic is exact).
  /// The formula's DESIGNED target is plus or minus 15 percent of the byte count a real encode
  /// produces for a genuinely-compressible source.
  ///
  /// Measured live on this project's danserver emulator's software H.264 encoder, at every one
  /// of the four presets against this project's high-bitrate corpus clip, the real encode's
  /// actual byte count diverged from this prediction by far more than 15 percent in three of
  /// the four cases (measured 7.9 to 67.0 percent, not monotonic with resolution) -- consistent
  /// with the SAME real, already-documented software-encoder CBR rate-control characteristic
  /// `CompressOptions.targetSizeMb`'s own dartdoc describes, not a new arithmetic bug. This is a
  /// flagged, deliberately unresolved assumption (see 02-07-PLAN.md's "Flagged assumptions" and
  /// `QUESTIONS.md` #3): whether a real phone's hardware encoder holds nearer the designed 15
  /// percent, or diverges differently again, is untested pending physical-device verification.
  /// The emulator integration test uses a documented, wider 75 percent tolerance for this
  /// reason -- treat this prediction as a rough, not a precise, budget until that is resolved.
  final int outputBytes;

  /// Predicted duration of the output, in milliseconds -- the trimmed duration when a trim is
  /// requested, otherwise the input's own duration.
  final int durationMs;

  /// Predicted displayed width of the output, in pixels -- the exact dimension the real job
  /// would produce for the same input and options, since both are resolved by the same
  /// function.
  final int widthPx;

  /// Predicted displayed height of the output, in pixels -- the exact dimension the real job
  /// would produce for the same input and options, since both are resolved by the same
  /// function.
  final int heightPx;

  /// Whether the request would run as a transmux (container remux, no video re-encode) rather
  /// than a full encode.
  ///
  /// This is the SAME predicate [CompressResult.transmuxed]'s real job resolves against --
  /// they cannot disagree about which operation would be attempted. It is still a pre-flight
  /// recommendation, not a guarantee about the bytes a real job would end up returning: a real
  /// job re-verifies the actual output against the never-larger rule after it runs, exactly as
  /// [CompressResult.transmuxed]'s own dartdoc describes.
  final bool wouldTransmux;

  /// Whether the request would fall back to copying the original input rather than encoding.
  ///
  /// This is the SAME predicate [CompressResult.usedOriginal]'s real job resolves against --
  /// they cannot disagree about which operation would be attempted.
  final bool wouldUseOriginal;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CompressEstimate &&
          other.outputBytes == outputBytes &&
          other.durationMs == durationMs &&
          other.widthPx == widthPx &&
          other.heightPx == heightPx &&
          other.wouldTransmux == wouldTransmux &&
          other.wouldUseOriginal == wouldUseOriginal);

  @override
  int get hashCode => Object.hash(
    outputBytes,
    durationMs,
    widthPx,
    heightPx,
    wouldTransmux,
    wouldUseOriginal,
  );

  @override
  String toString() =>
      'CompressEstimate(outputBytes: $outputBytes, durationMs: $durationMs, '
      'widthPx: $widthPx, heightPx: $heightPx, wouldTransmux: $wouldTransmux, '
      'wouldUseOriginal: $wouldUseOriginal)';
}
