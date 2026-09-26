import VideoToolbox

/// Hardware HEVC capability probe (CDEC-01, CDEC-03) -- the Apple twin of Android's
/// `CodecCapabilities.kt`.
///
/// Structured the same way, per 04-PATTERNS.md's injectable-capability-probe pattern (mirroring
/// `SizeGuard`'s own pure-function-over-an-explicit-input shape and `ErrorMapping`'s pure
/// mapping shape): a pure function (`hasHardwareEncoder(isHardwareEncoderAvailable:)`) over an
/// injected closure, unit-testable in `RunnerTests.swift` with both an injected `{ true }` and
/// an injected `{ false }` closure -- no VideoToolbox call and no real hardware required -- and
/// a thin wrapper (`hasHardwareHevcEncoder()`) that supplies the real VideoToolbox lookup.
///
/// The wrapper's own probe (`probeHardwareHevcEncoder`) runs a real
/// `VTCopySupportedPropertyDictionaryForEncoder` call that requires a real device or simulator
/// to behave correctly against the system's own encoder list -- `SizeGuard`/`ErrorMapping`'s own
/// "no AVFoundation/simulator dependency" convention does not extend to this file's wrapper half
/// for that reason. Only the pure half is exercised by `RunnerTests.swift`;
/// `hasHardwareHevcEncoder` itself is exercised end to end by `hard_inputs_test.dart` on the iOS
/// simulator and the macOS host.
enum CodecCapabilities {
  /// Pure: answers "does this device have a hardware-accelerated HEVC encoder" from
  /// `isHardwareEncoderAvailable`'s own answer, with no VideoToolbox call of its own -- exactly
  /// what `hasHardwareHevcEncoder()` below drives with a real probe closure, and what
  /// `RunnerTests.swift` drives with injected `{ true }`/`{ false }` closures instead (D-05), no
  /// real hardware required either way.
  static func hasHardwareEncoder(isHardwareEncoderAvailable: () -> Bool) -> Bool {
    isHardwareEncoderAvailable()
  }

  /// Returns `true` when this device has a hardware-accelerated encoder for HEVC (CDEC-01's
  /// HEVC opt-in, and CDEC-03's keep-HDR opt-in, which requires the same hardware HEVC encoder
  /// specifically), `false` otherwise -- including on the iOS Simulator, which has no hardware
  /// encoder of any kind (04-RESEARCH.md, mirroring the Android emulator's own zero-HEVC-encoder
  /// finding). Dispatched through `hasHardwareEncoder(isHardwareEncoderAvailable:)` so its own
  /// decision function is the same one `RunnerTests.swift` exercises directly.
  static func hasHardwareHevcEncoder() -> Bool {
    hasHardwareEncoder(isHardwareEncoderAvailable: probeHardwareHevcEncoder)
  }

  /// The real VideoToolbox lookup: `VTCopySupportedPropertyDictionaryForEncoder` with a
  /// specification dictionary containing
  /// `kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder` set `true` for
  /// `kCMVideoCodecType_HEVC`. A non-zero status OR a `nil` returned dictionary both count as
  /// "no hardware encoder" -- Assumption A2 (04-RESEARCH.md) notes this failure mode is inferred
  /// from the API's documented contract rather than independently verified against a real
  /// device that lacks one; either shape a rejecting device could plausibly return is treated
  /// identically as "no".
  private static func probeHardwareHevcEncoder() -> Bool {
    let specification: [CFString: Any] = [
      kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true
    ]
    var supportedProperties: CFDictionary?
    let status = VTCopySupportedPropertyDictionaryForEncoder(
      width: 1920,
      height: 1080,
      codecType: kCMVideoCodecType_HEVC,
      encoderSpecification: specification as CFDictionary,
      encoderIDOut: nil,
      supportedPropertiesOut: &supportedProperties
    )
    return status == noErr && supportedProperties != nil
  }
}
