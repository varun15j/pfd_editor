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

/// One piece of a page in the PDF, top to bottom. Its box is in fractions
/// of the page (0 to 1), used when the pieces keep their places.
sealed class PagePiece {
  const PagePiece(this.top, this.left, this.bottom, this.right);
  final double top;
  final double left;
  final double bottom;
  final double right;
}

class TextPiece extends PagePiece {
  const TextPiece(this.text, {required double top, double left = 0, double bottom = 0, double right = 1})
    : super(top, left, bottom, right);
  final String text;
}

class ImagePiece extends PagePiece {
  const ImagePiece(super.top, super.left, super.bottom, super.right, this.jpeg, this.width, this.height);
  final Uint8List jpeg;
  final int width;
  final int height;
}

/// A page ready to build: its shape (height over width) and what is on it.
class PageDraft {
  const PageDraft(this.aspect, this.pieces);
  final double aspect;
  final List<PagePiece> pieces;
}

/// Height over width of the PDF page that keeps the scan's shape.
const _placedWidth = 595.0;

/// Share of a line's box height that the font takes: the box holds the
/// letters' tallest and lowest parts, so the font is a little smaller.
const _lineFontShare = 0.85;

/// Builds a text PDF from OCR results: the text that was read, in reading
/// order, with the parts of the page that were not read (pictures,
/// drawings) added as images where they sat. A page with no text at all
/// goes in as one image.
class OcrPdfBuilder {
  OcrPdfBuilder(this._store);

  final PageStore _store;

  /// [keepLayout] puts each line of text and each picture at its place on the
  /// page (Pro and Gold). Without it the text flows in reading order.
  Future<OcrPdfFile> build(
    List<OcrPdfPage> pages, {
    String? fileName,
    bool keepLayout = false,
    void Function(int done, int total)? onProgress,
  }) async {
    if (pages.isEmpty) throw ArgumentError('No pages to build a PDF from');
    final built = <(int, PageDraft)>[];
    for (final (i, p) in pages.indexed) {
      built.add((p.number, await Isolate.run(() => pageDraft(p, keepLayout: keepLayout))));
      onProgress?.call(i + 1, pages.length + 1);
    }
    final (bytes, pageCount) = await Isolate.run(() => _document(built, keepLayout: keepLayout));
    onProgress?.call(pages.length + 1, pages.length + 1);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = fileName ?? 'Text_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.pdf';
    return OcrPdfFile(await _store.writeExportAtomically(await _store.freeExportName(name), bytes), pageCount);
  }
}

/// What goes on one page, with each piece's place. Public for tests.
PageDraft pageDraft(OcrPdfPage p, {bool keepLayout = false}) {
  final image = renderRecipe(File(p.page.originalPath).readAsBytesSync(), p.page.recipe, maxDimension: 1600);
  final aspect = image.height / image.width;
  final blocks = p.layout?.blocks ?? const <OcrBlock>[];
  if (blocks.isEmpty && p.text.trim().isEmpty) return PageDraft(aspect, [_picture(0, 0, 1, 1, image)]);
  if (keepLayout && blocks.isNotEmpty) {
    // The photo of the page, as it was, on a white page. The recognized text
    // is set over it in a transparent layer at each line's place: it can be
    // searched and copied, and the photo shows through unchanged.
    final lines = [for (final b in blocks) ...(b.lines.isEmpty ? [b] : b.lines)];
    return PageDraft(aspect, [
      _picture(0, 0, 1, 1, image),
      for (final l in lines) TextPiece(l.text, top: l.top, left: l.left, bottom: l.bottom, right: l.right),
    ]);
  }
  final pieces = <PagePiece>[
    if (blocks.isEmpty) TextPiece(p.text, top: 0) else for (final b in blocks) TextPiece(b.text, top: b.top),
    for (final f in findFigures(image, [for (final b in blocks) (b.top, b.bottom)])) _picture(f.top, 0, 1, 1, f.image),
  ];
  return PageDraft(aspect, pieces..sort((a, b) => a.top.compareTo(b.top)));
}

ImagePiece _picture(double top, double left, double bottom, double right, RgbImage image) =>
    ImagePiece(top, left, bottom, right, image.encodeJpg(quality: 80), image.width, image.height);

Future<(Uint8List, int)> _document(List<(int, PageDraft)> pages, {required bool keepLayout}) async {
  final doc = pw.Document(title: 'Recognized text', creator: 'LumaScan');
  for (final (number, draft) in pages) {
    if (keepLayout) {
      doc.addPage(_placedPage(number, draft));
      continue;
    }
    final pieces = draft.pieces;
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
              TextPiece() => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(_printable(piece.text), style: const pw.TextStyle(fontSize: 11, lineSpacing: 2)),
              ),
              ImagePiece() => pw.Padding(
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

/// A page with every piece at its place on the scan: a white layer, the photo
/// on it, and the text on top in a transparent layer. Each line's font is
/// sized to its box, and the text is shrunk where it would run past the box's
/// width.
pw.Page _placedPage(int number, PageDraft draft) {
  final width = _placedWidth;
  final height = width * draft.aspect;
  return pw.Page(
    pageFormat: PdfPageFormat(width, height, marginAll: 0),
    build: (_) => pw.Stack(
      children: [
        pw.Positioned(left: 0, top: 0, child: pw.Container(width: width, height: height, color: PdfColors.white)),
        for (final piece in draft.pieces)
          pw.Positioned(
            left: piece.left * width,
            top: piece.top * height,
            child: pw.SizedBox(
              width: (piece.right - piece.left) * width,
              height: (piece.bottom - piece.top) * height,
              child: switch (piece) {
                TextPiece() => pw.Opacity(
                  // Fully transparent: the text is there to search and copy.
                  opacity: 0,
                  child: pw.FittedBox(
                    fit: pw.BoxFit.scaleDown,
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      _printable(piece.text),
                      style: pw.TextStyle(fontSize: (piece.bottom - piece.top) * height * _lineFontShare),
                    ),
                  ),
                ),
                ImagePiece() => pw.Image(pw.MemoryImage(piece.jpeg), fit: pw.BoxFit.fill),
              },
            ),
          ),
      ],
    ),
  );
}

/// The picture's width on the page: its own size at 150 dpi, but never more
/// than the text column.
double _imageWidth(ImagePiece p) => (p.width * 72 / 150).clamp(60.0, PdfPageFormat.a4.width - 72);

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
