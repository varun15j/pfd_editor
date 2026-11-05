import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/features/open/pdf_file_check.dart';

import 'support/temp_dir.dart';

Uint8List b(String s) => Uint8List.fromList(latin1.encode(s));

const minimalPdf =
    '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
    '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
    '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]>>endobj\n'
    'trailer<</Root 1 0 R>>\n%%EOF\n';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('lumascan_check'));
  tearDown(() => deleteTemp(dir));

  Future<String> write(String name, List<int> bytes) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  Future<OpenFailure?> failure(String path) async {
    try {
      await checkPdfFile(path);
      return null;
    } on DocumentOpenException catch (e) {
      return e.kind;
    }
  }

  test('a small valid PDF passes and ends with %%EOF', () async {
    final facts = await checkPdfFile(await write('ok.pdf', b(minimalPdf)));
    expect(facts.endsWithEof, isTrue);
    expect(facts.size, minimalPdf.length);
  });

  test('a large PDF is checked from its ends only', () async {
    final big = BytesBuilder()
      ..add(b('%PDF-1.7\n'))
      ..add(Uint8List(8 * 1024 * 1024))
      ..add(b('\n%%EOF\n'));
    final facts = await checkPdfFile(await write('big.pdf', big.takeBytes()));
    expect(facts.endsWithEof, isTrue);
  });

  test('junk before the header and after %%EOF is allowed', () async {
    final facts = await checkPdfFile(await write('junk.pdf', b('garbage\n$minimalPdf${'x' * 100}')));
    expect(facts.endsWithEof, isTrue);
  });

  test('a cut-short PDF passes the check but is marked', () async {
    final cut = minimalPdf.substring(0, minimalPdf.length ~/ 2);
    final facts = await checkPdfFile(await write('cut.pdf', b(cut)));
    expect(facts.endsWithEof, isFalse);
    expect(pdfiumFailure(pdfiumErrFormat, facts: facts).kind, OpenFailure.truncated);
  });

  test('junk after the header is damaged, not incomplete', () async {
    final noise = [...latin1.encode('%PDF-1.7\n'), ...List.generate(5000, (i) => (i * 131 + 7) % 256)];
    final facts = await checkPdfFile(await write('garbage.pdf', noise));
    expect(facts.endsWithEof, isFalse);
    expect(facts.looksTruncated, isFalse);
    expect(pdfiumFailure(pdfiumErrFormat, facts: facts).kind, OpenFailure.corrupted);
  });

  test('missing, empty and random files fail with their reason', () async {
    expect(await failure('${dir.path}/nope.pdf'), OpenFailure.missing);
    expect(await failure(await write('empty.pdf', const [])), OpenFailure.empty);
    expect(await failure(await write('noise.pdf', List.generate(5000, (i) => i * 7 % 256))), OpenFailure.wrongFormat);
  });

  test('other formats renamed to .pdf are named in the message', () async {
    Future<String?> detail(List<int> bytes) async {
      try {
        await checkPdfFile(await write('f.pdf', bytes));
        return 'passed';
      } on DocumentOpenException catch (e) {
        return e.message;
      }
    }

    expect(await detail([0xFF, 0xD8, 0xFF, 0xE0, 0, 0]), contains('a JPEG image'));
    expect(await detail([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]), contains('a PNG image'));
    expect(
      await detail([0x50, 0x4B, 0x03, 0x04, ...latin1.encode('....word/document.xml')]),
      contains('a Word document'),
    );
    expect(await detail(latin1.encode('<!DOCTYPE html><html>error</html>')), contains('web page'));
    expect(await detail(latin1.encode('hello')), 'This file is not a PDF, so it cannot be opened here.');
  });

  test('PDFium error codes map to plain messages', () {
    const ended = PdfFileFacts(size: 10, endsWithEof: true);
    expect(pdfiumFailure(pdfiumErrFile).kind, OpenFailure.unreadable);
    expect(pdfiumFailure(pdfiumErrFormat, facts: ended).kind, OpenFailure.corrupted);
    expect(pdfiumFailure(pdfiumErrSecurity).kind, OpenFailure.unsupportedSecurity);
    expect(pdfiumFailure(pdfiumErrPage).kind, OpenFailure.damagedPage);
    expect(pdfiumFailure(1, facts: ended).kind, OpenFailure.corrupted);
  });

  test('every failure has a title and a sentence', () {
    for (final kind in OpenFailure.values) {
      expect(kind.title, isNotEmpty);
      expect(kind.message(null), endsWith('.'));
    }
  });

  test('page sizes that would break layout are rejected', () {
    expect(isUsablePageSize(612, 792), isTrue);
    expect(isUsablePageSize(0, 792), isFalse);
    expect(isUsablePageSize(-1, 792), isFalse);
    expect(isUsablePageSize(double.nan, 792), isFalse);
    expect(isUsablePageSize(612, double.infinity), isFalse);
  });
}
