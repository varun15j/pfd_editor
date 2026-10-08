import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/page_store.dart';
import '../domain/models.dart';
import '../domain/ocr.dart';
import '../imaging/ocr_figures.dart';
import '../imaging/page_renderer.dart';
import '../imaging/rgb_image.dart';

/// One page for the text PDF: its recipe, what was read and where.
class OcrPdfPage {
  const OcrPdfPage({required this.page, required this.number, required this.text, this.layout});

  final ScanPage page;

  /// Place in the document, counted from 1.
  final int number;
  final String text;
  final OcrLayout? layout;
}

/// The saved text PDF and how many PDF pages it came to (text can run
/// longer than the scanned page it came from).
class OcrPdfFile {
  const OcrPdfFile(this.file, this.pageCount);

  final File file;
  final int pageCount;
}

/// One piece of a page in the PDF, top to bottom.
sealed class _Piece {
  const _Piece(this.top);
  final double top;
}

class _TextPiece extends _Piece {
  const _TextPiece(super.top, this.text);
  final String text;
}

class _ImagePiece extends _Piece {
  const _ImagePiece(super.top, this.jpeg, this.width, this.height);
  final Uint8List jpeg;
  final int width;
  final int height;
}

/// Builds a text PDF from OCR results: the text that was read, in reading
/// order, with the parts of the page that were not read (pictures,
/// drawings) added as images where they sat. A page with no text at all
/// goes in as one image.
class OcrPdfBuilder {
  OcrPdfBuilder(this._store);

  final PageStore _store;

  Future<OcrPdfFile> build(
    List<OcrPdfPage> pages, {
    String? fileName,
    void Function(int done, int total)? onProgress,
  }) async {
    if (pages.isEmpty) throw ArgumentError('No pages to build a PDF from');
    final built = <(int, List<_Piece>)>[];
    for (final (i, p) in pages.indexed) {
      built.add((p.number, await Isolate.run(() => _pieces(p))));
      onProgress?.call(i + 1, pages.length + 1);
    }
    final (bytes, pageCount) = await Isolate.run(() => _document(built));
    onProgress?.call(pages.length + 1, pages.length + 1);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = fileName ?? 'Text_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.pdf';
    return OcrPdfFile(await _store.writeExportAtomically(await _store.freeExportName(name), bytes), pageCount);
  }
}

List<_Piece> _pieces(OcrPdfPage p) {
  final image = renderRecipe(File(p.page.originalPath).readAsBytesSync(), p.page.recipe, maxDimension: 1600);
  final blocks = p.layout?.blocks ?? const <OcrBlock>[];
  if (blocks.isEmpty && p.text.trim().isEmpty) return [_picture(0, image)];
  final pieces = <_Piece>[
    if (blocks.isEmpty) _TextPiece(0, p.text) else for (final b in blocks) _TextPiece(b.top, b.text),
    for (final f in findFigures(image, [for (final b in blocks) (b.top, b.bottom)])) _picture(f.top, f.image),
  ];
  return pieces..sort((a, b) => a.top.compareTo(b.top));
}

_ImagePiece _picture(double top, RgbImage image) =>
    _ImagePiece(top, image.encodeJpg(quality: 80), image.width, image.height);

Future<(Uint8List, int)> _document(List<(int, List<_Piece>)> pages) async {
  final doc = pw.Document(title: 'Recognized text', creator: 'LumaScan');
  for (final (number, pieces) in pages) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (_) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text('Page $number', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ),
        build: (_) => [
          for (final piece in pieces)
            switch (piece) {
              _TextPiece() => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(_printable(piece.text), style: const pw.TextStyle(fontSize: 11, lineSpacing: 2)),
              ),
              _ImagePiece() => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Center(
                  child: pw.Image(pw.MemoryImage(piece.jpeg), fit: pw.BoxFit.contain, width: _imageWidth(piece)),
                ),
              ),
            },
        ],
      ),
    );
  }
  final bytes = await doc.save();
  return (bytes, doc.document.pdfPageList.pages.length);
}

/// The picture's width on the page: its own size at 150 dpi, but never more
/// than the text column.
double _imageWidth(_ImagePiece p) => (p.width * 72 / 150).clamp(60.0, PdfPageFormat.a4.width - 72);

const _swaps = {
  '‘': "'", '’': "'", '“': '"', '”': '"', '–': '-', '—': '-', //
  '•': '·', '…': '...',
};

/// The standard PDF font covers Latin-1 only, so other characters become a
/// close match or "?".
String _printable(String s) {
  final out = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    out.write(r < 256 ? c : (_swaps[c] ?? '?'));
  }
  return out.toString();
}
