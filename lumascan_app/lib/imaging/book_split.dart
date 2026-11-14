import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/models.dart';
import 'corner_model.dart';
import 'page_detector.dart';
import 'rgb_image.dart';

/// The two halves of a frame, used for a book spread until its spine is
/// found.
const leftHalf = CropQuad(NormPoint(0, 0), NormPoint(0.5, 0), NormPoint(0.5, 1), NormPoint(0, 1));
const rightHalf = CropQuad(NormPoint(0.5, 0), NormPoint(1, 0), NormPoint(1, 1), NormPoint(0.5, 1));

/// Splits a photo of an open book into its left and right page
/// (docs/capture-modes-algorithms.md, Book mode). The spread is the page
/// region found in the photo (the whole photo when none is found), and the
/// spine is the line across it that looks most like a gutter ([spineLine]).
/// Returns the left page, then the right.
/// With a corner [model], its outline is tried first, as in the camera.
(CropQuad, CropQuad) splitSpread(RgbImage photo, {bool smart = true, CornerModel? model}) {
  // The gutter can cut the paper in two, so a region that does not reach
  // across the middle is one page, not the spread: use the whole photo.
  final found = model?.find(photo) ?? detectPageQuad(photo, minArea: 0.2, smart: smart);
  final spread = found != null && showsSpread(found) ? found : CropQuad.full;
  final (s, t) = spineLine(photo, spread);
  final top = _lerp(spread.tl, spread.tr, s);
  final bottom = _lerp(spread.bl, spread.br, t);
  return (CropQuad(spread.tl, top, bottom, spread.bl), CropQuad(top, spread.tr, spread.br, bottom));
}

/// Whether the page found in Book mode is an open spread, both pages in
/// view, rather than one page with the other cut off or out of view. It is
/// a spread when it reaches across the middle of the frame, or when no page
/// was found at all (then the frame is split in halves).
bool showsSpread(CropQuad? found) =>
    found == null || (found.tl.x < 0.4 && found.bl.x < 0.4 && found.tr.x > 0.6 && found.br.x > 0.6);

/// How far from the middle of the spread the spine is looked for, as a
/// share of its width each way. A dark desk or the outer page edges beside
/// the book are never taken for the gutter.
const _spineReach = 0.22;

/// The spine may lean by this share of the spread's width between its top
/// and its bottom end: a book held at an angle, or one page raised.
const _spineLean = 0.1;

/// Below this score no line stands out and the spread is split down the
/// middle.
const _minSpineScore = 6.0;

/// Where the spine crosses the top side and the bottom side of [spread],
/// each from 0 (left end) to 1 (right end).
///
/// The spine is searched for as a straight line that may lean, rated the
/// way Adobe's book patent rates its bind line (US 12,705,755): a line
/// scores for what a gutter looks like along its whole length, and loses
/// for leaning and for lying far from the middle. A gutter shows in two
/// ways. The two pages are lit differently where one of them rises from the
/// other, so there is a *step* in brightness across the line; and the
/// paper curves down into the binding, so the line itself is *darker* than
/// the paper on both sides. Both are read as what three quarters of the
/// line show at least: a picture, a heading or a finger over part of the
/// line does not hide it, and a line that only crosses the gutter, or runs
/// beside a picture for a while, scores nothing. Falls back to the middle
/// (0.5, 0.5) when no line stands out.
(double, double) spineLine(RgbImage photo, CropQuad spread) {
  final work = _SpineWork.of(photo);
  const steps = 96, samples = 36;
  final from = ((0.5 - _spineReach) * steps).round(), to = ((0.5 + _spineReach) * steps).round();
  final lean = (_spineLean * steps).round();
  // Flanks a little over 1% of the spread's width away: outside the dark
  // notch of the gutter, inside the page margins.
  final width = ((spread.tr.x - spread.tl.x).abs() + (spread.br.x - spread.bl.x).abs()) / 2 * (work.w - 1);
  final reach = math.max(2.0, width * 0.014);
  // Direction across the spread, along its top side.
  final ax = (spread.tr.x - spread.tl.x) * (work.w - 1), ay = (spread.tr.y - spread.tl.y) * (work.h - 1);
  final al = math.max(1e-6, math.sqrt(ax * ax + ay * ay));
  final ux = ax / al * reach, uy = ay / al * reach;
  final stepsAcross = Float64List(samples), dips = Float64List(samples);
  var best = _minSpineScore, bestTop = steps ~/ 2, bestBottom = steps ~/ 2;
  for (var i = from; i <= to; i++) {
    final top = _lerp(spread.tl, spread.tr, i / steps);
    for (var j = math.max(from, i - lean); j <= math.min(to, i + lean); j++) {
      final bottom = _lerp(spread.bl, spread.br, j / steps);
      for (var k = 0; k < samples; k++) {
        // Skip the top and bottom tenth, where page edges and fingers sit.
        final v = 0.1 + 0.8 * k / (samples - 1);
        final x = (top.x + (bottom.x - top.x) * v) * (work.w - 1), y = (top.y + (bottom.y - top.y) * v) * (work.h - 1);
        final here = work.at(x, y), left = work.at(x - ux, y - uy), right = work.at(x + ux, y + uy);
        // Read again half as far out, so that of two lines over the same
        // step the one centred on it scores more.
        final near = work.at(x - ux / 2, y - uy / 2) - work.at(x + ux / 2, y + uy / 2);
        stepsAcross[k] = (left - right + near) / 2;
        dips[k] = math.min(left, right) - here;
      }
      stepsAcross.sort();
      dips.sort();
      // What three quarters of the line show at least, the same way round.
      final step = stepsAcross[samples ~/ 2] > 0
          ? math.max(0.0, stepsAcross[samples ~/ 4])
          : math.max(0.0, -stepsAcross[samples - 1 - samples ~/ 4]);
      final dip = math.max(0.0, dips[samples ~/ 4]);
      final off = ((i + j) / 2 / steps - 0.5).abs(), leans = (i - j).abs() / steps;
      final score = (step + 2 * dip) * (1 - 1.2 * off) * (1 - leans);
      if (score > best) {
        best = score;
        bestTop = i;
        bestBottom = j;
      }
    }
  }
  return (bestTop / steps, bestBottom / steps);
}

/// Brightness of the photo at no more than 320 pixels a side, smoothed, for
/// [spineLine].
class _SpineWork {
  _SpineWork(this.w, this.h, this.luma);

  factory _SpineWork.of(RgbImage src) {
    final scale = math.min(1.0, 320 / math.max(src.width, src.height));
    final w = math.max(8, (src.width * scale).round()), h = math.max(8, (src.height * scale).round());
    final raw = Float32List(w * h);
    final fx = src.width / w, fy = src.height / h;
    final d = src.data;
    for (var y = 0; y < h; y++) {
      final y0 = (y * fy).floor(), y1 = math.max(y0 + 1, ((y + 1) * fy).floor());
      for (var x = 0; x < w; x++) {
        final x0 = (x * fx).floor(), x1 = math.max(x0 + 1, ((x + 1) * fx).floor());
        var sum = 0, n = 0;
        for (var sy = y0; sy < y1 && sy < src.height; sy++) {
          var i = (sy * src.width + x0) * 3;
          for (var sx = x0; sx < x1 && sx < src.width; sx++, i += 3) {
            sum += d[i] * 77 + d[i + 1] * 150 + d[i + 2] * 29;
            n++;
          }
        }
        raw[y * w + x] = sum / n / 256;
      }
    }
    // Smoothed 1-2-1 down the page only: text lines blur into an even
    // grey, while the spine, which runs down the page, stays sharp.
    final luma = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      final up = (y > 0 ? y - 1 : y) * w, down = (y < h - 1 ? y + 1 : y) * w, row = y * w;
      for (var x = 0; x < w; x++) {
        luma[row + x] = (raw[up + x] + 2 * raw[row + x] + raw[down + x]) / 4;
      }
    }
    return _SpineWork(w, h, luma);
  }

  final int w, h;
  final Float32List luma;

  double at(double x, double y) {
    final xi = x.round().clamp(0, w - 1), yi = y.round().clamp(0, h - 1);
    return luma[yi * w + xi];
  }
}

NormPoint _lerp(NormPoint a, NormPoint b, double t) => NormPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);

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
