import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns the app's private files: page originals, rendered derivatives and
/// exported PDFs. Scanner output lives in a plugin cache that can be cleared
/// at any time, so every page is copied here before it is shown.
class PageStore {
  PageStore({Future<Directory> Function()? rootDir})
      : _rootDir = rootDir ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _rootDir;
  int _counter = 0;

  Future<Directory> _dir(String name) async {
    final root = await _rootDir();
    final dir = Directory(p.join(root.path, name));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> get originalsDir => _dir('pages');
  Future<Directory> get renderDir => _dir('renders');
  Future<Directory> get exportsDir => _dir('exports');

  String newId() => '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  /// Copies a scanner file into private storage and returns the new path.
  Future<String> importOriginal(String sourcePath, String id) async {
    final dir = await originalsDir;
    final ext = p.extension(sourcePath).toLowerCase();
    final dest = p.join(dir.path, '$id${ext.isEmpty ? '.jpg' : ext}');
    await File(sourcePath).copy(dest);
    return dest;
  }

  Future<void> deleteOriginal(String path) async {
    final f = File(path);
    if (f.existsSync()) await f.delete();
  }

  /// Writes bytes to a temp file and renames it, so a crash never leaves a
  /// half-written PDF behind (HLD: crash safe exports).
  Future<File> writeExportAtomically(String fileName, List<int> bytes) async {
    final dir = await exportsDir;
    final finalPath = p.join(dir.path, fileName);
    final tmp = File('$finalPath.part');
    await tmp.writeAsBytes(bytes, flush: true);
    return tmp.rename(finalPath);
  }
}
