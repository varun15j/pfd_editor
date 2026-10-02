import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/data/ui_prefs_store.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/ui_prefs.dart';
import 'package:lumascan/features/library/document_tile.dart';
import 'package:path/path.dart' as path;

import 'support/memory_stores.dart';
import 'support/pump_app.dart';

SavedDocument doc(String id, String name, {int day = 7}) => SavedDocument(
  id: id,
  name: name,
  pdfPath: '/nowhere/exports/$name.pdf',
  pageCount: 3,
  type: ScanType.document,
  createdAt: DateTime(2026, 3, day),
  modifiedAt: DateTime(2026, 3, day),
);

LibraryIndex threeDocs() => const LibraryIndex().copyWith(
  documents: [doc('a', 'Lease', day: 9), doc('b', 'Receipt', day: 8), doc('c', 'Tax form')],
);

Future<void> openLibrary(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Library'));
  await tester.pumpAndSettle();
}

Future<void> menu(WidgetTester tester, String name, String action) async {
  await tester.tap(find.byTooltip('More for $name'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

void main() {
  group('library list and grid', () {
    testWidgets('rows show thumbnail, name, time, pages and on-device status', (tester) async {
      await pumpApp(tester, library: MemoryLibraryStore(threeDocs()));
      await openLibrary(tester);
      expect(find.byType(DocumentRow), findsNWidgets(3));
      expect(find.text('Lease'), findsWidgets);
      expect(find.text('9 Mar 2026 · 3 pages'), findsOneWidget);
      expect(find.text('On device'), findsNWidgets(3));
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsWidgets);
      expect(find.bySemanticsLabel(RegExp(r'^Lease, 9 Mar 2026, 3 pages, on device')), findsOneWidget);
    });

    testWidgets('grid choice is remembered after a restart', (tester) async {
      final prefs = MemoryUiPrefsStore();
      await pumpApp(tester, library: MemoryLibraryStore(threeDocs()), prefs: prefs);
      await openLibrary(tester);
      await tester.tap(find.byTooltip('Show as grid'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentGridCard), findsNWidgets(3));
      expect(prefs.prefs.libraryView, LibraryView.grid);

      // A new app run reads the stored choice.
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, library: MemoryLibraryStore(threeDocs()), prefs: prefs);
      await openLibrary(tester);
      expect(find.byType(DocumentGridCard), findsNWidgets(3));
      await tester.tap(find.byTooltip('Show as list'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentRow), findsNWidgets(3));
      expect(prefs.prefs.libraryView, LibraryView.list);
    });

    testWidgets('grid fits at 200% text size', (tester) async {
      await pumpApp(
        tester,
        textScale: 2,
        library: MemoryLibraryStore(threeDocs()),
        prefs: MemoryUiPrefsStore(const UiPrefs(libraryView: LibraryView.grid)),
      );
      await openLibrary(tester);
      expect(find.byType(DocumentGridCard), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('view toggle is off while the library is empty', (tester) async {
      await pumpApp(tester);
      await openLibrary(tester);
      final button = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.grid_view_outlined));
      expect(button.onPressed, isNull);
    });
  });

  group('selection', () {
    testWidgets('long press selects; tap adds more; select all and cancel', (tester) async {
      await pumpApp(tester, library: MemoryLibraryStore(threeDocs()));
      await openLibrary(tester);
      await tester.longPress(find.text('Lease').last);
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(3));
      expect(find.byTooltip('More for Lease'), findsNothing);

      await tester.tap(find.text('Receipt').last);
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Cancel selection'));
      await tester.pumpAndSettle();
      expect(find.text('Library'), findsWidgets);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('system back leaves selection instead of the app', (tester) async {
      await pumpApp(tester, library: MemoryLibraryStore(threeDocs()));
      await openLibrary(tester);
      await tester.longPress(find.text('Lease').last);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsNothing);
      expect(find.byType(DocumentRow), findsNWidgets(3));
    });

    testWidgets('deleting a selection can be undone', (tester) async {
      final store = MemoryLibraryStore(threeDocs());
      await pumpApp(tester, library: store);
      await openLibrary(tester);
      await tester.longPress(find.text('Lease').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receipt').last);
      await tester.tap(find.byTooltip('Delete selected'));
      await tester.pumpAndSettle();
      expect(find.text('2 documents deleted'), findsOneWidget);
      expect(find.byType(DocumentRow), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentRow), findsNWidgets(3));
      expect(store.index.documents, hasLength(3));
    });
  });

  group('row menu', () {
    testWidgets('delete hides the document at once and removes it when the undo time ends', (tester) async {
      final store = MemoryLibraryStore(threeDocs());
      await pumpApp(tester, library: store);
      await openLibrary(tester);
      await menu(tester, 'Receipt', 'Delete');
      expect(find.text('Receipt deleted'), findsOneWidget);
      expect(find.text('Receipt'), findsNothing);
      // Nothing is deleted while Undo is still offered.
      expect(store.index.documents, hasLength(3));

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Receipt deleted'), findsNothing);
      expect([for (final d in store.index.documents) d.name], ['Lease', 'Tax form']);
    });

    testWidgets('deleted documents also leave Home', (tester) async {
      await pumpApp(tester, library: MemoryLibraryStore(threeDocs()));
      expect(find.byType(RecentDocumentCard), findsNWidgets(3));
      await openLibrary(tester);
      await menu(tester, 'Lease', 'Delete');
      await tester.tap(find.bySemanticsLabel('Home'));
      await tester.pumpAndSettle();
      expect(find.byType(RecentDocumentCard), findsNWidgets(2));
    });

    testWidgets('rename asks for a name and rejects an empty one', (tester) async {
      await pumpApp(tester, library: MemoryLibraryStore(threeDocs()));
      await openLibrary(tester);
      await menu(tester, 'Lease', 'Rename');
      expect(find.text('Rename'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Lease'), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('menu items are at least 48 dp tall', (tester) async {
      await pumpApp(tester, library: MemoryLibraryStore(threeDocs()));
      await openLibrary(tester);
      expect(tester.getSize(find.byTooltip('More for Lease')).height, greaterThanOrEqualTo(48));
    });
  });

  group('home', () {
    testWidgets('recent documents show as cards', (tester) async {
      await pumpApp(tester, library: MemoryLibraryStore(threeDocs()));
      expect(find.byType(RecentDocumentCard), findsNWidgets(3));
      expect(find.text('Your scans will show up here.'), findsNothing);
      expect(find.bySemanticsLabel('Lease, 9 Mar 2026'), findsOneWidget);
    });

    testWidgets('the photos card can be dismissed for good', (tester) async {
      final prefs = MemoryUiPrefsStore();
      await pumpApp(tester, prefs: prefs);
      expect(find.text('Turn photos into a PDF'), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss Turn photos into a PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Turn photos into a PDF'), findsNothing);
      expect(prefs.prefs.dismissedCards, {'photos_to_pdf'});

      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, prefs: prefs);
      expect(find.text('Turn photos into a PDF'), findsNothing);
    });

    testWidgets('home fits at 200% text with recent cards', (tester) async {
      await pumpApp(tester, textScale: 2, library: MemoryLibraryStore(threeDocs()));
      expect(tester.takeException(), isNull);
    });
  });

  group('stored UI choices', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('lumascan_prefs'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('choices survive a restart and a damaged file falls back to defaults', () async {
      ProviderContainer launch() =>
          ProviderContainer(overrides: [pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp))]);
      final first = launch();
      final prefs = first.read(uiPrefsProvider.notifier);
      await prefs.settled;
      prefs
        ..setLibraryView(LibraryView.grid)
        ..dismissCard('photos_to_pdf');
      await prefs.settled;
      first.dispose();

      final file = File(path.join(tmp.path, UiPrefsStore.prefsFile));
      expect(jsonDecode(file.readAsStringSync()), {
        'libraryView': 'grid',
        'dismissedCards': ['photos_to_pdf'],
      });

      final second = launch();
      await second.read(uiPrefsProvider.notifier).settled;
      expect(second.read(uiPrefsProvider).libraryView, LibraryView.grid);
      expect(second.read(uiPrefsProvider).dismissedCards, {'photos_to_pdf'});
      second.dispose();

      file.writeAsStringSync('nonsense');
      final third = launch();
      await third.read(uiPrefsProvider.notifier).settled;
      expect(third.read(uiPrefsProvider).libraryView, LibraryView.list);
      third.dispose();
    });
  });
}
