import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/ocr.dart';
import 'package:lumascan/export/ocr_pdf_builder.dart';

/// Line boxes per sample photo, read with tesseract (see the fixture's
/// note in the PR): fractions of the photo's width and height. They stand in
/// for ML Kit's boxes, which only run on a phone.
Map<String, List<OcrLine>> _fixtures() {
  final json = jsonDecode(File('test/fixtures/ocr_lines_samples.json').readAsStringSync()) as Map<String, Object?>;
  return {
    for (final e in json.entries)
      e.key: [
        for (final l in e.value! as List<Object?>)
          OcrLine(
            text: (l as Map)['text'] as String,
            left: (l['left'] as num).toDouble(),
            top: (l['top'] as num).toDouble(),
            right: (l['right'] as num).toDouble(),
            bottom: (l['bottom'] as num).toDouble(),
          ),
      ],
  };
}

OcrPdfPage _pageFor(String path, List<OcrLine> lines) => OcrPdfPage(
  page: ScanPage(id: path, originalPath: path),
  number: 1,
  text: lines.map((l) => l.text).join('\n'),
  layout: OcrLayout([
    for (final l in lines) OcrBlock(text: l.text, left: l.left, top: l.top, right: l.right, bottom: l.bottom, lines: [l]),
  ]),
);

void main() {
  final fixtures = _fixtures();

  test('the fixtures cover every sample photo, the book sets included', () {
    expect(fixtures.keys.where((k) => k.contains('sample_photos/book/')), hasLength(20));
    expect(fixtures.keys.where((k) => k.contains('sample_photos/odds_book/')), hasLength(6));
    expect(fixtures.keys.where((k) => !k.contains('book/')), hasLength(5));
  });

  group('keepLayout places every line on its detected box, over the page', () {
    for (final path in fixtures.keys) {
      test(path, () {
        final lines = fixtures[path]!;
        final draft = pageDraft(_pageFor(path, lines), keepLayout: true);
        final texts = draft.pieces.whereType<TextPiece>().toList();
        final pictures = draft.pieces.whereType<ImagePiece>().toList();

        expect(texts, hasLength(lines.length));
        for (final (i, piece) in texts.indexed) {
          expect(piece.text, lines[i].text);
          expect(piece.left, lines[i].left);
          expect(piece.top, lines[i].top);
          expect(piece.right, lines[i].right);
          expect(piece.bottom, lines[i].bottom);
        }

        // The page itself is the background, and it covers the whole page.
        expect(pictures, hasLength(1));
        expect([pictures.single.left, pictures.single.top, pictures.single.right, pictures.single.bottom], [0, 0, 1, 1]);
        expect(draft.pieces.first, pictures.single);
      });
    }
  });

  test('without keepLayout the text still flows in reading order, as in Basic', () {
    final path = fixtures.keys.first;
    final draft = pageDraft(_pageFor(path, fixtures[path]!));
    final tops = draft.pieces.whereType<TextPiece>().map((t) => t.top).toList();
    expect(tops, [...tops]..sort());
  });

  test('a keep-layout PDF of a book page is one page with the text and its picture', () async {
    final path = fixtures.keys.firstWhere((k) => k.endsWith('05_bend_a_straw.jpg'));
    final tmp = Directory.systemTemp.createTempSync('lumascan_placed');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final out = await OcrPdfBuilder(PageStore(rootDir: () async => tmp))
        .build([_pageFor(path, fixtures[path]!)], fileName: 'placed.pdf', keepLayout: true);
    expect(out.pageCount, 1);
    final bytes = out.file.readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // The text layer is fully transparent, so the photo shows unchanged.
    expect(latin1.decode(bytes), contains('/ca 0'));
  });

  test('without keepLayout the text is not made transparent, as in Basic', () async {
    final path = fixtures.keys.firstWhere((k) => k.endsWith('05_bend_a_straw.jpg'));
    final tmp = Directory.systemTemp.createTempSync('lumascan_flow');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final out = await OcrPdfBuilder(PageStore(rootDir: () async => tmp))
        .build([_pageFor(path, fixtures[path]!)], fileName: 'flow.pdf');
    expect(latin1.decode(out.file.readAsBytesSync()), isNot(contains('/ca 0')));
  });
}
