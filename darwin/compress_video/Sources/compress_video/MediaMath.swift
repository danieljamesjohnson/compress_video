import CoreGraphics
import Foundation

/// Pure, unit-testable rotation/dimension/codec/duration logic shared by every Apple call.
///
/// Mirrors Android's `MediaMath.kt` function for function, name for name. No AVFoundation
/// import -- every function here is exercisable as plain Swift with no simulator, which is
/// what `RunnerTests` (identical on iOS and macOS) does.
enum MediaMath {
  /// Returns the displayed (rotation-corrected) `(width, height)` pair for a video whose
  /// coded dimensions are `codedWidthPx x codedHeightPx` and whose unsigned clockwise
  /// rotation is `rotationDegrees`.
  ///
  /// Swaps width/height for 90 and 270; passes both through unchanged for 0 and 180. The two
  /// cases are decided by separate branches over the rotation value, so a clip whose coded
  /// width and height happen to be equal is still reported with the correct rotation instead
  /// of the swap silently becoming a no-op.
  static func displayedSize(
    codedWidthPx: Int,
    codedHeightPx: Int,
    rotationDegrees: Int
  ) -> (width: Int, height: Int) {
    switch rotationDegrees {
    case 90, 270:
      return (codedHeightPx, codedWidthPx)
    default:
      return (codedWidthPx, codedHeightPx)
    }
  }

  /// Normalises a platform-reported MIME type or FourCC into one of the wire-contract codec
  /// tokens: `h264`, `hevc`, `av1`, `vp9`, `unknown`. `nil` input, and any value this function
  /// does not recognise, both map to `unknown` -- never a crash.
  static func normalizeCodec(_ mimeOrFourCc: String?) -> String {
    guard let mimeOrFourCc else { return "unknown" }
    switch mimeOrFourCc.lowercased() {
    case "video/avc", "avc1", "h264":
      return "h264"
    case "video/hevc", "hvc1", "hev1", "h265", "hevc":
      return "hevc"
    case "video/av01", "av01", "av1":
      return "av1"
    case "video/x-vnd.on2.vp9", "vp09", "vp9":
      return "vp9"
    default:
      return "unknown"
    }
  }

  /// Rounds a millisecond duration value half-away-from-zero: `.5` rounds away from zero
  /// (`4000.5` -> `4001`), `.4` rounds down (`4000.4` -> `4000`). Used only where a value must
  /// be produced from a floating-point seconds/millisecond quantity outside the single
  /// `CMTimeConvertScale` conversion point `Probe.swift`/`Thumbnails.swift` use for the wire
  /// `durationMs` field itself.
  static func roundHalfUpMs(_ valueMs: Double) -> Int64 {
    Int64(floor(valueMs + 0.5))
  }

  /// Returns the `(width, height)` a displayed `displayedWidthPx x displayedHeightPx` frame
  /// should be scaled to so its longer side is at most `maxDimensionPx`, preserving aspect
  /// ratio and rounding to the nearest integer.
  ///
  /// Returns the input unchanged -- never a larger dimension than the input -- when
  /// `maxDimensionPx` is `nil` or already at least the longer of the two input sides. This is
  /// what guarantees a thumbnail is never upscaled.
  static func scaledSize(
    displayedWidthPx: Int,
    displayedHeightPx: Int,
    maxDimensionPx: Int?
  ) -> (width: Int, height: Int) {
    guard let maxDimensionPx else {
      return (displayedWidthPx, displayedHeightPx)
    }
    let longerSidePx = max(displayedWidthPx, displayedHeightPx)
    if maxDimensionPx >= longerSidePx {
      return (displayedWidthPx, displayedHeightPx)
    }
    let scale = Double(maxDimensionPx) / Double(longerSidePx)
    let scaledWidthPx = max(Int((Double(displayedWidthPx) * scale).rounded()), 1)
    let scaledHeightPx = max(Int((Double(displayedHeightPx) * scale).rounded()), 1)
    return (scaledWidthPx, scaledHeightPx)
  }

  /// Clamps a requested `positionMs` to `durationMs`: a value above `durationMs` clamps down
  /// to it, and `positionMs == durationMs` passes through unchanged so the last frame is still
  /// returned, not an error. A negative `positionMs` is never seen here -- `Arguments` rejects
  /// it before this is ever called -- so this function does not special-case it.
  static func clampPositionMs(_ positionMs: Int64, durationMs: Int64) -> Int64 {
    positionMs > durationMs ? durationMs : positionMs
  }

  /// Derives unsigned clockwise rotation degrees (0, 90, 180 or 270) from a track's
  /// `preferredTransform` by taking the angle of the transform's `b`/`a` components and
  /// normalising it to the nearest quarter turn.
  static func rotationDegrees(from transform: CGAffineTransform) -> Int {
    let radians = atan2(transform.b, transform.a)
    let degrees = Int((radians * 180 / .pi).rounded())
    let normalizedDegrees = ((degrees % 360) + 360) % 360
    let quarterTurns = ((normalizedDegrees + 45) / 90) % 4
    return quarterTurns * 90
  }
}
