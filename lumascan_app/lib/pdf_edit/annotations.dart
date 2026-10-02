import 'package:flutter/foundation.dart';

import '../domain/models.dart';

/// Annotations are an app-owned overlay on top of the source PDF (ADR-013).
/// Every coordinate is normalized to the displayed page, (0,0) top-left and
/// (1,1) bottom-right, so the same data drives the on-screen overlay and the
/// flattened PDF. Sizes (stroke width, font size) are fractions of the page
/// width for the same reason.
@immutable
sealed class Annotation {
  const Annotation(this.id);

  final String id;
}

/// A freehand pen or highlighter stroke.
class InkAnnotation extends Annotation {
  const InkAnnotation({
    required String id,
    required this.points,
    required this.color,
    required this.width,
    this.highlighter = false,
  }) : super(id);

  final List<NormPoint> points;

  /// ARGB colour, as in `Color.toARGB32()`.
  final int color;

  /// Stroke width as a fraction of the page width.
  final double width;

  /// Highlighter strokes are drawn translucent and wide.
  final bool highlighter;

  InkAnnotation withPoint(NormPoint p) =>
      InkAnnotation(id: id, points: [...points, p.clamp()], color: color, width: width, highlighter: highlighter);
}

/// A single-line or multi-line text box anchored at its top-left corner.
class TextAnnotation extends Annotation {
  const TextAnnotation({
    required String id,
    required this.origin,
    required this.text,
    required this.color,
    this.fontSize = 0.035,
  }) : super(id);

  final NormPoint origin;
  final String text;
  final int color;

  /// Font size as a fraction of the page width.
  final double fontSize;

  TextAnnotation copyWith({NormPoint? origin, String? text, int? color, double? fontSize}) => TextAnnotation(
    id: id,
    origin: origin ?? this.origin,
    text: text ?? this.text,
    color: color ?? this.color,
    fontSize: fontSize ?? this.fontSize,
  );
}

/// A drawn signature. Strokes are normalized to the signature's own box, so
/// moving or resizing the box never touches the strokes. A drawn signature is
/// a visual mark, not a certificate-based digital signature (PDF-03).
class SignatureAnnotation extends Annotation {
  const SignatureAnnotation({
    required String id,
    required this.strokes,
    required this.left,
    required this.top,
    required this.width,
    required this.aspectRatio,
    required this.color,
  }) : super(id);

  final List<List<NormPoint>> strokes;
  final double left;
  final double top;

  /// Box width as a fraction of the page width.
  final double width;

  /// Width over height of the signature box, in page units, so the
  /// signature keeps its shape on any page.
  final double aspectRatio;
  final int color;

  /// Pen width as a fraction of the box width, on screen and in the PDF.
  static const strokeFraction = 0.015;

  /// Box height as a fraction of the page height, for a page whose
  /// width/height ratio is [pageAspect].
  double heightOn(double pageAspect) => width * pageAspect / aspectRatio;

  SignatureAnnotation copyWith({double? left, double? top, double? width}) => SignatureAnnotation(
    id: id,
    strokes: strokes,
    left: left ?? this.left,
    top: top ?? this.top,
    width: width ?? this.width,
    aspectRatio: aspectRatio,
    color: color,
  );

  /// Builds a signature from raw pad strokes in pad pixels. The strokes are
  /// cropped to their bounding box (plus a small pad) and normalized to it.
  /// Returns null when there is nothing drawn.
  static SignatureAnnotation? fromPadStrokes({
    required String id,
    required List<List<(double, double)>> strokes,
    required int color,
    required double pageAspect,
    double width = 0.35,
  }) {
    final all = [for (final s in strokes) ...s];
    if (all.isEmpty) return null;
    var minX = all.first.$1, maxX = minX, minY = all.first.$2, maxY = minY;
    for (final (x, y) in all) {
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    const pad = 4.0;
    minX -= pad;
    minY -= pad;
    final w = (maxX + pad) - minX;
    final h = (maxY + pad) - minY;
    final normalized = [
      for (final s in strokes)
        if (s.isNotEmpty) [for (final (x, y) in s) NormPoint((x - minX) / w, (y - minY) / h)],
    ];
    final aspect = w / h;
    // Centre the box on the page; heightOn() gives its page-relative height.
    final boxHeight = width * pageAspect / aspect;
    return SignatureAnnotation(
      id: id,
      strokes: normalized,
      left: (1 - width) / 2,
      top: ((1 - boxHeight) / 2).clamp(0.0, 1.0),
      width: width,
      aspectRatio: aspect,
      color: color,
    );
  }
}

/// One page of the document being edited. [sourcePage] is the 1-based page
/// number in the untouched source PDF; reordering and deleting only change
/// the list of EditorPages, never the source file.
@immutable
class EditorPage {
  const EditorPage({
    required this.id,
    required this.sourcePage,
    required this.widthPt,
    required this.heightPt,
    this.annotations = const [],
  });

  final String id;
  final int sourcePage;

  /// Displayed page size in PDF points (rotation already applied).
  final double widthPt;
  final double heightPt;
  final List<Annotation> annotations;

  double get aspect => widthPt / heightPt;

  EditorPage withAnnotations(List<Annotation> annotations) =>
      EditorPage(id: id, sourcePage: sourcePage, widthPt: widthPt, heightPt: heightPt, annotations: annotations);
}
