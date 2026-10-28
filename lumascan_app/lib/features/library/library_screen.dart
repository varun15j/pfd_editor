import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/document_text.dart';
import '../../domain/library.dart';
import '../../domain/library_query.dart';
import '../../domain/plan.dart';
import '../../domain/scanner_service.dart';
import '../../domain/ui_prefs.dart';
import '../../ui/state_views.dart';
import '../split/split_actions.dart';
import '../word/word_actions.dart';
import 'document_text_controller.dart';
import 'document_tile.dart';
import 'library_actions.dart';
import 'library_controller.dart';
import 'library_organize.dart';
import 'library_query_controller.dart';
import 'library_query_sheets.dart';
import '../../ui/luma_icons.dart';

/// Library tab: every saved document as a list or a grid (the choice is
/// remembered), with search by name (and by text on Pro), sort and filters (US-02.2, US-02.4).
/// Folder chips browse one folder at a time. Long press selects several
/// documents to share, delete, move or tag.
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
      case DocumentMenuAction.move:
        moveToFolderSheet(context, ref, [doc]);
      case DocumentMenuAction.tags:
        editTagsSheet(context, ref, [doc]);
      case DocumentMenuAction.share:
        shareDocuments(context, [doc]);
      case DocumentMenuAction.password:
        addPasswordToDocument(context, ref, doc);
      case DocumentMenuAction.textPdf:
        createTextPdf(context, ref, doc);
      case DocumentMenuAction.word:
        convertToWord(context, ref, doc);
      case DocumentMenuAction.split:
        splitDocument(context, ref, doc);
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
    final folder = library.value?.folderById(query.folderId);
    final view = ref.watch(uiPrefsProvider.select((p) => p.libraryView));
    // Pro and Gold: start reading documents for search as soon as the
    // Library opens, so results are ready when the user types.
    final searchText = ref.watch(planIncludesProvider(PlanFeature.searchText));
    final reading = searchText ? ref.watch(documentTextProvider.select((s) => s.left)) : 0;
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
            icon: LumaIcons.folderOpen,
            title: 'No saved documents yet',
            message: 'PDFs you save will appear here, ready to find and share.',
            actionLabel: 'Scan a document',
            actionIcon: LumaIcons.scan,
            onAction: () => scanThenReview(context, ref, ScanSource.camera),
          ),
          AsyncValue(hasValue: true) => Column(
            children: [
              _searchBar(query),
              _folderBar(query),
              if (query.isSorted || query.isFiltered) _activeChips(query),
              if (query.isSearching && searchText && reading > 0 && docs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xs),
                  child: Text(
                    'Reading $reading more document${reading == 1 ? '' : 's'} for search…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Expanded(
                child: docs.isEmpty && folder != null && !query.isSearching && !query.isFiltered
                    ? EmptyState(
                        icon: LumaIcons.folderOpen,
                        title: '${folder.name} is empty',
                        message: 'Use Move to folder on a document to add it here.',
                        actionLabel: 'Show all documents',
                        actionIcon: LumaIcons.allFolders,
                        onAction: () => ref.read(libraryQueryProvider.notifier).openFolder(null),
                      )
                    : docs.isEmpty
                    ? EmptyState(
                        icon: LumaIcons.noResults,
                        title: 'No matches',
                        message: !query.isSearching
                            ? 'No documents match these filters.'
                            : searchText
                            ? 'No document name or text contains "${query.text.trim()}".'
                                  '${reading > 0 ? ' Still reading $reading document${reading == 1 ? '' : 's'}.' : ''}'
                            : 'No document name contains "${query.text.trim()}". '
                                  'Pro also searches the text inside documents.',
                        actionLabel: 'Show all documents',
                        actionIcon: LumaIcons.clearFilter,
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
          tooltip: 'Folders and tags',
          icon: const Icon(LumaIcons.tag),
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ManageLabelsScreen())),
        ),
        IconButton(
          tooltip: grid ? 'Show as list' : 'Show as grid',
          icon: Icon(grid ? LumaIcons.listView : LumaIcons.gridView),
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
      leading: IconButton(tooltip: 'Cancel selection', icon: const Icon(LumaIcons.close), onPressed: _clearSelection),
      title: Semantics(liveRegion: true, child: Text('${picked.length} selected')),
      actions: [
        IconButton(
          tooltip: all ? 'Select none' : 'Select all',
          icon: Icon(all ? LumaIcons.deselect : LumaIcons.selectAll),
          onPressed: () => setState(() => all ? _selected.clear() : _selected.addAll(docs.map((d) => d.id))),
        ),
        Builder(
          builder: (buttonContext) => IconButton(
            tooltip: 'Share selected',
            icon: const Icon(LumaIcons.share),
            onPressed: () => shareDocuments(buttonContext, _selectedDocs(ref.read(filteredDocumentsProvider))),
          ),
        ),
        IconButton(
          tooltip: 'Delete selected',
          icon: const Icon(LumaIcons.delete),
          onPressed: () {
            // Read at tap time so a selection change in the same frame counts.
            final docs = _selectedDocs(ref.read(filteredDocumentsProvider));
            _clearSelection();
            deleteWithUndo(context, ref, docs);
          },
        ),
        PopupMenuButton<int>(
          tooltip: 'More actions',
          onSelected: (v) {
            final docs = _selectedDocs(ref.read(filteredDocumentsProvider));
            _clearSelection();
            v == 0 ? moveToFolderSheet(context, ref, docs) : editTagsSheet(context, ref, docs);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 0,
              child: ListTile(leading: Icon(LumaIcons.moveToFolder), title: Text('Move to folder')),
            ),
            PopupMenuItem(
              value: 1,
              child: ListTile(leading: Icon(LumaIcons.tag), title: Text('Tags')),
            ),
          ],
        ),
      ],
    );
  }

  String? _labels(SavedDocument doc) => documentLabels(doc, ref.read(libraryProvider).value ?? const LibraryIndex());

  void _resetAll() {
    _search.clear();
    ref.read(libraryQueryProvider.notifier)
      ..search('')
      ..resetSortAndFilters()
      ..openFolder(null);
  }

  Widget _searchBar(LibraryQuery query) {
    final searchText = ref.watch(planIncludesProvider(PlanFeature.searchText));
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
                hintText: searchText ? 'Search names and text' : 'Search by name',
                prefixIcon: const Icon(LumaIcons.search),
                suffixIcon: query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(LumaIcons.close),
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
            icon: const Icon(LumaIcons.sort),
            onPressed: () => showSortSheet(context),
          ),
          IconButton(
            tooltip: filters == 0 ? 'Filter' : 'Filter, $filters active',
            icon: Badge(isLabelVisible: filters > 0, label: Text('$filters'), child: const Icon(LumaIcons.filter)),
            onPressed: () => showFilterSheet(context),
          ),
        ],
      ),
    );
  }

  /// "All" plus one chip per folder; picking one browses that folder.
  Widget _folderBar(LibraryQuery query) {
    final index = ref.watch(libraryProvider).value ?? const LibraryIndex();
    final current = index.folderById(query.folderId)?.id;
    final q = ref.read(libraryQueryProvider.notifier);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Space.page),
      child: Row(
        children: [
          ChoiceChip(label: const Text('All'), selected: current == null, onSelected: (_) => q.openFolder(null)),
          for (final f in index.folders) ...[
            const SizedBox(width: Space.sm),
            ChoiceChip(
              label: Text(f.name),
              selected: current == f.id,
              onSelected: (_) => q.openFolder(current == f.id ? null : f.id),
            ),
          ],
          const SizedBox(width: Space.sm),
          ActionChip(
            avatar: const Icon(LumaIcons.createNewFolder, size: 18),
            label: const Text('New folder'),
            onPressed: () async {
              final folder = await createFolderFlow(context, ref);
              if (folder != null) q.openFolder(folder.id);
            },
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
              avatar: const Icon(LumaIcons.sort, size: 18),
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
          if (query.tags.isNotEmpty)
            InputChip(
              avatar: const Icon(LumaIcons.tag, size: 18),
              label: Text(query.tags.join(', ')),
              onPressed: () => showFilterSheet(context),
              onDeleted: q.clearTags,
              deleteButtonTooltipMessage: 'Remove tag filter',
            ),
          if (query.date != DateFilter.any)
            InputChip(
              avatar: const Icon(LumaIcons.removeDate, size: 18),
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
        labels: _labels(doc),
        snippet: _snippet(doc),
        selecting: _selecting,
        selected: _selected.contains(doc.id),
        onTap: () => _onTap(doc),
        onLongPress: () => _toggle(doc.id),
        onMenu: (a) => _onMenu(doc, a),
      );
    },
  );

  /// Where the search text was found inside [doc], when not in its name.
  String? _snippet(SavedDocument doc) {
    final needle = ref.read(libraryQueryProvider).text.trim();
    if (needle.isEmpty || doc.name.toLowerCase().contains(needle.toLowerCase())) return null;
    final text = ref.read(searchableTextsProvider)[doc.id]?.text;
    return text == null ? null : searchSnippet(text, needle);
  }

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
            labels: _labels(doc),
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
