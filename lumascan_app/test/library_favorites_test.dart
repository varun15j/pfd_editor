import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/library_query.dart';
import 'package:lumascan/features/library/document_tile.dart';
import 'package:lumascan/ui/luma_icons.dart';

import 'support/memory_stores.dart';
import 'support/pump_app.dart';

SavedDocument doc(String id, String name, {int day = 7, bool favorite = false}) => SavedDocument(
  id: id,
  name: name,
  pdfPath: '/nowhere/exports/$name.pdf',
  pageCount: 3,
  type: ScanType.document,
  createdAt: DateTime(2026, 3, day),
  modifiedAt: DateTime(2026, 3, day),
  favorite: favorite,
);

/// Tax form is the oldest, so without favorites it is listed last.
LibraryIndex threeDocs({bool taxFavorite = false}) => const LibraryIndex().copyWith(
  documents: [
    doc('a', 'Lease', day: 9),
    doc('b', 'Receipt', day: 8),
    doc('c', 'Tax form', favorite: taxFavorite),
  ],
);

Future<void> openLibrary(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Search'));
  await tester.pumpAndSettle();
}

List<String> rowNames(WidgetTester tester) => [
  for (final r in tester.widgetList<DocumentRow>(find.byType(DocumentRow))) r.document.name,
];

void main() {
  group('favorites in the index', () {
    test('favorite is saved and read back; old files read as not favorite', () {
      final json = doc('c', 'Tax form', favorite: true).toJson('/root');
      expect(json['favorite'], true);
      expect(SavedDocument.fromJson(json, '/root').favorite, isTrue);
      expect(doc('a', 'Lease').toJson('/root').containsKey('favorite'), isFalse);
      expect(SavedDocument.fromJson(doc('a', 'Lease').toJson('/root'), '/root').favorite, isFalse);
    });

    test('favorites come first, then newest first', () {
      expect([for (final d in threeDocs(taxFavorite: true).documents) d.name], ['Tax form', 'Lease', 'Receipt']);
    });

    test('favorites stay first under every sort', () {
      final docs = [
        doc('a', 'Lease', day: 9),
        doc('b', 'Receipt', day: 8, favorite: true),
        doc('c', 'Tax form', favorite: true),
        doc('d', 'Bill', day: 10),
      ];
      List<String> sorted(LibrarySort s) => [
        for (final d in LibraryQuery(sort: s).apply(docs, DateTime(2026, 3, 20))) d.name,
      ];
      expect(sorted(LibrarySort.newest), ['Receipt', 'Tax form', 'Bill', 'Lease']);
      expect(sorted(LibrarySort.oldest), ['Tax form', 'Receipt', 'Lease', 'Bill']);
      expect(sorted(LibrarySort.nameAz), ['Receipt', 'Tax form', 'Bill', 'Lease']);
      expect(sorted(LibrarySort.nameZa), ['Tax form', 'Receipt', 'Lease', 'Bill']);
    });
  });

  group('heart in Library', () {
    testWidgets('tapping the heart moves the document to the top and saves it', (tester) async {
      final store = MemoryLibraryStore(threeDocs());
      await pumpApp(tester, library: store);
      await openLibrary(tester);
      expect(rowNames(tester), ['Lease', 'Receipt', 'Tax form']);

      await tester.tap(find.byTooltip('Add Tax form to favorites'));
      await tester.pumpAndSettle();
      expect(rowNames(tester), ['Tax form', 'Lease', 'Receipt']);
      expect(store.index.byId('c')!.favorite, isTrue);
      // Favoriting is not an edit, so the date is unchanged.
      expect(store.index.byId('c')!.modifiedAt, DateTime(2026, 3, 7));
      expect(find.text('Tax form added to favorites'), findsOneWidget);
      expect(find.byIcon(LumaIcons.favoriteFilled), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Tax form, favorite, ')), findsOneWidget);

      await tester.tap(find.byTooltip('Remove Tax form from favorites'));
      await tester.pumpAndSettle();
      expect(rowNames(tester), ['Lease', 'Receipt', 'Tax form']);
      expect(store.index.byId('c')!.favorite, isFalse);
    });

    testWidgets('grid cards have the heart too', (tester) async {
      final store = MemoryLibraryStore(threeDocs());
      await pumpApp(tester, library: store);
      await openLibrary(tester);
      await tester.tap(find.byTooltip('Show as grid'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add Receipt to favorites'));
      await tester.pumpAndSettle();
      expect(store.index.byId('b')!.favorite, isTrue);
      final cards = tester.widgetList<DocumentGridCard>(find.byType(DocumentGridCard));
      expect(cards.first.document.name, 'Receipt');
    });
  });

  group('favorites cannot be deleted', () {
    testWidgets('Delete is disabled in the menu of a favorite', (tester) async {
      final store = MemoryLibraryStore(threeDocs(taxFavorite: true));
      await pumpApp(tester, library: store);
      await openLibrary(tester);
      await tester.tap(find.byTooltip('More for Tax form'));
      await tester.pumpAndSettle();
      expect(find.text('Remove from favorites to delete'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(store.index.documents, hasLength(3));
    });

    testWidgets('a selection deletes the others and keeps favorites', (tester) async {
      final store = MemoryLibraryStore(threeDocs(taxFavorite: true));
      await pumpApp(tester, library: store);
      await openLibrary(tester);
      await tester.longPress(find.text('Lease').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete selected'));
      await tester.pumpAndSettle();
      expect(find.text('2 documents deleted. 1 favorite kept'), findsOneWidget);
      expect(rowNames(tester), ['Tax form']);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect([for (final d in store.index.documents) d.name], ['Tax form']);
    });

    testWidgets('only favorites selected: nothing is deleted and the hint says why', (tester) async {
      final store = MemoryLibraryStore(threeDocs(taxFavorite: true));
      await pumpApp(tester, library: store);
      await openLibrary(tester);
      await tester.longPress(find.text('Tax form').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete selected'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Favorites can't be deleted"), findsOneWidget);
      expect(rowNames(tester), hasLength(3));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(store.index.documents, hasLength(3));
    });

    testWidgets('a selection can be added to favorites and removed again', (tester) async {
      final store = MemoryLibraryStore(threeDocs());
      await pumpApp(tester, library: store);
      await openLibrary(tester);
      await tester.longPress(find.text('Lease').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receipt').last);
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to favorites'));
      await tester.pumpAndSettle();
      expect([for (final d in store.index.documents) d.favorite], [true, true, false]);

      await tester.longPress(find.text('Lease').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receipt').last);
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from favorites'));
      await tester.pumpAndSettle();
      expect(store.index.documents.where((d) => d.favorite), isEmpty);
    });
  });

  group('heart on Home', () {
    testWidgets('favorites lead the list and the gallery', (tester) async {
      final store = MemoryLibraryStore(threeDocs());
      await pumpApp(tester, library: store);
      final firstPdf = find.bySemanticsLabel(RegExp(r' · PDF$')).first;
      expect(tester.getSemantics(firstPdf).label, startsWith('Lease'));

      await tester.tap(find.byTooltip('Add Tax form to favorites'));
      await tester.pumpAndSettle();
      expect(store.index.byId('c')!.favorite, isTrue);
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp(r' · PDF$')).first).label,
        startsWith('Tax form, favorite'),
      );

      await tester.tap(find.byTooltip('Show as gallery'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove Tax form from favorites'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp(r' · PDF$')).first).label,
        startsWith('Tax form, favorite'),
      );
    });
  });
}
