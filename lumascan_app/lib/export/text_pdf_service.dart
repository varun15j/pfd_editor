import 'dart:io';

import '../data/page_store.dart';
import '../domain/models.dart';
import '../domain/ocr.dart';
import '../features/batch_edit/batch_ocr_job.dart';
import '../pdf_edit/pdf_saver.dart';
import 'ocr_pdf_builder.dart';

/// Makes a text PDF: every page is read with OCR and the text goes into a
/// new PDF, with the parts that were not read kept as images. A page that
/// could not be read at all goes in as an image, so nothing is lost.
class TextPdfService {
  TextPdfService(this._store, this._ocr, this._rasterizer);

  final PageStore _store;
  final OcrEngine _ocr;
  final PdfRasterizer _rasterizer;

  /// Longest side of a PDF page when it is rendered to be read.
  static const readSize = 2000;

  /// "Lease (text).pdf" for "Lease".
  static String textName(String name) {
    final stem = name.toLowerCase().endsWith('.pdf') ? name.substring(0, name.length - 4) : name;
    return PdfEditSaver.safeFileName('$stem (text)');
  }

  /// Reads [pages] and saves the text PDF as [fileName]. Progress counts
  /// each page read, then the PDF being built.
  Future<OcrPdfFile> fromPages(
    List<ScanPage> pages, {
    required String fileName,
    String languageCode = 'en',
    void Function(double fraction)? onProgress,
  }) async {
    if (pages.isEmpty) throw ArgumentError('No pages to read');
    final capability = await _ocr.capability(languageCode);
    if (capability.readiness == OcrReadiness.needsDownload) await _ocr.prepare(languageCode);
    if (capability.readiness == OcrReadiness.unavailable) {
      throw UnsupportedError(capability.reason ?? 'Text recognition is not available.');
    }
    final snapshot = List<ScanPage>.unmodifiable(pages);
    final job = BatchOcrJob(engine: _ocr, pages: snapshot, languageCode: languageCode);
    // Reading is most of the work: 90%, the PDF build the rest.
    job.addListener(() => onProgress?.call(job.finished / snapshot.length * 0.9));
    try {
      await job.start();
    } finally {
      job.dispose();
    }
    final read = job.results;
    if (read.every((r) => r.status == OcrPageStatus.failed || r.status == OcrPageStatus.cancelled)) {
      throw StateError('No page could be read.');
    }
    return OcrPdfBuilder(_store).build(
      [
        for (final (i, r) in read.indexed)
          OcrPdfPage(page: snapshot[i], number: i + 1, text: r.text ?? '', layout: r.layout),
      ],
      fileName: fileName,
      onProgress: (done, total) => onProgress?.call(0.9 + 0.1 * done / total),
    );
  }

  /// Reads a saved PDF (a scan, or any PDF of photos): its pages are
  /// rendered to pictures first, since there is no text in them to take.
  Future<OcrPdfFile> fromPdf(
    String sourcePath, {
    required int pageCount,
    required String fileName,
    String languageCode = 'en',
    void Function(double fraction)? onProgress,
  }) async {
    if (pageCount <= 0) throw ArgumentError('No pages to read');
    final temp = await Directory.systemTemp.createTemp('lumascan_textpdf');
    try {
      final pages = <ScanPage>[];
      final rasters = _rasterizer.renderPages(
        sourcePath,
        [for (var i = 1; i <= pageCount; i++) i],
        longEdge: readSize,
        jpegQuality: 85,
      );
      await for (final r in rasters) {
        final file = File('${temp.path}/p${pages.length}.jpg');
        await file.writeAsBytes(r.jpeg, flush: true);
        pages.add(ScanPage(id: 'p${pages.length}', originalPath: file.path));
        // Rendering the pages is a tenth of the work.
        onProgress?.call(pages.length / pageCount * 0.1);
      }
      return await fromPages(
        pages,
        fileName: fileName,
        languageCode: languageCode,
        onProgress: onProgress == null ? null : (f) => onProgress(0.1 + f * 0.9),
      );
    } finally {
      await temp.delete(recursive: true);
    }
  }
}
