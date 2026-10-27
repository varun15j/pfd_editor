import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../domain/photo_import.dart';
import '../domain/share_inbox.dart';

/// [ShareInbox] kept as folders on disk: one folder per share, holding its
/// images named in order (`001.jpg`, `002.png`, ...).
///
/// The native side writes a share into a folder whose name starts with a
/// dot and renames it when every image is in, so a share still being copied
/// is never picked up half done.
class DirectoryShareInbox implements ShareInbox {
  DirectoryShareInbox(this._dir);

  /// The inbox folder, or null when the platform has none.
  final Future<Directory?> Function() _dir;

  @override
  Future<List<SharedBatch>> pending() async {
    final dir = await _dir();
    if (dir == null || !await dir.exists()) return const [];
    final folders = [
      await for (final e in dir.list())
        if (e is Directory && !p.basename(e.path).startsWith('.')) e,
    ]..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    final batches = <SharedBatch>[];
    for (final folder in folders) {
      final files = [
        await for (final e in folder.list())
          if (e is File && !p.basename(e.path).startsWith('.')) e,
      ]..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      batches.add(
        SharedBatch(
          id: folder.path,
          photos: [for (final f in files) PickedPhoto(path: f.path, name: p.basename(f.path))],
        ),
      );
    }
    return batches;
  }

  @override
  Future<void> discard(SharedBatch batch) async {
    final folder = Directory(batch.id);
    if (await folder.exists()) await folder.delete(recursive: true);
  }
}

/// Asks the platform where shared images are saved: the app's own files on
/// Android, the App Group the share extension writes to on iOS. Null when
/// the platform has no inbox (desktop, tests, or an iOS build without the
/// App Group).
Future<Directory?> platformShareInboxDir() async {
  try {
    final path = await const MethodChannel('lumascan/share_inbox').invokeMethod<String>('inboxPath');
    return path == null ? null : Directory(path);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
