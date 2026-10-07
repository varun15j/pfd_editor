import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/ocr.dart';
import 'package:lumascan/export/ocr_pdf_builder.dart';
import 'package:lumascan/imaging/ocr_figures.dart';
import 'package:lumascan/imaging/rgb_image.dart';

/// White page 200 x 400 with a dark square picture between y 150 and 250.
RgbImage _page({bool picture = true}) {
  final image = img.Image(width: 200, height: 400, numChannels: 3)..clear(img.ColorRgb8(255, 255, 255));
  if (picture) img.fillRect(image, x1: 40, y1: 150, x2: 160, y2: 250, color: img.ColorRgb8(20, 40, 160));
  return RgbImage.fromImage(image);
}

void main() {
  group('findFigures', () {
    test('keeps the picture between two text blocks, cropped to what is on it', () {
      final figures = findFigures(_page(), [(0.0, 0.3), (0.7, 1.0)]);
      expect(figures, hasLength(1));
      expect(figures.single.top, closeTo(0.3, 0.01));
      expect(figures.single.image.width, inInclusiveRange(120, 130));
      expect(figures.single.image.height, inInclusiveRange(100, 110));
    });

    test('ignores blank stretches between text', () {
      expect(findFigures(_page(picture: false), [(0.0, 0.3), (0.7, 1.0)]), isEmpty);
    });

    test('finds a picture below the last text block', () {
      final figures = findFigures(_page(), [(0.0, 0.2)]);
      expect(figures, hasLength(1));
    });
  });

  test('the text PDF holds the text and the picture of each read page', () async {
    final tmp = Directory.systemTemp.createTempSync('lumascan_ocrpdf');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final file = File('${tmp.path}/p.jpg')..writeAsBytesSync(_page().encodeJpg());
    final page = ScanPage(id: 'p', originalPath: file.path);
    final layout = OcrLayout(const [
      OcrBlock(text: 'Heading', left: 0, top: 0, right: 1, bottom: 0.3),
      OcrBlock(text: 'Caption', left: 0, top: 0.7, right: 1, bottom: 1),
    ]);
    final out = await OcrPdfBuilder(PageStore(rootDir: () async => tmp))
        .build([OcrPdfPage(page: page, number: 1, text: layout.text, layout: layout)], fileName: 'x.pdf');
    final bytes = Uint8List.fromList(out.readAsBytesSync());
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // The picture is an embedded JPEG.
    expect(String.fromCharCodes(bytes), contains('DCTDecode'));
  });
}
