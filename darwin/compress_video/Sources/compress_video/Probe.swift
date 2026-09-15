import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// `ProbeHostApi` implementation: reads media info via `AVAsset`/`AVAssetTrack`, mirroring
/// Android's `Probe.kt` field for field.
///
/// Holds no shared mutable request state, so two calls in flight at once never cross replies
/// -- every local below is this call's own. The modern awaited property-loading API
/// (`load(_:)`) is used when available; the completion-handler
/// (`loadValuesAsynchronously(forKeys:)`) API is used below it, so this builds and runs at
/// iOS 13 and macOS 11 -- both paths read the same underlying values.
final class Probe: ProbeHostApi {
  func getMediaInfo(path: String) async throws -> MediaInfoMessage {
    let standardizedPath = try Arguments.requireReadableMediaFile(path)
    let asset = AVURLAsset(url: URL(fileURLWithPath: standardizedPath))

    let duration: CMTime
    let videoTracks: [AVAssetTrack]
    let hasAudioTrack: Bool
    do {
      if #available(iOS 16, macOS 13, *) {
        duration = try await asset.load(.duration)
        videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        hasAudioTrack = !audioTracks.isEmpty
      } else {
        try await awaitLegacyLoad(asset, keys: ["duration", "tracks"])
        duration = asset.duration
        videoTracks = asset.tracks(withMediaType: .video)
        hasAudioTrack = !asset.tracks(withMediaType: .audio).isEmpty
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
    let estimatedDataRate: Float
    let nominalFrameRate: Float
    let formatDescriptions: [CMFormatDescription]
    do {
      if #available(iOS 16, macOS 13, *) {
        naturalSize = try await track.load(.naturalSize)
        preferredTransform = try await track.load(.preferredTransform)
        estimatedDataRate = try await track.load(.estimatedDataRate)
        nominalFrameRate = try await track.load(.nominalFrameRate)
        formatDescriptions = try await track.load(.formatDescriptions)
      } else {
        try await awaitLegacyLoad(
          track,
          keys: ["naturalSize", "preferredTransform", "estimatedDataRate", "nominalFrameRate", "formatDescriptions"]
        )
        naturalSize = track.naturalSize
        preferredTransform = track.preferredTransform
        estimatedDataRate = track.estimatedDataRate
        nominalFrameRate = track.nominalFrameRate
        formatDescriptions = track.formatDescriptions.compactMap { $0 as? CMFormatDescription }
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

    // Single conversion point for durationMs: convert the CMTime directly to a timescale of
    // 1000 with half-away-from-zero rounding and take the integer value -- never go through a
    // floating-point seconds value, which is what the must-have's 4000.5ms/4000.4ms rounding
    // examples require.
    let convertedDuration = CMTimeConvertScale(duration, timescale: 1000, method: .roundHalfAwayFromZero)

    let sizeBytes: Int64
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: standardizedPath)
      sizeBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    } catch {
      throw CompressVideoError(
        code: "io",
        message: "Could not read file size",
        details: error.localizedDescription
      )
    }

    return MediaInfoMessage(
      durationMs: convertedDuration.value,
      widthPx: Int64(displayedSize.width),
      heightPx: Int64(displayedSize.height),
      rotationDegrees: Int64(rotationDegrees),
      sizeBytes: sizeBytes,
      videoCodec: MediaMath.normalizeCodec(fourCharacterCode(from: formatDescriptions.first)),
      videoBitrateBps: normalizedBitrateBps(estimatedDataRate),
      frameRateFps: normalizedFrameRateFps(nominalFrameRate),
      hasAudio: hasAudioTrack,
      isHdr: isHdr(track: track, formatDescriptions: formatDescriptions)
    )
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

  /// Reads the video track's average bitrate, in bits per second, from `estimatedDataRate`.
  /// Returns `nil` -- never `0` -- when the value is zero or non-finite, both of which
  /// `AVAssetTrack` can legitimately report.
  private func normalizedBitrateBps(_ estimatedDataRate: Float) -> Int64? {
    guard estimatedDataRate.isFinite, estimatedDataRate > 0 else { return nil }
    return Int64(estimatedDataRate.rounded())
  }

  /// Reads the video track's frame rate, in frames per second, from `nominalFrameRate`.
  /// Returns `nil` -- never `0` -- when the value is zero or non-finite. Never rounded to an
  /// integer.
  private func normalizedFrameRateFps(_ nominalFrameRate: Float) -> Double? {
    guard nominalFrameRate.isFinite, nominalFrameRate > 0 else { return nil }
    return Double(nominalFrameRate)
  }

  /// Converts a track's media subtype (a `FourCharCode`) into its 4-character ASCII string
  /// form (`"avc1"`, `"hvc1"`, ...), or `nil` when there is no format description to read.
  private func fourCharacterCode(from formatDescription: CMFormatDescription?) -> String? {
    guard let formatDescription else { return nil }
    let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)
    let bytes: [UInt8] = [
      UInt8((mediaSubType >> 24) & 0xFF),
      UInt8((mediaSubType >> 16) & 0xFF),
      UInt8((mediaSubType >> 8) & 0xFF),
      UInt8(mediaSubType & 0xFF),
    ]
    return String(bytes: bytes, encoding: .ascii)
  }

  /// Detects HDR via the `containsHDRVideo` media characteristic where available, falling
  /// back to inspecting the format description's transfer-function extension for the HLG and
  /// PQ values. Returns `false` -- never throws -- when neither is determinable, which is the
  /// correct behaviour whether that's because the running OS predates the availability guard
  /// or because the clip genuinely has no HDR transfer characteristic.
  private func isHdr(track: AVAssetTrack, formatDescriptions: [CMFormatDescription]) -> Bool {
    if #available(iOS 14, macOS 11, *) {
      if track.hasMediaCharacteristic(.containsHDRVideo) {
        return true
      }
    }

    guard let formatDescription = formatDescriptions.first,
      let extensions = CMFormatDescriptionGetExtensions(formatDescription) as? [String: Any],
      let transferFunction = extensions[kCMFormatDescriptionExtension_TransferFunction as String]
        as? String
    else {
      return false
    }
    return transferFunction == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String)
      || transferFunction == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)
  }
}
