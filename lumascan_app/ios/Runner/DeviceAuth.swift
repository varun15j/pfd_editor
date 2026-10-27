import Flutter
import LocalAuthentication

/// The app lock's check that the phone's owner is holding it: Face ID or
/// Touch ID, with the passcode as the fallback. Dart calls it through the
/// `lumascan/device_auth` channel.
///
/// `authenticate` answers "success", "cancelled", "unavailable" (no passcode
/// is set) or "failed" (for example, too many tries).
enum DeviceAuth {
  static let channel = "lumascan/device_auth"

  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: channel, binaryMessenger: messenger).setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        var error: NSError?
        result(LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error))
      case "authenticate":
        let reason = (call.arguments as? [String: Any])?["reason"] as? String ?? "Unlock"
        authenticate(reason: reason, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func authenticate(reason: String, result: @escaping FlutterResult) {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      result(error?.code == LAError.passcodeNotSet.rawValue ? "unavailable" : "failed")
      return
    }
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
      let answer: String
      if success {
        answer = "success"
      } else {
        switch (error as? LAError)?.code {
        case .userCancel?, .appCancel?, .systemCancel?, .userFallback?:
          answer = "cancelled"
        case .passcodeNotSet?:
          answer = "unavailable"
        default:
          answer = "failed"
        }
      }
      DispatchQueue.main.async { result(answer) }
    }
  }
}
