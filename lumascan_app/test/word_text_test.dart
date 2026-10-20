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
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/export/word/docx_reader.dart';
import 'package:lumascan/export/word/docx_to_pdf.dart';
import 'package:lumascan/export/word/docx_writer.dart';
import 'package:lumascan/export/word/pdf_text_reader.dart';
import 'package:lumascan/export/word/word_service.dart';
import 'package:lumascan/export/word/word_text_layout.dart';
import 'package:lumascan/features/export/export_choice.dart';
import 'package:lumascan/features/merge/pdf_inspector.dart';
import 'package:lumascan/features/tools/tools_screen.dart';
import 'package:lumascan/features/word/word_saved_sheet.dart';
import 'package:lumascan/pdf_edit/pdf_saver.dart';
import 'package:lumascan/ui/state_views.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'support/memory_stores.dart';

Uint8List _jpeg(int width, int height) =>
    img.encodeJpg(img.Image(width: width, height: height)..clear(img.ColorRgb8(200, 200, 200)));

/// Renders only the pages asked for, and remembers which they were.
class _RecordingRasterizer implements PdfRasterizer {
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
      yield RasterPage(_jpeg(300, 400), 300, 400, widthPt: 612, heightPt: 792);
    }
  }
}

class _FakeTextReader implements PdfTextReader {
  _FakeTextReader(this.pages, {this.fail = false});

  final List<PdfPageLines> pages;
  final bool fail;

  @override
  Future<List<PdfPageLines>> readPages(String path, {required int pageCount, String? password}) async {
    if (fail) throw StateError('broken text layer');
    return pages;
  }
}

PdfTextLine _line(String text, double top, {double left = 72, double right = 540, double height = 12}) =>
    PdfTextLine(text, left: left, top: top, right: right, bottom: top + height);

const _letterPage = (w: 612.0, h: 792.0);

PdfPageLines _textPage(List<PdfTextLine> lines) =>
    PdfPageLines(widthPt: _letterPage.w, heightPt: _letterPage.h, lines: lines);

const _empty = PdfPageLines(widthPt: 612, heightPt: 792, lines: []);

void main() {
  group('PDF text lines', () {
    test('lines are split at line breaks and turned to top-left page coordinates', () {
      const text = 'Hi\nYo';
      final rects = [
        const PdfRect(10, 700, 20, 688),
        const PdfRect(20, 700, 30, 688),
        const PdfRect(30, 700, 30, 688), // the line break
        const PdfRect(10, 680, 20, 668),
        const PdfRect(20, 680, 32, 668),
      ];
      final lines = PdfrxTextReader.linesOf(text, rects, 792);
      expect(lines.map((l) => l.text), ['Hi', 'Yo']);
      expect(lines.first.left, 10);
      expect(lines.first.right, 30);
      expect(lines.first.top, closeTo(92, 0.01));
      expect(lines.first.bottom, closeTo(104, 0.01));
      expect(lines.last.right, 32);
    });

    test('blank lines and lines without boxes are left out', () {
      final lines = PdfrxTextReader.linesOf('\n \nA', [
        const PdfRect(0, 0, 0, 0),
        const PdfRect(0, 0, 0, 0),
        const PdfRect(0, 0, 0, 0),
        const PdfRect(5, 20, 9, 10),
      ], 100);
      expect(lines.map((l) => l.text), ['A']);
    });
  });

  group('Word text layout', () {
    test('lines that run on join into one paragraph; a short line ends it', () {
      final paragraphs = WordTextLayout.fromLines(
        _textPage([
          _line('The tenant pays the rent on the first day of each', 72),
          _line('month, by bank transfer.', 86, right: 220),
          _line('Signed in London.', 120, right: 200),
        ]),
      );
      expect(paragraphs.map((p) => p.text), [
        'The tenant pays the rent on the first day of each month, by bank transfer.',
        'Signed in London.',
      ]);
      expect(paragraphs.first.fontSizePt, closeTo(12.5, 0.01));
      expect(paragraphs.first.indentPt, closeTo(72 - WordTextLayout.marginPt, 0.01));
      expect(paragraphs.last.spaceBeforePt, greaterThan(10));
    });

    test('a heading in a bigger size is a paragraph of its own', () {
      final paragraphs = WordTextLayout.fromLines(
        _textPage([_line('Lease agreement', 60, height: 24), _line('This lease is made between the parties', 90)]),
      );
      expect(paragraphs, hasLength(2));
      expect(paragraphs.first.fontSizePt, greaterThan(paragraphs.last.fontSizePt * 1.8));
    });

    test('a word broken with a hyphen is joined without a space', () {
      final paragraphs = WordTextLayout.fromLines(_textPage([_line('An agree-', 72), _line('ment.', 86, right: 120)]));
      expect(paragraphs.single.text, 'An agree-ment.');
    });

    test('a page that would run onto a second Word page is tightened to fit', () {
      final crowded = [
        for (var i = 0; i < 60; i++)
          DocxParagraph(
            'Line $i of a crowded question paper with a lot of words on it',
            fontSizePt: 12,
            spaceBeforePt: 6,
          ),
      ];
      final fitted = WordTextLayout.fitToPage(crowded, 612, 792);
      const width = 612 - 2 * WordTextLayout.marginPt;
      double height(List<DocxParagraph> ps) =>
          ps.fold(0.0, (h, para) => h + para.spaceBeforePt + WordTextLayout.estimateHeight(para, width));
      expect(height(crowded), greaterThan(792 - 2 * WordTextLayout.marginPt));
      expect(height(fitted), lessThan(height(crowded)));
      expect(fitted.first.spaceBeforePt, lessThan(6));
      // Shrunk at most to 80%, to the nearest half point.
      expect(fitted.first.fontSizePt, greaterThanOrEqualTo(9.5));
      // A page that fits is left as it is.
      expect(WordTextLayout.fitToPage(crowded.take(3).toList(), 612, 792).first.spaceBeforePt, 6);
    });

    test('OCR text keeps its lines, and a blank line becomes space above', () {
      final paragraphs = WordTextLayout.fromPlainText('Invoice 42\n\nTotal: 10\r\nPaid');
      expect(paragraphs.map((p) => p.text), ['Invoice 42', 'Total: 10', 'Paid']);
      expect(paragraphs[0].spaceBeforePt, 0);
      expect(paragraphs[1].spaceBeforePt, WordTextLayout.plainFontPt);
      expect(paragraphs[2].spaceBeforePt, 0);
    });
  });

  group('Word text pages', () {
    test('text pages are read back as editable text, with markup characters kept', () async {
      final bytes = DocxWriter.build([
        const DocxPage.text(
          paragraphs: [DocxParagraph('Fish & chips <2 for 1>', fontSizePt: 14), DocxParagraph('Second\u0001 line')],
          pageWidthPt: 612,
          pageHeightPt: 792,
        ),
        DocxPage(jpeg: _jpeg(120, 160), imageWidth: 120, imageHeight: 160, pageWidthPt: 595, pageHeightPt: 842),
      ]);
      final doc = DocxReader.parse(bytes);
      expect(doc.sections, hasLength(2));
      expect(doc.sections[0].pageWidthPt, closeTo(612, 0.1));
      expect(doc.sections[0].margins.left, DocxWriter.textMarginPt);
      expect(doc.sections[0].blocks.cast<DocxText>().map((t) => t.text), ['Fish & chips <2 for 1>', 'Second line']);
      expect(doc.sections[1].blocks.single, isA<DocxPicture>());

      // And it opens as a PDF again, one page each.
      final pdf = await DocxToPdf.build(doc);
      expect(pdf.pageCount, 2);
    });
  });

  group('WordService text', () {
    late Directory tmp;
    late PageStore store;
    late String pdfPath;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lumascan_word_text');
      store = PageStore(rootDir: () async => tmp);
      pdfPath = p.join(tmp.path, 'source.pdf');
      File(pdfPath).writeAsBytesSync([0x25, 0x50, 0x44, 0x46]);
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    test('a page with text becomes text, a picture page stays a picture, in page order', () async {
      final rasterizer = _RecordingRasterizer();
      final service = WordService(
        store,
        rasterizer,
        _FakeTextReader([
          _empty,
          _textPage([_line('Question 1. Write the number seven hundred in words.', 72)]),
          _textPage([_line('3', 760, left: 300, right: 306)]), // only a page number
        ]),
      );
      final word = await service.pdfToWord(pdfPath, pageCount: 3, name: 'Exam');
      expect(word.textPages, 1);
      expect(word.picturePages, 2);
      // Only the pages without text are rendered.
      expect(rasterizer.asked, [1, 3]);

      final sections = DocxReader.parse(word.file.readAsBytesSync()).sections;
      expect(sections, hasLength(3));
      expect(sections[0].blocks.single, isA<DocxPicture>());
      expect((sections[1].blocks.single as DocxText).text, startsWith('Question 1.'));
      expect(sections[2].blocks.single, isA<DocxPicture>());
    });

    test('Exact look makes every page a picture, even pages with text', () async {
      final rasterizer = _RecordingRasterizer();
      final service = WordService(
        store,
        rasterizer,
        _FakeTextReader([
          _textPage([_line('Question 1. Write the number seven hundred in words.', 72)]),
        ]),
      );
      final word = await service.pdfToWord(pdfPath, pageCount: 1, name: 'Exam', editableText: false);
      expect((word.textPages, word.picturePages), (0, 1));
      expect(rasterizer.asked, [1]);
    });

    test('a text layer that cannot be read leaves every page a picture', () async {
      final rasterizer = _RecordingRasterizer();
      final service = WordService(store, rasterizer, _FakeTextReader(const [], fail: true));
      final word = await service.pdfToWord(pdfPath, pageCount: 2, name: 'Scan');
      expect(word.textPages, 0);
      expect(word.picturePages, 2);
      expect(rasterizer.asked, [1, 2]);
    });

    test('scan pages read with OCR become text; the others are pictures with their edits', () async {
      final photo = File(p.join(tmp.path, 'photo.jpg'))..writeAsBytesSync(_jpeg(400, 300));
      final service = WordService(store, _RecordingRasterizer());
      final word = await service.pagesToWord([
        ScanPage(id: 'a', originalPath: photo.path, text: 'Grocery list\nMilk 2\nBread 1\nEggs 12'),
        ScanPage(id: 'b', originalPath: photo.path),
      ], name: 'Groceries');
      expect(p.basename(word.file.path), 'Groceries.docx');
      expect((word.textPages, word.picturePages), (1, 1));
      final sections = DocxReader.parse(word.file.readAsBytesSync()).sections;
      expect(sections[0].blocks.cast<DocxText>().map((t) => t.text), ['Grocery list', 'Milk 2', 'Bread 1', 'Eggs 12']);
      final picture = sections[1].blocks.single as DocxPicture;
      // The landscape photo gives a landscape page.
      expect(sections[1].pageWidthPt, greaterThan(sections[1].pageHeightPt));
      expect(picture.widthPt, greaterThan(picture.heightPt));
    });

    test('the saved sheet sums up text and picture pages', () {
      final file = File('x.docx');
      expect(
        WordSavedSheet.summary(WordFile(file, textPages: 2, picturePages: 1)),
        '2 pages of editable text, 1 picture page',
      );
      expect(WordSavedSheet.summary(WordFile(file, textPages: 1, picturePages: 0)), '1 page of editable text');
    });
  });

  group('Word in the app', () {
    Future<void> pumpTools(WidgetTester tester, AppPlan plan) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryStoreProvider.overrideWithValue(MemoryLibraryStore()),
            pdfInspectorProvider.overrideWithValue(_NoInspector()),
            planProvider.overrideWithValue(plan),
          ],
          child: MaterialApp(theme: buildLumaTheme(Brightness.light), home: const ToolsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> pumpExport(WidgetTester tester, AppPlan plan) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryStoreProvider.overrideWithValue(MemoryLibraryStore()),
            planProvider.overrideWithValue(plan),
          ],
          child: MaterialApp(
            theme: buildLumaTheme(Brightness.light),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(onPressed: () => showExportChoice(context, ref), child: const Text('Export')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
    }

    test('PDF to Word is part of Pro, and Gold has it too', () {
      expect(AppPlan.basic.includes(PlanFeature.word), isFalse);
      expect(AppPlan.pro.includes(PlanFeature.word), isTrue);
      expect(AppPlan.gold.includes(PlanFeature.word), isTrue);
    });

    testWidgets('Tools has PDF to Word and Word to PDF; on Basic PDF to Word is marked Pro', (tester) async {
      await pumpTools(tester, AppPlan.basic);
      await tester.scrollUntilVisible(find.text('PDF to Word'), 200);
      expect(find.text('PDF to Word'), findsOneWidget);
      expect(find.text('Word to PDF'), findsOneWidget);
      expect(find.widgetWithText(PremiumBadge, 'Pro'), findsOneWidget);

      await tester.ensureVisible(find.text('PDF to Word'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PDF to Word'));
      await tester.pumpAndSettle();
      expect(find.text('Upgrade to Pro'), findsWidgets);
    });

    testWidgets('on Gold PDF to Word has no lock', (tester) async {
      await pumpTools(tester, AppPlan.gold);
      await tester.scrollUntilVisible(find.text('PDF to Word'), 200);
      expect(find.byType(PremiumBadge), findsNothing);
    });

    testWidgets('Export offers Export as PDF and Export as Word, Word locked on Basic', (tester) async {
      await pumpExport(tester, AppPlan.basic);
      expect(find.text('Export as PDF'), findsOneWidget);
      expect(find.text('Export as Word'), findsOneWidget);
      expect(find.text('JPG images'), findsOneWidget);
      expect(find.widgetWithText(PremiumBadge, 'Pro'), findsOneWidget);

      await tester.tap(find.text('Export as Word'));
      await tester.pumpAndSettle();
      expect(find.text('Upgrade to Pro'), findsWidgets);
    });

    testWidgets('on Pro Export as Word has no lock', (tester) async {
      await pumpExport(tester, AppPlan.pro);
      expect(find.text('Export as Word'), findsOneWidget);
      expect(find.byType(PremiumBadge), findsNothing);
    });
  });
}

class _NoInspector implements PdfInspector {
  @override
  Future<PdfInfo> inspect(String path) async => const PdfInfo.problem(PdfProblem.unreadable);
}
