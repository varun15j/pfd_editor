import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/app_info.dart';
import 'docx_reader.dart';

/// Lays a [DocxDocument] out as a PDF. Each Word section keeps its page size
/// and margins, text flows in a standard font, and a picture is scaled down
/// when it is larger than the space it sits in.
///
/// The PDF's text uses the standard Helvetica font, as the OCR text PDFs do,
/// so characters outside Latin scripts may not show.
class DocxToPdf {
  DocxToPdf._();

  static const _bodyPt = 11.0;

  static Future<({Uint8List bytes, int pageCount})> build(DocxDocument document, {String title = 'Document'}) async {
    final doc = pw.Document(title: title, creator: appName);
    for (final section in document.sections) {
      final m = section.margins;
      final contentW = section.pageWidthPt - m.left - m.right;
      final contentH = section.pageHeightPt - m.top - m.bottom;
      final children = <pw.Widget>[
        for (final block in section.blocks)
          switch (block) {
            DocxText(:final text, :final bold) => pw.Paragraph(
              text: text,
              style: pw.TextStyle(fontSize: _bodyPt, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
              margin: const pw.EdgeInsets.only(bottom: 6),
            ),
            DocxPicture() => _picture(block, contentW, contentH) ?? _missingPicture,
          },
      ];
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat(section.pageWidthPt, section.pageHeightPt),
          margin: pw.EdgeInsets.fromLTRB(m.left, m.top, m.right, m.bottom),
          build: (_) => children.isEmpty ? [pw.SizedBox()] : children,
        ),
      );
    }
    final pageCount = doc.document.pdfPageList.pages.length;
    return (bytes: await doc.save(), pageCount: pageCount);
  }

  /// Stands in for a picture whose format this converter cannot read.
  static final _missingPicture = pw.Paragraph(
    text: '[Picture not shown]',
    style: const pw.TextStyle(fontSize: _bodyPt),
  );

  /// A picture at its size on the page, or null when its format is unknown.
  static pw.Widget? _picture(DocxPicture picture, double maxW, double maxH) {
    var data = picture.bytes;
    var w = picture.widthPt;
    var h = picture.heightPt;
    if (!_isJpegOrPng(data) || w <= 0 || h <= 0) {
      final decoded = img.decodeImage(data);
      if (decoded == null) return null;
      if (w <= 0 || h <= 0) {
        w = decoded.width.toDouble();
        h = decoded.height.toDouble();
      }
      if (!_isJpegOrPng(data)) data = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
    }
    final scale = math.min(1.0, math.min(maxW / w, maxH / h));
    return pw.Image(pw.MemoryImage(data), width: w * scale, height: h * scale);
  }

  static bool _isJpegOrPng(Uint8List b) =>
      (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) ||
      (b.length > 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47);
}
