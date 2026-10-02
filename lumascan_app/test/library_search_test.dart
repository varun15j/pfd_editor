import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/library_query.dart';
import 'package:lumascan/features/library/document_tile.dart';

import 'support/memory_stores.dart';
import 'support/pump_app.dart';

final now = DateTime.now();
DateTime daysAgo(int n) => now.subtract(Duration(days: n));

SavedDocument doc(String id, String name, DateTime modified, {ScanType type = ScanType.document}) => SavedDocument(
  id: id,
  name: name,
  pdfPath: '/nowhere/$name.pdf',
  pageCount: 1,
  type: type,
  createdAt: modified,
  modifiedAt: modified,
);

final docs = [
  doc('a', 'Lease agreement', daysAgo(1)),
  doc('b', 'electricity bill', daysAgo(3)),
  doc('c', 'Signed lease', daysAgo(12), type: ScanType.pdf),
  doc('d', 'Passport', daysAgo(45), type: ScanType.idCard),
];

List<String> names(List<SavedDocument> list) => [for (final d in list) d.name];

Future<void> openLibrary(WidgetTester tester) async {
  await pumpApp(tester, library: MemoryLibraryStore(const LibraryIndex().copyWith(documents: docs)));
  await tester.tap(find.bySemanticsLabel('Library'));
  await tester.pumpAndSettle();
}

List<String> shownNames(WidgetTester tester) => [
  for (final row in tester.widgetList<DocumentRow>(find.byType(DocumentRow))) row.document.name,
];

void main() {
  group('query rules', () {
    test('search matches any part of the name, ignoring case and spaces around it', () {
      expect(names(const LibraryQuery(text: '  LEASE ').apply(docs, now)), ['Lease agreement', 'Signed lease']);
      expect(const LibraryQuery(text: 'zzz').apply(docs, now), isEmpty);
    });

    test('sorts by date or name in either direction', () {
      List<String> sorted(LibrarySort s) => names(LibraryQuery(sort: s).apply(docs, now));
      expect(sorted(LibrarySort.newest), ['Lease agreement', 'electricity bill', 'Signed lease', 'Passport']);
      expect(sorted(LibrarySort.oldest), ['Passport', 'Signed lease', 'electricity bill', 'Lease agreement']);
      expect(sorted(LibrarySort.nameAz), ['electricity bill', 'Lease agreement', 'Passport', 'Signed lease']);
      expect(sorted(LibrarySort.nameZa), ['Signed lease', 'Passport', 'Lease agreement', 'electricity bill']);
    });

    test('filters by type and by relative date', () {
      expect(names(const LibraryQuery(types: {ScanType.pdf, ScanType.idCard}).apply(docs, now)), [
        'Signed lease',
        'Passport',
      ]);
      expect(names(const LibraryQuery(date: DateFilter.last7Days).apply(docs, now)), [
        'Lease agreement',
        'electricity bill',
      ]);
      expect(names(const LibraryQuery(date: DateFilter.last30Days).apply(docs, now)), hasLength(3));
    });

    test('custom range includes both end days', () {
      final day = daysAgo(12);
      final q = LibraryQuery(
        date: DateFilter.custom,
        from: DateTime(day.year, day.month, day.day),
        to: DateTime(day.year, day.month, day.day),
      );
      expect(names(q.apply(docs, now)), ['Signed lease']);
    });

    test('custom range rejects From later than To', () {
      expect(LibraryQuery.rangeError(DateTime(2026, 5, 2), DateTime(2026, 5, 1)), 'From must be on or before To');
      expect(LibraryQuery.rangeError(DateTime(2026, 5, 1), DateTime(2026, 5, 1)), isNull);
      expect(LibraryQuery.rangeError(null, DateTime(2026, 5, 1)), 'Pick both dates');
    });

    test('reset keeps the search text', () {
      const q = LibraryQuery(text: 'bill', sort: LibrarySort.nameAz, types: {ScanType.pdf});
      expect(q.resetSortAndFilters().text, 'bill');
      expect(q.resetSortAndFilters().isSorted || q.resetSortAndFilters().isFiltered, isFalse);
    });
  });

  group('library screen', () {
    testWidgets('search filters as you type and clears in one tap', (tester) async {
      await openLibrary(tester);
      await tester.enterText(find.byType(TextField), 'lea');
      await tester.pumpAndSettle();
      expect(shownNames(tester), ['Lease agreement', 'Signed lease']);

      await tester.enterText(find.byType(TextField), 'lease a');
      await tester.pumpAndSettle();
      expect(shownNames(tester), ['Lease agreement']);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(shownNames(tester), hasLength(4));
      expect(find.byTooltip('Clear search'), findsNothing);
    });

    testWidgets('no matches offers a way back to everything', (tester) async {
      await openLibrary(tester);
      await tester.enterText(find.byType(TextField), 'nothing like this');
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);
      await tester.tap(find.text('Show all documents'));
      await tester.pumpAndSettle();
      expect(shownNames(tester), hasLength(4));
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('sort sheet marks the active choice and shows it as a chip', (tester) async {
      await openLibrary(tester);
      await tester.tap(find.byTooltip('Sort: Newest first'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.tap(find.text('Name A to Z'));
      await tester.pumpAndSettle();
      expect(shownNames(tester), ['electricity bill', 'Lease agreement', 'Passport', 'Signed lease']);
      expect(find.widgetWithText(InputChip, 'Name A to Z'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove sort'));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
      expect(shownNames(tester).first, 'Lease agreement');
    });

    testWidgets('filter by type and date, then reset', (tester) async {
      await openLibrary(tester);
      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'PDF'));
      await tester.tap(find.widgetWithText(FilterChip, 'Document'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Last 7 days'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();
      expect(shownNames(tester), ['Lease agreement', 'electricity bill']);
      expect(find.widgetWithText(InputChip, 'Document, PDF'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Last 7 days'), findsOneWidget);
      expect(find.byTooltip('Filter, 2 active'), findsOneWidget);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(shownNames(tester), hasLength(4));
      expect(find.byTooltip('Filter'), findsOneWidget);
    });

    testWidgets('custom range asks for both dates before it can apply', (tester) async {
      await openLibrary(tester);
      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Custom'));
      await tester.pumpAndSettle();
      expect(find.text('Pick both dates'), findsOneWidget);
      final apply = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Show results'));
      expect(apply.onPressed, isNull);
    });

    testWidgets('search and filters survive switching tabs', (tester) async {
      await openLibrary(tester);
      await tester.enterText(find.byType(TextField), 'bill');
      await tester.tap(find.byTooltip('Sort: Newest first'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oldest first'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Library'));
      await tester.pumpAndSettle();
      expect(shownNames(tester), ['electricity bill']);
      expect(find.widgetWithText(InputChip, 'Oldest first'), findsOneWidget);
      expect(find.text('bill'), findsOneWidget);
    });

    testWidgets('select all only takes the documents that are shown', (tester) async {
      await openLibrary(tester);
      await tester.enterText(find.byType(TextField), 'lease');
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Signed lease'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('search, sort and filter fit at 200% text', (tester) async {
      await pumpApp(tester, textScale: 2, library: MemoryLibraryStore(const LibraryIndex().copyWith(documents: docs)));
      await tester.tap(find.bySemanticsLabel('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Custom'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
