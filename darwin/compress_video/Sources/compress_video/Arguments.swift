import Foundation

/// Pure argument validation for a path about to be handed to a native file API, mirroring
/// Android's `Arguments.kt`.
///
/// No file API beyond `FileManager` itself is touched until this passes -- `Probe` and
/// `Thumbnails` both call this first, on every request.
enum Arguments {
  /// Resolves `path` to its canonical absolute form (symlinks resolved, matching Android's
  /// `canonicalFile`) and returns it, or throws a `CompressVideoError` naming the specific
  /// rejection reason. Requires an existing, readable, non-empty regular file.
  ///
  /// Canonicalising the path before use means a relative, traversing, or symlinked path cannot
  /// reach outside what the caller's own process could already read -- the plugin runs inside
  /// the host app's own sandbox, so this control cannot grant access the caller did not already
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

  /// Resolves `outputPath` to its canonical absolute form (symlinks resolved in whatever
  /// prefix already exists, matching Android's `canonicalFile`) and requires its parent
  /// directory to already exist and be writable, throwing a `CompressVideoError` with reason
  /// `"io"` if either requirement fails -- before any bytes are written. This is the
  /// traversal mitigation for a write destination: a canonicalised path cannot resolve outside
  /// what the caller's own process could already write, and turning a bad destination into a
  /// typed error here means the caller never sees a partial file or an unexpected native
  /// failure (including on a sandboxed macOS host app, where an arbitrary destination may
  /// simply not be writable).
  static func requireWritableOutputParent(_ outputPath: String) throws -> String {
    let standardizedPath = standardizedAbsolutePath(outputPath)
    let parentPath = (standardizedPath as NSString).deletingLastPathComponent
    let fileManager = FileManager.default

    var isOutputPathDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: standardizedPath, isDirectory: &isOutputPathDirectory),
      isOutputPathDirectory.boolValue
    {
      throw CompressVideoError(
        code: "io",
        message: "outputPath already exists as a directory",
        details: nil
      )
    }

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

  /// Returns `"unsupportedInput"` if `maxFps` is not positive, or `nil` if it is valid.
  static func validateMaxFps(_ maxFps: Int64) -> String? {
    maxFps <= 0 ? "unsupportedInput" : nil
  }

  /// Returns `"unsupportedInput"` if `maxLongSidePx` is given and below `16`, or `nil` if it
  /// is valid (including `16` itself, and including `nil`, meaning "use the preset's own
  /// value").
  static func validateMaxLongSidePx(_ maxLongSidePx: Int64?) -> String? {
    if let maxLongSidePx, maxLongSidePx < 16 {
      return "unsupportedInput"
    }
    return nil
  }

  /// Returns `"unsupportedInput"` if `videoBitrateBps` is given and not positive, or `nil` if
  /// it is valid (including `nil`, meaning "resolve it from the preset or targetSizeMb").
  static func validateVideoBitrateBps(_ videoBitrateBps: Int64?) -> String? {
    if let videoBitrateBps, videoBitrateBps <= 0 {
      return "unsupportedInput"
    }
    return nil
  }

  /// Returns `"unsupportedInput"` if `targetSizeMb` is given and is not a finite, positive
  /// number, or `nil` if it is valid (including `nil`, meaning "no target size requested").
  static func validateTargetSizeMb(_ targetSizeMb: Double?) -> String? {
    if let targetSizeMb, !targetSizeMb.isFinite || targetSizeMb <= 0 {
      return "unsupportedInput"
    }
    return nil
  }

  /// Returns `"unsupportedInput"` if `targetSizeMb` and `videoBitrateBps` are both given --
  /// contradictory targets for the same output size -- or `nil` otherwise.
  static func validateSizeTargetsNotContradictory(
    targetSizeMb: Double?,
    videoBitrateBps: Int64?
  ) -> String? {
    (targetSizeMb != nil && videoBitrateBps != nil) ? "unsupportedInput" : nil
  }

  /// Returns `"unsupportedInput"` if `trimStartMs` is negative, or if `trimEndMs` is given
  /// and not strictly greater than `trimStartMs` (defaulting to `0` when `trimStartMs` is
  /// `nil`), or `nil` if the trim range is valid.
  static func validateTrimRange(trimStartMs: Int64?, trimEndMs: Int64?) -> String? {
    if let trimStartMs, trimStartMs < 0 {
      return "unsupportedInput"
    }
    if let trimEndMs, trimEndMs <= (trimStartMs ?? 0) {
      return "unsupportedInput"
    }
    return nil
  }

  /// Returns `"unsupportedInput"` if `videoCodec` is anything other than `"h264"` -- the only
  /// accepted value in this phase; HEVC opt-in is Phase 4 -- or `nil` if it is valid.
  static func validateVideoCodec(_ videoCodec: String) -> String? {
    videoCodec != "h264" ? "unsupportedInput" : nil
  }

  /// Returns `"unsupportedInput"` if `hdrMode` is anything other than `"toneMapToSdr"` -- the
  /// only accepted value in this phase; keep-HDR opt-in is Phase 4 -- or `nil` if it is valid.
  static func validateHdrMode(_ hdrMode: String) -> String? {
    hdrMode != "toneMapToSdr" ? "unsupportedInput" : nil
  }

  /// Returns `"unsupportedInput"` when `audioMode` is `.reencode` and either
  /// `audioBitrateBps` is not positive or `audioChannels` is outside `1` to `2` inclusive, or
  /// `nil` if the combination is valid (including any other `audioMode`, where these two
  /// fields are not required to be set at all).
  static func validateAudioReencode(
    audioMode: AudioModeMessage,
    audioBitrateBps: Int64?,
    audioChannels: Int64?
  ) -> String? {
    guard audioMode == .reencode else { return nil }
    if audioBitrateBps == nil || audioBitrateBps! <= 0 {
      return "unsupportedInput"
    }
    if audioChannels == nil || audioChannels! < 1 || audioChannels! > 2 {
      return "unsupportedInput"
    }
    return nil
  }

  /// Runs every compress-request argument check, in the same order as Android's
  /// `Arguments.kt`'s `requireValidCompressRequest`, and throws a `CompressVideoError` naming
  /// the first violated reason -- or returns normally if `request` is entirely valid.
  ///
  /// Mirrors the Dart-side checks deliberately: the Dart side gives a fast local failure
  /// without crossing the channel, while this is the authority for any caller that reaches the
  /// generated host API another way.
  ///
  /// Written as a list of checks walked in order rather than one `??` chain: a ten-term
  /// `??` expression over `String?` is exactly the shape Swift's type-checker gives up on
  /// ("unable to type-check this expression in reasonable time") -- it compiled on CI's
  /// runner but failed on the MacBook Air (03-01 task 1, 2026-09-25), because the limit is
  /// wall-clock and therefore machine-dependent.
  static func requireValidCompressRequest(_ request: CompressRequestMessage) throws {
    let checks: [() -> String?] = [
      { validateMaxFps(request.maxFps) },
      { validateMaxLongSidePx(request.maxLongSidePx) },
      { validateVideoBitrateBps(request.videoBitrateBps) },
      { validateTargetSizeMb(request.targetSizeMb) },
      {
        validateSizeTargetsNotContradictory(
          targetSizeMb: request.targetSizeMb, videoBitrateBps: request.videoBitrateBps)
      },
      { validateTrimRange(trimStartMs: request.trimStartMs, trimEndMs: request.trimEndMs) },
      { validateOutputPath(request.outputPath) },
      { validateVideoCodec(request.videoCodec) },
      { validateHdrMode(request.hdrMode) },
      {
        validateAudioReencode(
          audioMode: request.audioMode,
          audioBitrateBps: request.audioBitrateBps,
          audioChannels: request.audioChannels)
      },
    ]
    for check in checks {
      if let violatedReason = check() {
        throw CompressVideoError(
          code: violatedReason,
          message: "Invalid compress request argument",
          details: nil
        )
      }
    }
  }

  /// Resolves `path` to a fully-qualified, canonical absolute filesystem path: relative paths
  /// are resolved against the current directory, redundant `.`/`..` components are removed,
  /// and any symlinks are resolved to their real target -- matching Android's
  /// `File.canonicalFile` semantics used by `Arguments.kt`'s `requireReadableMediaFile`/
  /// `requireWritableOutputParent`, and the cross-platform contract `CompressOptions
  /// .outputPath` already documents ("the native side resolves `.`/`..` segments and symbolic
  /// links before writing").
  ///
  /// `resolvingSymlinksInPath()` can only fully resolve components that already exist, which
  /// matters for `outputPath`: it names a file that is about to be *created*, so its leaf
  /// component never exists yet at validation time. Resolve symlinks in whatever prefix of the
  /// path does exist and reattach the (possibly nonexistent) remaining suffix literally --
  /// the same "canonicalise the existing prefix, append the rest" behaviour Java's
  /// `File.canonicalFile` gives on the Kotlin side for a not-yet-existing output path -- rather
  /// than silently skipping symlink resolution altogether for the entire path.
  ///
  /// The result is Unicode-normalised to NFC (`precomposedStringWithCanonicalMapping`) before
  /// being returned. `URL(fileURLWithPath:)`/`standardizedFileURL`/`resolvingSymlinksInPath()`
  /// route a path through Apple's file-system-representation conversion, which decomposes
  /// precomposed characters into NFD -- confirmed live on CI (run 36176323945): a caller-
  /// supplied `vidéo_日本語_output.mp4` (NFC, as any normal Dart string literal is) came back
  /// from this function, and therefore from `CompressResultMessage.outputPath`, byte-different
  /// at the "é" despite looking and printing identically. Both filesystems this project targets
  /// treat NFC and NFD forms of the same name as the same file for lookup purposes (confirmed by
  /// the same failing test's `resolveSymbolicLinksSync()` comparison passing either way), so
  /// normalising back to NFC here changes nothing about which file is written or read -- it only
  /// restores the byte sequence the caller (and Android's `File.canonicalFile`, which performs
  /// no such conversion at all) would otherwise expect back unchanged.
  private static func standardizedAbsolutePath(_ path: String) -> String {
    let standardizedURL = URL(fileURLWithPath: path).standardizedFileURL
    let fileManager = FileManager.default

    if fileManager.fileExists(atPath: standardizedURL.path) {
      return standardizedURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping
    }

    // Walk up from the full path to the nearest existing ancestor, resolve symlinks in that
    // ancestor, then reattach the nonexistent suffix components literally.
    var existingAncestor = standardizedURL.deletingLastPathComponent()
    var suffixComponents: [String] = [standardizedURL.lastPathComponent]
    while !fileManager.fileExists(atPath: existingAncestor.path) && existingAncestor.path != "/" {
      suffixComponents.append(existingAncestor.lastPathComponent)
      existingAncestor = existingAncestor.deletingLastPathComponent()
    }

    var resolved = existingAncestor.resolvingSymlinksInPath()
    for component in suffixComponents.reversed() {
      resolved = resolved.appendingPathComponent(component)
    }
    return resolved.standardizedFileURL.path.precomposedStringWithCanonicalMapping
  }
}
