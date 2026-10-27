import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/document_text_reader.dart';
import 'package:lumascan/domain/document_text.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/library_query.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/ocr.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/export/word/pdf_text_reader.dart';
import 'package:lumascan/features/library/document_tile.dart';
import 'package:lumascan/pdf_edit/pdf_saver.dart';

import 'support/memory_stores.dart';
import 'support/pump_app.dart';

final now = DateTime.now();

SavedDocument doc(String id, String name, {int pages = 1, DateTime? modified}) => SavedDocument(
  id: id,
  name: name,
  pdfPath: '/nowhere/$id.pdf',
  pageCount: pages,
  type: ScanType.document,
  createdAt: modified ?? now.subtract(const Duration(days: 1)),
  modifiedAt: modified ?? now.subtract(const Duration(days: 1)),
);

/// Gives each PDF path the text in [byPath], noting what it read.
class _FakeReader implements DocumentTextReader {
  _FakeReader(this.byPath);
  final Map<String, String> byPath;
  final paths = <String>[];

  @override
  Future<String> read(String pdfPath, {required int pageCount, String languageCode = 'en'}) async {
    paths.add(pdfPath);
    final text = byPath[pdfPath];
    if (text == null) throw StateError('cannot open');
    return text;
  }
}

class _Layer implements PdfTextReader {
  _Layer(this.pages);
  final List<String> pages;

  @override
  Future<List<PdfPageLines>> readPages(String path, {required int pageCount, String? password}) async => [
    for (final t in pages)
      PdfPageLines(
        widthPt: 595,
        heightPt: 842,
        lines: [if (t.isNotEmpty) PdfTextLine(t, left: 0, top: 0, right: 100, bottom: 10)],
      ),
  ];
}

class _Raster implements PdfRasterizer {
  final asked = <int>[];

  @override
  Stream<RasterPage> renderPages(
    String path,
    List<int> pageNumbers, {
    required int longEdge,
    required int jpegQuality,
    String? password,
  }) async* {
    for (final n in pageNumbers) {
      asked.add(n);
      yield RasterPage(Uint8List.fromList([n]), 10, 10);
    }
  }
}

class _Ocr implements OcrEngine {
  _Ocr(this.text, {this.ready = true});
  final String text;
  final bool ready;
  int calls = 0;

  @override
  Future<OcrCapability> capability(String languageCode) async => OcrCapability(
    readiness: ready ? OcrReadiness.ready : OcrReadiness.unavailable,
    language: 'English',
  );

  @override
  Future<void> prepare(String languageCode) async {}

  @override
  Future<String> recognize(ScanPage page, {required String languageCode}) async => text;

  @override
  Future<String> recognizeFile(String path, {String languageCode = 'en'}) async {
    calls++;
    return text;
  }
}

void main() {
  group('query rules', () {
    final docs = [doc('a', 'Scan 1'), doc('b', 'Lease agreement')];
    final texts = {'a': DocumentText('Rent of ₹12,000 for\nMarch paid to Mr Rao', now)};

    test('with texts, a search matches the text inside a document, across line breaks and case', () {
      List<String> found(String q) => [for (final d in LibraryQuery(text: q).apply(docs, now, texts: texts)) d.id];
      expect(found('MARCH PAID'), ['a']);
      expect(found('for march'), ['a']);
      expect(found('lease'), ['b']);
      expect(found('nothing'), isEmpty);
    });

    test('without texts only names are searched', () {
      expect(const LibraryQuery(text: 'march').apply(docs, now), isEmpty);
    });

    test('a snippet shows the words around the match', () {
      final long = 'The tenant agrees to pay the rent of twelve thousand rupees for March to the owner before the fifth day of every month without fail';
      final s = searchSnippet(long, 'march')!;
      expect(s, contains('March'));
      expect(s.startsWith('…'), isTrue);
      expect(s.endsWith('…'), isTrue);
      expect(s.length, lessThan(long.length));
      expect(searchSnippet('short text', 'short'), 'short text');
      expect(searchSnippet('short text', 'zzz'), isNull);
    });

    test('text survives a round trip through JSON', () {
      final t = DocumentText('hello', DateTime.fromMillisecondsSinceEpoch(1000));
      final back = DocumentText.fromJson(t.toJson())!;
      expect(back.text, 'hello');
      expect(back.readAt, t.readAt);
      expect(DocumentText.fromJson('junk'), isNull);
    });
  });

  group('reading a PDF', () {
    test('a text layer is used as it is, with no OCR', () async {
      final ocr = _Ocr('ocr text');
      final raster = _Raster();
      final reader = DocumentTextReader(_Layer(['This page has a real text layer']), raster, ocr);
      expect(await reader.read('/x.pdf', pageCount: 1), 'This page has a real text layer');
      expect(ocr.calls, 0);
      expect(raster.asked, isEmpty);
    });

    test('pages that are pictures are read with OCR, in page order', () async {
      final ocr = _Ocr('read by OCR');
      final raster = _Raster();
      final reader = DocumentTextReader(_Layer(['A page with plenty of real text on it', '']), raster, ocr);
      final text = await reader.read('/x.pdf', pageCount: 3);
      expect(raster.asked, [2, 3]);
      expect(text, 'A page with plenty of real text on it\n\nread by OCR\n\nread by OCR');
    });

    test('without OCR, picture pages are left out', () async {
      final reader = DocumentTextReader(_Layer(['']), _Raster(), _Ocr('x', ready: false));
      expect(await reader.read('/x.pdf', pageCount: 1), '');
    });
  });

  group('Library', () {
    final docs = [doc('a', 'Scan 1'), doc('b', 'Lease agreement'), doc('c', 'Broken')];

    Future<(_FakeReader, MemoryDocumentTextStore)> open(WidgetTester tester, AppPlan plan) async {
      final reader = _FakeReader({'/nowhere/a.pdf': 'Electricity bill for March, consumer no 4471', '/nowhere/b.pdf': ''});
      final store = MemoryDocumentTextStore();
      await pumpApp(
        tester,
        library: MemoryLibraryStore(const LibraryIndex().copyWith(documents: docs)),
        overrides: [
          planProvider.overrideWith((ref) => plan),
          documentTextReaderProvider.overrideWithValue(reader),
        ],
        textStore: store,
      );
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      return (reader, store);
    }

    List<String> shown(WidgetTester tester) => [
      for (final row in tester.widgetList<DocumentRow>(find.byType(DocumentRow))) row.document.name,
    ];

    testWidgets('on Pro the text inside documents is read and searched, with the matching words shown', (
      tester,
    ) async {
      final (reader, store) = await open(tester, AppPlan.pro);
      expect(find.text('Search names and text'), findsOneWidget);
      // Every document is read once, including one that cannot be opened.
      expect(reader.paths.toSet(), {'/nowhere/a.pdf', '/nowhere/b.pdf', '/nowhere/c.pdf'});
      expect(store.texts.keys.toSet(), {'a', 'b', 'c'});

      await tester.enterText(find.byType(TextField), 'consumer no');
      await tester.pumpAndSettle();
      expect(shown(tester), ['Scan 1']);
      expect(find.textContaining('consumer no 4471'), findsOneWidget);

      // A name match shows no snippet.
      await tester.enterText(find.byType(TextField), 'lease');
      await tester.pumpAndSettle();
      expect(shown(tester), ['Lease agreement']);
      expect(find.textContaining('…'), findsNothing);
    });

    testWidgets('text already read is not read again', (tester) async {
      final reader = _FakeReader({});
      final store = MemoryDocumentTextStore({
        for (final d in docs) d.id: DocumentText(d.id == 'a' ? 'march' : '', now),
      });
      await pumpApp(
        tester,
        library: MemoryLibraryStore(const LibraryIndex().copyWith(documents: docs)),
        overrides: [
          planProvider.overrideWith((ref) => AppPlan.gold),
          documentTextReaderProvider.overrideWithValue(reader),
        ],
        textStore: store,
      );
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(reader.paths, isEmpty);
      await tester.enterText(find.byType(TextField), 'march');
      await tester.pumpAndSettle();
      expect(shown(tester), ['Scan 1']);
    });

    testWidgets('on Basic only names are searched and nothing is read', (tester) async {
      final (reader, _) = await open(tester, AppPlan.basic);
      expect(find.text('Search by name'), findsOneWidget);
      expect(reader.paths, isEmpty);

      await tester.enterText(find.byType(TextField), 'consumer');
      await tester.pumpAndSettle();
      expect(shown(tester), isEmpty);
      expect(find.textContaining('Pro also searches the text inside documents'), findsOneWidget);
    });
  });
}
