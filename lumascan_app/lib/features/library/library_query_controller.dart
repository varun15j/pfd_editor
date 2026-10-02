import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/library.dart';
import '../../domain/library_query.dart';
import 'library_actions.dart';

/// The Library's search, sort and filters. App-wide state, so it survives
/// tab changes and rotation; it resets when the app restarts.
final libraryQueryProvider = NotifierProvider<LibraryQueryController, LibraryQuery>(LibraryQueryController.new);

class LibraryQueryController extends Notifier<LibraryQuery> {
  @override
  LibraryQuery build() => const LibraryQuery();

  void search(String text) => state = state.copyWith(text: text);

  void sortBy(LibrarySort sort) => state = state.copyWith(sort: sort);

  void filter({required Set<ScanType> types, required DateFilter date, DateTime? from, DateTime? to}) =>
      state = state.copyWith(
        types: types,
        date: date,
        from: () => date == DateFilter.custom ? from : null,
        to: () => date == DateFilter.custom ? to : null,
      );

  void clearTypes() => state = state.copyWith(types: const {});

  void clearDate() => state = state.copyWith(date: DateFilter.any, from: () => null, to: () => null);

  void resetSortAndFilters() => state = state.resetSortAndFilters();
}

/// Documents the Library shows after search, filters and sort.
final filteredDocumentsProvider = Provider<List<SavedDocument>>(
  (ref) => ref.watch(libraryQueryProvider).apply(ref.watch(visibleDocumentsProvider), DateTime.now()),
);
