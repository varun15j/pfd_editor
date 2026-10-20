import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

/// One line of text on a PDF page and where it sits, in points from the
/// page's top-left corner.
@immutable
class PdfTextLine {
  const PdfTextLine(this.text, {required this.left, required this.top, required this.right, required this.bottom});

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get height => bottom - top;
}

/// The text of one PDF page, in reading order. Empty when the page has no
/// text layer, such as a photo or a plain scan.
@immutable
class PdfPageLines {
  const PdfPageLines({required this.widthPt, required this.heightPt, required this.lines});

  final double widthPt;
  final double heightPt;
  final List<PdfTextLine> lines;

  /// Letters and digits on the page, without spaces.
  int get characterCount => lines.fold(0, (n, l) => n + l.text.replaceAll(RegExp(r'\s'), '').length);
}

/// Reads the text layer of a PDF: the text of a text PDF, or the OCR text
/// LumaScan puts in a text PDF. Nothing is recognised here; a page without
/// a text layer comes back empty. Behind an interface so tests do not need
/// the PDFium engine.
abstract class PdfTextReader {
  /// The text of pages 1 to [pageCount], in order.
  Future<List<PdfPageLines>> readPages(String path, {required int pageCount, String? password});
}

/// pdfrx (PDFium) text reader.
class PdfrxTextReader implements PdfTextReader {
  @override
  Future<List<PdfPageLines>> readPages(String path, {required int pageCount, String? password}) async {
    await pdfrxFlutterInitialize();
    final doc = await PdfDocument.openFile(path, passwordProvider: createSimplePasswordProvider(password));
    try {
      final result = <PdfPageLines>[];
      for (var i = 0; i < pageCount && i < doc.pages.length; i++) {
        final page = doc.pages[i];
        final text = await page.loadStructuredText();
        result.add(
          PdfPageLines(
            widthPt: page.width,
            heightPt: page.height,
            lines: linesOf(text.fullText, text.charRects, page.height),
          ),
        );
      }
      return result;
    } finally {
      await doc.dispose();
    }
  }

  /// Splits [fullText] at its line breaks and gives each line the box around
  /// its characters, turned from PDF coordinates (origin bottom left) into
  /// page coordinates (origin top left).
  @visibleForTesting
  static List<PdfTextLine> linesOf(String fullText, List<PdfRect> charRects, double pageHeight) {
    final lines = <PdfTextLine>[];
    var start = 0;
    void addLine(int end) {
      final text = fullText.substring(start, end).replaceAll('\r', '').trim();
      if (text.isEmpty) return;
      double? left, top, right, bottom;
      for (var i = start; i < end && i < charRects.length; i++) {
        final r = charRects[i];
        if (r.width <= 0 && r.height <= 0) continue;
        left = left == null || r.left < left ? r.left : left;
        right = right == null || r.right > right ? r.right : right;
        top = top == null || r.top > top ? r.top : top;
        bottom = bottom == null || r.bottom < bottom ? r.bottom : bottom;
      }
      if (left == null) return;
      lines.add(PdfTextLine(text, left: left, top: pageHeight - top!, right: right!, bottom: pageHeight - bottom!));
    }

    for (var i = 0; i < fullText.length; i++) {
      if (fullText[i] == '\n') {
        addLine(i);
        start = i + 1;
      }
    }
    addLine(fullText.length);
    return lines;
  }
}
