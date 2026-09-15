/// The reason a [CompressVideoException] was thrown.
///
/// The first six values were established in Phase 1 for media-info and thumbnail calls; the
/// last three were appended in Phase 2 for compression jobs. All nine are stable — no value's
/// meaning changes once added, and this order is preserved.
enum CompressVideoErrorReason {
  /// The path given did not resolve to a readable file.
  fileNotFound,

  /// The input file exists but its container or codec is not supported.
  unsupportedInput,

  /// The platform could not obtain a decoder for the input (for example, a codec the device's
  /// hardware and software decoders both refuse).
  decoderUnavailable,

  /// A platform I/O error occurred that is not one of the more specific reasons above (for
  /// example, a read or write failure unrelated to the input format itself).
  io,

  /// The operation was cancelled before it completed.
  cancelled,

  /// The platform reported an error code this version of the plugin does not recognise.
  ///
  /// The original platform error code is preserved in [CompressVideoException.platformDetail]
  /// so it is never silently discarded.
  unknown,

  /// The device could not obtain or configure an encoder for the requested output.
  encoderUnavailable,

  /// The destination filesystem does not have room for the output.
  outOfSpace,

  /// The operation was interrupted by the system before it completed and can be retried.
  /// Thrown only by the Apple engine (Phase 5), but present in the taxonomy now so this enum's
  /// shape does not change later.
  interrupted,
}

/// Maps a native platform error code to a [CompressVideoErrorReason].
///
/// Native code throws with the reason's enum name (for example `"fileNotFound"`) as the error
/// code. Any code that does not match one of [CompressVideoErrorReason]'s value names — including
/// a code introduced by a newer native implementation that this Dart version predates — maps to
/// [CompressVideoErrorReason.unknown] rather than throwing or silently dropping the detail.
CompressVideoErrorReason reasonFromPlatformCode(String code) {
  for (final CompressVideoErrorReason reason
      in CompressVideoErrorReason.values) {
    if (reason.name == code) {
      return reason;
    }
  }
  return CompressVideoErrorReason.unknown;
}

/// Thrown when a `compress_video` call fails.
///
/// No public API call in this plugin ever resolves to `null` or lets a raw platform exception
/// escape; every failure completes the call's `Future` with a `CompressVideoException` instead.
class CompressVideoException implements Exception {
  /// Creates a [CompressVideoException].
  const CompressVideoException({
    required this.reason,
    required this.message,
    this.platformDetail,
  });

  /// The category of failure. See [CompressVideoErrorReason].
  final CompressVideoErrorReason reason;

  /// A human-readable description of what went wrong.
  final String message;

  /// The original platform error code or detail string, when available.
  ///
  /// Populated whenever [reason] is [CompressVideoErrorReason.unknown] so the original signal
  /// from the platform is never discarded, and may also be populated for other reasons when the
  /// platform provides extra detail.
  final String? platformDetail;

  @override
  String toString() =>
      'CompressVideoException(${reason.name}): $message'
      '${platformDetail != null ? ' (platformDetail: $platformDetail)' : ''}';
}
