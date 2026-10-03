import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/models.dart';
import 'annotations.dart';

/// A page ready to be written: the rendered source page as JPEG plus the
/// annotations to flatten on top of it.
class FlattenPage {
  const FlattenPage({required this.jpeg, required this.widthPt, required this.heightPt, required this.annotations});

  final Uint8List jpeg;
  final double widthPt;
  final double heightPt;
  final List<Annotation> annotations;
}

/// Writes a new PDF with the `pdf` package (ADR-011): each page keeps its
/// original size in points, shows the rendered source page, and has its
/// annotations drawn as vector marks on top (ADR-013, flattened at export).
Future<Uint8List> buildEditedPdf(List<FlattenPage> pages, {String? title}) {
  if (pages.isEmpty) throw ArgumentError('A PDF needs at least one page');
  final doc = pw.Document(title: title, creator: 'LumaScan');
  for (final page in pages) {
    final w = page.widthPt, h = page.heightPt;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(w, h),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            pw.Positioned.fill(child: pw.Image(pw.MemoryImage(page.jpeg), fit: pw.BoxFit.fill)),
            ...markWidgets(page.annotations, w, h),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

/// The annotations as PDF widgets for a box [w] by [h] points: vector strokes
/// and signatures in one layer, and text as real PDF text. Place them in a
/// stack over the page image.
List<pw.Widget> markWidgets(List<Annotation> annotations, double w, double h) => [
  pw.Positioned.fill(
    child: pw.CustomPaint(size: PdfPoint(w, h), painter: (canvas, size) => _paintMarks(canvas, size, annotations)),
  ),
  for (final a in annotations)
    if (a is TextAnnotation)
      pw.Positioned(
        left: a.origin.x * w,
        top: a.origin.y * h,
        child: pw.Text(
          a.text,
          style: pw.TextStyle(fontSize: a.fontSize * w, color: _pdfColor(a.color), lineSpacing: 0),
        ),
      ),
];

PdfColor _pdfColor(int argb) => PdfColor.fromInt(argb | 0xFF000000);

double _alpha(int argb) => ((argb >> 24) & 0xFF) / 255;

// PDF canvas origin is bottom-left, annotation origin is top-left.
void _paintMarks(PdfGraphics canvas, PdfPoint size, List<Annotation> annotations) {
  for (final a in annotations) {
    switch (a) {
      case InkAnnotation():
        final alpha = a.highlighter ? 0.35 : _alpha(a.color);
        _stroke(
          canvas,
          [a.points],
          a.color,
          alpha,
          a.width * size.x,
          (p) => PdfPoint(p.x * size.x, size.y - p.y * size.y),
        );
      case SignatureAnnotation():
        final left = a.left * size.x;
        final top = a.top * size.y;
        final bw = a.width * size.x;
        final bh = bw / a.aspectRatio;
        _stroke(
          canvas,
          a.strokes,
          a.color,
          1,
          bw * SignatureAnnotation.strokeFraction,
          (p) => PdfPoint(left + p.x * bw, size.y - (top + p.y * bh)),
        );
      case TextAnnotation():
        break; // Drawn as a text widget so it uses real PDF text.
    }
  }
}

void _stroke(
  PdfGraphics canvas,
  List<List<NormPoint>> strokes,
  int color,
  double alpha,
  double width,
  PdfPoint Function(NormPoint) map,
) {
  canvas
    ..saveContext()
    ..setGraphicState(PdfGraphicState(opacity: alpha))
    ..setStrokeColor(_pdfColor(color))
    ..setFillColor(_pdfColor(color))
    ..setLineWidth(width)
    ..setLineCap(PdfLineCap.round)
    ..setLineJoin(PdfLineJoin.round);
  for (final s in strokes) {
    if (s.isEmpty) continue;
    if (s.length == 1) {
      final p = map(s.first);
      canvas
        ..drawEllipse(p.x, p.y, width / 2, width / 2)
        ..fillPath();
      continue;
    }
    final first = map(s.first);
    canvas.moveTo(first.x, first.y);
    for (final p in s.skip(1)) {
      final q = map(p);
      canvas.lineTo(q.x, q.y);
    }
    canvas.strokePath();
  }
  canvas.restoreContext();
}
