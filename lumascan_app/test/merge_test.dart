import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/app/theme.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/export/pdf_merger.dart';
import 'package:lumascan/features/merge/merge_controller.dart';
import 'package:lumascan/features/merge/merge_screen.dart';
import 'package:lumascan/features/merge/pdf_inspector.dart';
import 'package:lumascan/features/merge/pdf_picker.dart';
import 'package:lumascan/features/share/pdf_sharer.dart';
import 'package:lumascan/features/tools/tools_screen.dart';
import 'package:lumascan/pdf_edit/pdf_edit_controller.dart';
import 'package:lumascan/pdf_edit/pdf_saver.dart';

import 'support/memory_stores.dart';

/// Reports a page count (or a problem) for each path, and counts the checks.
class _FakeInspector implements PdfInspector {
  _FakeInspector(this.infos);
  final Map<String, PdfInfo> infos;
  final checked = <String>[];

  @override
  Future<PdfInfo> inspect(String path) async {
    checked.add(path);
    return infos[path] ?? const PdfInfo.problem(PdfProblem.unreadable);
  }
}

class _FakePicker implements PdfPicker {
  _FakePicker([this.files = const []]);
  List<PickedPdf> files;
  Object? failure;

  @override
  Future<List<PickedPdf>> pick() async {
    if (failure != null) throw failure!;
    return files;
  }
}

/// Renders every page of a file as a small flat image whose point size is
/// taken from [sizes] by file name, so the order and size of merged pages can
/// be read back from the output.
class _FakeRasterizer implements PdfRasterizer {
  _FakeRasterizer(this.sizes);
  final Map<String, (double, double)> sizes;
  final opened = <String>[];
  Object? failure;

  @override
  Stream<RasterPage> renderPages(
    String path,
    List<int> pageNumbers, {
    required int longEdge,
    required int jpegQuality,
    String? password,
  }) async* {
    if (failure != null) throw failure!;
    opened.add(path);
    final (w, h) = sizes[path.split('/').last] ?? (612.0, 792.0);
    for (final _ in pageNumbers) {
      yield RasterPage(
        Uint8List.fromList(img.encodeJpg(img.Image(width: 30, height: 40)..clear(img.ColorRgb8(200, 200, 200)))),
        30,
        40,
        widthPt: w,
        heightPt: h,
      );
    }
  }
}

class _FakeSharer implements PdfSharer {
  final sent = <String>[];

  @override
  Future<SendOutcome> send(String path, {Rect? origin}) async {
    sent.add(path);
    return SendOutcome.sent;
  }
}

SavedDocument _doc(String id, String name, String path, int pages) => SavedDocument(
  id: id,
  name: name,
  pdfPath: path,
  pageCount: pages,
  type: ScanType.document,
  createdAt: DateTime(2026),
  modifiedAt: DateTime(2026, 1, int.parse(id.replaceAll(RegExp(r'\D'), '').padLeft(1, '0'))),
);

void main() {
  late Directory tmp;
  var ready = false;

  void makeTmp() {
    tmp = Directory.systemTemp.createTempSync('lumascan_merge');
    ready = true;
  }

  tearDown(() {
    if (!ready) return;
    ready = false;
    tmp.deleteSync(recursive: true);
  });

  File source(String name, [int bytes = 100]) => File('${tmp.path}/$name')..writeAsBytesSync(List.filled(bytes, 9));

  List<String> mediaBoxes(File pdf) => [
    for (final m in RegExp(r'/MediaBox\[0 0 (\d+) (\d+)\]').allMatches(String.fromCharCodes(pdf.readAsBytesSync())))
      '${m[1]}x${m[2]}',
  ];

  group('PdfMerger', () {
    late PageStore store;
    late _FakeRasterizer rasterizer;
    late PdfMerger merger;

    void setUpMerger() {
      makeTmp();
      store = PageStore(rootDir: () async => tmp);
      rasterizer = _FakeRasterizer({'a.pdf': (612, 792), 'b.pdf': (842, 595), 'c.pdf': (400, 400)});
      merger = PdfMerger(store, rasterizer);
    }

    test('joins the PDFs in the order given, each page at its own size', () async {
      setUpMerger();
      final a = source('a.pdf'), b = source('b.pdf'), c = source('c.pdf');
      final out = await merger.merge([
        MergeInput(path: b.path, pageCount: 2),
        MergeInput(path: c.path, pageCount: 1),
        MergeInput(path: a.path, pageCount: 3),
      ], fileName: 'All');
      expect(out.path, endsWith('All.pdf'));
      expect(String.fromCharCodes(out.readAsBytesSync().sublist(0, 4)), '%PDF');
      expect(mediaBoxes(out), ['842x595', '842x595', '400x400', '612x792', '612x792', '612x792']);
      expect(rasterizer.opened, [b.path, c.path, a.path]);
    });

    test('never changes the PDFs it reads', () async {
      setUpMerger();
      final a = source('a.pdf', 50), b = source('b.pdf', 70);
      final before = [a.readAsBytesSync(), b.readAsBytesSync()];
      await merger.merge([
        MergeInput(path: a.path, pageCount: 1),
        MergeInput(path: b.path, pageCount: 1),
      ], fileName: 'x');
      expect(a.readAsBytesSync(), before[0]);
      expect(b.readAsBytesSync(), before[1]);
    });

    test('a name that is taken gets a number instead of replacing the file', () async {
      setUpMerger();
      final a = source('a.pdf');
      final existing = await store.writeExportAtomically('Merged.pdf', [1, 2, 3]);
      final out = await merger.merge([MergeInput(path: a.path, pageCount: 1)], fileName: 'Merged');
      expect(out.path, endsWith('Merged (2).pdf'));
      expect(existing.readAsBytesSync(), [1, 2, 3]);
    });

    test('reports progress up to the full total', () async {
      setUpMerger();
      final a = source('a.pdf');
      final steps = <(int, int)>[];
      await merger.merge(
        [MergeInput(path: a.path, pageCount: 2), MergeInput(path: a.path, pageCount: 1)],
        fileName: 'x',
        onProgress: (done, total) => steps.add((done, total)),
      );
      expect(steps.first, (1, 4));
      expect(steps.last, (4, 4));
    });

    test('a source that cannot be rendered fails the merge and leaves no file', () async {
      setUpMerger();
      final a = source('a.pdf');
      rasterizer.failure = StateError('damaged');
      await expectLater(
        merger.merge([MergeInput(path: a.path, pageCount: 1)], fileName: 'x'),
        throwsA(isA<StateError>()),
      );
      expect(Directory('${tmp.path}/exports').existsSync() ? Directory('${tmp.path}/exports').listSync() : [], isEmpty);
    });

    test('nothing to merge is an error', () async {
      setUpMerger();
      await expectLater(merger.merge(const [], fileName: 'x'), throwsArgumentError);
    });
  });

  group('MergeController', () {
    ProviderContainer containerFor(Map<String, PdfInfo> infos) {
      final c = ProviderContainer(overrides: [pdfInspectorProvider.overrideWithValue(_FakeInspector(infos))]);
      addTearDown(c.dispose);
      c.listen(mergeControllerProvider, (_, _) {});
      return c;
    }

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

    test('checks each file once and keeps the order it was added in', () async {
      final c = containerFor({'/a.pdf': const PdfInfo.ok(3), '/b.pdf': const PdfInfo.ok(5)});
      c.read(mergeControllerProvider.notifier).add(const [
        NewMergeSource(name: 'a.pdf', path: '/a.pdf'),
        NewMergeSource(name: 'b.pdf', path: '/b.pdf'),
      ]);
      expect(c.read(mergeControllerProvider).checking, isTrue);
      await settle();
      final state = c.read(mergeControllerProvider);
      expect(state.sources.map((s) => (s.name, s.pages)), [('a.pdf', 3), ('b.pdf', 5)]);
      expect(state.canMerge, isTrue);
      expect(state.totalPages, 8);
    });

    test('flags locked and unreadable files, which blocks merging', () async {
      final c = containerFor({'/a.pdf': const PdfInfo.ok(1), '/locked.pdf': const PdfInfo.problem(PdfProblem.locked)});
      c.read(mergeControllerProvider.notifier).add(const [
        NewMergeSource(name: 'a.pdf', path: '/a.pdf'),
        NewMergeSource(name: 'locked.pdf', path: '/locked.pdf'),
        NewMergeSource(name: 'gone.pdf', path: '/gone.pdf'),
      ]);
      await settle();
      final state = c.read(mergeControllerProvider);
      expect(state.flagged.map((s) => (s.name, s.problem)), [
        ('locked.pdf', PdfProblem.locked),
        ('gone.pdf', PdfProblem.unreadable),
      ]);
      expect(state.canMerge, isFalse);
    });

    test('a file that makes the check throw is flagged, not lost', () async {
      final c = ProviderContainer(overrides: [pdfInspectorProvider.overrideWithValue(_ThrowingInspector())]);
      addTearDown(c.dispose);
      c.listen(mergeControllerProvider, (_, _) {});
      c.read(mergeControllerProvider.notifier).add(const [NewMergeSource(name: 'a.pdf', path: '/a.pdf')]);
      await settle();
      expect(c.read(mergeControllerProvider).flagged.single.problem, PdfProblem.unreadable);
    });

    test('reorder follows the final position, and remove drops one file', () async {
      final c = containerFor({'/a': const PdfInfo.ok(1), '/b': const PdfInfo.ok(1), '/c': const PdfInfo.ok(1)});
      final notifier = c.read(mergeControllerProvider.notifier);
      notifier.add(const [
        NewMergeSource(name: 'a', path: '/a'),
        NewMergeSource(name: 'b', path: '/b'),
        NewMergeSource(name: 'c', path: '/c'),
      ]);
      await settle();
      List<String> names() => c.read(mergeControllerProvider).sources.map((s) => s.name).toList();
      notifier.reorder(0, 2);
      expect(names(), ['b', 'c', 'a']);
      notifier.reorder(2, 0);
      expect(names(), ['a', 'b', 'c']);
      notifier.remove(c.read(mergeControllerProvider).sources[1].key);
      expect(names(), ['a', 'c']);
    });

    test('the same PDF can be added twice', () async {
      final c = containerFor({'/a': const PdfInfo.ok(2)});
      c.read(mergeControllerProvider.notifier).add(const [
        NewMergeSource(name: 'a', path: '/a'),
        NewMergeSource(name: 'a', path: '/a'),
      ]);
      await settle();
      final state = c.read(mergeControllerProvider);
      expect(state.sources.length, 2);
      expect(state.sources.first.key, isNot(state.sources.last.key));
      expect(state.canMerge, isTrue);
    });

    test('one file is not enough to merge', () async {
      final c = containerFor({'/a': const PdfInfo.ok(2)});
      c.read(mergeControllerProvider.notifier).add(const [NewMergeSource(name: 'a', path: '/a')]);
      await settle();
      expect(c.read(mergeControllerProvider).canMerge, isFalse);
    });
  });

  group('Merge screen', () {
    late _FakeInspector inspector;
    late _FakePicker picker;
    late _FakeRasterizer rasterizer;
    late _FakeSharer sharer;
    late MemoryLibraryStore library;
    late ProviderContainer container;
    late File a, b, c;

    Future<void> setUp({List<SavedDocument> docs = const []}) async {
      makeTmp();
      a = source('Lease.pdf');
      b = source('Receipt.pdf');
      c = source('Notes.pdf');
      inspector = _FakeInspector({
        a.path: const PdfInfo.ok(3),
        b.path: const PdfInfo.ok(5),
        c.path: const PdfInfo.problem(PdfProblem.locked),
      });
      picker = _FakePicker([PickedPdf(path: a.path, name: 'Lease.pdf'), PickedPdf(path: b.path, name: 'Receipt.pdf')]);
      rasterizer = _FakeRasterizer({'Lease.pdf': (612, 792), 'Receipt.pdf': (842, 595)});
      sharer = _FakeSharer();
      library = MemoryLibraryStore(LibraryIndex(documents: docs));
      container = ProviderContainer(
        overrides: [
          pdfInspectorProvider.overrideWithValue(inspector),
          pdfPickerProvider.overrideWithValue(picker),
          pdfRasterizerProvider.overrideWithValue(rasterizer),
          pdfSharerProvider.overrideWithValue(sharer),
          libraryStoreProvider.overrideWithValue(library),
          pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
        ],
      );
      addTearDown(container.dispose);
    }

    Future<void> pumpScreen(WidgetTester tester, {double textScale = 1}) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildLumaTheme(Brightness.light),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MergeScreen())),
                  child: const Text('open merge'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open merge'));
      await tester.pumpAndSettle();
    }

    /// Lets real async work (file checks, writes, isolates) run between frames.
    Future<void> work(WidgetTester tester, {int rounds = 30}) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    Future<void> addFromDevice(WidgetTester tester) async {
      await tester.tap(find.text('Add PDFs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From this device'));
      await tester.pumpAndSettle();
      await work(tester, rounds: 3);
    }

    FilledButton mergeButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Merge'));

    List<String> rowNames(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(ListTile), matching: find.byType(Text))))
        if (t.data != null && t.data!.endsWith('.pdf')) t.data!,
    ];

    testWidgets('starts empty and says what it does', (tester) async {
      await tester.runAsync(setUp);
      await pumpScreen(tester);
      expect(find.text('Combine PDFs into one'), findsOneWidget);
      expect(find.textContaining('Your originals are not changed'), findsOneWidget);
      expect(find.text('Add PDFs'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Merge'), findsNothing);
    });

    testWidgets('files from the device are listed with their page counts', (tester) async {
      await tester.runAsync(setUp);
      await pumpScreen(tester);
      await addFromDevice(tester);
      expect(rowNames(tester), ['Lease.pdf', 'Receipt.pdf']);
      expect(find.textContaining('3 pages'), findsOneWidget);
      expect(find.textContaining('5 pages'), findsOneWidget);
      expect(find.text('2 PDFs · 8 pages'), findsOneWidget);
      expect(mergeButton(tester).onPressed, isNotNull);
    });

    testWidgets('files from the Library are added in the order they were ticked', (tester) async {
      await tester.runAsync(() => setUp(docs: []));
      library.index = LibraryIndex(documents: [_doc('1', 'Lease', a.path, 3), _doc('2', 'Receipt', b.path, 5)]);
      await pumpScreen(tester);
      await tester.tap(find.text('Add PDFs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From Library'));
      await tester.pumpAndSettle();
      await work(tester, rounds: 3);
      await tester.pumpAndSettle();
      expect(find.text('Add'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add')).onPressed, isNull);

      await tester.tap(find.text('Receipt'));
      await tester.pump();
      await tester.tap(find.text('Lease'));
      await tester.pump();
      await tester.tap(find.text('Add 2'));
      await tester.pumpAndSettle();
      await work(tester, rounds: 3);
      expect(rowNames(tester), ['Receipt.pdf', 'Lease.pdf']);
      expect(find.textContaining('5 pages'), findsOneWidget);
    });

    testWidgets('an empty Library says so', (tester) async {
      await tester.runAsync(setUp);
      await pumpScreen(tester);
      await tester.tap(find.text('Add PDFs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From Library'));
      await tester.pumpAndSettle();
      await work(tester, rounds: 3);
      await tester.pumpAndSettle();
      expect(find.textContaining('Your Library has no documents yet'), findsOneWidget);
    });

    testWidgets('dragging the handle changes the order', (tester) async {
      await tester.runAsync(setUp);
      await pumpScreen(tester);
      await addFromDevice(tester);
      final gesture = await tester.startGesture(tester.getCenter(find.byIcon(Icons.drag_handle).first));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 16));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(rowNames(tester), ['Receipt.pdf', 'Lease.pdf']);
    });

    testWidgets('a locked file is flagged and must be removed before merging', (tester) async {
      await tester.runAsync(setUp);
      picker.files = [
        PickedPdf(path: a.path, name: 'Lease.pdf'),
        PickedPdf(path: c.path, name: 'Notes.pdf'),
        PickedPdf(path: '${tmp.path}/gone.pdf', name: 'gone.pdf'),
      ];
      await pumpScreen(tester);
      await addFromDevice(tester);
      expect(find.textContaining('Password protected'), findsOneWidget);
      expect(find.textContaining('cannot be read as a PDF'), findsOneWidget);
      expect(find.text('Remove the files marked above to continue.'), findsOneWidget);
      expect(mergeButton(tester).onPressed, isNull);

      await tester.tap(find.byTooltip('Remove Notes.pdf'));
      await tester.pump();
      await tester.tap(find.byTooltip('Remove gone.pdf'));
      await tester.pump();
      expect(find.text('Add at least one more PDF to merge.'), findsOneWidget);
      expect(mergeButton(tester).onPressed, isNull, reason: 'one file is not a merge');
    });

    testWidgets('a picker that fails says so and keeps the list', (tester) async {
      await tester.runAsync(setUp);
      await pumpScreen(tester);
      picker.failure = StateError('no storage');
      await addFromDevice(tester);
      expect(find.textContaining('Could not add those files'), findsOneWidget);
    });

    testWidgets('merging saves a new Library document and leaves the originals alone', (tester) async {
      await tester.runAsync(setUp);
      final before = [a.readAsBytesSync(), b.readAsBytesSync()];
      await pumpScreen(tester);
      await addFromDevice(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();
      expect(find.text('Merge 2 PDFs'), findsOneWidget);
      expect(find.textContaining('text in the new PDF cannot be selected'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Lease and receipt');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Merge').last);
      await work(tester);
      await tester.pumpAndSettle();

      expect(find.text('Merged'), findsOneWidget);
      expect(find.textContaining('Lease and receipt.pdf · 8 pages'), findsOneWidget);
      expect(find.textContaining('original PDFs are unchanged'), findsOneWidget);

      final saved = library.index.documents.single;
      expect((saved.name, saved.pageCount, saved.type), ('Lease and receipt', 8, ScanType.pdf));
      expect(mediaBoxes(File(saved.pdfPath)), [...List.filled(3, '612x792'), ...List.filled(5, '842x595')]);
      expect(a.readAsBytesSync(), before[0]);
      expect(b.readAsBytesSync(), before[1]);
    });

    testWidgets('Send opens the send sheet for the merged file, Done closes the screen', (tester) async {
      await tester.runAsync(setUp);
      await pumpScreen(tester);
      await addFromDevice(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Merge').last);
      await work(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Send smaller copy'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(MergeScreen), findsNothing);
      expect(find.text('Merged PDF saved to Library'), findsOneWidget);
    });

    testWidgets('a failed merge keeps the list and the name, and can be retried', (tester) async {
      await tester.runAsync(setUp);
      await pumpScreen(tester);
      await addFromDevice(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();
      rasterizer.failure = StateError('out of memory');
      await tester.enterText(find.byType(TextField), 'Joined');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Merge').last);
      await work(tester, rounds: 10);
      await tester.pumpAndSettle();
      expect(find.textContaining('Merging failed. Your PDFs are unchanged.'), findsOneWidget);
      expect(library.index.documents, isEmpty);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Joined');

      rasterizer.failure = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Merge').last);
      await work(tester);
      await tester.pumpAndSettle();
      expect(find.text('Merged'), findsOneWidget);
    });

    testWidgets('fits at 200% text size with files listed and the merge sheet open', (tester) async {
      await tester.runAsync(setUp);
      await pumpScreen(tester, textScale: 2);
      await addFromDevice(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Tools screen', () {
    Future<void> pumpTools(WidgetTester tester, {double textScale = 1}) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryStoreProvider.overrideWithValue(MemoryLibraryStore()),
            pdfInspectorProvider.overrideWithValue(_FakeInspector(const {})),
          ],
          child: MaterialApp(theme: buildLumaTheme(Brightness.light), home: const ToolsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows Sign, Reorder pages and Merge PDFs, and nothing that is not built', (tester) async {
      await pumpTools(tester);
      for (final title in ['Sign', 'Reorder pages', 'Merge PDFs']) {
        expect(find.text(title), findsOneWidget);
      }
      for (final missing in ['Compress', 'Split', 'Protect', 'OCR']) {
        expect(find.textContaining(missing), findsNothing);
      }
    });

    testWidgets('Merge PDFs opens the merge screen', (tester) async {
      await pumpTools(tester);
      await tester.tap(find.text('Merge PDFs'));
      await tester.pumpAndSettle();
      expect(find.byType(MergeScreen), findsOneWidget);
    });

    testWidgets('fits at 200% text size, with every tool still reachable', (tester) async {
      await pumpTools(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Photos to PDF'), 200);
      expect(find.text('Photos to PDF'), findsOneWidget);
    });
  });
}

class _ThrowingInspector implements PdfInspector {
  @override
  Future<PdfInfo> inspect(String path) => Future.error(StateError('engine failed'));
}
