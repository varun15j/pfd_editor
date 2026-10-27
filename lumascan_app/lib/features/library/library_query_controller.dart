import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../domain/document_text.dart';
import '../../domain/library.dart';
import '../../domain/plan.dart';
import 'document_text_controller.dart';
import '../../domain/library_query.dart';
import 'library_actions.dart';
import 'library_controller.dart';

/// The Library's search, sort and filters. App-wide state, so it survives
/// tab changes and rotation; it resets when the app restarts.
final libraryQueryProvider = NotifierProvider<LibraryQueryController, LibraryQuery>(LibraryQueryController.new);

class LibraryQueryController extends Notifier<LibraryQuery> {
  @override
  LibraryQuery build() => const LibraryQuery();

  void search(String text) => state = state.copyWith(text: text);

  void sortBy(LibrarySort sort) => state = state.copyWith(sort: sort);

  void filter({
    required Set<ScanType> types,
    required DateFilter date,
    DateTime? from,
    DateTime? to,
    Set<String> tags = const {},
  }) => state = state.copyWith(
    tags: {for (final t in tags) t.toLowerCase()},
    types: types,
    date: date,
    from: () => date == DateFilter.custom ? from : null,
    to: () => date == DateFilter.custom ? to : null,
  );

  void clearTypes() => state = state.copyWith(types: const {});

  void clearTags() => state = state.copyWith(tags: const {});

  /// Browses one folder, or every document when [folderId] is null.
  void openFolder(String? folderId) => state = state.copyWith(folderId: () => folderId);

  void clearDate() => state = state.copyWith(date: DateFilter.any, from: () => null, to: () => null);

  void resetSortAndFilters() => state = state.resetSortAndFilters();
}

/// Documents the Library shows after search, filters and sort.
final filteredDocumentsProvider = Provider<List<SavedDocument>>((ref) {
  var query = ref.watch(libraryQueryProvider);
  final index = ref.watch(libraryProvider).value;
  // A folder or tag deleted while selected stops narrowing the list.
  if (query.folderId != null && index?.folderById(query.folderId) == null) {
    query = query.copyWith(folderId: () => null);
  }
  if (query.tags.isNotEmpty && index != null) {
    final known = {for (final t in index.allTags) t.toLowerCase()};
    query = query.copyWith(tags: query.tags.intersection(known));
  }
  return query.apply(ref.watch(visibleDocumentsProvider), DateTime.now(), texts: ref.watch(searchableTextsProvider));
});

/// Text of documents to search in: on Pro and Gold, while searching. Empty
/// otherwise, so Basic searches names only and nothing is read in vain.
final searchableTextsProvider = Provider<Map<String, DocumentText>>((ref) {
  final searching = ref.watch(libraryQueryProvider.select((q) => q.isSearching));
  if (!searching || !ref.watch(planIncludesProvider(PlanFeature.searchText))) return const {};
  return ref.watch(documentTextProvider.select((s) => s.texts));
});
