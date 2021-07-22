import Flutter
import UIKit

public class SwiftFlutterSaltyrtcClientPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_saltyrtc_client", binaryMessenger: registrar.messenger())
    let instance = SwiftFlutterSaltyrtcClientPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result("iOS " + UIDevice.current.systemVersion)
  }
}
