import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/library_store.dart';
import '../../domain/models.dart';
import '../../domain/photo_import.dart';
import '../../domain/scanner_service.dart';

@immutable
class ScanState {
  const ScanState({
    this.pages = const [],
    this.busy = false,
    this.undoStack = const [],
    this.redoStack = const [],
    this.unsaved = false,
  });

  final List<ScanPage> pages;

  /// True while the scanner is open or pages are being imported. Repeat
  /// taps on the scan button are ignored while busy (LLD section 6).
  final bool busy;
  final List<List<ScanPage>> undoStack;
  final List<List<ScanPage>> redoStack;

  /// True when the pages changed since they were last exported as a PDF.
  final bool unsaved;

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  ScanPage? pageById(String id) {
    for (final p in pages) {
      if (p.id == id) return p;
    }
    return null;
  }

  ScanState copyWith({
    List<ScanPage>? pages,
    bool? busy,
    List<List<ScanPage>>? undoStack,
    List<List<ScanPage>>? redoStack,
    bool? unsaved,
  }) => ScanState(
    pages: pages ?? this.pages,
    busy: busy ?? this.busy,
    undoStack: undoStack ?? this.undoStack,
    redoStack: redoStack ?? this.redoStack,
    unsaved: unsaved ?? this.unsaved,
  );
}

sealed class ScanOutcome {
  const ScanOutcome();
}

class ScanAdded extends ScanOutcome {
  const ScanAdded(this.count);
  final int count;
}

class ScanCancelled extends ScanOutcome {
  const ScanCancelled();
}

class ScanPermissionBlocked extends ScanOutcome {
  const ScanPermissionBlocked({required this.permanently});
  final bool permanently;
}

class ScanFailed extends ScanOutcome {
  const ScanFailed(this.message);
  final String message;
}

final scanControllerProvider = NotifierProvider<ScanController, ScanState>(ScanController.new);

class ScanController extends Notifier<ScanState> {
  static const _undoLimit = 30;

  /// Draft reads and writes, chained so they reach the disk in order.
  Future<void> _draftIo = Future.value();

  /// Completes once the restored draft is loaded and every change made so
  /// far is on disk.
  @visibleForTesting
  Future<void> get draftSaved => _draftIo;

  @override
  ScanState build() {
    _draftIo = _restoreDraft().catchError((Object e) => debugPrint('Draft restore failed: $e'));
    return const ScanState();
  }

  /// Brings back the draft that was on screen when the app was last closed
  /// or killed (US-09.1). The undo history is not restored.
  Future<void> _restoreDraft() async {
    final store = ref.read(draftStoreProvider);
    final saved = await store.load();
    if (!ref.mounted || saved.isEmpty) return;
    // Pages scanned while the draft was loading go after the restored ones;
    // their own save is queued behind this restore and writes the merge.
    state = state.copyWith(pages: List.unmodifiable([...saved, ...state.pages]), unsaved: true);
  }

  /// Queues a save of the draft. The pages are read when the save runs, so
  /// it always writes the latest draft, even if it waited behind the restore.
  void _persistDraft() {
    final store = ref.read(draftStoreProvider);
    _draftIo = _draftIo.then((_) {
      if (ref.mounted) return _saveQuietly(store, state.pages);
    });
  }

  static Future<void> _saveQuietly(DraftStore store, List<ScanPage> pages) async {
    try {
      await store.save(pages);
    } catch (e) {
      // The draft stays in memory; the next change tries again.
      debugPrint('Draft autosave failed: $e');
    }
  }

  /// Opens the scanner and appends the captured pages to the draft.
  Future<ScanOutcome> scan(ScanSource source) async {
    if (state.busy) return const ScanCancelled();
    state = state.copyWith(busy: true);
    final scanner = ref.read(scannerServiceProvider);
    final store = ref.read(pageStoreProvider);
    try {
      final paths = await scanner.scan(source: source);
      if (paths.isEmpty) return const ScanCancelled();
      final added = <ScanPage>[];
      for (final path in paths) {
        final id = store.newId();
        added.add(ScanPage(id: id, originalPath: await store.importOriginal(path, id)));
      }
      await scanner.cleanUp();
      _commit([...state.pages, ...added]);
      return ScanAdded(added.length);
    } on ScannerPermissionDenied catch (e) {
      return ScanPermissionBlocked(permanently: e.permanently);
    } on ScannerFailure catch (e) {
      return ScanFailed(e.message);
    } catch (e) {
      return ScanFailed('Could not save the scanned pages ($e)');
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  /// Adds picked photos to the end of the draft in the given order. Photos
  /// that can't be read are skipped and named in the result; the rest are
  /// still added. With [autoCrop], each page starts cropped to the page found
  /// in it, which the user can still adjust.
  Future<PhotoImportResult> importPhotos(List<PickedPhoto> photos, {required bool autoCrop}) async {
    if (state.busy || photos.isEmpty) return const PhotoImportResult(added: 0);
    state = state.copyWith(busy: true);
    final analyzer = ref.read(photoAnalyzerProvider);
    final store = ref.read(pageStoreProvider);
    final added = <ScanPage>[];
    final unreadable = <String>[];
    try {
      for (final photo in photos) {
        try {
          final quad = await analyzer.analyze(photo.path);
          final id = store.newId();
          final original = await store.importOriginal(photo.path, id);
          added.add(
            ScanPage(
              id: id,
              originalPath: original,
              recipe: autoCrop && quad != null ? EditRecipe(crop: quad) : const EditRecipe(),
            ),
          );
        } catch (_) {
          unreadable.add(photo.name);
        }
      }
      if (added.isNotEmpty && ref.mounted) _commit([...state.pages, ...added]);
      return PhotoImportResult(added: added.length, unreadable: unreadable);
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  /// Replaces [pageId] with a new camera capture. The page keeps its place;
  /// its old image stays until the draft is cleared, so undo brings it back.
  Future<ScanOutcome> retake(String pageId) async {
    if (state.busy || state.pageById(pageId) == null) return const ScanCancelled();
    state = state.copyWith(busy: true);
    final scanner = ref.read(scannerServiceProvider);
    final store = ref.read(pageStoreProvider);
    try {
      final paths = await scanner.scan(source: ScanSource.camera, maxPages: 1);
      if (paths.isEmpty) return const ScanCancelled();
      final id = store.newId();
      final page = ScanPage(id: id, originalPath: await store.importOriginal(paths.first, id));
      await scanner.cleanUp();
      if (!ref.mounted) return const ScanCancelled();
      _commit([for (final p in state.pages) p.id == pageId ? page : p]);
      return const ScanAdded(1);
    } on ScannerPermissionDenied catch (e) {
      return ScanPermissionBlocked(permanently: e.permanently);
    } on ScannerFailure catch (e) {
      return ScanFailed(e.message);
    } catch (e) {
      return ScanFailed('Could not save the new page ($e)');
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  /// Inserts a copy of [pageId], with the same edits, right after it. Both
  /// pages share the original image, which is never modified.
  void duplicate(String pageId) {
    final i = state.pages.indexWhere((p) => p.id == pageId);
    if (i < 0) return;
    final copy = ScanPage(
      id: ref.read(pageStoreProvider).newId(),
      originalPath: state.pages[i].originalPath,
      recipe: state.pages[i].recipe,
    );
    _commit([...state.pages]..insert(i + 1, copy));
  }

  /// Called once the pages are written to a PDF.
  void markSaved() => state = state.copyWith(unsaved: false);

  void updateRecipe(String pageId, EditRecipe recipe) {
    _commit([for (final p in state.pages) p.id == pageId ? p.copyWith(recipe: recipe) : p]);
  }

  void rotate(String pageId, {bool clockwise = true}) {
    final page = state.pageById(pageId);
    if (page == null) return;
    updateRecipe(pageId, page.recipe.copyWith(quarterTurns: page.recipe.quarterTurns + (clockwise ? 1 : 3)));
  }

  /// Batch apply copies only the filter; each page keeps its own crop and
  /// rotation (LLD section 7).
  void applyFilterToAll(DocumentFilter filter) {
    _commit([for (final p in state.pages) p.copyWith(recipe: p.recipe.copyWith(filter: filter))]);
  }

  /// Saves [draft] as [pageId]'s recipe and copies its filter, brightness and
  /// contrast to every page in [alsoPageIds]. Those pages keep their own crop
  /// and rotation. One undo step covers all of it.
  void applyEnhancement(String pageId, EditRecipe draft, {Iterable<String> alsoPageIds = const []}) {
    final others = alsoPageIds.toSet()..remove(pageId);
    _commit([
      for (final p in state.pages)
        if (p.id == pageId)
          p.copyWith(recipe: draft)
        else if (others.contains(p.id))
          p.copyWith(
            recipe: p.recipe.copyWith(filter: draft.filter, brightness: draft.brightness, contrast: draft.contrast),
          )
        else
          p,
    ]);
  }

  /// Moves a page; [newIndex] is its position after removal from [oldIndex].
  void move(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final pages = [...state.pages];
    pages.insert(newIndex, pages.removeAt(oldIndex));
    _commit(pages);
  }

  /// Removes a page from the draft. The original file is kept until the
  /// draft is cleared so the removal can be undone.
  void remove(String pageId) {
    _commit([
      for (final p in state.pages)
        if (p.id != pageId) p,
    ]);
  }

  void undo() {
    if (!state.canUndo) return;
    final stack = [...state.undoStack];
    final previous = stack.removeLast();
    state = state.copyWith(
      pages: previous,
      undoStack: stack,
      redoStack: [...state.redoStack, state.pages],
      unsaved: true,
    );
    _persistDraft();
  }

  void redo() {
    if (!state.canRedo) return;
    final stack = [...state.redoStack];
    final next = stack.removeLast();
    state = state.copyWith(pages: next, redoStack: stack, undoStack: [...state.undoStack, state.pages], unsaved: true);
    _persistDraft();
  }

  /// Discards the draft and deletes its original files.
  Future<void> clear() async {
    final store = ref.read(pageStoreProvider);
    final paths = {
      for (final p in state.pages) p.originalPath,
      for (final snapshot in [...state.undoStack, ...state.redoStack])
        for (final p in snapshot) p.originalPath,
    };
    state = const ScanState();
    _persistDraft();
    for (final path in paths) {
      await store.deleteOriginal(path);
    }
  }

  void _commit(List<ScanPage> pages) {
    var stack = [...state.undoStack, state.pages];
    if (stack.length > _undoLimit) stack = stack.sublist(stack.length - _undoLimit);
    state = state.copyWith(pages: List.unmodifiable(pages), undoStack: stack, redoStack: const [], unsaved: true);
    _persistDraft();
  }
}
