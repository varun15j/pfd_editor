import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../domain/library.dart';
import '../domain/models.dart';
import '../imaging/page_renderer.dart';
import 'page_store.dart';

/// Reads and writes the library index (`library/index.json`) and document
/// thumbnails. Every write replaces the whole file atomically, so a crash
/// mid-save leaves the previous index intact.
class LibraryStore {
  LibraryStore(this._files);

  final PageStore _files;

  static const indexFile = 'library/index.json';
  static const thumbnailSize = 360;

  Future<LibraryIndex> load() async {
    final text = await _files.readText(indexFile);
    if (text == null) return const LibraryIndex();
    final root = await _files.rootPath;
    try {
      return LibraryIndex.fromJson((jsonDecode(text) as Map).cast(), root);
    } catch (_) {
      // A damaged index must not lock the user out of the app. Keep it aside
      // for diagnosis and start empty; the PDFs themselves are untouched.
      await File(path.join(root, indexFile))
          .rename(path.join(root, 'library', 'index.corrupt-${DateTime.now().millisecondsSinceEpoch}.json'));
      return const LibraryIndex();
    }
  }

  Future<void> save(LibraryIndex index) async {
    final root = await _files.rootPath;
    await _files.writeFileAtomically(indexFile, utf8.encode(jsonEncode(index.toJson(root))));
  }

  /// Renders [page] as the thumbnail for document [docId]. Returns null if
  /// rendering fails, since a missing thumbnail must not block saving.
  Future<String?> writeThumbnail(String docId, ScanPage page) async {
    try {
      final dir = await _files.thumbnailsDir;
      final out = await renderToFile(
        originalPath: page.originalPath,
        recipe: page.recipe,
        outPath: path.join(dir.path, '$docId.jpg'),
        maxDimension: thumbnailSize,
        quality: 75,
      );
      return out.path;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the document's PDF and thumbnail.
  Future<void> deleteFiles(SavedDocument doc) async {
    for (final p in [doc.pdfPath, doc.thumbnailPath]) {
      if (p == null) continue;
      final f = File(p);
      if (f.existsSync()) await f.delete();
    }
  }
}

/// Keeps the unsaved scan draft on disk (`drafts/current.json`) so it
/// survives the app being killed (US-09.1). The page images already live in
/// [PageStore.originalsDir]; this file holds their order and edit recipes.
class DraftStore {
  DraftStore(this._files);

  final PageStore _files;

  static const draftFile = 'drafts/current.json';
  static const version = 1;

  /// Returns the saved draft pages whose image files still exist, or an
  /// empty list when there is no draft or it cannot be read.
  Future<List<ScanPage>> load() async {
    try {
      final text = await _files.readText(draftFile);
      if (text == null) return const [];
      final json = (jsonDecode(text) as Map).cast<String, Object?>();
      final originals = (await _files.originalsDir).path;
      return [for (final p in json['pages']! as List) ScanPage.fromJson((p as Map).cast(), originalsDir: originals)]
          .where((p) => File(p.originalPath).existsSync())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Saves [pages] as the draft; an empty list removes the draft file.
  Future<void> save(List<ScanPage> pages) async {
    if (pages.isEmpty) return _files.deleteFile(draftFile);
    final json = {
      'version': version,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'pages': [for (final p in pages) p.toJson()],
    };
    await _files.writeFileAtomically(draftFile, utf8.encode(jsonEncode(json)));
  }
}
