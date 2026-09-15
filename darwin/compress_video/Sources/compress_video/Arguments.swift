import Foundation

/// Pure argument validation for a path about to be handed to a native file API, mirroring
/// Android's `Arguments.kt`.
///
/// No file API beyond `FileManager` itself is touched until this passes -- `Probe` and
/// `Thumbnails` both call this first, on every request.
enum Arguments {
  /// Resolves `path` to its standardised absolute form and returns it, or throws a
  /// `CompressVideoError` naming the specific rejection reason. Requires an existing,
  /// readable, non-empty regular file.
  ///
  /// Standardising the path before use means a relative or traversing path cannot reach
  /// outside what the caller's own process could already read -- the plugin runs inside the
  /// host app's own sandbox, so this control cannot grant access the caller did not already
  /// have. It exists to turn a traversal attempt into a typed `CompressVideoError` instead of
  /// an unexpected native failure.
  static func requireReadableMediaFile(_ path: String) throws -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      throw CompressVideoError(
        code: "unsupportedInput",
        message: "path must not be empty or whitespace-only",
        details: nil
      )
    }

    let standardizedPath = standardizedAbsolutePath(path)
    let fileManager = FileManager.default

    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: standardizedPath, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      throw CompressVideoError(
        code: "fileNotFound",
        message: "No readable file at the given path",
        details: nil
      )
    }
    guard fileManager.isReadableFile(atPath: standardizedPath) else {
      throw CompressVideoError(
        code: "fileNotFound",
        message: "File exists but is not readable",
        details: nil
      )
    }

    let sizeBytes: Int64
    do {
      let attributes = try fileManager.attributesOfItem(atPath: standardizedPath)
      sizeBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    } catch {
      throw CompressVideoError(
        code: "fileNotFound",
        message: "Could not read file attributes",
        details: error.localizedDescription
      )
    }
    if sizeBytes == 0 {
      throw CompressVideoError(code: "unsupportedInput", message: "File is empty", details: nil)
    }

    return standardizedPath
  }

  /// Resolves `outputPath` to its standardised absolute form and requires its parent
  /// directory to already exist and be writable, throwing a `CompressVideoError` with reason
  /// `"io"` if either requirement fails -- before any bytes are written. This is the
  /// traversal mitigation for a write destination: a standardised path cannot resolve outside
  /// what the caller's own process could already write, and turning a bad destination into a
  /// typed error here means the caller never sees a partial file or an unexpected native
  /// failure (including on a sandboxed macOS host app, where an arbitrary destination may
  /// simply not be writable).
  static func requireWritableOutputParent(_ outputPath: String) throws -> String {
    let standardizedPath = standardizedAbsolutePath(outputPath)
    let parentPath = (standardizedPath as NSString).deletingLastPathComponent
    let fileManager = FileManager.default

    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: parentPath, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw CompressVideoError(
        code: "io",
        message: "outputPath's parent directory does not exist",
        details: nil
      )
    }
    guard fileManager.isWritableFile(atPath: parentPath) else {
      throw CompressVideoError(
        code: "io",
        message: "outputPath's parent directory is not writable",
        details: nil
      )
    }

    return standardizedPath
  }

  /// Returns `"unsupportedInput"` if `positionMs` is negative, or `nil` if it is valid.
  ///
  /// There is no frame before the start of a clip, so a negative position is a caller bug --
  /// this is deliberately an error rather than a silent clamp to `0`, which would hide it.
  static func validatePositionMs(_ positionMs: Int64) -> String? {
    positionMs < 0 ? "unsupportedInput" : nil
  }

  /// Returns `"unsupportedInput"` if `quality` is outside 1 to 100 inclusive (the JPEG
  /// quality range the option name promises), or `nil` if it is valid.
  static func validateQuality(_ quality: Int64) -> String? {
    (quality < 1 || quality > 100) ? "unsupportedInput" : nil
  }

  /// Returns `"unsupportedInput"` if `maxDimensionPx` is given and not positive, or `nil` if
  /// it is valid (including when it is `nil`, meaning "no cap").
  static func validateMaxDimensionPx(_ maxDimensionPx: Int64?) -> String? {
    if let maxDimensionPx, maxDimensionPx <= 0 {
      return "unsupportedInput"
    }
    return nil
  }

  /// Returns `"unsupportedInput"` if `outputPath` is given and blank, or `nil` if it is valid
  /// (including when it is `nil`, meaning "use the default cache location").
  static func validateOutputPath(_ outputPath: String?) -> String? {
    if let outputPath, outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "unsupportedInput"
    }
    return nil
  }

  /// Runs every thumbnail argument check and throws a `CompressVideoError` naming the first
  /// violated reason, or returns normally if all four are valid.
  ///
  /// These mirror the Dart-side checks in `CompressVideo` deliberately: the Dart side gives a
  /// fast local failure without crossing the channel, while this is the authority for any
  /// caller that reaches the channel another way (for example, a different language binding
  /// calling the generated host API directly).
  static func requireValidThumbnailArgs(
    positionMs: Int64,
    quality: Int64,
    maxDimensionPx: Int64?,
    outputPath: String?
  ) throws {
    let violatedReason =
      validatePositionMs(positionMs)
      ?? validateQuality(quality)
      ?? validateMaxDimensionPx(maxDimensionPx)
      ?? validateOutputPath(outputPath)
    if let violatedReason {
      throw CompressVideoError(
        code: violatedReason,
        message: "Invalid thumbnail argument",
        details: nil
      )
    }
  }

  /// Resolves `path` to a fully-qualified, standardised absolute filesystem path: relative
  /// paths are resolved against the current directory, and redundant `.`/`..` components are
  /// removed. Does not resolve symlinks -- this is standardisation, not canonicalisation.
  private static func standardizedAbsolutePath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
  }
}
