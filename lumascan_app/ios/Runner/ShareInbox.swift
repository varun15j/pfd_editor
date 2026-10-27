import Flutter
import Foundation

/// Tells Dart where the share extension saves images shared from Photos:
/// the `share_inbox` folder in the App Group both targets belong to. Dart
/// imports what it finds there each time the app comes to the front.
enum ShareInbox {
  static let channel = "lumascan/share_inbox"

  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: channel, binaryMessenger: messenger).setMethodCallHandler { call, result in
      guard call.method == "inboxPath" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(inboxURL()?.path)
    }
  }

  /// Nil when the App Group is missing from the signing profile.
  static func inboxURL() -> URL? {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "ShareAppGroup") as? String,
      let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else { return nil }
    return container.appendingPathComponent("share_inbox", isDirectory: true)
  }
}
