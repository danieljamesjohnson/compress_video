import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#else
  #error("Unsupported platform.")
#endif

/// The `compress_video` Flutter plugin: registers the generated `ProbeHostApi` and
/// `ThumbnailHostApi` implementations against the platform's binary messenger.
///
/// No hand-written channel code exists here or anywhere else in this package -- every
/// quantity crossing the platform channel is a Pigeon-generated type, wired through the
/// generated `*Setup.setUp(binaryMessenger:api:)` entry points below.
public class CompressVideoPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #elseif os(macOS)
      let messenger = registrar.messenger
    #endif

    ProbeHostApiSetup.setUp(binaryMessenger: messenger, api: Probe())
    ThumbnailHostApiSetup.setUp(binaryMessenger: messenger, api: Thumbnails())
  }
}
