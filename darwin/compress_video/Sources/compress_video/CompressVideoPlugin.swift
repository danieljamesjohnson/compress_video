import Foundation

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import Cocoa
  import FlutterMacOS
#endif

public class CompressVideoPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: "compress_video", binaryMessenger: messenger)
    let instance = CompressVideoPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      #if os(iOS)
        result("iOS " + UIDevice.current.systemVersion)
      #elseif os(macOS)
        result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
      #endif
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
