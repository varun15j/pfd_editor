import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app/app_info.dart';
import '../data/page_store.dart';
import '../domain/models.dart';
import '../domain/ocr.dart';
import '../imaging/ocr_figures.dart';
import '../imaging/page_jobs.dart';
import '../imaging/page_renderer.dart';
import '../pdf_edit/annotations.dart';
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
  OcrPdfBuilder(this._store, {this.pageImage});

  final PageStore _store;

  /// The page as text recognition read it: cropped, filtered and with its
  /// masks, as a finished JPEG (the app passes the render service's OCR
  /// copy, which is already on disk once the page has been read). When it
  /// is given, a page is never drawn again from the full-size photo, the
  /// slow step on a phone. Without it, or when it fails, the page is drawn
  /// from the photo as before.
  final Future<RenderedImage> Function(ScanPage page)? pageImage;

  /// [keepLayout] puts each line of text and each picture at its place on the
  /// page (Pro and Gold). Without it the text flows in reading order.
  ///
  /// Pages are drawn two at a time on their own isolates. [isCancelled] is
  /// checked between pages and before the file is written; once it is true
  /// the build stops with [PageJobsCancelled] and writes nothing.
  Future<OcrPdfFile> build(
    List<OcrPdfPage> pages, {
    String? fileName,
    bool keepLayout = false,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (pages.isEmpty) throw ArgumentError('No pages to build a PDF from');
    final images = <RenderedImage?>[];
    for (final p in pages) {
      if (isCancelled?.call() ?? false) throw const PageJobsCancelled();
      images.add(await _imageOf(p.page));
    }
    final drafts = await runPageJobs(
      [for (final (i, p) in pages.indexed) (p, images[i])],
      ((OcrPdfPage, RenderedImage?) job) => pageDraft(job.$1, keepLayout: keepLayout, image: job.$2),
      onProgress: (done, _) => onProgress?.call(done, pages.length + 1),
      isCancelled: isCancelled,
    );
    final built = [for (final (i, p) in pages.indexed) (p.number, drafts[i])];
    final (bytes, pageCount) = await Isolate.run(() => _document(built, keepLayout: keepLayout));
    if (isCancelled?.call() ?? false) throw const PageJobsCancelled();
    onProgress?.call(pages.length + 1, pages.length + 1);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = fileName ?? 'Text_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.pdf';
    return OcrPdfFile(await _store.writeExportAtomically(await _store.freeExportName(name), bytes), pageCount);
  }

  Future<RenderedImage?> _imageOf(ScanPage page) async {
    final of = pageImage;
    if (of == null) return null;
    try {
      return await of(page);
    } on Object {
      return null;
    }
  }
}

/// What goes on one page, with each piece's place. Public for tests.
///
/// [image] is the page as text recognition read it (see
/// [OcrPdfBuilder.pageImage]). A page shown whole (Pro and Gold, or a page
/// with no text) takes its JPEG as it is; a page whose text flows decodes
/// that smaller copy to find its pictures. Only without it is the page drawn
/// again from the full-size photo.
PageDraft pageDraft(OcrPdfPage p, {bool keepLayout = false, RenderedImage? image}) {
  final blocks = p.layout?.blocks ?? const <OcrBlock>[];
  final noText = blocks.isEmpty && p.text.trim().isEmpty;
  final placed = keepLayout && blocks.isNotEmpty;
  final jpeg = image == null ? null : _bytesOf(image.path);
  // The recognized lines, set over the photo in an invisible layer at each
  // line's place: they can be searched and copied, and the photo shows
  // through unchanged.
  List<TextPiece> lines() => [
    for (final b in blocks)
      for (final l in (b.lines.isEmpty ? [b] : b.lines))
        TextPiece(l.text, top: l.top, left: l.left, bottom: l.bottom, right: l.right),
  ];
  if (jpeg != null && image != null && (noText || placed)) {
    final whole = ImagePiece(0, 0, 1, 1, jpeg, image.width, image.height);
    return PageDraft(image.height / image.width, [whole, if (placed) ...lines()]);
  }
  final picture = jpeg != null
      ? RgbImage.decode(jpeg, maxDimension: 1600)
      : renderRecipe(
          File(p.page.originalPath).readAsBytesSync(),
          p.page.recipe,
          maxDimension: 1600,
          masks: masksIn(p.page.annotations),
        );
  final aspect = picture.height / picture.width;
  if (noText) return PageDraft(aspect, [_picture(0, 0, 1, 1, picture)]);
  if (placed) return PageDraft(aspect, [_picture(0, 0, 1, 1, picture), ...lines()]);
  final pieces = <PagePiece>[
    if (blocks.isEmpty) TextPiece(p.text, top: 0) else for (final b in blocks) TextPiece(b.text, top: b.top),
    for (final f in findFigures(picture, [for (final b in blocks) (b.top, b.bottom)]))
      _picture(f.top, 0, 1, 1, f.image),
  ];
  return PageDraft(aspect, pieces..sort((a, b) => a.top.compareTo(b.top)));
}

Uint8List? _bytesOf(String path) {
  try {
    final bytes = File(path).readAsBytesSync();
    return bytes.isEmpty ? null : bytes;
  } on FileSystemException {
    return null;
  }
}

ImagePiece _picture(double top, double left, double bottom, double right, RgbImage image) =>
    ImagePiece(top, left, bottom, right, image.encodeJpg(quality: 80), image.width, image.height);

Future<(Uint8List, int)> _document(List<(int, PageDraft)> pages, {required bool keepLayout}) async {
  final doc = pw.Document(title: 'Recognized text', creator: appName);
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
                  child: pw.Image(
                    pw.MemoryImage(piece.jpeg),
                    fit: pw.BoxFit.contain,
                    width: _imageWidth(piece),
                    height: _imageHeight(piece),
                  ),
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
/// on it, and the text on top in an invisible layer. Each line's font is
/// sized to its box, and the text is shrunk where it would run past the box's
/// width.
pw.Page _placedPage(int number, PageDraft draft) {
  final width = _placedWidth;
  final height = width * draft.aspect;
  return pw.Page(
    pageFormat: PdfPageFormat(width, height, marginAll: 0),
    build: (_) => pw.Stack(
      children: [
        pw.Positioned(
          left: 0,
          top: 0,
          child: pw.Container(width: width, height: height, color: PdfColors.white),
        ),
        for (final piece in draft.pieces)
          pw.Positioned(
            left: piece.left * width,
            top: piece.top * height,
            child: pw.SizedBox(
              width: (piece.right - piece.left) * width,
              height: (piece.bottom - piece.top) * height,
              child: switch (piece) {
                // Invisible text (PDF text render mode 3), the way scanners
                // and OCR tools write it: every PDF app finds, selects and
                // copies it, and nothing is drawn over the photo.
                TextPiece() => pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    _printable(piece.text),
                    style: pw.TextStyle(
                      fontSize: (piece.bottom - piece.top) * height * _lineFontShare,
                      renderingMode: PdfTextRenderingMode.invisible,
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

/// The picture's height at [_imageWidth], never more than the space a page
/// has below its header: a very tall cut-out (a whole page with a short
/// line of text) is shrunk to fit, where a page break cannot split it.
double _imageHeight(ImagePiece p) =>
    (_imageWidth(p) * p.height / p.width).clamp(1.0, PdfPageFormat.a4.height - 72 - _headerSpace);

/// The "Page N" header and the space under the picture.
const _headerSpace = 40.0;

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
