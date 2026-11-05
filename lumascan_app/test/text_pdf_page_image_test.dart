import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/ocr.dart';
import 'package:lumascan/export/ocr_pdf_builder.dart';
import 'package:lumascan/features/ocr_word/ocr_word_figure.dart';
import 'package:lumascan/imaging/page_jobs.dart';
import 'package:lumascan/imaging/page_renderer.dart';

import 'support/pdf_content.dart';
import 'support/temp_dir.dart';
import 'support/word_pages.dart';

/// The page image text recognition read, as the render service keeps it:
/// the page drawn once at the working size and saved as a JPEG.
RenderedImage _ocrImage(ScanPage page, Directory dir) {
  final image = renderRecipe(File(page.originalPath).readAsBytesSync(), page.recipe, maxDimension: 1600);
  final path = '${dir.path}/${page.id}_ocr.jpg';
  File(path).writeAsBytesSync(image.encodeJpg(quality: 85));
  return RenderedImage(path, image.width, image.height);
}

/// [page] with a photo that is not there: building from it fails if the
/// photo is read again.
ScanPage _withoutPhoto(ScanPage page) => ScanPage(id: page.id, originalPath: '/no/such/photo_${page.id}.jpg');

bool _contains(Uint8List haystack, Uint8List needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('lumascan_textpdf_image'));
  tearDown(() => deleteTemp(tmp));

  test('the page image text recognition read goes into the PDF as it is; the photo is not drawn again', () async {
    final (page, layout) = wordTestPage(1);
    final ocrImage = _ocrImage(page, tmp);
    final out = await OcrPdfBuilder(PageStore(rootDir: () async => tmp), pageImage: (_) async => ocrImage).build(
      [OcrPdfPage(page: _withoutPhoto(page), number: 1, text: layout.text, layout: layout)],
      keepLayout: true,
      fileName: 'x.pdf',
    );
    final pdf = out.file.readAsBytesSync();
    // The very same JPEG bytes are in the PDF: no decode, no new encode.
    final jpeg = File(ocrImage.path).readAsBytesSync();
    expect(_contains(pdf, jpeg.sublist(jpeg.length ~/ 2, jpeg.length ~/ 2 + 4096)), isTrue);
  });

  test('the text sits over the photo as invisible PDF text (render mode 3) that PDF apps find and copy', () async {
    final (page, layout) = wordTestPage(1);
    final out = await OcrPdfBuilder(PageStore(rootDir: () async => tmp), pageImage: (_) async => _ocrImage(page, tmp))
        .build(
          [OcrPdfPage(page: page, number: 1, text: layout.text, layout: layout)],
          keepLayout: true,
          fileName: 'x.pdf',
        );
    final content = pdfContentText(out.file.readAsBytesSync());
    expect(content, contains('3 Tr'));
    // Every line of the page is in the text layer.
    final firstLine = layout.blocks.first.lines.first.text;
    expect(content, contains(firstLine.split(' ').first));
    expect(
      RegExp(r'Tj|TJ').allMatches(content).length,
      greaterThanOrEqualTo(layout.blocks.expand((b) => b.lines).length),
    );
    // Nothing is drawn see-through on top of the photo.
    expect(String.fromCharCodes(out.file.readAsBytesSync()), isNot(contains('/ca 0')));
  });

  test('a page whose image cannot be had is drawn from the photo instead', () async {
    final (page, layout) = wordTestPage(1);
    final out =
        await OcrPdfBuilder(
          PageStore(rootDir: () async => tmp),
          pageImage: (_) async => throw StateError('render failed'),
        ).build(
          [OcrPdfPage(page: page, number: 1, text: layout.text, layout: layout)],
          keepLayout: true,
          fileName: 'x.pdf',
        );
    expect(out.pageCount, 1);
    expect(String.fromCharCodes(out.file.readAsBytesSync()), contains('DCTDecode'));
  });

  test('flowing text: a picture taller than a page is shrunk to fit instead of failing the PDF', () async {
    // A tall page: one short line at the top, then a long drawing below it.
    final photo = img.Image(width: 500, height: 4000)..clear(img.ColorRgb8(250, 250, 250));
    for (var y = 200; y < 3900; y += 40) {
      img.fillRect(photo, x1: 40, y1: y, x2: 460, y2: y + 25, color: img.ColorRgb8(30, 90, 160));
    }
    final file = File('${tmp.path}/tall.jpg')..writeAsBytesSync(img.encodeJpg(photo));
    final page = ScanPage(id: 'tall', originalPath: file.path);
    final layout = OcrLayout(const [
      OcrBlock(
        text: 'More than lemonade',
        left: 0.1,
        top: 0.005,
        right: 0.9,
        bottom: 0.03,
        lines: [OcrLine(text: 'More than lemonade', left: 0.1, top: 0.005, right: 0.9, bottom: 0.03)],
      ),
    ]);
    final out = await OcrPdfBuilder(PageStore(rootDir: () async => tmp))
        .build([OcrPdfPage(page: page, number: 1, text: layout.text, layout: layout)], fileName: 'x.pdf');
    expect(out.pageCount, greaterThanOrEqualTo(1));
  });

  test('Word pictures are cut from the page image text recognition read, not from the photo', () {
    final (page, layout) = wordTestPage(21);
    final fromPhoto = ocrWordFigures(page, text: layout.text, layout: layout);
    final fromImage = ocrWordFigures(
      _withoutPhoto(page),
      text: layout.text,
      layout: layout,
      image: _ocrImage(page, tmp),
    );
    expect(fromImage, isNotEmpty);
    expect(fromImage.length, fromPhoto.length);
    for (final (i, f) in fromImage.indexed) {
      expect(f.top, closeTo(fromPhoto[i].top, 0.01));
      expect(f.bottom, closeTo(fromPhoto[i].bottom, 0.01));
    }
  });

  test('a Word page with no text takes the page image whole, as it is', () {
    final (page, _) = wordTestPage(21);
    final ocrImage = _ocrImage(page, tmp);
    final figures = ocrWordFigures(_withoutPhoto(page), text: '', image: ocrImage);
    expect(figures, hasLength(1));
    expect(figures.single.jpeg, File(ocrImage.path).readAsBytesSync());
    expect((figures.single.pixelWidth, figures.single.pixelHeight), (ocrImage.width, ocrImage.height));
  });

  group('the screen\'s progress and Cancel checks stay on the main isolate', () {
    // On the device the Cancel check and progress closures hold the
    // screen's State, which holds Futures, and an isolate cannot be sent a
    // Future. These stand in for them: if a page job's closure captures
    // them, Isolate.run fails with "object is unsendable".
    late Future<void> unsendable;
    setUp(() {
      unsendable = Completer<void>().future;
    });
    bool cancelled() {
      unsendable.ignore();
      return false;
    }

    void progress(int done, int total) => unsendable.ignore();

    test('Create text PDF', () async {
      final (page, layout) = wordTestPage(1);
      for (final keepLayout in [true, false]) {
        final out =
            await OcrPdfBuilder(
              PageStore(rootDir: () async => tmp),
              pageImage: (_) async => _ocrImage(page, tmp),
            ).build(
              [OcrPdfPage(page: page, number: 1, text: layout.text, layout: layout)],
              keepLayout: keepLayout,
              fileName: 'x$keepLayout.pdf',
              onProgress: progress,
              isCancelled: cancelled,
            );
        expect(out.pageCount, greaterThanOrEqualTo(1));
      }
    });

    test('Create Word file', () async {
      final (page, layout) = wordTestPage(21);
      final figures = await runPageJobs(
        [(page: page, text: layout.text, layout: layout, image: _ocrImage(page, tmp))],
        ocrWordFiguresOf,
        onProgress: progress,
        isCancelled: cancelled,
      );
      expect(figures.single, isNotEmpty);
    });
  });
}
