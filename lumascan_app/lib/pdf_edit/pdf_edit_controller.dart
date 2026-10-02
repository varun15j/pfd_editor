import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'annotations.dart';
import 'pdf_saver.dart';

final pdfRasterizerProvider = Provider<PdfRasterizer>((ref) => PdfrxRasterizer());

final pdfEditSaverProvider = Provider<PdfEditSaver>(
  (ref) => PdfEditSaver(ref.watch(pageStoreProvider), ref.watch(pdfRasterizerProvider)),
);

/// The PDF being edited. The source file is opened read-only; the edit is
/// the ordered page list plus each page's annotations.
@immutable
class PdfEditState {
  const PdfEditState({
    this.sourcePath,
    this.sourceName = '',
    this.password,
    this.pages = const [],
    this.undoStack = const [],
    this.dirty = false,
  });

  final String? sourcePath;
  final String sourceName;

  /// Kept in memory only, so pages can be re-opened when saving.
  final String? password;
  final List<EditorPage> pages;
  final List<List<EditorPage>> undoStack;

  /// True when there are changes that have not been saved to a new PDF.
  final bool dirty;

  bool get isOpen => sourcePath != null;
  bool get canUndo => undoStack.isNotEmpty;

  EditorPage? pageById(String id) {
    for (final p in pages) {
      if (p.id == id) return p;
    }
    return null;
  }

  PdfEditState copyWith({List<EditorPage>? pages, List<List<EditorPage>>? undoStack, bool? dirty}) => PdfEditState(
    sourcePath: sourcePath,
    sourceName: sourceName,
    password: password,
    pages: pages ?? this.pages,
    undoStack: undoStack ?? this.undoStack,
    dirty: dirty ?? this.dirty,
  );
}

final pdfEditControllerProvider = NotifierProvider<PdfEditController, PdfEditState>(PdfEditController.new);

class PdfEditController extends Notifier<PdfEditState> {
  static const _undoLimit = 50;
  int _counter = 0;

  @override
  PdfEditState build() => const PdfEditState();

  String newId() => '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  /// Starts editing a document. [pageSizes] are the displayed page sizes in
  /// points, in source order.
  void open({required String path, required String name, required List<(double, double)> pageSizes, String? password}) {
    state = PdfEditState(
      sourcePath: path,
      sourceName: name,
      password: password,
      pages: [
        for (var i = 0; i < pageSizes.length; i++)
          EditorPage(id: newId(), sourcePage: i + 1, widthPt: pageSizes[i].$1, heightPt: pageSizes[i].$2),
      ],
    );
  }

  void close() => state = const PdfEditState();

  void _commit(List<EditorPage> pages) {
    final undo = [...state.undoStack, state.pages];
    state = state.copyWith(
      pages: pages,
      undoStack: undo.length > _undoLimit ? undo.sublist(undo.length - _undoLimit) : undo,
      dirty: true,
    );
  }

  void undo() {
    if (!state.canUndo) return;
    final undo = [...state.undoStack];
    final previous = undo.removeLast();
    state = state.copyWith(pages: previous, undoStack: undo, dirty: true);
  }

  void markSaved() => state = state.copyWith(dirty: false);

  List<EditorPage> _mapPage(String pageId, List<Annotation> Function(List<Annotation>) change) => [
    for (final p in state.pages) p.id == pageId ? p.withAnnotations(change(p.annotations)) : p,
  ];

  void addAnnotation(String pageId, Annotation a) => _commit(_mapPage(pageId, (list) => [...list, a]));

  void replaceAnnotation(String pageId, Annotation a) =>
      _commit(_mapPage(pageId, (list) => [for (final x in list) x.id == a.id ? a : x]));

  void removeAnnotation(String pageId, String annotationId) => _commit(
    _mapPage(
      pageId,
      (list) => [
        for (final x in list)
          if (x.id != annotationId) x,
      ],
    ),
  );

  /// Moves a page using ReorderableListView.onReorderItem indices.
  void movePage(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final pages = [...state.pages];
    final page = pages.removeAt(oldIndex);
    pages.insert(newIndex.clamp(0, pages.length), page);
    _commit(pages);
  }

  /// Deletes a page. The last remaining page cannot be deleted because a
  /// PDF needs at least one page. Returns false when nothing was deleted.
  bool deletePage(String pageId) {
    if (state.pages.length <= 1) return false;
    _commit([
      for (final p in state.pages)
        if (p.id != pageId) p,
    ]);
    return true;
  }
}
