import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerAppBadgeChannel(engineBridge.pluginRegistry)
  }

  /// "gps_cielo/app_badge": setCount(Int) sets the number on the app icon
  /// (lib/core/services/push/app_badge.dart keeps it equal to the unread
  /// notifications).
  private func registerAppBadgeChannel(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "GpsCieloAppBadge") else { return }
    let channel = FlutterMethodChannel(
      name: "gps_cielo/app_badge",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "setCount" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let count = max(0, (call.arguments as? Int) ?? 0)
      if #available(iOS 16.0, *) {
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in
          result(nil)
        }
      } else {
        UIApplication.shared.applicationIconBadgeNumber = count
        result(nil)
      }
    }
  }
}
