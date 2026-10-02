import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models.dart';
import '../../domain/scanner_service.dart';

@immutable
class ScanState {
  const ScanState({this.pages = const [], this.busy = false, this.undoStack = const []});

  final List<ScanPage> pages;

  /// True while the scanner is open or pages are being imported. Repeat
  /// taps on the scan button are ignored while busy (LLD section 6).
  final bool busy;
  final List<List<ScanPage>> undoStack;

  bool get canUndo => undoStack.isNotEmpty;

  ScanPage? pageById(String id) {
    for (final p in pages) {
      if (p.id == id) return p;
    }
    return null;
  }

  ScanState copyWith({List<ScanPage>? pages, bool? busy, List<List<ScanPage>>? undoStack}) => ScanState(
        pages: pages ?? this.pages,
        busy: busy ?? this.busy,
        undoStack: undoStack ?? this.undoStack,
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

  @override
  ScanState build() => const ScanState();

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

  void updateRecipe(String pageId, EditRecipe recipe) {
    _commit([
      for (final p in state.pages) p.id == pageId ? p.copyWith(recipe: recipe) : p,
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
    _commit([for (final p in state.pages) if (p.id != pageId) p]);
  }

  void undo() {
    if (!state.canUndo) return;
    final stack = [...state.undoStack];
    final previous = stack.removeLast();
    state = state.copyWith(pages: previous, undoStack: stack);
  }

  /// Discards the draft and deletes its original files.
  Future<void> clear() async {
    final store = ref.read(pageStoreProvider);
    final paths = {
      for (final p in state.pages) p.originalPath,
      for (final snapshot in state.undoStack)
        for (final p in snapshot) p.originalPath,
    };
    state = const ScanState();
    for (final path in paths) {
      await store.deleteOriginal(path);
    }
  }

  void _commit(List<ScanPage> pages) {
    var stack = [...state.undoStack, state.pages];
    if (stack.length > _undoLimit) stack = stack.sublist(stack.length - _undoLimit);
    state = state.copyWith(pages: List.unmodifiable(pages), undoStack: stack);
  }
}
