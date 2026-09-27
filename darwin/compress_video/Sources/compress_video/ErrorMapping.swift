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
    .unsupportedOutputSettings,
    invalidSampleCursor,
    interruptedBySystem,
  ]

  /// AVFoundation's "Invalid sample cursor" error (-11880) -- observed live reading a
  /// genuinely damaged/truncated MP4 (`truncated_mdat.mp4`, CI run 36151081384: a real
  /// `AVAssetReader` surfaced this reading past the file's truncated `mdat` box). Constructed
  /// by RAW VALUE rather than a named case literal like `.unsupportedOutputSettings` above:
  /// this exact case's Swift name was not independently confirmed against 03-RESEARCH.md's
  /// Pitfall 6 caution against guessing AVFoundation case names by analogy, and matching by the
  /// integer this SDK's own `AVError.Code(rawValue:)` already accepted (proven live by this
  /// exact failure reaching `reasonForAVError` with a non-nil `code` at all,
  /// `CompressionEngine.mapToCompressVideoError`) avoids the compile-time risk of a guessed
  /// name that may not exist on this project's iOS 13/macOS 11 deployment floor. Force-unwrapped
  /// because that same live observation is proof the initializer succeeds for this raw value.
  private static let invalidSampleCursor = AVError.Code(rawValue: -11880)!

  /// AVFoundation's own signal that the system took a job's execution time away from it before
  /// it finished (D-11, 05-04) -- observed named in an Apple engineer's own forum reply as the
  /// code an interrupted export reports (`.planning/research/sources/VIDEO_COMPRESS_BRIEF.md`
  /// §5 "Background"), quoted there as `AVError -11847`. Constructed by RAW VALUE, exactly like
  /// `invalidSampleCursor` above and for the identical reason (03-RESEARCH.md Pitfall 6): this
  /// project has already been burned once guessing an AVFoundation case name by analogy (the
  /// CONTEXT.md-prose `.decoderNotAvailable`/`.encoderNotAvailable`, which do not exist), and the
  /// plausible-sounding name for this code -- `.operationInterrupted` -- was never independently
  /// confirmed against Apple's own header or documentation, so it is deliberately not written
  /// here as a case literal. `RunnerTests.swift`'s own assertion that this raw value resolves to
  /// a real `AVError.Code` case at all runs before anything else in this file depends on it.
  private static let interruptedBySystem = AVError.Code(rawValue: -11847)!

  /// Maps `code` to a `CompressVideoErrorReason` name string (for example
  /// `"decoderUnavailable"`). A code outside `knownAVErrorCodes` returns `"unknown"` -- the
  /// caller is responsible for preserving the original `AVError` details, exactly as
  /// `CompressVideoException`'s own `reasonFromPlatformCode` round trip already does for a
  /// reason name this Dart version does not recognise.
  static func reasonForAVError(_ code: AVError.Code) -> String {
    // `invalidSampleCursor` is a raw-value-constructed `let`, not a declared enum case name --
    // a bare `case invalidSampleCursor:` inside the switch below would be parsed as a NEW
    // catch-all BINDING (Swift only treats a lowercase switch-case identifier as an existing
    // case reference when it names a real case of the switched type), silently matching every
    // code before `default` ever runs. Checked here, ahead of the switch, instead.
    if code == invalidSampleCursor {
      // -11880 ("Invalid sample cursor"): observed live reading a genuinely damaged/truncated
      // MP4 (CI run 36151081384) -- a malformed sample table is unsupported input, the same
      // bucket .fileFormatNotRecognized/.fileFailedToParse/.decodeFailed already fall into.
      return "unsupportedInput"
    }
    if code == interruptedBySystem {
      // -11847: the system took this job's execution time away from it (D-11) -- an app
      // suspension mid-export, surfaced here as a typed AVError. Retryable, not a hang and not
      // a `null` -- the ONE reason string this file maps to "interrupted".
      return "interrupted"
    }
    switch code {
    case .decoderNotFound, .decoderTemporarilyUnavailable:
      return "decoderUnavailable"
    case .encoderNotFound, .encoderTemporarilyUnavailable:
      return "encoderUnavailable"
    case .unsupportedOutputSettings:
      // -11861: the writer's own encoder session rejected an output-settings dictionary
      // canApply(outputSettings:forMediaType:) accepted as generally shaped -- confirmed live
      // in CI run 35809012150 (a too-low AAC bitrate reached the writer despite passing the
      // earlier static check). Treated as encoder-unavailable, the same bucket a device that
      // cannot support the requested settings at all falls into.
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
  /// not `AVError`-typed) to a `CompressVideoErrorReason` name string: `"interrupted"` when
  /// `error` is itself in AVFoundation's own error domain carrying the interruption code (D-11)
  /// -- a writer that fails its session after the app has resigned active can surface the
  /// condition as a plain `NSError` in that domain rather than as a typed `AVError`, so this
  /// domain-SCOPED check (never a bare numeric match against `error.code` alone, which would
  /// wrongly capture an unrelated domain's error that happens to reuse the same number) runs
  /// ahead of the out-of-space heuristic below; `"outOfSpace"` when `error`'s message indicates
  /// the destination filesystem is full (a best-effort SECONDARY defence -- the pre-flight
  /// free-space check is the primary one and does not depend on this string matching across OS
  /// versions); otherwise `"io"`.
  static func reasonForNSError(_ error: NSError) -> String {
    if error.domain == AVFoundationErrorDomain && error.code == interruptedBySystem.rawValue {
      return "interrupted"
    }
    return isOutOfSpaceMessage(error.localizedDescription) ? "outOfSpace" : "io"
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
