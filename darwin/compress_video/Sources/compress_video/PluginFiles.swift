import Foundation

/// The single definition of where this plugin writes files, and the atomic-write/delete
/// helpers every file-producing native call in this plugin shares.
///
/// Mirrors Android's `PluginFiles.kt`. Every file this plugin creates lives inside the
/// `compress_video` subdirectory of the app's own cache directory -- never external or shared
/// storage, and no storage permission is ever requested. Path canonicalisation reuses
/// `Arguments.swift`'s own `resolvingSymlinksInPath()` idiom rather than inventing a second
/// one.
enum PluginFiles {
  /// Returns the plugin's own cache subdirectory, creating it if it does not already exist.
  /// Throws a `CompressVideoError` with reason `"io"` if it cannot be resolved or created.
  static func cacheSubDir() throws -> URL {
    guard
      let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else {
      throw CompressVideoError(
        code: "io", message: "Could not resolve the caches directory", details: nil)
    }
    let dir = cachesDir.appendingPathComponent("compress_video", isDirectory: true)
    if !FileManager.default.fileExists(atPath: dir.path) {
      do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      } catch {
        throw CompressVideoError(
          code: "io",
          message: "Could not create the plugin cache directory",
          details: error.localizedDescription
        )
      }
    }
    return dir
  }

  /// Returns a temp file beside `destination` -- the same directory, so the later
  /// `moveIntoPlace` rename is atomic on every filesystem.
  static func tempFileBeside(_ destination: URL) -> URL {
    let name = "\(destination.lastPathComponent).tmp-\(randomHex(8))"
    return destination.deletingLastPathComponent().appendingPathComponent(name)
  }

  /// Renames `tempFile` into `destination`, throwing a `CompressVideoError` with reason
  /// `"io"` on failure. Touches no file other than these two.
  ///
  /// Unlike Android's `File.renameTo` (an atomic POSIX rename that transparently replaces an
  /// existing destination), Foundation's `FileManager.moveItem` throws if `destination` already
  /// exists -- this plugin's destinations are always freshly-resolved, job-scoped paths, so an
  /// existing destination is the rare case of a caller reusing an `outputPath`; it is removed
  /// first so the move can proceed, mirroring the same final observable state.
  static func moveIntoPlace(tempFile: URL, destination: URL) throws {
    do {
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.moveItem(at: tempFile, to: destination)
    } catch {
      throw CompressVideoError(
        code: "io",
        message: "Could not move the output into place",
        details: error.localizedDescription
      )
    }
  }

  /// Deletes `file` if it exists, ignoring the result -- used on every failure/cancel path.
  static func quietDelete(_ file: URL?) {
    guard let file else { return }
    try? FileManager.default.removeItem(at: file)
  }

  /// Deletes the immediate contents of `cacheDir`, except `skipResolvedPaths` (files a
  /// still-running job owns) and anything whose resolved (symlinks-resolved) path falls
  /// outside `cacheDir`'s own resolved path -- a symbolic link placed inside the directory
  /// cannot be used to walk a delete outside it (T-03-06). A no-op, not an error, when
  /// `cacheDir` does not exist. Returns the count deleted.
  ///
  /// A single, bounded directory listing over `cacheDir` itself -- never a recursive tree
  /// walk (T-03-07), and never a touch of `cacheDir`'s own parent. A subdirectory placed
  /// inside `cacheDir` is deleted only when it is already empty -- unlike Android's
  /// `File.delete()` (which simply fails on a non-empty directory), Foundation's
  /// `FileManager.removeItem` recursively deletes a non-empty directory's entire contents, so
  /// this sweep checks each directory entry's own (single-level, non-recursive) listing first
  /// and skips it outright when non-empty, rather than ever walking into it -- what T-03-07's
  /// test proves by planting a file inside a subdirectory and asserting it survives.
  @discardableResult
  static func sweep(cacheDir: URL, skipResolvedPaths: Set<String>) -> Int {
    let resolvedCacheDir = cacheDir.resolvingSymlinksInPath()
    let cacheDirPrefix = resolvedCacheDir.path + "/"

    guard
      let entries = try? FileManager.default.contentsOfDirectory(
        at: cacheDir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
    else {
      return 0
    }

    var deletedCount = 0
    for entry in entries {
      let resolvedEntry = entry.resolvingSymlinksInPath()
      guard resolvedEntry.path.hasPrefix(cacheDirPrefix) else {
        // Escapes the plugin's own directory (a symbolic link pointing elsewhere) -- never
        // delete something this sweep did not create.
        continue
      }
      if skipResolvedPaths.contains(resolvedEntry.path) {
        continue
      }
      let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
      if isDirectory {
        let subContents = try? FileManager.default.contentsOfDirectory(
          at: entry, includingPropertiesForKeys: nil, options: [])
        guard subContents?.isEmpty == true else {
          continue
        }
      }
      if (try? FileManager.default.removeItem(at: entry)) != nil {
        deletedCount += 1
      }
    }
    return deletedCount
  }

  /// A short random hex suffix for `tempFileBeside`, using Swift's default (CSPRNG-backed on
  /// Apple platforms) random number generator -- no `Security` framework import needed for a
  /// uniqueness suffix, not a cryptographic secret. Builds each byte's hex pair with
  /// `String(_:radix:)` rather than `String(format:)`, which avoids a `UInt8`-into-varargs
  /// promotion pitfall entirely.
  private static func randomHex(_ length: Int) -> String {
    let byteCount = (length + 1) / 2
    let hex = (0..<byteCount)
      .map { _ -> String in
        let byte = UInt8.random(in: 0...255)
        let hexPair = String(byte, radix: 16)
        return byte < 16 ? "0" + hexPair : hexPair
      }
      .joined()
    return String(hex.prefix(length))
  }
}
