import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Lists the app in the share sheet when images are shared from Photos or
/// any other app. It saves the images into the App Group inbox the app
/// reads (one folder per share, files named in order), then opens the app,
/// which imports them as a new document when it comes to the front.
///
/// HEIC and other formats are saved as JPEG, which the app's page import
/// reads. The folder is written under a name starting with a dot and
/// renamed when complete, so the app never picks up half a share.
class ShareViewController: UIViewController {
  /// Most images taken from one share, as on Android.
  private let maxImages = 100

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    let spinner = UIActivityIndicatorView(style: .large)
    spinner.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(spinner)
    NSLayoutConstraint.activate([
      spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
    spinner.startAnimating()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task { await saveAndOpenApp() }
  }

  private func saveAndOpenApp() async {
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
      .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
      .prefix(maxImages)
    guard let inbox = Self.inboxURL(), !providers.isEmpty else {
      finish(error: "No images to add.")
      return
    }
    let batch = String(Int(Date().timeIntervalSince1970 * 1000))
    let incoming = inbox.appendingPathComponent(".incoming-\(batch)", isDirectory: true)
    let fm = FileManager.default
    do {
      try fm.createDirectory(at: incoming, withIntermediateDirectories: true)
    } catch {
      finish(error: "Could not save the images.")
      return
    }
    var saved = 0
    for provider in providers {
      guard let data = await Self.loadImageData(provider) else { continue }
      let name = String(format: "%03d.%@", saved + 1, data.ext)
      if (try? data.bytes.write(to: incoming.appendingPathComponent(name))) != nil { saved += 1 }
    }
    if saved == 0 || (try? fm.moveItem(at: incoming, to: inbox.appendingPathComponent(batch, isDirectory: true))) == nil {
      try? fm.removeItem(at: incoming)
      finish(error: "Those images could not be read.")
      return
    }
    openHostApp()
    extensionContext?.completeRequest(returningItems: nil)
  }

  private func finish(error: String) {
    let alert = UIAlertController(title: nil, message: error, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
      self?.extensionContext?.completeRequest(returningItems: nil)
    })
    present(alert, animated: true)
  }

  /// The App Group folder shared with the app, from the `ShareAppGroup`
  /// Info.plist key.
  static func inboxURL() -> URL? {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "ShareAppGroup") as? String,
      let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else { return nil }
    return container.appendingPathComponent("share_inbox", isDirectory: true)
  }

  /// The image's bytes: JPEG and PNG as they are, anything else (HEIC, …)
  /// re-encoded as JPEG with its orientation kept.
  private static func loadImageData(_ provider: NSItemProvider) async -> (bytes: Data, ext: String)? {
    let type = UTType.image.identifier
    let data: Data? = await withCheckedContinuation { done in
      provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in done.resume(returning: data) }
    }
    if let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
      let typeId = CGImageSourceGetType(source), let uti = UTType(typeId as String)
    {
      if uti.conforms(to: .jpeg) { return (data, "jpg") }
      if uti.conforms(to: .png) { return (data, "png") }
      let out = NSMutableData()
      if let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) {
        CGImageDestinationAddImageFromSource(
          dest, source, 0, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        if CGImageDestinationFinalize(dest) { return (out as Data, "jpg") }
      }
    }
    // Some apps share a UIImage object rather than a file.
    let image: UIImage? = await withCheckedContinuation { done in
      provider.loadItem(forTypeIdentifier: type) { item, _ in
        switch item {
        case let image as UIImage: done.resume(returning: image)
        case let url as URL: done.resume(returning: UIImage(contentsOfFile: url.path))
        default: done.resume(returning: nil)
        }
      }
    }
    return image?.jpegData(compressionQuality: 0.92).map { ($0, "jpg") }
  }

  /// Opens the app through its share URL scheme. Extensions cannot call
  /// UIApplication.open directly, so it is found through the responder
  /// chain. If this ever fails, the images still wait in the inbox and are
  /// imported the next time the app is opened.
  private func openHostApp() {
    // The extension's bundle id is the app's plus ".ShareExtension".
    guard let extensionId = Bundle.main.bundleIdentifier else { return }
    let hostId = extensionId.split(separator: ".").dropLast().joined(separator: ".")
    guard let url = URL(string: "\(hostId).share://import") else { return }
    let selector = NSSelectorFromString("openURL:options:completionHandler:")
    var responder: UIResponder? = self
    while let current = responder {
      if let app = current as? UIApplication, app.responds(to: selector) {
        typealias Open = @convention(c) (NSObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
        let open = unsafeBitCast(app.method(for: selector), to: Open.self)
        open(app, selector, url as NSURL, NSDictionary(), nil)
        return
      }
      responder = current.next
    }
  }
}
