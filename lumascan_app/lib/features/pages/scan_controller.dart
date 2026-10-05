import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../app/providers.dart';
import '../../data/library_store.dart';
import '../../domain/models.dart';
import '../../domain/photo_import.dart';
import '../../domain/scanner_service.dart';
import '../../pdf_edit/annotations.dart';

/// Pages being added to the draft: [done] of [total] are ready. The screen
/// shows a placeholder for each page still to come.
@immutable
class AddProgress {
  const AddProgress({required this.total, this.done = 0});

  final int total;
  final int done;

  AddProgress advanced() => AddProgress(total: total, done: done + 1);

  @override
  bool operator ==(Object other) => other is AddProgress && other.total == total && other.done == done;

  @override
  int get hashCode => Object.hash(total, done);
}

@immutable
class ScanState {
  const ScanState({
    this.pages = const [],
    this.busy = false,
    this.adding,
    this.undoStack = const [],
    this.redoStack = const [],
    this.unsaved = false,
  });

  final List<ScanPage> pages;

  /// True while the scanner is open or pages are being imported. Repeat
  /// taps on the scan button are ignored while busy (LLD section 6).
  final bool busy;

  /// Set while the pages of one scan or import are being saved, so the screen
  /// can show what is coming. Null the rest of the time.
  final AddProgress? adding;
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
    Object? adding = _keep,
    List<List<ScanPage>>? undoStack,
    List<List<ScanPage>>? redoStack,
    bool? unsaved,
  }) => ScanState(
    pages: pages ?? this.pages,
    busy: busy ?? this.busy,
    adding: identical(adding, _keep) ? this.adding : adding as AddProgress?,
    undoStack: undoStack ?? this.undoStack,
    redoStack: redoStack ?? this.redoStack,
    unsaved: unsaved ?? this.unsaved,
  );
}

const Object _keep = Object();

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

/// Whether the draft on disk matches the pages on screen. [saved] is only
/// reported once the draft file was written, so the screen never claims a
/// save that did not happen.
enum DraftSaveStatus { saved, saving, failed }

final draftSaveStatusProvider = NotifierProvider<DraftSaveStatusNotifier, DraftSaveStatus>(DraftSaveStatusNotifier.new);

class DraftSaveStatusNotifier extends Notifier<DraftSaveStatus> {
  @override
  DraftSaveStatus build() => DraftSaveStatus.saved;

  void set(DraftSaveStatus status) => state = status;
}

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

  /// Saves queued and not yet written, for [draftSaveStatusProvider].
  int _pendingSaves = 0;

  /// Queues a save of the draft. The pages are read when the save runs, so
  /// it always writes the latest draft, even if it waited behind the restore.
  void _persistDraft() {
    final store = ref.read(draftStoreProvider);
    final status = ref.read(draftSaveStatusProvider.notifier);
    _pendingSaves++;
    status.set(DraftSaveStatus.saving);
    _draftIo = _draftIo.then((_) async {
      if (!ref.mounted) return;
      final ok = await _saveQuietly(store, state.pages);
      _pendingSaves--;
      if (!ref.mounted) return;
      if (!ok) {
        status.set(DraftSaveStatus.failed);
      } else if (_pendingSaves == 0) {
        status.set(DraftSaveStatus.saved);
      }
    });
  }

  static Future<bool> _saveQuietly(DraftStore store, List<ScanPage> pages) async {
    try {
      await store.save(pages);
      return true;
    } catch (e) {
      // The draft stays in memory; the next change tries again.
      debugPrint('Draft autosave failed: $e');
      return false;
    }
  }

  /// What a newly captured page starts with: the filter chosen in Settings.
  EditRecipe get _newPageRecipe => EditRecipe(filter: ref.read(appSettingsProvider).defaultFilter);

  /// Shows [total] pages as on their way, then calls [onAdding] so the screen
  /// can open the draft while they are saved.
  void _beginAdding(int total, VoidCallback? onAdding) {
    state = state.copyWith(adding: AddProgress(total: total));
    onAdding?.call();
  }

  void _pageAdded() {
    final progress = state.adding;
    if (progress != null && ref.mounted) state = state.copyWith(adding: progress.advanced());
  }

  /// Opens the scanner and appends the captured pages to the draft. [onAdding]
  /// is called once the captured pages are known and are being saved.
  Future<ScanOutcome> scan(ScanSource source, {VoidCallback? onAdding}) async {
    if (state.busy) return const ScanCancelled();
    state = state.copyWith(busy: true);
    final scanner = ref.read(scannerServiceProvider);
    final store = ref.read(pageStoreProvider);
    try {
      final paths = await scanner.scan(source: source);
      if (paths.isEmpty) return const ScanCancelled();
      if (!ref.mounted) return const ScanCancelled();
      _beginAdding(paths.length, onAdding);
      final added = <ScanPage>[];
      for (final path in paths) {
        final id = store.newId();
        added.add(ScanPage(id: id, originalPath: await store.importOriginal(path, id), recipe: _newPageRecipe));
        _pageAdded();
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
      if (ref.mounted) state = state.copyWith(busy: false, adding: null);
    }
  }

  /// Adds picked photos to the end of the draft in the given order. Photos
  /// that can't be read are skipped and named in the result; the rest are
  /// still added. With [autoCrop], each page starts cropped to the page found
  /// in it, which the user can still adjust.
  Future<PhotoImportResult> importPhotos(
    List<PickedPhoto> photos, {
    required bool autoCrop,
    VoidCallback? onAdding,
  }) async {
    if (state.busy || photos.isEmpty) return const PhotoImportResult(added: 0);
    state = state.copyWith(busy: true);
    _beginAdding(photos.length, onAdding);
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
              recipe: autoCrop && quad != null ? _newPageRecipe.copyWith(crop: quad) : _newPageRecipe,
            ),
          );
        } catch (_) {
          unreadable.add(photo.name);
        }
        _pageAdded();
      }
      if (added.isNotEmpty && ref.mounted) _commit([...state.pages, ...added]);
      return PhotoImportResult(added: added.length, unreadable: unreadable);
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false, adding: null);
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
      final page = ScanPage(id: id, originalPath: await store.importOriginal(paths.first, id), recipe: _newPageRecipe);
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
      annotations: state.pages[i].annotations,
    );
    _commit([...state.pages]..insert(i + 1, copy));
  }

  /// Called once the pages are written to a PDF.
  void markSaved() => state = state.copyWith(unsaved: false);

  /// Saves [recipe] for [pageId]. Marks are placed on the rendered page, so a
  /// new crop or rotation removes them (see [dropsMarks]).
  void updateRecipe(String pageId, EditRecipe recipe) {
    _commit([for (final p in state.pages) p.id == pageId ? _withRecipe(p, recipe) : p]);
  }

  static ScanPage _withRecipe(ScanPage page, EditRecipe recipe) =>
      page.copyWith(recipe: recipe, annotations: _changesGeometry(page.recipe, recipe) ? const [] : page.annotations);

  static bool _changesGeometry(EditRecipe a, EditRecipe b) => a.crop != b.crop || a.quarterTurns != b.quarterTurns;

  /// True when saving [recipe] on [pageId] would remove marks, so the screen
  /// can say so.
  bool dropsMarks(String pageId, EditRecipe recipe) {
    final page = state.pageById(pageId);
    return page != null && page.annotations.isNotEmpty && _changesGeometry(page.recipe, recipe);
  }

  /// Replaces the marks on [pageId]. One undo step.
  void setAnnotations(String pageId, List<Annotation> annotations) {
    final page = state.pageById(pageId);
    if (page == null) return;
    _commit([
      for (final p in state.pages) p.id == pageId ? p.copyWith(annotations: List.unmodifiable(annotations)) : p,
    ]);
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
          _withRecipe(p, draft)
        else if (others.contains(p.id))
          p.copyWith(
            recipe: p.recipe.copyWith(filter: draft.filter, brightness: draft.brightness, contrast: draft.contrast),
          )
        else
          p,
    ]);
  }

  /// Rotates every page in [ids] a quarter turn. Pages keep their order and
  /// unknown IDs are ignored. One undo step covers all of them. Like a single
  /// rotation, it removes the marks on the rotated pages.
  void rotatePages(Set<String> ids, {bool clockwise = true}) {
    if (!_hasAny(ids)) return;
    _commit([
      for (final p in state.pages)
        if (ids.contains(p.id))
          _withRecipe(p, p.recipe.copyWith(quarterTurns: p.recipe.quarterTurns + (clockwise ? 1 : 3)))
        else
          p,
    ]);
  }

  /// True when rotating the pages in [ids] would remove marks from any of
  /// them, so the screen can warn once.
  bool rotationDropsMarks(Set<String> ids) => state.pages.any((p) => ids.contains(p.id) && p.annotations.isNotEmpty);

  /// Copies the filter, brightness and contrast of [recipe] to every page in
  /// [ids]. Each page keeps its own crop, rotation and marks. One undo step.
  void applyEnhancementToPages(Set<String> ids, EditRecipe recipe) {
    if (!_hasAny(ids)) return;
    _commit([
      for (final p in state.pages)
        if (ids.contains(p.id))
          p.copyWith(
            recipe: p.recipe.copyWith(filter: recipe.filter, brightness: recipe.brightness, contrast: recipe.contrast),
          )
        else
          p,
    ]);
  }

  /// Removes every page in [ids]. One undo step brings them all back in
  /// their places; the original files are kept until the draft is cleared.
  void removePages(Set<String> ids) {
    if (!_hasAny(ids)) return;
    _commit([
      for (final p in state.pages)
        if (!ids.contains(p.id)) p,
    ]);
  }

  /// Puts the pages in the order of [ids], as one undo step. Ignored unless
  /// [ids] names every page exactly once, so no page can be lost or doubled.
  void reorderPages(List<String> ids) {
    final pages = state.pages;
    if (ids.length != pages.length || ids.toSet().length != ids.length) return;
    final byId = {for (final p in pages) p.id: p};
    if (!ids.every(byId.containsKey)) return;
    if ([for (final p in pages) p.id].join('/') == ids.join('/')) return;
    _commit([for (final id in ids) byId[id]!]);
  }

  bool _hasAny(Set<String> ids) => state.pages.any((p) => ids.contains(p.id));

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
