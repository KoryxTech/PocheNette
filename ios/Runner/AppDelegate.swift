import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let stateDefaults = UserDefaults.standard
  private let secureDefaults = UserDefaults(suiteName: "pochenette_secure") ?? .standard

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "pochenette/local",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "GONE", message: "AppDelegate released", details: nil))
        return
      }
      switch call.method {
      case "load":
        result(self.stateDefaults.string(forKey: "state"))
      case "save":
        guard let payload = call.arguments as? String else {
          result(FlutterError(code: "SAVE", message: "Invalid payload", details: nil))
          return
        }
        self.stateDefaults.set(payload, forKey: "state")
        result(nil)
      case "secureGet":
        guard let key = call.arguments as? String else {
          result(FlutterError(code: "SECURE", message: "Missing key", details: nil))
          return
        }
        result(self.secureDefaults.string(forKey: key))
      case "secureSet":
        guard
          let args = call.arguments as? [String: Any?],
          let key = args["key"] as? String,
          !key.isEmpty
        else {
          result(FlutterError(code: "SECURE", message: "Missing key", details: nil))
          return
        }
        if let value = args["value"] as? String {
          self.secureDefaults.set(value, forKey: key)
        } else {
          self.secureDefaults.removeObject(forKey: key)
        }
        result(true)
      case "dialUssd":
        guard let code = call.arguments as? String else {
          result(FlutterError(code: "DIAL", message: "Missing code", details: nil))
          return
        }
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code
        guard let url = URL(string: "tel:\(encoded)") else {
          result(FlutterError(code: "DIAL", message: "Cannot open dialer", details: nil))
          return
        }
        UIApplication.shared.open(url, options: [:]) { success in
          if success {
            result(nil)
          } else {
            result(FlutterError(code: "DIAL", message: "Cannot open dialer", details: nil))
          }
        }
      case "permission":
        // SMS inbox access is Android-only.
        result(false)
      case "requestPermission":
        result(false)
      case "readInbox":
        result(
          FlutterError(
            code: "UNSUPPORTED",
            message: "SMS sync is not available on iOS",
            details: nil
          )
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
