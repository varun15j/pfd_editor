import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';

/// Where the image-loading profile database lives.
///
/// On Android it goes to the phone's shared Documents folder,
/// `Documents/LumaScan/debug/image_profile.db`, which is not removed when the
/// app is uninstalled, so a fresh install picks the data up again. Reaching
/// that folder from a reinstalled app needs "All files access", which only
/// debug builds ask for (see `android/app/src/debug/AndroidManifest.xml`).
/// Until it is allowed, and on iOS (where nothing outside the app survives an
/// uninstall), the database stays in the app's private folder.
class ProfileLocation {
  ProfileLocation({
    String? sharedDir,
    Future<String> Function()? privateDir,
    Future<bool> Function()? requestAccess,
    bool? isAndroid,
  }) : sharedDir = sharedDir ?? defaultSharedDir,
       _privateDir = privateDir ?? getDatabasesPath,
       _requestAccess = requestAccess ?? _askForAllFilesAccess,
       _isAndroid = isAndroid ?? Platform.isAndroid;

  /// The shared Documents folder on Android's primary storage.
  static const defaultSharedDir = '/storage/emulated/0/Documents/LumaScan/debug';
  static const fileName = 'image_profile.db';

  final String sharedDir;
  final Future<String> Function() _privateDir;
  final Future<bool> Function() _requestAccess;
  final bool _isAndroid;

  String get sharedPath => p.join(sharedDir, fileName);
  Future<String> get privatePath async => p.join(await _privateDir(), fileName);

  /// True when the shared folder can be written, tried for real, because
  /// what a permission reports differs between Android versions.
  Future<bool> canUseShared() async {
    if (!_isAndroid) return false;
    try {
      final dir = Directory(sharedDir);
      await dir.create(recursive: true);
      final probe = File(p.join(sharedDir, '.write_check'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// The database to open now: the shared one when it can be used, copying
  /// over what was recorded privately the first time; else the private one.
  Future<String> resolve() async {
    final private = await privatePath;
    if (!await canUseShared()) return private;
    final shared = File(sharedPath);
    final old = File(private);
    if (!shared.existsSync() && old.existsSync()) await old.copy(shared.path);
    return shared.path;
  }

  /// Asks for access to the shared folder. Returns whether it can be used.
  Future<bool> requestShared() async {
    if (!_isAndroid) return false;
    if (await canUseShared()) return true;
    await _requestAccess();
    return canUseShared();
  }

  /// Android 11 and newer: "All files access" (opens the system page);
  /// Android 8 to 10: the storage permission.
  static Future<bool> _askForAllFilesAccess() async {
    if ((await Permission.manageExternalStorage.request()).isGranted) return true;
    return (await Permission.storage.request()).isGranted;
  }
}
