import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/library.dart';
import '../../domain/library_query.dart';
import '../../domain/scanner_service.dart';
import '../../domain/ui_prefs.dart';
import '../../ui/state_views.dart';
import 'document_tile.dart';
import 'library_actions.dart';
import 'library_controller.dart';
import 'library_query_controller.dart';
import 'library_query_sheets.dart';

/// Library tab: every saved document as a list or a grid (the choice is
/// remembered), with search by name, sort and filters (US-02.2, US-02.4).
/// Long press selects several documents to share or delete. Folders and
/// tags come with B3.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _selected = <String>{};
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(libraryQueryProvider).text);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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
    final all = ref.watch(visibleDocumentsProvider);
    final docs = ref.watch(filteredDocumentsProvider);
    final query = ref.watch(libraryQueryProvider);
    final view = ref.watch(uiPrefsProvider.select((p) => p.libraryView));
    // Drop selections of documents that were deleted or filtered out.
    _selected.retainAll({for (final d in docs) d.id});

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: _selecting ? _selectionBar(docs) : _normalBar(view, enabled: all.isNotEmpty),
        // Riverpod keeps retrying a failed load in the background, so an
        // error can arrive while the state still reads as loading.
        body: switch (library) {
          AsyncValue(hasValue: false, hasError: true) => ErrorState(
            title: 'Library could not be opened',
            message: 'Your PDFs are still on this device.',
            onRetry: () => ref.invalidate(libraryProvider),
          ),
          AsyncValue(hasValue: true) when all.isEmpty => EmptyState(
            icon: Icons.folder_open_outlined,
            title: 'No saved documents yet',
            message: 'PDFs you save will appear here, ready to find and share.',
            actionLabel: 'Scan a document',
            actionIcon: Icons.document_scanner_outlined,
            onAction: () => scanThenReview(context, ref, ScanSource.camera),
          ),
          AsyncValue(hasValue: true) => Column(
            children: [
              _searchBar(query),
              if (query.isSorted || query.isFiltered) _activeChips(query),
              Expanded(
                child: docs.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off,
                        title: 'No matches',
                        message: query.isSearching
                            ? 'No document name contains "${query.text.trim()}".'
                            : 'No documents match these filters.',
                        actionLabel: 'Show all documents',
                        actionIcon: Icons.filter_alt_off_outlined,
                        onAction: _resetAll,
                      )
                    : view == LibraryView.grid
                    ? _grid(docs)
                    : _list(docs),
              ),
            ],
          ),
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
            onPressed: () => shareDocuments(buttonContext, _selectedDocs(ref.read(filteredDocumentsProvider))),
          ),
        ),
        IconButton(
          tooltip: 'Delete selected',
          icon: const Icon(Icons.delete_outline),
          onPressed: () {
            // Read at tap time so a selection change in the same frame counts.
            final docs = _selectedDocs(ref.read(filteredDocumentsProvider));
            _clearSelection();
            deleteWithUndo(context, ref, docs);
          },
        ),
      ],
    );
  }

  void _resetAll() {
    _search.clear();
    ref.read(libraryQueryProvider.notifier)
      ..search('')
      ..resetSortAndFilters();
  }

  Widget _searchBar(LibraryQuery query) {
    final filters = (query.types.isEmpty ? 0 : 1) + (query.date == DateFilter.any ? 0 : 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.page, Space.xs, Space.sm, Space.xs),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: ref.read(libraryQueryProvider.notifier).search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by name',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          ref.read(libraryQueryProvider.notifier).search('');
                        },
                      ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sort: ${query.sort.label}',
            icon: const Icon(Icons.sort),
            onPressed: () => showSortSheet(context),
          ),
          IconButton(
            tooltip: filters == 0 ? 'Filter' : 'Filter, $filters active',
            icon: Badge(isLabelVisible: filters > 0, label: Text('$filters'), child: const Icon(Icons.filter_list)),
            onPressed: () => showFilterSheet(context),
          ),
        ],
      ),
    );
  }

  /// Active sort and filters as removable chips, with one Reset.
  Widget _activeChips(LibraryQuery query) {
    final q = ref.read(libraryQueryProvider.notifier);
    // Wrap, not a scrolling row, so Reset is never pushed off screen.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Space.page),
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (query.isSorted)
            InputChip(
              avatar: const Icon(Icons.sort, size: 18),
              label: Text(query.sort.label),
              onPressed: () => showSortSheet(context),
              onDeleted: () => q.sortBy(LibrarySort.newest),
              deleteButtonTooltipMessage: 'Remove sort',
            ),
          if (query.types.isNotEmpty)
            InputChip(
              label: Text(
                [
                  for (final t in ScanType.values)
                    if (query.types.contains(t)) t.label,
                ].join(', '),
              ),
              onPressed: () => showFilterSheet(context),
              onDeleted: q.clearTypes,
              deleteButtonTooltipMessage: 'Remove type filter',
            ),
          if (query.date != DateFilter.any)
            InputChip(
              avatar: const Icon(Icons.event, size: 18),
              label: Text(query.dateLabel),
              onPressed: () => showFilterSheet(context),
              onDeleted: q.clearDate,
              deleteButtonTooltipMessage: 'Remove date filter',
            ),
          TextButton(onPressed: q.resetSortAndFilters, child: const Text('Reset')),
        ],
      ),
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
