import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../app/providers.dart';
import '../../domain/library.dart';
import '../../domain/models.dart';
import '../../pdf_edit/pdf_saver.dart';

/// The on-device document library. Loaded once from the index file; every
/// change is applied in memory and then written back atomically.
final libraryProvider = AsyncNotifierProvider<LibraryController, LibraryIndex>(LibraryController.new);

/// All saved documents, newest first. Empty while loading or on error; read
/// [libraryProvider] directly to show those states.
final savedDocumentsProvider = Provider<List<SavedDocument>>(
  (ref) => ref.watch(libraryProvider).value?.documents ?? const [],
);

/// One saved document by id, or null when it is not (or no longer) there.
final savedDocumentProvider = Provider.family<SavedDocument?, String>(
  (ref, id) => ref.watch(libraryProvider).value?.byId(id),
);

class LibraryController extends AsyncNotifier<LibraryIndex> {
  Future<void> _writes = Future.value();

  @override
  Future<LibraryIndex> build() => ref.read(libraryStoreProvider).load();

  /// Registers a PDF exported from scanned [pages] and renders its thumbnail
  /// from the first page.
  Future<SavedDocument> addScan(File pdf, List<ScanPage> pages, {ScanType type = ScanType.document}) async {
    final id = await _idFor(pdf);
    final thumbnail = pages.isEmpty ? null : await ref.read(libraryStoreProvider).writeThumbnail(id, pages.first);
    return _add(id, pdf, pageCount: pages.length, type: type, thumbnailPath: thumbnail);
  }

  /// Registers a PDF saved from the PDF editor.
  Future<SavedDocument> addPdf(File pdf, {required int pageCount}) async =>
      _add(await _idFor(pdf), pdf, pageCount: pageCount, type: ScanType.pdf);

  /// Saving again under the same file name overwrites that file, so it keeps
  /// the existing entry's id instead of being listed twice.
  Future<String> _idFor(File pdf) async =>
      (await future).documents.where((d) => d.pdfPath == pdf.path).firstOrNull?.id ??
      ref.read(pageStoreProvider).newId();

  Future<SavedDocument> _add(
    String id,
    File pdf, {
    required int pageCount,
    required ScanType type,
    String? thumbnailPath,
  }) async {
    final now = DateTime.now();
    late SavedDocument saved;
    await _update((index) {
      final previous = index.byId(id);
      saved = SavedDocument(
        id: id,
        name: path.basenameWithoutExtension(pdf.path),
        pdfPath: pdf.path,
        pageCount: pageCount,
        thumbnailPath: thumbnailPath ?? previous?.thumbnailPath,
        type: type,
        createdAt: previous?.createdAt ?? now,
        modifiedAt: now,
        folderId: previous?.folderId,
        tags: previous?.tags ?? const [],
        sizeBytes: pdf.lengthSync(),
      );
      return index.copyWith(documents: [saved, ...index.documents.where((d) => d.id != id)]);
    });
    return saved;
  }

  /// Renames the document and its PDF file, so shared files carry the new
  /// name. Picks "Name (2)" when another file already has that name.
  Future<void> rename(String id, String name) async {
    final doc = state.value?.byId(id);
    if (doc == null) return;
    final dir = path.dirname(doc.pdfPath);
    final stem = path.basenameWithoutExtension(PdfEditSaver.safeFileName(name));
    var target = path.join(dir, '$stem.pdf');
    for (var n = 2; target != doc.pdfPath && File(target).existsSync(); n++) {
      target = path.join(dir, '$stem ($n).pdf');
    }
    if (target != doc.pdfPath) await File(doc.pdfPath).rename(target);
    await _edit(id, (d) => d.copyWith(name: path.basenameWithoutExtension(target), pdfPath: target));
  }

  /// Removes the document from the library and deletes its files.
  Future<void> delete(String id) async {
    final doc = state.value?.byId(id);
    if (doc == null) return;
    await _update((index) => index.copyWith(documents: [...index.documents.where((d) => d.id != id)]));
    await ref.read(libraryStoreProvider).deleteFiles(doc);
  }

  /// Moves a document into [folderId], or to the library root when null.
  Future<void> moveToFolder(String id, String? folderId) => moveManyToFolder([id], folderId);

  /// Moves documents into [folderId], or to the library root when null.
  /// Organising does not count as a change, so dates and order stay put.
  Future<void> moveManyToFolder(Iterable<String> ids, String? folderId) {
    final set = ids.toSet();
    return _update(
      (index) => index.copyWith(
        documents: [for (final d in index.documents) set.contains(d.id) ? d.copyWith(folderId: () => folderId) : d],
      ),
    );
  }

  Future<void> setTags(String id, List<String> tags) => updateTags([id], add: tags.toSet(), replace: true);

  /// Adds [add] and removes [remove] on every document in [ids]; with
  /// [replace], each document's tags become exactly [add]. Tags match
  /// without regard to case, and new ones join the tag list.
  Future<void> updateTags(
    Iterable<String> ids, {
    Set<String> add = const {},
    Set<String> remove = const {},
    bool replace = false,
  }) {
    final set = ids.toSet();
    final adding = {for (final t in add) t.trim()}..remove('');
    final removing = {for (final t in remove) t.trim().toLowerCase()};
    List<String> apply(List<String> tags) {
      final out = <String>[];
      for (final t in [if (!replace) ...tags, ...adding]) {
        final lower = t.toLowerCase();
        if (removing.contains(lower) || out.any((o) => o.toLowerCase() == lower)) continue;
        out.add(t);
      }
      return List.unmodifiable(out);
    }

    return _update(
      (index) => index.copyWith(
        tags: _withTags(index, adding),
        documents: [for (final d in index.documents) set.contains(d.id) ? d.copyWith(tags: apply(d.tags)) : d],
      ),
    );
  }

  Future<void> createTag(String name) => _update((index) => index.copyWith(tags: _withTags(index, {name.trim()})));

  /// Renames a tag everywhere it is used.
  Future<void> renameTag(String from, String to) {
    final lower = from.toLowerCase();
    final name = to.trim();
    List<String> swap(List<String> tags) => [for (final t in tags) t.toLowerCase() == lower ? name : t];
    return _update(
      (index) => index.copyWith(
        tags: swap(index.tags),
        documents: [
          for (final d in index.documents)
            d.tags.any((t) => t.toLowerCase() == lower) ? d.copyWith(tags: swap(d.tags)) : d,
        ],
      ),
    );
  }

  /// Removes a tag from the list and from every document; documents stay.
  Future<void> deleteTag(String name) {
    final lower = name.toLowerCase();
    List<String> drop(List<String> tags) => [
      for (final t in tags)
        if (t.toLowerCase() != lower) t,
    ];
    return _update(
      (index) => index.copyWith(
        tags: drop(index.tags),
        documents: [for (final d in index.documents) d.copyWith(tags: drop(d.tags))],
      ),
    );
  }

  static List<String> _withTags(LibraryIndex index, Set<String> add) => [
    ...index.tags,
    for (final t in add)
      if (t.isNotEmpty && !index.allTags.any((e) => e.toLowerCase() == t.toLowerCase())) t,
  ];

  Future<LibraryFolder> createFolder(String name) async {
    final folder = LibraryFolder(id: ref.read(pageStoreProvider).newId(), name: name.trim());
    await _update((index) => index.copyWith(folders: [...index.folders, folder]));
    return folder;
  }

  Future<void> renameFolder(String folderId, String name) => _update(
    (index) => index.copyWith(
      folders: [for (final f in index.folders) f.id == folderId ? LibraryFolder(id: f.id, name: name.trim()) : f],
    ),
  );

  /// Deletes the folder; its documents move to the library root.
  Future<void> deleteFolder(String folderId) => _update(
    (index) => index.copyWith(
      folders: [...index.folders.where((f) => f.id != folderId)],
      documents: [for (final d in index.documents) d.folderId == folderId ? d.copyWith(folderId: () => null) : d],
    ),
  );

  Future<void> _edit(String id, SavedDocument Function(SavedDocument) change) => _update(
    (index) => index.copyWith(
      documents: [for (final d in index.documents) d.id == id ? change(d).copyWith(modifiedAt: DateTime.now()) : d],
    ),
  );

  /// Applies [change] to the current index and writes it. Changes run one at
  /// a time, in order, so a later write never lands before an earlier one.
  Future<void> _update(LibraryIndex Function(LibraryIndex) change) {
    final run = _writes.then((_) async {
      final next = change(await future);
      await ref.read(libraryStoreProvider).save(next);
      state = AsyncData(next);
    });
    _writes = run.catchError((_) {});
    return run;
  }
}
