import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import '../../data/page_store.dart';
import '../../pdf_edit/pdf_saver.dart';
import 'docx_reader.dart';
import 'docx_to_pdf.dart';
import 'docx_writer.dart';

/// A PDF made from a Word file, saved in the exports folder.
class WordPdfFile {
  const WordPdfFile(this.file, this.pageCount);

  final File file;
  final int pageCount;
}

/// Converts between PDFs and Word (.docx) files. A PDF becomes a Word file
/// with each page as a full-size picture, so it looks the same in Word, but
/// its text is not editable. A Word file becomes a PDF with its text and
/// pictures laid out on the same page sizes.
class WordService {
  WordService(this._store, this._rasterizer);

  final PageStore _store;
  final PdfRasterizer _rasterizer;

  /// Longest side of each page picture in a Word file. 2400 px is about
  /// 200 dpi on A4.
  static const pictureSize = 2400;
  static const pictureQuality = 85;

  /// Portrait A4's long side in points, used when a page does not state its size.
  static const _a4LongSidePt = 842.0;

  /// Converts a saved PDF of [pageCount] pages to a Word file named after
  /// [name]. [onProgress] reports 0 to 1.
  Future<File> pdfToWord(
    String pdfPath, {
    required int pageCount,
    required String name,
    void Function(double fraction)? onProgress,
  }) async {
    if (pageCount <= 0) throw ArgumentError('No pages to convert');
    final pages = <DocxPage>[];
    final rasters = _rasterizer.renderPages(
      pdfPath,
      [for (var n = 1; n <= pageCount; n++) n],
      longEdge: pictureSize,
      jpegQuality: pictureQuality,
    );
    await for (final r in rasters) {
      final scale = _a4LongSidePt / math.max(r.width, r.height);
      pages.add(
        DocxPage(
          jpeg: r.jpeg,
          imageWidth: r.width,
          imageHeight: r.height,
          pageWidthPt: r.widthPt ?? r.width * scale,
          pageHeightPt: r.heightPt ?? r.height * scale,
        ),
      );
      // Rendering the pages is most of the work.
      onProgress?.call(pages.length / pageCount * 0.9);
    }
    if (pages.isEmpty) throw StateError('No page could be read.');
    final bytes = await Isolate.run(() => DocxWriter.build(pages));
    onProgress?.call(0.95);
    final file = await _store.writeExportAtomically(await _store.freeExportName(_wordName(name)), bytes);
    onProgress?.call(1);
    return file;
  }

  /// Converts the Word file at [docxPath] to a PDF saved as [name].pdf.
  /// Throws [FormatException] when the file is not a readable Word document.
  Future<WordPdfFile> wordToPdf(String docxPath, {required String name}) async {
    final bytes = await File(docxPath).readAsBytes();
    final document = await Isolate.run(() => DocxReader.parse(bytes));
    final pdf = await Isolate.run(() => DocxToPdf.build(document, title: _stem(name)));
    if (pdf.pageCount == 0) throw const FormatException('The Word document has no pages.');
    final fileName = await _store.freeExportName(PdfEditSaver.safeFileName(name));
    final file = await _store.writeExportAtomically(fileName, pdf.bytes);
    return WordPdfFile(file, pdf.pageCount);
  }

  /// "Lease.docx" for "Lease", with characters a file name cannot hold replaced.
  static String _wordName(String name) => '${_stem(name)}.docx';

  static String _stem(String name) {
    final pdfName = PdfEditSaver.safeFileName(name);
    return pdfName.substring(0, pdfName.length - '.pdf'.length);
  }
}
