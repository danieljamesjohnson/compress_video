import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#else
  #error("Unsupported platform.")
#endif

/// The `compress_video` Flutter plugin: registers the generated `ProbeHostApi`,
/// `ThumbnailHostApi` and `CompressHostApi` implementations against the platform's binary
/// messenger.
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
    CompressHostApiSetup.setUp(
      binaryMessenger: messenger,
      api: Compression(flutterApi: CompressVideoFlutterApi(binaryMessenger: messenger))
    )
  }

  // Per-platform teardown (03-RESEARCH.md Pattern 5/Pitfall 2): these are two GENUINELY
  // DIFFERENT events, not one method silently covering both platforms. iOS has a real
  // engine-detach hook (`FlutterPlugin.detachFromEngineForRegistrar:`); macOS's `FlutterPlugin`
  // protocol has no such method at all -- its nearest available substitute is
  // `FlutterAppLifecycleDelegate.handleWillTerminate(_:)`, fired when the whole app is about to
  // quit, which is a weaker guarantee than an engine-detach hook (a live job can outlive a
  // detached-but-still-running app on macOS in a way it cannot on iOS). Both call the same
  // `JobRegistry.cancelAll()`, and both cancel every live job BEFORE any registration would be
  // torn down (T-02-25's guarantee, carried over from Android).
  #if os(iOS)
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
      JobRegistry.cancelAll()
    }
  #elseif os(macOS)
    public func handleWillTerminate(_ notification: Notification) {
      JobRegistry.cancelAll()
    }
  #endif
}
