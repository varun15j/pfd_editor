import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/ocr.dart';
import 'package:lumascan/export/text_pdf_service.dart';
import 'package:lumascan/pdf_edit/pdf_saver.dart';

class _Pages implements PdfRasterizer {
  _Pages(this.jpeg);
  final Uint8List jpeg;

  @override
  Stream<RasterPage> renderPages(
    String path,
    List<int> pageNumbers, {
    required int longEdge,
    required int jpegQuality,
    String? password,
  }) async* {
    for (final _ in pageNumbers) {
      yield RasterPage(jpeg, 200, 300);
    }
  }
}

/// Reads the second page as "Total 42" and fails on the others.
class _Ocr implements OcrEngine, OcrLayoutEngine {
  final seen = <String>[];

  @override
  Future<OcrCapability> capability(String languageCode) async =>
      const OcrCapability(readiness: OcrReadiness.ready, language: 'English');

  @override
  Future<void> prepare(String languageCode) async {}

  @override
  Future<OcrLayout> recognizeLayout(ScanPage page, {required String languageCode}) async {
    seen.add(page.id);
    if (page.id != 'p1') throw StateError('unreadable');
    return const OcrLayout([OcrBlock(text: 'Total 42', left: 0, top: 0, right: 1, bottom: 0.2)]);
  }

  @override
  Future<String> recognize(ScanPage page, {required String languageCode}) async => '';

  @override
  Future<String> recognizeFile(String path) async => '';
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('lumascan_textpdf_svc'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a saved PDF is rendered, read, and unreadable pages are kept as images', () async {
    final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 200, height: 300)..clear(img.ColorRgb8(250, 250, 250))),
    );
    final ocr = _Ocr();
    final service = TextPdfService(PageStore(rootDir: () async => tmp), ocr, _Pages(jpeg));
    final progress = <double>[];

    final made = await service.fromPdf(
      '/any.pdf',
      pageCount: 3,
      fileName: TextPdfService.textName('Scan'),
      onProgress: progress.add,
    );

    expect(ocr.seen, ['p0', 'p1', 'p2']);
    expect(made.pageCount, 3, reason: 'one PDF page for each scanned page here');
    expect(made.file.path, endsWith('Scan (text).pdf'));
    expect(String.fromCharCodes(made.file.readAsBytesSync().take(5)), '%PDF-');
    expect(progress.last, closeTo(1, 1e-9));
    expect(progress, orderedEquals([...progress]..sort()), reason: 'progress only moves forward');
  });

  test('fails when no page can be read', () async {
    final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 20, height: 30)));
    final service = TextPdfService(PageStore(rootDir: () async => tmp), _AllFail(), _Pages(jpeg));
    expect(service.fromPdf('/any.pdf', pageCount: 2, fileName: 'x.pdf'), throwsA(isA<StateError>()));
  });

  test('text names carry (text) and one .pdf', () {
    expect(TextPdfService.textName('Lease'), 'Lease (text).pdf');
    expect(TextPdfService.textName('Lease.pdf'), 'Lease (text).pdf');
  });
}

class _AllFail extends _Ocr {
  @override
  Future<OcrLayout> recognizeLayout(ScanPage page, {required String languageCode}) => throw StateError('no');
}
