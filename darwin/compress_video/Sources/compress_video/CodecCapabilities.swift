import Foundation
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
/// The wrapper's own probe (`probeHardwareHevcEncoder`) runs a real `VTCopyVideoEncoderList`
/// call that requires a real device or simulator to behave correctly against the system's own
/// encoder list -- `SizeGuard`/`ErrorMapping`'s own "no AVFoundation/simulator dependency"
/// convention does not extend to this file's wrapper half for that reason. Only the pure half is
/// exercised by `RunnerTests.swift`; `hasHardwareHevcEncoder` itself is exercised end to end by
/// `hard_inputs_test.dart` on the iOS simulator and the macOS host.
///
/// Deliberately NOT `VTCopySupportedPropertyDictionaryForEncoder` with
/// `kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder`: that key is
/// iOS-17.4-only (CI run 36267121646 diagnosed this live -- "'...' is only available in iOS 17.4
/// or newer" -- against this plugin's iOS 13/macOS 11 floor). `VTCopyVideoEncoderList` and its
/// `kVTVideoEncoderList_IsHardwareAccelerated` key are available from iOS 8/macOS 10.8, well
/// below the floor, and answer the identical question by enumerating every encoder the system
/// reports and checking which ones are hardware-accelerated -- no per-codec specification
/// dictionary, and no availability gate needed on either platform.
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

  /// The real VideoToolbox lookup: `VTCopyVideoEncoderList(nil, _:)` enumerates every video
  /// encoder the system reports, then answers `true` only if at least one entry's
  /// `kVTVideoEncoderList_CodecType` is `kCMVideoCodecType_HEVC` AND its
  /// `kVTVideoEncoderList_IsHardwareAccelerated` key is present and `true` -- Apple's own
  /// documented contract is that this key is present (set `true`) only for a hardware-backed
  /// encoder and absent otherwise, so a missing key and an explicit `false` both correctly read
  /// as "not hardware" via the same optional-cast default. A non-zero status, a `nil` array, or
  /// an unreadable entry all count as "no hardware encoder" -- Assumption A2 (04-RESEARCH.md)
  /// notes this failure mode is inferred from the API's documented contract rather than
  /// independently verified against a real device that lacks one.
  private static func probeHardwareHevcEncoder() -> Bool {
    var encodersOut: CFArray?
    let status = VTCopyVideoEncoderList(nil, &encodersOut)
    guard status == noErr, let encoders = encodersOut as? [[String: Any]] else {
      return false
    }
    return encoders.contains { encoder in
      let codecType = (encoder[kVTVideoEncoderList_CodecType as String] as? NSNumber)?.uint32Value
      let isHardwareAccelerated =
        (encoder[kVTVideoEncoderList_IsHardwareAccelerated as String] as? Bool) ?? false
      return codecType == kCMVideoCodecType_HEVC && isHardwareAccelerated
    }
  }
}
