import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/library_query.dart';
import 'package:lumascan/features/library/document_tile.dart';
import 'package:lumascan/features/library/library_controller.dart';

import 'support/memory_stores.dart';
import 'support/pump_app.dart';

final when = DateTime(2026, 9, 1);

SavedDocument doc(String id, String name, {String? folderId, List<String> tags = const []}) => SavedDocument(
  id: id,
  name: name,
  pdfPath: '/nowhere/$name.pdf',
  pageCount: 1,
  type: ScanType.document,
  createdAt: when,
  modifiedAt: when,
  folderId: folderId,
  tags: tags,
);

LibraryIndex sample() => const LibraryIndex().copyWith(
  folders: const [LibraryFolder(id: 'f1', name: 'Bills')],
  tags: const ['travel'],
  documents: [
    doc('a', 'Electricity', folderId: 'f1', tags: ['tax']),
    doc('b', 'Water', folderId: 'f1', tags: ['Tax', '2026']),
    doc('c', 'Passport', tags: ['travel']),
  ],
);

List<String> shownNames(WidgetTester tester) => [
  for (final row in tester.widgetList<DocumentRow>(find.byType(DocumentRow))) row.document.name,
];

Future<MemoryLibraryStore> openLibrary(WidgetTester tester, [LibraryIndex? index]) async {
  final store = MemoryLibraryStore(index ?? sample());
  await pumpApp(tester, library: store);
  await tester.tap(find.bySemanticsLabel('Library'));
  await tester.pumpAndSettle();
  return store;
}

Finder dialogField() => find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));

void main() {
  group('name checks', () {
    test('empty, too long, bad characters and duplicates are rejected', () {
      expect(validateLabelName('  ', const []), 'Enter a name');
      expect(validateLabelName('x' * 41, const []), 'Use 40 characters or fewer');
      expect(validateLabelName('a/b', const []), "Names can't contain /");
      expect(validateLabelName('Bills?', const []), "Names can't contain ?");
      expect(validateLabelName(' bills ', const ['Bills']), 'That name is already used');
      expect(validateLabelName('Bills', const ['Bills'], current: 'Bills'), isNull);
      expect(validateLabelName('Home 2026', const ['Bills']), isNull);
    });

    test('all tags merges the tag list and document tags, ignoring case', () {
      expect(sample().allTags, ['2026', 'tax', 'travel']);
    });

    test('query narrows to a folder and to documents carrying every chosen tag', () {
      final docs = sample().documents;
      List<String> names(LibraryQuery q) => [for (final d in q.apply(docs, when)) d.name];
      expect(names(const LibraryQuery(folderId: 'f1')), unorderedEquals(['Electricity', 'Water']));
      expect(names(const LibraryQuery(tags: {'tax'})), unorderedEquals(['Electricity', 'Water']));
      expect(names(const LibraryQuery(tags: {'tax', '2026'})), ['Water']);
      expect(const LibraryQuery(folderId: 'f1', text: 'x').resetSortAndFilters().folderId, 'f1');
    });
  });

  group('controller', () {
    late MemoryLibraryStore store;
    late ProviderContainer c;
    LibraryController lib() => c.read(libraryProvider.notifier);
    SavedDocument byId(String id) => c.read(savedDocumentProvider(id))!;

    setUp(() async {
      store = MemoryLibraryStore(sample());
      c = ProviderContainer(overrides: [libraryStoreProvider.overrideWithValue(store)]);
      await c.read(libraryProvider.future);
    });
    tearDown(() => c.dispose());

    test('moving and tagging keep dates and are saved', () async {
      await lib().moveManyToFolder(['c'], 'f1');
      await lib().updateTags(['a', 'c'], add: {'Home'}, remove: {'TAX'});
      expect(byId('c').folderId, 'f1');
      expect(byId('a').tags, ['Home']);
      expect(byId('c').tags, ['travel', 'Home']);
      expect(byId('a').modifiedAt, when);
      expect(store.index.byId('c')!.tags, ['travel', 'Home']);
      expect(store.index.allTags, contains('Home'));
    });

    test('adding a tag that exists in another case reuses it', () async {
      await lib().updateTags(['c'], add: {'TAX'});
      expect(c.read(libraryProvider).value!.allTags.where((t) => t.toLowerCase() == 'tax'), hasLength(1));
    });

    test('renaming a tag changes it on every document', () async {
      await lib().renameTag('tax', 'Taxes');
      expect(byId('a').tags, ['Taxes']);
      expect(byId('b').tags, ['Taxes', '2026']);
    });

    test('deleting a tag or folder never deletes documents', () async {
      await lib().deleteTag('tax');
      await lib().deleteFolder('f1');
      final index = c.read(libraryProvider).value!;
      expect(index.documents, hasLength(3));
      expect(index.allTags, ['2026', 'travel']);
      expect(index.folders, isEmpty);
      expect(byId('a').folderId, isNull);
    });

    test('tag list survives a save and reload', () {
      final back = LibraryIndex.fromJson(sample().toJson('/r'), '/r');
      expect(back.tags, ['travel']);
    });
  });

  group('library screen', () {
    testWidgets('folder chips browse one folder; rows show folder and tags', (tester) async {
      await openLibrary(tester);
      expect(find.text('Bills · tax'), findsOneWidget);
      expect(find.text('travel'), findsWidgets);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Bills'));
      await tester.pumpAndSettle();
      expect(shownNames(tester), unorderedEquals(['Electricity', 'Water']));
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      expect(shownNames(tester), hasLength(3));
    });

    testWidgets('new folder checks the name as you type', (tester) async {
      await openLibrary(tester);
      await tester.tap(find.widgetWithText(ActionChip, 'New folder'));
      await tester.pumpAndSettle();
      await tester.enterText(dialogField(), 'bills');
      await tester.pump();
      expect(find.text('That name is already used'), findsOneWidget);
      await tester.enterText(dialogField(), 'Home/Rent');
      await tester.pump();
      expect(find.text("Names can't contain /"), findsOneWidget);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(dialogField(), 'Home');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, 'Home'), findsOneWidget);
      expect(find.text('Home is empty'), findsOneWidget);
    });

    testWidgets('move a document to a folder from its menu', (tester) async {
      final store = await openLibrary(tester);
      await tester.tap(find.byTooltip('More for Passport'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(RadioListTile<String>, 'Bills'));
      await tester.pumpAndSettle();
      expect(find.text('Moved to Bills'), findsOneWidget);
      expect(store.index.byId('c')!.folderId, 'f1');
      expect(find.text('Bills · travel'), findsOneWidget);
    });

    testWidgets('tag several documents at once, keeping mixed tags as they are', (tester) async {
      final store = await openLibrary(tester);
      await tester.longPress(find.text('Electricity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Water'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tags'));
      await tester.pumpAndSettle();
      // "2026" is on only one of the two.
      expect(find.text('On some selected documents'), findsOneWidget);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'travel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(store.index.byId('a')!.tags, ['tax', 'travel']);
      expect(store.index.byId('b')!.tags, ['Tax', '2026', 'travel']);
    });

    testWidgets('filter by tag', (tester) async {
      await openLibrary(tester);
      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();
      expect(shownNames(tester), ['Water']);
      expect(find.widgetWithText(InputChip, '2026'), findsOneWidget);
    });

    testWidgets('deleting a folder asks first and keeps its documents', (tester) async {
      final store = await openLibrary(tester);
      await tester.tap(find.byTooltip('Folders and tags'));
      await tester.pumpAndSettle();
      expect(find.text('2 documents'), findsWidgets);
      await tester.tap(find.byTooltip('More for Bills'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete folder "Bills"?'), findsOneWidget);
      expect(find.textContaining('No documents are deleted'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(store.index.folders, isEmpty);
      expect(store.index.documents, hasLength(3));
    });

    testWidgets('renaming a tag from the manage screen', (tester) async {
      final store = await openLibrary(tester);
      await tester.tap(find.byTooltip('Folders and tags'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More for tax'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(dialogField(), 'travel');
      await tester.pump();
      expect(find.text('That name is already used'), findsOneWidget);
      await tester.enterText(dialogField(), 'Taxes');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.index.byId('a')!.tags, ['Taxes']);
      expect(store.index.byId('b')!.tags, ['Taxes', '2026']);
    });

    testWidgets('folders and tags screens fit at 200% text', (tester) async {
      await pumpApp(tester, textScale: 2, library: MemoryLibraryStore(sample()));
      await tester.tap(find.bySemanticsLabel('Library'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Folders and tags'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
