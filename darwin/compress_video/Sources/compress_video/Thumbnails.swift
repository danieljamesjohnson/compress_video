import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import Security

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import Cocoa
  import FlutterMacOS
#endif

/// `ThumbnailHostApi` implementation: extracts a rotation-correct poster frame via
/// `AVAssetImageGenerator`, exactly as `Probe` does for media info.
///
/// `getThumbnail` and `getThumbnailFile` share one frame-extraction-and-encode path
/// (`extractThumbnailJpeg`) so the two entry points can never drift apart in how they convert
/// `positionMs`, scale, or encode -- only where the resulting bytes end up differs.
final class Thumbnails: ThumbnailHostApi {
  func getThumbnail(
    path: String,
    positionMs: Int64,
    quality: Int64,
    maxDimensionPx: Int64?
  ) async throws -> FlutterStandardTypedData {
    try Arguments.requireValidThumbnailArgs(
      positionMs: positionMs,
      quality: quality,
      maxDimensionPx: maxDimensionPx,
      outputPath: nil
    )
    let jpegData = try await extractThumbnailJpeg(
      path: path,
      positionMs: positionMs,
      quality: quality,
      maxDimensionPx: maxDimensionPx
    )
    return FlutterStandardTypedData(bytes: jpegData)
  }

  func getThumbnailFile(
    path: String,
    positionMs: Int64,
    quality: Int64,
    maxDimensionPx: Int64?,
    outputPath: String?
  ) async throws -> String {
    try Arguments.requireValidThumbnailArgs(
      positionMs: positionMs,
      quality: quality,
      maxDimensionPx: maxDimensionPx,
      outputPath: outputPath
    )
    let jpegData = try await extractThumbnailJpeg(
      path: path,
      positionMs: positionMs,
      quality: quality,
      maxDimensionPx: maxDimensionPx
    )
    return try writeJpegAtomically(jpegData, outputPath: outputPath)
  }

  /// Reads the requested frame from `path` at `positionMs` and returns it JPEG-encoded at
  /// `quality`, with the longer displayed side capped at `maxDimensionPx` (never upscaled).
  ///
  /// `positionMs` is clamped to the media's duration (a value past the end returns the last
  /// frame rather than erroring, matching `MediaMath.clampPositionMs`'s pinned contract) and
  /// then used to build the requested `CMTime` at a timescale of 1000 -- the single conversion
  /// point in this class, mirroring the single multiply on Android. `appliesPreferredTrackTransform`
  /// is set explicitly (its documented default is `false`) and both time tolerances are zero,
  /// so the returned frame is the exact one at the requested moment, upright.
  private func extractThumbnailJpeg(
    path: String,
    positionMs: Int64,
    quality: Int64,
    maxDimensionPx: Int64?
  ) async throws -> Data {
    let standardizedPath = try Arguments.requireReadableMediaFile(path)
    let asset = AVURLAsset(url: URL(fileURLWithPath: standardizedPath))

    let duration: CMTime
    let videoTracks: [AVAssetTrack]
    do {
      if #available(iOS 16, macOS 13, *) {
        duration = try await asset.load(.duration)
        videoTracks = try await asset.loadTracks(withMediaType: .video)
      } else {
        try await awaitLegacyLoad(asset, keys: ["duration", "tracks"])
        duration = asset.duration
        videoTracks = asset.tracks(withMediaType: .video)
      }
    } catch let error as CompressVideoError {
      throw error
    } catch {
      throw CompressVideoError(
        code: "unsupportedInput",
        message: "The platform could not read this file as media",
        details: error.localizedDescription
      )
    }

    guard let track = videoTracks.first else {
      throw CompressVideoError(code: "unsupportedInput", message: "No video track found", details: nil)
    }

    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    do {
      if #available(iOS 16, macOS 13, *) {
        naturalSize = try await track.load(.naturalSize)
        preferredTransform = try await track.load(.preferredTransform)
      } else {
        try await awaitLegacyLoad(track, keys: ["naturalSize", "preferredTransform"])
        naturalSize = track.naturalSize
        preferredTransform = track.preferredTransform
      }
    } catch let error as CompressVideoError {
      throw error
    } catch {
      throw CompressVideoError(
        code: "unsupportedInput",
        message: "Could not read the video track",
        details: error.localizedDescription
      )
    }

    let rotationDegrees = MediaMath.rotationDegrees(from: preferredTransform)
    let displayedSize = MediaMath.displayedSize(
      codedWidthPx: Int(naturalSize.width.rounded()),
      codedHeightPx: Int(naturalSize.height.rounded()),
      rotationDegrees: rotationDegrees
    )
    let targetSize = MediaMath.scaledSize(
      displayedWidthPx: displayedSize.width,
      displayedHeightPx: displayedSize.height,
      maxDimensionPx: maxDimensionPx.map { Int($0) }
    )

    // durationMs -> the single ms-timescale conversion point on this platform. The requested
    // CMTime below reuses this same timescale symbolically (never a second `1000` literal),
    // so the clamped positionMs is expressed at exactly the timescale this conversion produced.
    let convertedDuration = CMTimeConvertScale(duration, timescale: 1000, method: .roundHalfAwayFromZero)
    let clampedPositionMs = MediaMath.clampPositionMs(positionMs, durationMs: convertedDuration.value)
    let requestedTime = CMTime(value: clampedPositionMs, timescale: convertedDuration.timescale)

    let generator = AVAssetImageGenerator(asset: asset)
    // Documented default is false -- every rotated thumbnail comes back sideways without this.
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    if maxDimensionPx != nil {
      generator.maximumSize = CGSize(width: targetSize.width, height: targetSize.height)
    }

    let decodedImage = try await copyCGImage(generator: generator, at: requestedTime)
    // AVAssetImageGenerator's `maximumSize` is a fit-within bounding box (scaled by whichever
    // dimension is more constraining), not two independent exact output dimensions -- the same
    // platform quirk 01-05-SUMMARY.md documented for Android's getScaledFrameAtTime (confirmed
    // live: a maxDimensionPx=1919 request came back at height 1918, not 1919, because
    // MediaMath.scaledSize's independently-rounded target box isn't perfectly proportional to
    // the source's exact aspect ratio). Snap to the exact target unconditionally so the
    // observable output matches MediaMath.scaledSize's pure-math contract exactly, regardless
    // of platform decode-box rounding.
    let exactlySizedImage = resizedIfNeeded(decodedImage, to: targetSize)
    return try encodeJpeg(exactlySizedImage, quality: quality)
  }

  /// Resizes `cgImage` to exactly `targetSize` if it isn't already that size, drawing into a
  /// fresh device-RGB bitmap context. Falls back to the original image (never crashes) if the
  /// context cannot be created.
  private func resizedIfNeeded(_ cgImage: CGImage, to targetSize: (width: Int, height: Int)) -> CGImage {
    if cgImage.width == targetSize.width && cgImage.height == targetSize.height {
      return cgImage
    }
    guard
      let context = CGContext(
        data: nil,
        width: targetSize.width,
        height: targetSize.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return cgImage
    }
    context.interpolationQuality = .high
    context.draw(
      cgImage,
      in: CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height)
    )
    return context.makeImage() ?? cgImage
  }

  /// Generates the image at `time` using the completion-handler generation API (works down to
  /// iOS 13, unlike the async `image(at:)` API which requires a newer minimum), surfacing a
  /// generation failure as `unsupportedInput`.
  private func copyCGImage(generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
      generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, error in
        switch result {
        case .succeeded:
          if let cgImage {
            continuation.resume(returning: cgImage)
          } else {
            continuation.resume(
              throwing: CompressVideoError(
                code: "unsupportedInput",
                message: "No frame could be decoded at the requested position",
                details: nil
              )
            )
          }
        default:
          continuation.resume(
            throwing: CompressVideoError(
              code: "unsupportedInput",
              message: "No frame could be decoded at the requested position",
              details: error?.localizedDescription
            )
          )
        }
      }
    }
  }

  /// Encodes `cgImage` to JPEG at `quality` (1-100, converted to the 0-1 compression factor
  /// both platform encoders expect). iOS wraps it in a `UIImage`; macOS wraps it in an
  /// `NSBitmapImageRep` -- the one platform branch this file needs beyond the shared
  /// import block.
  private func encodeJpeg(_ cgImage: CGImage, quality: Int64) throws -> Data {
    let compressionFactor = CGFloat(quality) / 100.0
    #if os(iOS)
      let image = UIImage(cgImage: cgImage)
      guard let jpegData = image.jpegData(compressionQuality: compressionFactor) else {
        throw CompressVideoError(code: "io", message: "Could not encode JPEG", details: nil)
      }
      return jpegData
    #elseif os(macOS)
      let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
      guard
        let jpegData = bitmapRep.representation(
          using: .jpeg,
          properties: [.compressionFactor: compressionFactor]
        )
      else {
        throw CompressVideoError(code: "io", message: "Could not encode JPEG", details: nil)
      }
      return jpegData
    #endif
  }

  /// Writes `jpegData` to a unique name inside the app's `compress_video` caches
  /// subdirectory, or to `outputPath` when given, and returns the destination's standardised
  /// absolute path.
  ///
  /// `Data.write(to:options:.atomic)` writes to a temporary file first and renames it into
  /// place, so a failure mid-write never leaves a truncated JPEG at the destination -- this
  /// never touches `path` (the caller's input video); only the destination file is ever
  /// written here.
  ///
  /// `destinationPath` is normalised to NFC (`precomposedStringWithCanonicalMapping`) before
  /// being returned, mirroring `CompressionEngine.buildResult`'s own fix for the identical
  /// Unicode-decomposition hazard (CI runs 36176323945, 36181752118): any `String` that has
  /// been through a file URL's `.path` getter on Darwin can come back NFD regardless of what
  /// Unicode form went in. The explicit-`outputPath` branch below is already NFC end to end
  /// (`Arguments.requireWritableOutputParent`'s own return value is used directly, with no
  /// further `URL(fileURLWithPath:)`-then-`.path` round trip), and the generated-filename
  /// branch is ASCII-only (no decomposable characters), so normalising here is a defensive
  /// no-op on the current code paths rather than a fix for an observed failure -- kept so a
  /// future change to either branch cannot silently reopen the same bug.
  private func writeJpegAtomically(_ jpegData: Data, outputPath: String?) throws -> String {
    let destinationPath: String
    if let outputPath {
      destinationPath = try Arguments.requireWritableOutputParent(outputPath)
    } else {
      // Shares PluginFiles.cacheSubDir() with CompressionEngine's own output placement (D-12)
      // -- not a second, coincidentally-identical path computation -- so a thumbnail this
      // plugin wrote is reclaimed by the same Compression.clearCache() sweep as a compression
      // output, matching what Android's Phase 2 Thumbnails.kt already does.
      let cacheDirectory = try PluginFiles.cacheSubDir()
      destinationPath = cacheDirectory.appendingPathComponent(uniqueThumbnailFileName()).path
    }

    do {
      try jpegData.write(to: URL(fileURLWithPath: destinationPath), options: .atomic)
    } catch {
      throw CompressVideoError(
        code: "io",
        message: "Failed to write thumbnail file",
        details: error.localizedDescription
      )
    }

    return destinationPath.precomposedStringWithCanonicalMapping
  }

  /// A `.jpg` filename unique per call -- epoch milliseconds plus an 8-character random hex
  /// suffix, so a millisecond collision is additionally broken by the random component and
  /// two calls for the same input and position never overwrite each other.
  private func uniqueThumbnailFileName() -> String {
    let epochMillis = Int64((Date().timeIntervalSince1970 * 1000).rounded())
    return "compress_video_thumb_\(epochMillis)_\(randomHex(8)).jpg"
  }

  private func randomHex(_ length: Int) -> String {
    let byteCount = (length + 1) / 2
    var bytes = [UInt8](repeating: 0, count: byteCount)
    let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
    if status != errSecSuccess {
      // Fall back to a non-cryptographic source rather than failing the whole thumbnail
      // write over a naming collision that only needs to be astronomically unlikely, not
      // cryptographically hardened.
      bytes = (0..<byteCount).map { _ in UInt8.random(in: 0...255) }
    }
    let hex = bytes.map { String(format: "%02x", $0) }.joined()
    return String(hex.prefix(length))
  }

  /// Awaits legacy (`loadValuesAsynchronously`) loading of `keys` on `keyValueLoadable`
  /// (the iOS-13/macOS-11-compatible path), throwing if any key fails to load.
  private func awaitLegacyLoad(
    _ keyValueLoadable: AVAsynchronousKeyValueLoading,
    keys: [String]
  ) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      keyValueLoadable.loadValuesAsynchronously(forKeys: keys) {
        for key in keys {
          var error: NSError?
          let status = keyValueLoadable.statusOfValue(forKey: key, error: &error)
          if status != .loaded {
            continuation.resume(
              throwing: CompressVideoError(
                code: "unsupportedInput",
                message: "Could not load '\(key)'",
                details: error?.localizedDescription
              )
            )
            return
          }
        }
        continuation.resume(returning: ())
      }
    }
  }
}
