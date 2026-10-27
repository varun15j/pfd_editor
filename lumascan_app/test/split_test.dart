import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/app/theme.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/export/pdf_splitter.dart';
import 'package:lumascan/features/merge/pdf_inspector.dart';
import 'package:lumascan/features/merge/pdf_picker.dart';
import 'package:lumascan/features/split/split_actions.dart';
import 'package:lumascan/features/split/split_screen.dart';
import 'package:lumascan/features/tools/tools_screen.dart';
import 'package:lumascan/pdf_edit/pdf_edit_controller.dart';
import 'package:lumascan/pdf_edit/pdf_saver.dart';

import 'support/memory_stores.dart';

/// Renders each page as a small image whose width in points is 100 times
/// its page number, so the pages in each output can be read back from the
/// MediaBoxes.
class _FakeRasterizer implements PdfRasterizer {
  final requested = <List<int>>[];
  int? failOnCall;

  @override
  Stream<RasterPage> renderPages(
    String path,
    List<int> pageNumbers, {
    required int longEdge,
    required int jpegQuality,
    String? password,
  }) async* {
    requested.add(pageNumbers);
    if (failOnCall == requested.length) throw StateError('broken page');
    for (final n in pageNumbers) {
      yield RasterPage(
        Uint8List.fromList(img.encodeJpg(img.Image(width: 30, height: 40)..clear(img.ColorRgb8(200, 200, 200)))),
        30,
        40,
        widthPt: 100.0 * n,
        heightPt: 800,
      );
    }
  }
}

class _FakeInspector implements PdfInspector {
  _FakeInspector(this.info);
  final PdfInfo info;

  @override
  Future<PdfInfo> inspect(String path) async => info;
}

class _FakePicker implements PdfPicker {
  _FakePicker(this.files);
  final List<PickedPdf> files;

  @override
  Future<List<PickedPdf>> pick() async => files;
}

List<int> pagesIn(File pdf) => [
  for (final m in RegExp(r'/MediaBox\[0 0 (\d+) \d+\]').allMatches(String.fromCharCodes(pdf.readAsBytesSync())))
    int.parse(m[1]!) ~/ 100,
];

void main() {
  group('parsePageRanges', () {
    test('reads single pages, ranges and open ends', () {
      expect(parsePageRanges('1-3, 5, 8-', 10), [
        [1, 2, 3],
        [5],
        [8, 9, 10],
      ]);
      expect(parsePageRanges(' 2 – 4 ,, 6 ', 6), [
        [2, 3, 4],
        [6],
      ]);
    });

    test('explains what is wrong', () {
      expect(() => parsePageRanges('', 5), throwsA(isA<PageRangeException>()));
      expect(
        () => parsePageRanges('1-7', 5),
        throwsA(isA<PageRangeException>().having((e) => e.message, 'message', contains('Page 7 is not in this PDF'))),
      );
      expect(
        () => parsePageRanges('4-2', 5),
        throwsA(isA<PageRangeException>().having((e) => e.message, 'message', contains('2-4'))),
      );
      expect(() => parsePageRanges('0', 5), throwsA(isA<PageRangeException>()));
      expect(() => parsePageRanges('a-b', 5), throwsA(isA<PageRangeException>()));
    });
  });

  test('pagesInChunks leaves a shorter last file', () {
    expect(pagesInChunks(5, 2), [
      [1, 2],
      [3, 4],
      [5],
    ]);
    expect(pagesInChunks(3, 3), [
      [1, 2, 3],
    ]);
  });

  test('describePages joins runs', () {
    expect(describePages([10, 1, 2, 3, 5, 9, 8]), '1-3, 5, 8-10');
    expect(describePages([4]), '4');
  });

  group('PdfSplitter', () {
    late Directory tmp;
    late PageStore store;
    late _FakeRasterizer rasterizer;
    late File source;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lumascan_split');
      store = PageStore(rootDir: () async => tmp);
      rasterizer = _FakeRasterizer();
      source = File('${tmp.path}/Book.pdf')..writeAsBytesSync(List.filled(64, 7));
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('writes one PDF per part with only its pages, and leaves the source alone', () async {
      final before = source.readAsBytesSync();
      final files = await PdfSplitter(store, rasterizer).split(source.path, const [
        SplitPart(pages: [1, 2], name: 'Book part 1'),
        SplitPart(pages: [3], name: 'Book part 2'),
      ]);
      expect(files.map((f) => f.path.split('/').last), ['Book part 1.pdf', 'Book part 2.pdf']);
      expect(pagesIn(files[0]), [1, 2]);
      expect(pagesIn(files[1]), [3]);
      expect(source.readAsBytesSync(), before);
    });

    test('never replaces an existing file', () async {
      final splitter = PdfSplitter(store, rasterizer);
      const part = SplitPart(pages: [2], name: 'Book pages 2');
      final first = await splitter.split(source.path, const [part]);
      final second = await splitter.split(source.path, const [part]);
      expect(first.single.existsSync(), isTrue);
      expect(second.single.path, endsWith('Book pages 2 (2).pdf'));
    });

    test('a failed part removes the parts already written', () async {
      rasterizer.failOnCall = 2;
      await expectLater(
        PdfSplitter(store, rasterizer).split(source.path, const [
          SplitPart(pages: [1], name: 'A'),
          SplitPart(pages: [2], name: 'B'),
        ]),
        throwsStateError,
      );
      final exports = await store.exportsDir;
      expect(exports.listSync().whereType<File>().where((f) => f.path.endsWith('.pdf')), isEmpty);
    });
  });

  group('Split screen', () {
    late Directory tmp;
    late _FakeRasterizer rasterizer;
    late MemoryLibraryStore library;
    late ProviderContainer container;
    late File source;

    void makeContainer({AppPlan plan = AppPlan.pro, PdfInfo info = const PdfInfo.ok(5)}) {
      tmp = Directory.systemTemp.createTempSync('lumascan_split_ui');
      addTearDown(() => tmp.deleteSync(recursive: true));
      source = File('${tmp.path}/Notes.pdf')..writeAsBytesSync(List.filled(64, 7));
      rasterizer = _FakeRasterizer();
      library = MemoryLibraryStore(const LibraryIndex());
      container = ProviderContainer(
        overrides: [
          planProvider.overrideWithValue(plan),
          pdfInspectorProvider.overrideWithValue(_FakeInspector(info)),
          pdfPickerProvider.overrideWithValue(_FakePicker([PickedPdf(path: source.path, name: 'Notes.pdf')])),
          pdfRasterizerProvider.overrideWithValue(rasterizer),
          libraryStoreProvider.overrideWithValue(library),
          pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
        ],
      );
      addTearDown(container.dispose);
    }

    Future<void> pump(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: buildLumaTheme(Brightness.light), home: home),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openScreen(WidgetTester tester) =>
        pump(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SplitScreen(
                      source: SplitSource(name: 'Notes', path: source.path, pageCount: 5),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ).then((_) async {
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
        });

    Future<void> work(WidgetTester tester) async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    testWidgets('splits every two pages into three files in the Library', (tester) async {
      makeContainer();
      await openScreen(tester);
      expect(find.text('Notes part 1.pdf'), findsOneWidget);
      expect(find.text('Notes part 3.pdf'), findsOneWidget);
      await tester.tap(find.text('Split into 3 PDFs'));
      await work(tester);
      expect(find.text('Saved 3 new PDFs'), findsOneWidget);
      expect(rasterizer.requested, [
        [1, 2],
        [3, 4],
        [5],
      ]);
      final docs = library.index.documents;
      expect(docs.map((d) => d.pageCount).toList()..sort(), [1, 2, 2]);
    });

    testWidgets('typed ranges show errors, then make one file per range', (tester) async {
      makeContainer();
      await openScreen(tester);
      await tester.tap(find.text('By page ranges'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1-9');
      await tester.pump();
      expect(find.textContaining('Page 9 is not in this PDF'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1-5');
      await tester.pump();
      expect(find.textContaining('keeps every page in one file'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '2, 4-');
      await tester.pump();
      await tester.tap(find.text('Split into 2 PDFs'));
      await work(tester);
      expect(rasterizer.requested, [
        [2],
        [4, 5],
      ]);
    });

    testWidgets('extracts the ticked pages into one new PDF', (tester) async {
      makeContainer();
      await openScreen(tester);
      await tester.tap(find.text('Extract'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '4'));
      await tester.tap(find.widgetWithText(FilterChip, '2'));
      await tester.tap(find.widgetWithText(FilterChip, '3'));
      await tester.pump();
      expect(find.text('Pages 2-4 go into a new PDF.'), findsOneWidget);
      await tester.tap(find.text('Extract 3 pages'));
      await work(tester);
      expect(find.text('Saved 1 new PDF'), findsOneWidget);
      expect(find.text('Notes pages 2-4.pdf'), findsOneWidget);
      final exported = File('${tmp.path}/exports/Notes pages 2-4.pdf');
      expect(pagesIn(exported), [2, 3, 4]);
    });

    testWidgets('Basic sees the Pro badge and the upgrade pop-up', (tester) async {
      makeContainer(plan: AppPlan.basic);
      await pump(tester, const ToolsScreen());
      final tile = find.ancestor(of: find.text('Split PDF'), matching: find.byType(InkWell));
      expect(find.descendant(of: tile, matching: find.text('Pro')), findsOneWidget);
      await tester.ensureVisible(find.text('Split PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Split PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Upgrade to Pro'), findsWidgets);
      expect(find.byType(SplitScreen), findsNothing);
    });

    testWidgets('Pro opens a PDF from the device; a locked one is turned away', (tester) async {
      makeContainer(info: const PdfInfo.problem(PdfProblem.locked));
      await pump(
        tester,
        Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(onPressed: () => pickPdfToSplit(context, ref), child: const Text('split')),
          ),
        ),
      );
      await tester.tap(find.text('split'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From this device'));
      await tester.pumpAndSettle();
      expect(find.textContaining('locked with a password'), findsOneWidget);
      expect(find.byType(SplitScreen), findsNothing);
    });
  });
}
