import 'package:flutter/foundation.dart';

import 'library.dart';

enum LibrarySort {
  newest('Newest first'),
  oldest('Oldest first'),
  nameAz('Name A to Z'),
  nameZa('Name Z to A');

  const LibrarySort(this.label);
  final String label;
}

enum DateFilter {
  any('Any time'),
  last7Days('Last 7 days'),
  last30Days('Last 30 days'),
  custom('Custom');

  const DateFilter(this.label);
  final String label;
}

/// Search, sort and filter for the Library (US-02.2, US-02.4). Search
/// matches file names only until OCR exists.
@immutable
class LibraryQuery {
  const LibraryQuery({
    this.text = '',
    this.sort = LibrarySort.newest,
    this.types = const {},
    this.date = DateFilter.any,
    this.from,
    this.to,
  });

  final String text;
  final LibrarySort sort;

  /// Empty means every type.
  final Set<ScanType> types;
  final DateFilter date;

  /// Inclusive calendar days for [DateFilter.custom].
  final DateTime? from;
  final DateTime? to;

  bool get isSearching => text.trim().isNotEmpty;
  bool get isSorted => sort != LibrarySort.newest;
  bool get isFiltered => types.isNotEmpty || date != DateFilter.any;

  /// True when anything differs from the default view.
  bool get isActive => isSearching || isSorted || isFiltered;

  LibraryQuery copyWith({
    String? text,
    LibrarySort? sort,
    Set<ScanType>? types,
    DateFilter? date,
    DateTime? Function()? from,
    DateTime? Function()? to,
  }) => LibraryQuery(
    text: text ?? this.text,
    sort: sort ?? this.sort,
    types: types ?? this.types,
    date: date ?? this.date,
    from: from == null ? this.from : from(),
    to: to == null ? this.to : to(),
  );

  /// Clears sort and filters but keeps the search text.
  LibraryQuery resetSortAndFilters() => LibraryQuery(text: text);

  /// Null when the custom range is usable, otherwise what is wrong with it.
  static String? rangeError(DateTime? from, DateTime? to) {
    if (from == null || to == null) return 'Pick both dates';
    if (_day(from).isAfter(_day(to))) return 'From must be on or before To';
    return null;
  }

  /// Short label for the active date filter, for its chip.
  String get dateLabel {
    if (date != DateFilter.custom) return date.label;
    String f(DateTime? d) => d == null ? '?' : '${d.day} ${_months[d.month - 1]}';
    return '${f(from)} to ${f(to)}';
  }

  List<SavedDocument> apply(List<SavedDocument> docs, DateTime now) {
    final needle = text.trim().toLowerCase();
    final today = _day(now);
    final DateTime? start = switch (date) {
      DateFilter.any => null,
      DateFilter.last7Days => today.subtract(const Duration(days: 6)),
      DateFilter.last30Days => today.subtract(const Duration(days: 29)),
      DateFilter.custom => from == null ? null : _day(from!),
    };
    // Exclusive end: the day after the last day included.
    final DateTime? end = date == DateFilter.custom && to != null ? _day(to!).add(const Duration(days: 1)) : null;

    final out = [
      for (final d in docs)
        if ((needle.isEmpty || d.name.toLowerCase().contains(needle)) &&
            (types.isEmpty || types.contains(d.type)) &&
            (start == null || !d.modifiedAt.isBefore(start)) &&
            (end == null || d.modifiedAt.isBefore(end)))
          d,
    ];
    int byName(SavedDocument a, SavedDocument b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    out.sort(switch (sort) {
      LibrarySort.newest => (a, b) => b.modifiedAt.compareTo(a.modifiedAt),
      LibrarySort.oldest => (a, b) => a.modifiedAt.compareTo(b.modifiedAt),
      LibrarySort.nameAz => byName,
      LibrarySort.nameZa => (a, b) => byName(b, a),
    });
    return out;
  }

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
}
