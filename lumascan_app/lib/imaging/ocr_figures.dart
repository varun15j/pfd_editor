import 'dart:typed_data';

import 'rgb_image.dart';

/// A part of a page with no recognised text but something on it: a picture,
/// a drawing, a table the reader could not make out. [top] is where it sat
/// on the page (0 to 1), for placing it among the text.
class OcrFigure {
  const OcrFigure({required this.top, required this.image});

  final double top;
  final RgbImage image;
}

/// Finds the parts of [page] that text recognition left out. [text] holds
/// the text blocks as (top, bottom) fractions of the page height; the
/// stretches between them that are tall enough and not blank become
/// figures, cropped to what is on them.
List<OcrFigure> findFigures(
  RgbImage page,
  List<(double top, double bottom)> text, {
  double minHeight = 0.04,
  double padding = 0.004,
}) {
  final spans = [for (final (t, b) in text) (t - padding, b + padding)]..sort((a, b) => a.$1.compareTo(b.$1));
  final gaps = <(double, double)>[];
  var at = 0.0;
  for (final (t, b) in spans) {
    if (t - at >= minHeight) gaps.add((at, t));
    if (b > at) at = b;
  }
  if (1 - at >= minHeight) gaps.add((at, 1.0));

  final figures = <OcrFigure>[];
  for (final (top, bottom) in gaps) {
    final y0 = (top * page.height).round().clamp(0, page.height);
    final y1 = (bottom * page.height).round().clamp(0, page.height);
    final box = _inkBox(page, y0, y1);
    if (box != null) figures.add(OcrFigure(top: top, image: _crop(page, box)));
  }
  return figures;
}

typedef _Box = ({int x0, int y0, int x1, int y1});

/// The box around what differs from the band's own background, or null when
/// the band is blank (paper, margins, a shadow).
_Box? _inkBox(RgbImage page, int y0, int y1) {
  final w = page.width;
  if (y1 - y0 < 4) return null;
  final luma = Uint8List(w * (y1 - y0));
  final histogram = List.filled(256, 0);
  for (var y = y0; y < y1; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      final v = (page.data[i] * 77 + page.data[i + 1] * 150 + page.data[i + 2] * 29) >> 8;
      luma[(y - y0) * w + x] = v;
      histogram[v]++;
    }
  }
  var seen = 0, background = 0;
  for (var v = 0; v < 256; v++) {
    seen += histogram[v];
    if (seen * 2 >= luma.length) {
      background = v;
      break;
    }
  }
  const delta = 40;
  var minX = w, maxX = -1, minY = y1, maxY = -1, ink = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = 0; x < w; x++) {
      if ((luma[(y - y0) * w + x] - background).abs() > delta) {
        ink++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  // Specks and edge shadows are not figures.
  if (ink < luma.length * 0.01 || maxX - minX < w * 0.05 || maxY - minY < 8) return null;
  final pad = (w * 0.01).round();
  return (
    x0: (minX - pad).clamp(0, w),
    y0: (minY - pad).clamp(y0, y1),
    x1: (maxX + 1 + pad).clamp(0, w),
    y1: (maxY + 1 + pad).clamp(y0, y1),
  );
}

RgbImage _crop(RgbImage src, _Box b) {
  final w = b.x1 - b.x0, h = b.y1 - b.y0;
  final out = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    final from = ((b.y0 + y) * src.width + b.x0) * 3;
    out.setRange(y * w * 3, (y + 1) * w * 3, src.data, from);
  }
  return RgbImage(w, h, out);
}
