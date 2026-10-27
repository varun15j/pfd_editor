/// What the app was opened to do from outside it: a long-press shortcut on
/// the app icon (quick actions) or the home-screen widget (improvement.md
/// #16). Each one goes straight to the camera or the photo picker.
enum LaunchAction {
  scan('scan', 'Scan document'),
  book('book', 'Scan a book'),
  idCard('id_card', 'Scan ID card'),
  importPhotos('import', 'Import photos');

  const LaunchAction(this.id, this.title);

  /// Sent by the shortcut and the widget; stable across releases.
  final String id;

  /// Shown as the shortcut's name.
  final String title;

  static LaunchAction? fromId(String? id) => values.where((a) => a.id == id).firstOrNull;
}

/// Where launch actions come from. [start] reports the action the app was
/// opened with, if any, then every later one while the app runs.
abstract interface class LaunchActionSource {
  Future<void> start(void Function(LaunchAction action) onAction);
}

/// For tests and platforms without shortcuts: never reports anything.
class NoLaunchActions implements LaunchActionSource {
  const NoLaunchActions();

  @override
  Future<void> start(void Function(LaunchAction action) onAction) async {}
}
