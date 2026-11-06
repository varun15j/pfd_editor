import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/ocr.dart';
import 'package:lumascan/export/ocr_pdf_builder.dart';
import 'package:lumascan/features/ocr_word/ocr_word_builder.dart';
import 'package:lumascan/features/ocr_word/ocr_word_figure.dart';
import 'package:lumascan/imaging/ocr_figures.dart';
import 'package:lumascan/imaging/page_jobs.dart';
import 'package:lumascan/imaging/rgb_image.dart';
import 'package:lumascan/ui/work_progress.dart';
import 'package:luma_docx/luma_docx.dart';

import 'support/temp_dir.dart';
import 'support/word_pages.dart';

OcrWordFigure _figure(double top, double bottom, {double left = 0.2, double right = 0.8}) {
  final image = img.Image(width: 60, height: 30)..clear(img.ColorRgb8(200, 30, 30));
  return OcrWordFigure(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    jpeg: img.encodeJpg(image),
    pixelWidth: 60,
    pixelHeight: 30,
  );
}

OcrBlock _block(String text, double top, double bottom) => OcrBlock(
  text: text,
  left: 0.1,
  top: top,
  right: 0.9,
  bottom: bottom,
  lines: [OcrLine(text: text, left: 0.1, top: top, right: 0.9, bottom: bottom)],
);

void main() {
  group('pictures cut from the scan for OCR to Word', () {
    test('every picture on the pictures page is found where it sat, beside text too', () {
      final (page, layout) = wordTestPage(21);
      final figures = ocrWordFigures(page, text: layout.text, layout: layout);
      // The bar chart, the gradient right of a paragraph, the green picture
      // left of one, the centred green picture, the strip behind a line.
      final boxes = [for (final f in figures) (f.left, f.top, f.right, f.bottom)];
      const expected = [
        (0.24, 0.15, 0.77, 0.36),
        (0.69, 0.42, 0.88, 0.52),
        (0.12, 0.55, 0.27, 0.63),
        (0.42, 0.71, 0.58, 0.79),
        (0.12, 0.84, 0.50, 0.90),
      ];
      expect(boxes, hasLength(expected.length));
      for (final (i, (l, t, r, b)) in expected.indexed) {
        final (fl, ft, fr, fb) = boxes[i];
        expect(ft, closeTo(t, 0.03), reason: 'picture ${i + 1} top');
        expect(fb, closeTo(b, 0.03), reason: 'picture ${i + 1} bottom');
        expect((fl + fr) / 2, closeTo((l + r) / 2, 0.05), reason: 'picture ${i + 1} middle');
      }
      for (final f in figures) {
        expect(img.decodeJpg(f.jpeg)!.width, f.pixelWidth);
      }
    });

    test('chart labels read as text stay with the chart, and tables and boxed paragraphs stay text', () {
      final (page, layout) = wordTestPage(21);
      // As ML Kit reads it on a phone: the chart's title and axis labels as lines.
      OcrBlock label(String t, double l, double top, double r, double b) => OcrBlock(
        text: t,
        left: l,
        top: top,
        right: r,
        bottom: b,
        lines: [OcrLine(text: t, left: l, top: top, right: r, bottom: b)],
      );
      final read = OcrLayout([
        ...layout.blocks,
        label('Sample bar chart (PNG image)', 0.43, 0.158, 0.53, 0.164),
        for (var i = 0; i < 6; i++) label('Q${i + 1}', 0.305 + i * 0.073, 0.343, 0.32 + i * 0.073, 0.35),
      ]);
      final figures = ocrWordFigures(page, text: read.text, layout: read);
      expect(figures, hasLength(5));
      expect(figures.first.top, lessThan(0.158));
      expect(figures.first.bottom, greaterThan(0.35));
      // The labels are in the picture, so not repeated as text.
      final doc = buildOcrWordDocument([OcrWordPage(text: read.text, layout: read, figures: figures)]);
      final text = doc.sections.single.blocks
          .whereType<WordParagraph>()
          .expand((p) => p.inlines)
          .whereType<WordText>()
          .map((t) => t.text)
          .join(' ');
      expect(text, isNot(contains('Sample bar chart')));
      expect(text, contains('Text wrapping styles'));
      // Pages of tables, shaded rows and boxed paragraphs have no pictures.
      for (final n in [12, 17, 18, 19]) {
        final (p, l) = wordTestPage(n);
        expect(
          ocrWordFigures(p, text: l.text, layout: l),
          isEmpty,
          reason: 'page $n',
        );
      }
    });

    test('a page border and ruled lines are not pictures', () {
      for (final n in [32, 33]) {
        final (page, layout) = wordTestPage(n);
        expect(
          ocrWordFigures(page, text: layout.text, layout: layout),
          isEmpty,
          reason: 'page $n',
        );
      }
    });

    test('a page with no text goes in whole; text with no layout gets none', () {
      final (page, _) = wordTestPage(21);
      final whole = ocrWordFigures(page, text: '');
      expect(whole, hasLength(1));
      expect(whole.single.top, 0);
      expect(whole.single.bottom, 1);
      expect(ocrWordFigures(page, text: 'Some text'), isEmpty);
    });

    test('each picture goes in between the text above and below it', () {
      final layout = OcrLayout([_block('Above the picture', 0.1, 0.13), _block('Below the picture', 0.6, 0.63)]);
      final doc = buildOcrWordDocument([
        OcrWordPage(text: layout.text, layout: layout, figures: [_figure(0.2, 0.5)]),
      ]);
      final blocks = doc.sections.single.blocks.cast<WordParagraph>();
      String kind(WordParagraph p) => p.inlines.any((i) => i is WordPicture)
          ? 'picture'
          : p.inlines.whereType<WordText>().map((t) => t.text).join();
      expect(blocks.map(kind), ['Above the picture', 'picture', 'Below the picture']);
      final picture = blocks[1].inlines.single as WordPicture;
      // 60% of the page width, keeping the cut-out's shape.
      expect(picture.width, closeTo(595.3 * 0.6, 1));
      expect(picture.height, closeTo(picture.width / 2, 1));
    });

    test('a picture wider than the text area is shrunk to fit, and survives a save', () {
      final layout = OcrLayout([_block('Text', 0.1, 0.13)]);
      final bytes = buildOcrWordFile([
        OcrWordPage(text: layout.text, layout: layout, figures: [_figure(0.3, 0.9, left: 0, right: 1)]),
      ]);
      final read = WordReader.read(bytes);
      final pictures = [
        for (final b in read.sections.expand((s) => s.blocks).whereType<WordParagraph>())
          ...b.inlines.whereType<WordPicture>(),
      ];
      expect(pictures, hasLength(1));
      expect(pictures.single.width, lessThanOrEqualTo(595.3 - 2 * 54 + 0.5));
    });

    test('a scanned page with no text becomes one picture in the Word file', () {
      final doc = buildOcrWordDocument([
        OcrWordPage(text: '', figures: [_figure(0, 1, left: 0, right: 1)]),
      ]);
      final blocks = doc.sections.single.blocks.cast<WordParagraph>();
      expect(blocks, hasLength(1));
      expect(blocks.single.inlines.single, isA<WordPicture>());
    });

    test('the cut-out keeps where it sat across the page', () {
      final image = img.Image(width: 200, height: 400, numChannels: 3)..clear(img.ColorRgb8(255, 255, 255));
      img.fillRect(image, x1: 100, y1: 150, x2: 180, y2: 250, color: img.ColorRgb8(20, 40, 160));
      final f = findFigures(RgbImage.fromImage(image), [(0.0, 0.3), (0.7, 1.0)]).single;
      expect(f.left, closeTo(0.49, 0.02));
      expect(f.right, closeTo(0.91, 0.02));
      expect(f.bottom, closeTo(0.63, 0.02));
    });
  });

  group('page jobs', () {
    test('results come back in page order, with progress for each', () async {
      final seen = <int>[];
      final out = await runPageJobs([3, 1, 2, 5, 4], (int n) => n * 10, onProgress: (done, _) => seen.add(done));
      expect(out, [30, 10, 20, 50, 40]);
      expect(seen, [1, 2, 3, 4, 5]);
    });

    test('stopping before the next page throws and gives no result', () async {
      var stop = false;
      final future = runPageJobs(
        List.generate(6, (i) => i),
        (int n) => n,
        onProgress: (done, _) => stop = done >= 2,
        isCancelled: () => stop,
        concurrency: 1,
      );
      await expectLater(future, throwsA(isA<PageJobsCancelled>()));
    });

    test('a stopped text PDF writes no file', () async {
      final tmp = Directory.systemTemp.createTempSync('lumascan_ocrpdf_stop');
      addTearDown(() => deleteTemp(tmp));
      final (page, layout) = wordTestPage(1);
      final pages = [for (var i = 1; i <= 3; i++) OcrPdfPage(page: page, number: i, text: layout.text, layout: layout)];
      var stop = false;
      await expectLater(
        OcrPdfBuilder(PageStore(rootDir: () async => tmp))
            .build(pages, keepLayout: true, onProgress: (done, _) => stop = true, isCancelled: () => stop),
        throwsA(isA<PageJobsCancelled>()),
      );
      final pdfs = tmp.listSync(recursive: true).where((e) => e.path.endsWith('.pdf'));
      expect(pdfs, isEmpty);
    });
  });

  group('progress dialog', () {
    Future<BuildContext> pump(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const Scaffold();
            },
          ),
        ),
      );
      return ctx;
    }

    testWidgets('shows the page it is on and closes when done', (tester) async {
      final context = await pump(tester);
      final gate = Completer<String>();
      WorkProgress? seen;
      final result = runWithProgress(
        context,
        title: 'Creating text PDF',
        task: (progress) {
          seen = progress;
          return gate.future;
        },
      );
      await tester.pump();
      expect(find.text('Creating text PDF'), findsOneWidget);
      seen!.report(2, 35);
      await tester.pump();
      expect(find.text('Page 3 of 35'), findsOneWidget);
      gate.complete('made');
      await tester.pumpAndSettle();
      expect(await result, 'made');
      expect(find.text('Creating text PDF'), findsNothing);
    });

    testWidgets('Cancel closes it at once and drops the late result', (tester) async {
      final context = await pump(tester);
      final gate = Completer<String>();
      WorkProgress? seen;
      final result = runWithProgress(
        context,
        title: 'Creating Word file',
        task: (progress) {
          seen = progress;
          return gate.future;
        },
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('work-progress-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Creating Word file'), findsNothing);
      expect(seen!.cancelled, isTrue);
      gate.complete('late');
      expect(await result, isNull);
    });

    testWidgets('an error after Cancel is not shown as a failure', (tester) async {
      final context = await pump(tester);
      final gate = Completer<String>();
      final result = runWithProgress(context, title: 'Creating text PDF', task: (_) => gate.future);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('work-progress-cancel')));
      await tester.pumpAndSettle();
      gate.completeError(const PageJobsCancelled());
      expect(await result, isNull);
    });
  });
}
