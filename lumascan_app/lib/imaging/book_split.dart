import 'dart:math' as math;

import '../domain/models.dart';
import 'page_detector.dart';
import 'rgb_image.dart';

/// The two halves of a frame, used for a book spread until its spine is
/// found.
const leftHalf = CropQuad(NormPoint(0, 0), NormPoint(0.5, 0), NormPoint(0.5, 1), NormPoint(0, 1));
const rightHalf = CropQuad(NormPoint(0.5, 0), NormPoint(1, 0), NormPoint(1, 1), NormPoint(0.5, 1));

/// Splits a photo of an open book into its left and right page
/// (docs/capture-modes-algorithms.md, Book mode). The spread is the page
/// region found in the photo (the whole photo when none is found), and the
/// spine is the darkest column in its middle third: the gutter shadow, the
/// "luminance valley" of the design. Returns the left page, then the right.
(CropQuad, CropQuad) splitSpread(RgbImage photo) {
  // The gutter can cut the paper in two, so a region that does not reach
  // across the middle is one page, not the spread: use the whole photo.
  final found = detectPageQuad(photo, minArea: 0.2);
  final spread = found != null && showsSpread(found) ? found : CropQuad.full;
  final s = spineFraction(photo, spread);
  final top = _lerp(spread.tl, spread.tr, s);
  final bottom = _lerp(spread.bl, spread.br, s);
  return (CropQuad(spread.tl, top, bottom, spread.bl), CropQuad(top, spread.tr, spread.br, bottom));
}

/// Whether the page found in Book mode is an open spread, both pages in
/// view, rather than one page with the other cut off or out of view. It is
/// a spread when it reaches across the middle of the frame, or when no page
/// was found at all (then the frame is split in halves).
bool showsSpread(CropQuad? found) =>
    found == null || (found.tl.x < 0.4 && found.bl.x < 0.4 && found.tr.x > 0.6 && found.br.x > 0.6);

/// Where the spine is across [spread], from 0 (left edge) to 1 (right
/// edge). Searches the middle third only, so a dark desk beside the book is
/// never taken for the gutter, and falls back to the centre when no column
/// is clearly darker than its neighbours.
double spineFraction(RgbImage photo, CropQuad spread) {
  const steps = 60;
  final means = <double>[];
  for (var i = 0; i <= steps; i++) {
    final t = 1 / 3 + (i / steps) / 3;
    var sum = 0.0;
    const samples = 40;
    for (var j = 0; j < samples; j++) {
      // Skip the top and bottom tenth, where page edges and fingers sit.
      final v = 0.1 + 0.8 * j / (samples - 1);
      final top = _lerp(spread.tl, spread.tr, t), bottom = _lerp(spread.bl, spread.br, t);
      final p = _lerp(top, bottom, v);
      sum += _luma(photo, p);
    }
    means.add(sum / samples);
  }
  // Smooth over neighbours so one dark line of text does not win.
  final smooth = [
    for (var i = 0; i < means.length; i++)
      [for (var k = i - 2; k <= i + 2; k++) means[k.clamp(0, means.length - 1)]].reduce((a, b) => a + b) / 5,
  ];
  var best = 0;
  for (var i = 1; i < smooth.length; i++) {
    if (smooth[i] < smooth[best]) best = i;
  }
  final average = smooth.reduce((a, b) => a + b) / smooth.length;
  if (average - smooth[best] < 6) return 0.5;
  return 1 / 3 + (best / steps) / 3;
}

NormPoint _lerp(NormPoint a, NormPoint b, double t) => NormPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);

double _luma(RgbImage image, NormPoint p) {
  final x = (p.x * (image.width - 1)).round().clamp(0, image.width - 1);
  final y = (p.y * (image.height - 1)).round().clamp(0, image.height - 1);
  final i = (y * image.width + x) * 3;
  final d = image.data;
  return (d[i] * 77 + d[i + 1] * 150 + d[i + 2] * 29) / 256;
}

/// Mean brightness of an image, 0..255, for the low-light guard.
double meanLuma(RgbImage image) {
  final d = image.data;
  var sum = 0;
  final step = math.max(1, d.length ~/ 3 ~/ 4000) * 3;
  var n = 0;
  for (var i = 0; i + 2 < d.length; i += step) {
    sum += (d[i] * 77 + d[i + 1] * 150 + d[i + 2] * 29) >> 8;
    n++;
  }
  return n == 0 ? 0 : sum / n;
}
