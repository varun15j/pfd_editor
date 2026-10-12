import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/export/word/docx_reader.dart';
import 'package:lumascan/export/word/docx_to_pdf.dart';
import 'package:lumascan/export/word/docx_writer.dart';
import 'package:lumascan/export/word/word_service.dart';
import 'package:lumascan/pdf_edit/pdf_saver.dart';
import 'package:path/path.dart' as p;

Uint8List _jpeg(int width, int height, int shade) =>
    img.encodeJpg(img.Image(width: width, height: height)..clear(img.ColorRgb8(shade, shade, shade)));

/// A .docx with the given body XML and page size, built by hand so the test
/// reads text the way Word writes it.
Uint8List _docx(String body) {
  const ns =
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'word/document.xml',
        '<?xml version="1.0"?><w:document $ns><w:body>$body</w:body></w:document>',
      ),
    );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

const _letterSect =
    '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
    '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="0" w:footer="0" w:gutter="0"/></w:sectPr>';

class _FakeRasterizer implements PdfRasterizer {
  _FakeRasterizer(this.pageCount);

  final int pageCount;

  @override
  Stream<RasterPage> renderPages(
    String path,
    List<int> pageNumbers, {
    required int longEdge,
    required int jpegQuality,
    String? password,
  }) async* {
    for (var i = 0; i < pageCount; i++) {
      yield RasterPage(_jpeg(300, 400, 200 - i * 10), 300, 400, widthPt: 612, heightPt: 792);
    }
  }
}

void main() {
  group('Word file writer and reader', () {
    test('each picture is one page, and its page size and picture survive a round trip', () {
      final first = _jpeg(120, 160, 230);
      final bytes = DocxWriter.build([
        DocxPage(jpeg: first, imageWidth: 120, imageHeight: 160, pageWidthPt: 595, pageHeightPt: 842),
        DocxPage(jpeg: _jpeg(160, 120, 90), imageWidth: 160, imageHeight: 120, pageWidthPt: 792, pageHeightPt: 612),
      ]);

      final doc = DocxReader.parse(bytes);
      expect(doc.sections, hasLength(2));
      final portrait = doc.sections[0];
      final landscape = doc.sections[1];
      expect(portrait.pageWidthPt, closeTo(595, 0.1));
      expect(portrait.pageHeightPt, closeTo(842, 0.1));
      expect(landscape.pageWidthPt, closeTo(792, 0.1));
      expect(landscape.pageHeightPt, closeTo(612, 0.1));

      final picture = portrait.blocks.single as DocxPicture;
      expect(picture.bytes, first);
      // Fitted inside the margins: no wider than the page, and kept in shape.
      final maxW = portrait.pageWidthPt - DocxWriter.marginPt * 2;
      expect(picture.widthPt, lessThanOrEqualTo(maxW + 0.1));
      expect(picture.widthPt / picture.heightPt, closeTo(120 / 160, 0.01));
    });

    test('a word file that is not a zip or has no body is refused', () {
      expect(() => DocxReader.parse(Uint8List.fromList([1, 2, 3])), throwsFormatException);
      final noBody = Uint8List.fromList(
        ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.string('readme.txt', 'hi'))),
      );
      expect(() => DocxReader.parse(noBody), throwsFormatException);
    });

    test('text paragraphs and their bold runs are read in order, with the section size', () {
      final doc = DocxReader.parse(
        _docx(
          '<w:p><w:r><w:t>Hello</w:t></w:r><w:r><w:t xml:space="preserve"> world</w:t></w:r></w:p>'
          '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Second</w:t></w:r></w:p>'
          '$_letterSect',
        ),
      );
      expect(doc.sections, hasLength(1));
      final section = doc.sections.single;
      expect(section.pageWidthPt, 612);
      expect(section.pageHeightPt, 792);
      expect(section.margins.left, 72);
      final texts = section.blocks.cast<DocxText>();
      expect(texts.map((t) => t.text), ['Hello world', 'Second']);
      expect(texts.map((t) => t.bold), [false, true]);
    });
  });

  group('Word to PDF', () {
    test('a text document becomes a PDF with one page per section', () async {
      final doc = DocxReader.parse(_docx('<w:p><w:r><w:t>Invoice</w:t></w:r></w:p>$_letterSect'));
      final pdf = await DocxToPdf.build(doc, title: 'Invoice');
      expect(pdf.pageCount, 1);
      expect(String.fromCharCodes(pdf.bytes.take(5)), '%PDF-');
    });

    test('pictures on separate pages stay on separate pages', () async {
      final bytes = DocxWriter.build([
        for (var i = 0; i < 3; i++)
          DocxPage(
            jpeg: _jpeg(100, 140, 200 - i * 40),
            imageWidth: 100,
            imageHeight: 140,
            pageWidthPt: 595,
            pageHeightPt: 842,
          ),
      ]);
      final pdf = await DocxToPdf.build(DocxReader.parse(bytes));
      expect(pdf.pageCount, 3);
    });
  });

  group('WordService', () {
    late Directory tmp;
    late PageStore store;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lumascan_word');
      store = PageStore(rootDir: () async => tmp);
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    test('a saved PDF becomes a Word file with one picture per page, and back again', () async {
      final service = WordService(store, _FakeRasterizer(2));
      final progress = <double>[];
      final pdfPath = p.join(tmp.path, 'source.pdf');
      File(pdfPath).writeAsBytesSync([0x25, 0x50, 0x44, 0x46]);

      final docx = await service.pdfToWord(pdfPath, pageCount: 2, name: 'Lease', onProgress: progress.add);
      expect(p.basename(docx.path), 'Lease.docx');
      expect(p.basename(docx.parent.path), 'exports');
      expect(progress.last, 1);
      expect(DocxReader.parse(docx.readAsBytesSync()).sections, hasLength(2));

      final back = await service.wordToPdf(docx.path, name: 'Lease');
      expect(p.basename(back.file.path), 'Lease.pdf');
      expect(back.pageCount, 2);
      expect(back.file.existsSync(), isTrue);
    });

    test('a second conversion of the same name keeps the first file', () async {
      final service = WordService(store, _FakeRasterizer(1));
      final pdfPath = p.join(tmp.path, 'source.pdf');
      File(pdfPath).writeAsBytesSync([0x25]);
      final first = await service.pdfToWord(pdfPath, pageCount: 1, name: 'Bills');
      final second = await service.pdfToWord(pdfPath, pageCount: 1, name: 'Bills');
      expect(first.path, isNot(second.path));
      expect(first.existsSync(), isTrue);
    });

    test('a file that is not a Word document is refused before anything is saved', () async {
      final bad = File(p.join(tmp.path, 'bad.docx'))..writeAsBytesSync([1, 2, 3]);
      await expectLater(WordService(store, _FakeRasterizer(1)).wordToPdf(bad.path, name: 'bad'), throwsFormatException);
      expect(
        Directory(p.join(tmp.path, 'exports')).existsSync() &&
            Directory(p.join(tmp.path, 'exports')).listSync().isNotEmpty,
        isFalse,
      );
    });
  });
}
