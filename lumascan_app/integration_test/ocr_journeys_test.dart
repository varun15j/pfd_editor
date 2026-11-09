// Recognize text journeys, run on a device or emulator:
//
//   flutter test integration_test/ocr_journeys_test.dart -d emulator-5554
//
// The pages are the Word feature test pages bundled with the app
// (Settings > Developer > Add Word test pages, as a tester adds them by
// hand). Text recognition (ML Kit), the text PDF and the Word file are the
// real app on the device. Stores are in memory and files go to a temporary
// folder, so the device's own Library is never touched. The written cases
// are in docs/test-cases-user-journeys.md (J4 and J5).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luma_docx/luma_docx.dart';
import 'package:lumascan/export/word/pdf_text_reader.dart';

import 'support/journey_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Journey journey;
  setUp(() async => journey = await Journey.create());
  tearDown(() => journey.dispose());

  /// Home > Settings > Developer > Add Word test pages: a new 35-page
  /// document, open on the Pages screen.
  Future<void> addWordTestPages(WidgetTester tester) async {
    await tapOn(tester, find.byTooltip('Settings'));
    final tile = find.text('Add Word test pages');
    await tester.scrollUntilVisible(tile, 400, scrollable: find.byType(Scrollable).first);
    await tapOn(tester, tile);
    await waitUntil(tester, () => scanState(tester).pages.length == 35, timeout: const Duration(minutes: 5));
    await waitFor(tester, find.byTooltip('Batch edit'));
  }

  /// Taps "Page [n]" in Batch review, scrolling the grid to it.
  Future<void> togglePage(WidgetTester tester, int n) async {
    final tile = find.text('Page $n');
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable)).first,
    );
    await tapOn(tester, tile);
  }

  /// OCR > Recognize text on [count] pages, and waits until every page is read.
  Future<Duration> recognize(WidgetTester tester, int count) async {
    await tapOn(tester, find.text('OCR'));
    final clock = Stopwatch()..start();
    await tapOn(tester, find.text('Recognize text on $count page${count == 1 ? '' : 's'}'));
    await waitFor(tester, find.textContaining('Finished: '), timeout: const Duration(minutes: 20));
    return clock.elapsed;
  }

  /// The newest file ending in [extension] in [dir].
  File newest(String dir, String extension) {
    final files = Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith(extension)).toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    expect(files, isNotEmpty, reason: 'a $extension file in $dir');
    return files.first;
  }

  /// Create text PDF: the progress dialog shows, then the "Text PDF saved"
  /// sheet. Returns the PDF and how long it took.
  Future<(File, Duration)> createTextPdf(WidgetTester tester, {required Duration limit}) async {
    final clock = Stopwatch()..start();
    await tapOn(tester, find.text('Create text PDF'));
    await waitFor(tester, find.text('Text PDF saved'), timeout: limit);
    final took = clock.elapsed;
    // Close the sheet; the PDF stays in the exports folder.
    await tester.tapAt(const Offset(20, 40));
    await settle(tester);
    return (newest('${journey.root.path}/exports', '.pdf'), took);
  }

  /// Create Word file: the progress dialog shows, then "Word file ready".
  Future<(File, Duration)> createWordFile(WidgetTester tester, {required Duration limit}) async {
    final clock = Stopwatch()..start();
    await tapOn(tester, find.text('Create Word file'));
    await waitFor(tester, find.text('Word file ready'), timeout: limit);
    final took = clock.elapsed;
    await tester.tapAt(const Offset(20, 40));
    await settle(tester);
    return (newest('${journey.root.path}/exports/Saved', '.docx'), took);
  }

  /// The text layer of [pdf], page by page, as PDF apps read it (PDFium,
  /// the engine PDF to Word uses too).
  Future<List<String>> pdfText(File pdf, int pages) async {
    final read = await PdfrxTextReader().readPages(pdf.path, pageCount: pages);
    return [for (final p in read) p.lines.map((l) => l.text).join('\n')];
  }

  /// Every paragraph of a Word file, and how many pictures it holds.
  (String, int) wordContent(File docx) {
    final doc = WordReader.read(docx.readAsBytesSync());
    final text = StringBuffer();
    var pictures = 0;
    void walk(List<WordBlock> blocks) {
      for (final b in blocks) {
        switch (b) {
          case WordParagraph():
            for (final i in b.inlines) {
              if (i is WordText) text.write(i.text);
              if (i is WordPicture) pictures++;
            }
            text.writeln();
          case WordTable():
            for (final row in b.rows) {
              for (final cell in row.cells) {
                walk(cell.blocks);
              }
            }
        }
      }
    }

    for (final s in doc.sections) {
      walk(s.blocks);
    }
    return (text.toString(), pictures);
  }

  void report(String line) => debugPrint('JOURNEY_RESULT $line');

  testWidgets('J4: Word test pages, Recognize text on 5 pages, Create text PDF, then Create Word file', (tester) async {
    await journey.launch(tester);

    // 1. Add the Word test pages as a new document.
    await addWordTestPages(tester);
    expect(scanState(tester).pages, hasLength(35));

    // 2. Batch edit: only pages 1, 2, 6, 7 (the pages of the BlueStacks
    // report) and 21 (a chart and a picture).
    await tapOn(tester, find.byTooltip('Batch edit'));
    await tapOn(tester, find.text('Clear'));
    for (final n in [1, 2, 6, 7, 21]) {
      await togglePage(tester, n);
    }
    expect(find.text('5 selected'), findsOneWidget);

    // 3. Recognize text.
    final read = await recognize(tester, 5);
    expect(find.textContaining('Finished: 5 with text'), findsOneWidget);
    report('J4 recognize 5 pages: ${read.inMilliseconds} ms');

    // 4. Create text PDF: done in seconds, not minutes.
    final (pdf, pdfTime) = await createTextPdf(tester, limit: const Duration(minutes: 3));
    report('J4 text PDF 5 pages: ${pdfTime.inMilliseconds} ms, ${pdf.lengthSync()} bytes');
    expect(pdfTime, lessThan(const Duration(minutes: 1)));

    // 5. The PDF's text is there for PDF apps to find and copy, on every page.
    final text = await pdfText(pdf, 5);
    expect(text, hasLength(5));
    for (final (i, page) in text.indexed) {
      expect(page.trim(), isNotEmpty, reason: 'text layer on PDF page ${i + 1}');
    }
    expect(text.first.toLowerCase(), contains('feature test'));
    report('J4 text PDF text layer: ${[for (final t in text) t.length]} characters per page');

    // 6. Create Word file: the text, and the chart and picture of page 21
    // cut from the scan.
    final (docx, wordTime) = await createWordFile(tester, limit: const Duration(minutes: 3));
    final (wordText, pictures) = wordContent(docx);
    report('J4 Word file 5 pages: ${wordTime.inMilliseconds} ms, $pictures pictures, ${docx.lengthSync()} bytes');
    expect(wordTime, lessThan(const Duration(minutes: 1)));
    expect(wordText.toLowerCase(), contains('feature test'));
    expect(pictures, greaterThanOrEqualTo(2), reason: 'the chart and the picture on page 21');
  });

  testWidgets('J5: all 35 Word test pages, Recognize text, Create text PDF and Create Word file in time', (
    tester,
  ) async {
    await journey.launch(tester);
    await addWordTestPages(tester);

    // Batch edit opens with every page selected.
    await tapOn(tester, find.byTooltip('Batch edit'));
    expect(find.text('35 selected'), findsOneWidget);
    final read = await recognize(tester, 35);
    report('J5 recognize 35 pages: ${read.inMilliseconds} ms');

    final (pdf, pdfTime) = await createTextPdf(tester, limit: const Duration(minutes: 10));
    report('J5 text PDF 35 pages: ${pdfTime.inMilliseconds} ms, ${pdf.lengthSync()} bytes');
    expect(pdfTime, lessThan(const Duration(minutes: 2)));
    final text = await pdfText(pdf, 35);
    final withText = text.where((t) => t.trim().isNotEmpty).length;
    report('J5 text PDF pages with a text layer: $withText of 35');
    expect(withText, greaterThanOrEqualTo(30));

    final (docx, wordTime) = await createWordFile(tester, limit: const Duration(minutes: 10));
    final (_, pictures) = wordContent(docx);
    report('J5 Word file 35 pages: ${wordTime.inMilliseconds} ms, $pictures pictures, ${docx.lengthSync()} bytes');
    expect(wordTime, lessThan(const Duration(minutes: 2)));
    expect(pictures, greaterThanOrEqualTo(2));
  });
}
