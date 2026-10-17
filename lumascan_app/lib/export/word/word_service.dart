import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../data/page_store.dart';
import '../../domain/models.dart';
import '../../imaging/page_renderer.dart';
import '../../pdf_edit/pdf_saver.dart';
import 'docx_reader.dart';
import 'docx_to_pdf.dart';
import 'docx_writer.dart';
import 'pdf_text_reader.dart';
import 'word_text_layout.dart';

/// A PDF made from a Word file, saved in the exports folder.
class WordPdfFile {
  const WordPdfFile(this.file, this.pageCount);

  final File file;
  final int pageCount;
}

/// How a Word file came out: how many pages hold editable text and how many
/// are pictures.
class WordFile {
  const WordFile(this.file, {required this.textPages, required this.picturePages});

  final File file;
  final int textPages;
  final int picturePages;
}

/// Converts between PDFs and Word (.docx) files. A PDF page that has text
/// (a text PDF, or a text PDF LumaScan made with OCR) becomes editable Word
/// text; a page that is only a picture becomes one full-size picture on its
/// own Word page. Nothing is read with OCR here: the text comes from the
/// PDF's text layer. A Word file becomes a PDF with its text and pictures
/// laid out on the same page sizes.
class WordService {
  WordService(this._store, this._rasterizer, [this._textReader]);

  final PageStore _store;
  final PdfRasterizer _rasterizer;

  /// Reads the PDF's text layer. Without one every page is a picture.
  final PdfTextReader? _textReader;

  /// Longest side of each page picture in a Word file. 2400 px is about
  /// 200 dpi on A4.
  static const pictureSize = 2400;
  static const pictureQuality = 85;

  /// Portrait A4's long side in points, used when a page does not state its size.
  static const _a4LongSidePt = 842.0;
  static const _a4ShortSidePt = 595.0;

  /// Converts a saved PDF of [pageCount] pages to a Word file named after
  /// [name]. With [editableText] off, every page is a picture, so the Word
  /// file looks exactly like the PDF. [onProgress] reports 0 to 1.
  Future<WordFile> pdfToWord(
    String pdfPath, {
    required int pageCount,
    required String name,
    bool editableText = true,
    String? password,
    void Function(double fraction)? onProgress,
  }) async {
    if (pageCount <= 0) throw ArgumentError('No pages to convert');
    final text = editableText ? await _readText(pdfPath, pageCount, password) : const <PdfPageLines>[];
    onProgress?.call(0.1);
    final paragraphs = [
      for (var i = 0; i < pageCount; i++)
        i < text.length && text[i].characterCount >= WordTextLayout.minCharacters
            ? WordTextLayout.fromLines(text[i])
            : const <DocxParagraph>[],
    ];
    final pictureNumbers = [
      for (var n = 1; n <= pageCount; n++)
        if (paragraphs[n - 1].isEmpty) n,
    ];
    final pictures = <int, DocxPage>{};
    if (pictureNumbers.isNotEmpty) {
      final rasters = _rasterizer.renderPages(
        pdfPath,
        pictureNumbers,
        longEdge: pictureSize,
        jpegQuality: pictureQuality,
        password: password,
      );
      await for (final r in rasters) {
        final scale = _a4LongSidePt / math.max(r.width, r.height);
        pictures[pictureNumbers[pictures.length]] = DocxPage(
          jpeg: r.jpeg,
          imageWidth: r.width,
          imageHeight: r.height,
          pageWidthPt: r.widthPt ?? r.width * scale,
          pageHeightPt: r.heightPt ?? r.height * scale,
        );
        // Rendering the pages is most of the work.
        onProgress?.call(0.1 + pictures.length / pictureNumbers.length * 0.8);
      }
    }
    final pages = <DocxPage>[
      for (var n = 1; n <= pageCount; n++)
        if (paragraphs[n - 1].isNotEmpty)
          DocxPage.text(
            paragraphs: paragraphs[n - 1],
            pageWidthPt: text[n - 1].widthPt,
            pageHeightPt: text[n - 1].heightPt,
          )
        else if (pictures[n] != null)
          pictures[n]!,
    ];
    return _write(pages, name, onProgress);
  }

  /// Converts the pages of a scan to a Word file named after [name]. A page
  /// already read with OCR becomes its text; any other page becomes a
  /// picture with its crop, rotation and filter.
  Future<WordFile> pagesToWord(
    List<ScanPage> scanPages, {
    required String name,
    void Function(double fraction)? onProgress,
  }) async {
    if (scanPages.isEmpty) throw ArgumentError('No pages to convert');
    final temp = await Directory.systemTemp.createTemp('lumascan_word');
    try {
      final pages = <DocxPage>[];
      for (final (i, page) in scanPages.indexed) {
        final text = page.text ?? '';
        if (text.replaceAll(RegExp(r'\s'), '').length >= WordTextLayout.minCharacters) {
          pages.add(
            DocxPage.text(
              paragraphs: WordTextLayout.fromPlainText(text),
              pageWidthPt: _a4ShortSidePt,
              pageHeightPt: _a4LongSidePt,
            ),
          );
        } else {
          final rendered = await renderToFile(
            originalPath: page.originalPath,
            recipe: page.recipe,
            outPath: p.join(temp.path, 'p$i.jpg'),
            maxDimension: pictureSize,
            quality: pictureQuality,
          );
          final w = rendered.width, h = rendered.height;
          final scale = _a4LongSidePt / math.max(w, h);
          pages.add(
            DocxPage(
              jpeg: await File(rendered.path).readAsBytes(),
              imageWidth: w,
              imageHeight: h,
              pageWidthPt: w * scale,
              pageHeightPt: h * scale,
            ),
          );
        }
        onProgress?.call((i + 1) / scanPages.length * 0.9);
      }
      return await _write(pages, name, onProgress);
    } finally {
      await temp.delete(recursive: true);
    }
  }

  Future<List<PdfPageLines>> _readText(String pdfPath, int pageCount, String? password) async {
    final reader = _textReader;
    if (reader == null) return const [];
    try {
      return await reader.readPages(pdfPath, pageCount: pageCount, password: password);
    } on Object {
      // A text layer that cannot be read is not fatal: the pages go in as pictures.
      return const [];
    }
  }

  Future<WordFile> _write(List<DocxPage> pages, String name, void Function(double fraction)? onProgress) async {
    if (pages.isEmpty) throw StateError('No page could be read.');
    final bytes = await Isolate.run(() => DocxWriter.build(pages));
    onProgress?.call(0.95);
    final file = await _store.writeExportAtomically(await _store.freeExportName(_wordName(name)), bytes);
    onProgress?.call(1);
    final textPages = pages.where((p) => p.isText).length;
    return WordFile(file, textPages: textPages, picturePages: pages.length - textPages);
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
