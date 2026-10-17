import 'dart:math' as math;

import 'docx_writer.dart';
import 'pdf_text_reader.dart';

/// Turns the text lines of a page into Word paragraphs that Word can wrap
/// and edit. Lines that run on are joined into one paragraph; a short line,
/// a bigger gap, a change of size or an indent starts a new one. Font size,
/// indent and the space above each paragraph follow the page, so the Word
/// page looks close to the PDF.
class WordTextLayout {
  WordTextLayout._();

  /// A page counts as text when it holds at least this many letters and
  /// digits. Fewer is most likely a page number or a stamp on a picture,
  /// and the page goes in as a picture instead.
  static const minCharacters = 15;

  /// Space between the text and the page edge on a text page, in points.
  static const marginPt = DocxWriter.textMarginPt;

  static const _minFontPt = 7.0;
  static const _maxFontPt = 40.0;

  /// Body text size for text that comes without a position (OCR text).
  static const plainFontPt = 11.0;

  /// The paragraphs of a page read from a PDF text layer.
  static List<DocxParagraph> fromLines(PdfPageLines page) {
    final lines = [
      for (final l in page.lines)
        if (l.text.trim().isNotEmpty && l.height > 0) l,
    ];
    if (lines.isEmpty) return const [];
    final textRight = lines.map((l) => l.right).reduce(math.max);

    final paragraphs = <DocxParagraph>[];
    final text = StringBuffer();
    late PdfTextLine first;
    late PdfTextLine last;
    var previousBottom = marginPt;

    void flush() {
      if (text.isEmpty) return;
      final size = _fontSize(first);
      // Word puts about a fifth of the font size above each line of its own.
      final gap = first.top - previousBottom - size * 0.2;
      paragraphs.add(
        DocxParagraph(
          text.toString(),
          fontSizePt: size,
          spaceBeforePt: gap.clamp(0, page.heightPt / 2).toDouble(),
          indentPt: math.max(0, first.left - marginPt),
        ),
      );
      previousBottom = last.bottom;
      text.clear();
    }

    for (final line in lines) {
      if (text.isNotEmpty && _continues(last, line, first, textRight)) {
        final joined = text.toString();
        // A word broken over two lines is joined back without a space.
        if (!joined.endsWith('-')) text.write(' ');
        text.write(line.text.trim());
        last = line;
        continue;
      }
      flush();
      first = line;
      last = line;
      text.write(line.text.trim());
    }
    flush();
    return fitToPage(paragraphs, page.widthPt, page.heightPt);
  }

  /// Word's text is often wider than the PDF's (another font, no columns),
  /// so a page can run onto a second one. When the estimated height is more
  /// than the page holds, the space between paragraphs shrinks first, then
  /// the text, down to [_minScale] of its size.
  static List<DocxParagraph> fitToPage(List<DocxParagraph> paragraphs, double widthPt, double heightPt) {
    // The estimate is rough, so a tenth of the page is kept free.
    final available = (heightPt - 2 * marginPt) * 0.9;
    final width = widthPt - 2 * marginPt;
    double textHeight(double scale) => paragraphs.fold(0.0, (h, para) => h + estimateHeight(para, width, scale: scale));
    final spacing = paragraphs.fold(0.0, (h, para) => h + para.spaceBeforePt);
    final text = textHeight(1);
    if (text + spacing <= available) return paragraphs;

    // Keep a little space between paragraphs if the text alone fits.
    final spaceScale = text < available ? ((available - text) / spacing).clamp(0.0, 1.0) : 0.0;
    var scale = 1.0;
    for (var step = 1; scale > _minScale && textHeight(scale) + spacing * spaceScale > available; step++) {
      scale = math.max(_minScale, 1 - step * 0.05);
    }
    return [
      for (final para in paragraphs)
        DocxParagraph(
          para.text,
          fontSizePt: ((para.fontSizePt * scale * 2).round() / 2).clamp(_minFontPt, _maxFontPt).toDouble(),
          spaceBeforePt: para.spaceBeforePt * spaceScale,
          indentPt: para.indentPt,
        ),
    ];
  }

  static const _minScale = 0.8;

  /// The height Word gives [para] on a line [widthPt] wide: its lines at
  /// about 1.15 times the font size, with an average letter half the font
  /// size wide.
  static double estimateHeight(DocxParagraph para, double widthPt, {double scale = 1}) {
    final size = para.fontSizePt * scale;
    final lineWidth = math.max(widthPt - para.indentPt, size * 10);
    final lines = math.max(1, (para.text.length * size * 0.5 / lineWidth).ceil());
    return lines * size * 1.15;
  }

  /// The paragraphs of OCR text that has no positions: each line stays a
  /// line, and a blank line becomes space above the next one.
  static List<DocxParagraph> fromPlainText(String text) {
    final paragraphs = <DocxParagraph>[];
    var blank = 0;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        blank++;
        continue;
      }
      paragraphs.add(
        DocxParagraph(
          line.trim(),
          fontSizePt: plainFontPt,
          spaceBeforePt: paragraphs.isEmpty ? 0 : blank * plainFontPt,
        ),
      );
      blank = 0;
    }
    return paragraphs;
  }

  /// Whether [next] carries on the paragraph that [previous] ended.
  static bool _continues(PdfTextLine previous, PdfTextLine next, PdfTextLine first, double textRight) {
    final h = previous.height;
    // Going back up the page means a new column or a side note.
    if (next.top < previous.top) return false;
    if (next.top - previous.bottom > h * 0.8) return false;
    final ratio = next.height / h;
    if (ratio < 0.75 || ratio > 1.33) return false;
    if ((next.left - previous.left).abs() > h * 2 && (next.left - first.left).abs() > h * 2) return false;
    // A line that stops well before the right edge ends its paragraph.
    return previous.right >= textRight - h * 3;
  }

  /// The font size of [line] from the height of its letters. A line with
  /// letters that hang below it (g, p, y, brackets) is about the font size
  /// tall; capitals and digits alone are about 0.72 of it.
  static double _fontSize(PdfTextLine line) {
    final hangs = RegExp(r'[gjpqyQ,;()\[\]{}|/]').hasMatch(line.text);
    final size = line.height / (hangs ? 0.95 : 0.72);
    return ((size * 2).round() / 2).clamp(_minFontPt, _maxFontPt).toDouble();
  }
}
