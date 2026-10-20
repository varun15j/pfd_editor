import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../domain/library.dart';
import '../domain/models.dart';
import '../domain/scan_document.dart';
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

/// Keeps the scan document on screen (the draft) on disk
/// (`drafts/current.json`) after every change, so every scan is saved from
/// the first page and survives the app being killed (US-09.1). The page images already live in
/// [PageStore.originalsDir]; this file holds their order and edit recipes.
class DraftStore {
  DraftStore(this._files);

  final PageStore _files;

  static const draftFile = 'drafts/current.json';
  static const version = 1;

  /// Returns the saved draft: its pages whose image files still exist, and
  /// its name. Empty when there is no draft or it cannot be read.
  Future<SavedDraft> load() async {
    try {
      final text = await _files.readText(draftFile);
      if (text == null) return const SavedDraft();
      final json = (jsonDecode(text) as Map).cast<String, Object?>();
      final pages = _pages(json, (await _files.originalsDir).path);
      return SavedDraft(pages: pages, info: pages.isEmpty ? null : _info(json));
    } catch (_) {
      return const SavedDraft();
    }
  }

  /// Saves [pages] as the draft, named by [info]; an empty list removes the
  /// draft file.
  Future<void> save(List<ScanPage> pages, {ScanDocInfo? info}) async {
    if (pages.isEmpty) return _files.deleteFile(draftFile);
    final json = {
      'version': version,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      ...?info?.toJson(),
      'pages': [for (final p in pages) p.toJson()],
    };
    await _files.writeFileAtomically(draftFile, utf8.encode(jsonEncode(json)));
  }

  /// Earlier documents, set aside when a new scan started, live in
  /// `drafts/parked/<id>.json` until they are opened again.
  static const parkedDir = 'drafts/parked';

  /// Sets [pages] aside as an earlier document and returns it. The page
  /// images stay where they are.
  Future<ParkedDraft> park(List<ScanPage> pages, {bool exported = false, ScanDocInfo? info}) async {
    final now = DateTime.now();
    final draft = ParkedDraft(
      id: 'd${now.microsecondsSinceEpoch}',
      pageCount: pages.length,
      savedAt: now,
      exported: exported,
      cover: pages.first,
      info: info ?? ScanDocInfo(name: scanDocumentName(now), createdAt: now),
    );
    final json = {
      'version': version,
      'savedAt': now.toUtc().toIso8601String(),
      'exported': exported,
      ...draft.info.toJson(),
      'pages': [for (final p in pages) p.toJson()],
    };
    await _files.writeFileAtomically('$parkedDir/${draft.id}.json', utf8.encode(jsonEncode(json)));
    return draft;
  }

  /// The earlier documents, newest first. Unreadable files are skipped.
  Future<List<ParkedDraft>> parked() async {
    final dir = Directory(path.join(await _files.rootPath, parkedDir));
    if (!dir.existsSync()) return const [];
    final originals = (await _files.originalsDir).path;
    final found = <ParkedDraft>[];
    for (final file in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      try {
        final json = (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
        final pages = _pages(json, originals);
        if (pages.isEmpty) continue;
        final savedAt = DateTime.parse(json['savedAt']! as String).toLocal();
        found.add(
          ParkedDraft(
            id: path.basenameWithoutExtension(file.path),
            pageCount: pages.length,
            savedAt: savedAt,
            exported: json['exported'] == true,
            cover: pages.first,
            info: _info(json, fallback: savedAt),
          ),
        );
      } catch (_) {
        continue;
      }
    }
    return found..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  }

  /// The pages of earlier document [id], or none if it cannot be read.
  Future<List<ScanPage>> loadParked(String id) async {
    try {
      final text = await _files.readText('$parkedDir/$id.json');
      if (text == null) return const [];
      return _pages((jsonDecode(text) as Map).cast(), (await _files.originalsDir).path);
    } catch (_) {
      return const [];
    }
  }

  Future<void> deleteParked(String id) => _files.deleteFile('$parkedDir/$id.json');

  /// Renames earlier document [id]. Does nothing if it cannot be read.
  Future<void> renameParked(String id, String name) async {
    final text = await _files.readText('$parkedDir/$id.json');
    if (text == null) return;
    final json = (jsonDecode(text) as Map).cast<String, Object?>();
    final savedAt = DateTime.tryParse(json['savedAt'] as String? ?? '')?.toLocal() ?? DateTime.now();
    json.addAll(_info(json, fallback: savedAt).copyWith(name: name).toJson());
    await _files.writeFileAtomically('$parkedDir/$id.json', utf8.encode(jsonEncode(json)));
  }

  /// The name stored with a draft, or for a file from before scans had
  /// names, one made from the day it was saved.
  static ScanDocInfo _info(Map<String, Object?> json, {DateTime? fallback}) {
    final stored = ScanDocInfo.fromJson(json);
    if (stored != null) return stored;
    final t = fallback ?? DateTime.tryParse(json['savedAt'] as String? ?? '')?.toLocal() ?? DateTime.now();
    return ScanDocInfo(name: scanDocumentName(t), createdAt: t);
  }

  static List<ScanPage> _pages(Map<String, Object?> json, String originals) =>
      [for (final p in json['pages']! as List) ScanPage.fromJson((p as Map).cast(), originalsDir: originals)]
          .where((p) => File(p.originalPath).existsSync())
          .toList();
}

/// The draft read back from disk.
class SavedDraft {
  const SavedDraft({this.pages = const [], this.info});

  final List<ScanPage> pages;

  /// Null only when there are no pages.
  final ScanDocInfo? info;
}

/// An earlier scan document set aside when a new scan started. Opening it
/// makes it the draft again, so pages can be added to it.
class ParkedDraft {
  const ParkedDraft({
    required this.id,
    required this.pageCount,
    required this.savedAt,
    required this.exported,
    required this.cover,
    required this.info,
  });

  final String id;

  /// Name and start time.
  final ScanDocInfo info;

  String get name => info.name;

  ParkedDraft renamed(String name) => ParkedDraft(
    id: id,
    pageCount: pageCount,
    savedAt: savedAt,
    exported: exported,
    cover: cover,
    info: info.copyWith(name: name),
  );
  final int pageCount;
  final DateTime savedAt;

  /// Saved as a PDF and not changed since.
  final bool exported;

  /// The first page, for the thumbnail.
  final ScanPage cover;
}
