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
  Future<Directory> get thumbnailsDir => _dir('thumbnails');

  /// The private root every stored path is relative to.
  Future<String> get rootPath async => (await _rootDir()).path;

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

  /// [fileName], or "name (2).pdf", "name (3).pdf" and so on when that file
  /// already exists in the exports folder, so a new save never replaces one.
  Future<String> freeExportName(String fileName) async {
    final dir = (await exportsDir).path;
    final stem = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    var candidate = fileName;
    for (var n = 2; File(p.join(dir, candidate)).existsSync(); n++) {
      candidate = '$stem ($n)$ext';
    }
    return candidate;
  }

  /// Writes [bytes] to [relativePath] under the root through a temp file and
  /// a rename, so a crash leaves either the old file or the new one.
  Future<File> writeFileAtomically(String relativePath, List<int> bytes) async {
    final target = File(p.join(await rootPath, relativePath));
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    return tmp.rename(target.path);
  }

  /// Reads a text file under the root, or null when it does not exist.
  Future<String?> readText(String relativePath) async {
    final f = File(p.join(await rootPath, relativePath));
    return f.existsSync() ? f.readAsString() : null;
  }

  Future<void> deleteFile(String relativePath) async {
    final f = File(p.join(await rootPath, relativePath));
    if (f.existsSync()) await f.delete();
  }
}
