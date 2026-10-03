import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/library.dart';
import '../../domain/scanner_service.dart';
import '../../domain/ui_prefs.dart';
import '../../ui/state_views.dart';
import 'document_tile.dart';
import 'library_actions.dart';
import 'library_controller.dart';

/// Library tab: every saved document, newest first, as a list or a grid
/// (the choice is remembered). Long press selects several documents to
/// share or delete. Search, sort and filters come with B2; folders and tags
/// with B3.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _selected = <String>{};

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  void _clearSelection() => setState(_selected.clear);

  List<SavedDocument> _selectedDocs(List<SavedDocument> docs) => [
    for (final d in docs)
      if (_selected.contains(d.id)) d,
  ];

  void _onTap(SavedDocument doc) => _selecting ? _toggle(doc.id) : openDocument(context, ref, doc);

  void _onMenu(SavedDocument doc, DocumentMenuAction action) {
    switch (action) {
      case DocumentMenuAction.rename:
        renameDocument(context, ref, doc);
      case DocumentMenuAction.share:
        shareDocuments(context, [doc]);
      case DocumentMenuAction.delete:
        deleteWithUndo(context, ref, [doc]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    final docs = ref.watch(visibleDocumentsProvider);
    final view = ref.watch(uiPrefsProvider.select((p) => p.libraryView));
    // Drop selections of documents that were deleted meanwhile.
    _selected.retainAll({for (final d in docs) d.id});

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: _selecting ? _selectionBar(docs) : _normalBar(view, enabled: docs.isNotEmpty),
        // Riverpod keeps retrying a failed load in the background, so an
        // error can arrive while the state still reads as loading.
        body: switch (library) {
          AsyncValue(hasValue: false, hasError: true) => ErrorState(
            title: 'Library could not be opened',
            message: 'Your PDFs are still on this device.',
            onRetry: () => ref.invalidate(libraryProvider),
          ),
          AsyncValue(hasValue: true) when docs.isEmpty => EmptyState(
            icon: Icons.folder_open_outlined,
            title: 'No saved documents yet',
            message: 'PDFs you save will appear here, ready to find and share.',
            actionLabel: 'Scan a document',
            actionIcon: Icons.document_scanner_outlined,
            onAction: () => scanThenReview(context, ref, ScanSource.camera),
          ),
          AsyncValue(hasValue: true) => view == LibraryView.grid ? _grid(docs) : _list(docs),
          _ => const LoadingList(label: 'Loading documents'),
        },
      ),
    );
  }

  PreferredSizeWidget _normalBar(LibraryView view, {required bool enabled}) {
    final grid = view == LibraryView.grid;
    return AppBar(
      title: const Text('Library'),
      actions: [
        IconButton(
          tooltip: grid ? 'Show as list' : 'Show as grid',
          icon: Icon(grid ? Icons.view_list_outlined : Icons.grid_view_outlined),
          onPressed: enabled
              ? () => ref.read(uiPrefsProvider.notifier).setLibraryView(grid ? LibraryView.list : LibraryView.grid)
              : null,
        ),
      ],
    );
  }

  PreferredSizeWidget _selectionBar(List<SavedDocument> docs) {
    final picked = _selectedDocs(docs);
    final all = picked.length == docs.length;
    return AppBar(
      leading: IconButton(tooltip: 'Cancel selection', icon: const Icon(Icons.close), onPressed: _clearSelection),
      title: Semantics(liveRegion: true, child: Text('${picked.length} selected')),
      actions: [
        IconButton(
          tooltip: all ? 'Select none' : 'Select all',
          icon: Icon(all ? Icons.deselect : Icons.select_all),
          onPressed: () => setState(() => all ? _selected.clear() : _selected.addAll(docs.map((d) => d.id))),
        ),
        Builder(
          builder: (buttonContext) => IconButton(
            tooltip: 'Share selected',
            icon: const Icon(Icons.ios_share),
            onPressed: () => shareDocuments(buttonContext, _selectedDocs(ref.read(visibleDocumentsProvider))),
          ),
        ),
        IconButton(
          tooltip: 'Delete selected',
          icon: const Icon(Icons.delete_outline),
          onPressed: () {
            // Read at tap time so a selection change in the same frame counts.
            final docs = _selectedDocs(ref.read(visibleDocumentsProvider));
            _clearSelection();
            deleteWithUndo(context, ref, docs);
          },
        ),
      ],
    );
  }

  // Bottom padding keeps the last item clear of the centre Scan button.
  static const _padding = EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xxl * 3);

  Widget _list(List<SavedDocument> docs) => ListView.separated(
    padding: _padding,
    itemCount: docs.length,
    separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
    itemBuilder: (_, i) {
      final doc = docs[i];
      return DocumentRow(
        key: ValueKey(doc.id),
        document: doc,
        selecting: _selecting,
        selected: _selected.contains(doc.id),
        onTap: () => _onTap(doc),
        onLongPress: () => _toggle(doc.id),
        onMenu: (a) => _onMenu(doc, a),
      );
    },
  );

  Widget _grid(List<SavedDocument> docs) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth - _padding.horizontal;
      final columns = math.max(2, (width / 180).floor());
      final tileWidth = (width - Space.md * (columns - 1)) / columns;
      // Thumbnail area is a page shape; the text area grows with font size.
      final textHeight = MediaQuery.textScalerOf(context).scale(DocumentGridCard.textHeight);
      return GridView.builder(
        padding: _padding,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: Space.md,
          mainAxisSpacing: Space.md,
          mainAxisExtent: tileWidth * 1.1 + textHeight + Space.lg,
        ),
        itemCount: docs.length,
        itemBuilder: (_, i) {
          final doc = docs[i];
          return DocumentGridCard(
            key: ValueKey(doc.id),
            document: doc,
            selecting: _selecting,
            selected: _selected.contains(doc.id),
            onTap: () => _onTap(doc),
            onLongPress: () => _toggle(doc.id),
            onMenu: (a) => _onMenu(doc, a),
          );
        },
      );
    },
  );
}
