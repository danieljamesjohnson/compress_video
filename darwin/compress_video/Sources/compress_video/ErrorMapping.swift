import AVFoundation
import Foundation

/// Pure mapping from an AVFoundation `AVError`/plain `NSError` to a `CompressVideoErrorReason`
/// name string.
///
/// Mirrors Android's `ErrorMapping.kt`: exercisable as plain Swift with no simulator and no
/// `AVAssetReader`/`AVAssetWriter` construction required -- every function here takes an
/// already-produced error value and returns a reason string; nothing here builds or drives a
/// media pipeline. `knownAVErrorCodes`'s size is asserted by a test in `RunnerTests.swift`, so
/// a code added to `reasonForAVError`'s switch without being added here fails a test instead of
/// silently falling through to `"unknown"`.
///
/// The real Swift `AVError.Code` case names -- confirmed against 03-RESEARCH.md's Pitfall 6,
/// NOT the plausible-sounding `.decoderNotAvailable` / `.encoderNotAvailable` CONTEXT.md's own
/// prose used by analogy with this project's `decoderUnavailable`/`encoderUnavailable` reason
/// strings -- are `.decoderNotFound` / `.encoderNotFound` (no suitable codec could be found)
/// and `.decoderTemporarilyUnavailable` / `.encoderTemporarilyUnavailable` (one exists but is
/// momentarily busy).
enum ErrorMapping {
  /// Every `AVError.Code` this mapping recognises. Scoped to what a local-file
  /// reader/writer/export pipeline can plausibly surface -- not `AVError`'s full case range.
  /// Asserted for size by a test so a future code added to `reasonForAVError`'s switch without
  /// being added here fails a test instead of silently degrading to `"unknown"`.
  static let knownAVErrorCodes: Set<AVError.Code> = [
    .decoderNotFound,
    .encoderNotFound,
    .decoderTemporarilyUnavailable,
    .encoderTemporarilyUnavailable,
    .diskFull,
    .fileFormatNotRecognized,
    .fileFailedToParse,
    .decodeFailed,
    .exportFailed,
    .sessionNotRunning,
    .outOfMemory,
  ]

  /// Maps `code` to a `CompressVideoErrorReason` name string (for example
  /// `"decoderUnavailable"`). A code outside `knownAVErrorCodes` returns `"unknown"` -- the
  /// caller is responsible for preserving the original `AVError` details, exactly as
  /// `CompressVideoException`'s own `reasonFromPlatformCode` round trip already does for a
  /// reason name this Dart version does not recognise.
  static func reasonForAVError(_ code: AVError.Code) -> String {
    switch code {
    case .decoderNotFound, .decoderTemporarilyUnavailable:
      return "decoderUnavailable"
    case .encoderNotFound, .encoderTemporarilyUnavailable:
      return "encoderUnavailable"
    case .diskFull:
      return "outOfSpace"
    case .fileFormatNotRecognized, .fileFailedToParse, .decodeFailed:
      return "unsupportedInput"
    case .exportFailed, .sessionNotRunning, .outOfMemory:
      return "io"
    default:
      return "unknown"
    }
  }

  /// Maps a plain `NSError` (a `reader`/`writer` `.failed` status whose underlying error is
  /// not `AVError`-typed) to a `CompressVideoErrorReason` name string: `"outOfSpace"` when
  /// `error`'s message indicates the destination filesystem is full (a best-effort SECONDARY
  /// defence -- the pre-flight free-space check is the primary one and does not depend on this
  /// string matching across OS versions), otherwise `"io"`.
  static func reasonForNSError(_ error: NSError) -> String {
    isOutOfSpaceMessage(error.localizedDescription) ? "outOfSpace" : "io"
  }

  /// The human-readable message for an `NSError` that mapped to `"io"` or `"outOfSpace"`,
  /// folding the error's domain and numeric code into the text -- mirroring Android's
  /// always-preserve-the-numeric-code rule (`mapExportException`/`reasonForExportFailure`) so
  /// a failure this table cannot name more specifically never loses its original code.
  static func messageForNSError(_ error: NSError) -> String {
    "\(error.domain) error \(error.code): \(error.localizedDescription)"
  }

  private static func isOutOfSpaceMessage(_ message: String) -> Bool {
    let lower = message.lowercased()
    return lower.contains("enospc") || lower.contains("no space left")
  }
}
