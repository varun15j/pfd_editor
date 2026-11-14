import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/models.dart';
import 'rgb_image.dart';

/// Finds the four corners of a page with a small neural network, as a first
/// try before the hand-made detector ([detectPageQuad]).
///
/// The model is DocAligner's LCNet heatmap model (DocsaidLab/DocAligner,
/// Apache-2.0, `assets/models/`), fine-tuned on LumaScan's own marked
/// photos (books, colour books, made pages, handwritten notebook pages,
/// `tool/corner_model_training/`): a 256 x 256 RGB photo in, five 128 x 128
/// maps out: one heatmap per corner, TL, TR, BR, BL, and the page's area
/// (`docs/edge-model.md`). A corner out of the frame is put on the frame
/// edge, as with an open book filling the frame. Its answer is used when
/// every corner stands out ([minCornerConfidence]) or the corners and the
/// area map agree on the page ([pageOutline]); otherwise the hand-made
/// detector decides.
abstract class CornerModel {
  /// The page in [image], or null when the model is not sure of it. With
  /// [spread] (Book mode) an open book is taken whole, both pages, where
  /// the model sees them ([pageOutline]).
  CropQuad? find(RgbImage image, {bool spread = false});
}

/// Side of the square photo the model reads.
const cornerModelInputSize = 256;

/// Lowest heatmap peak, for every corner, at which the model's outline is
/// used. Measured on the fine-tuned model (2026-11-05): every held-back
/// photo of a page scored above 0.5, and plain surfaces, gradients and
/// noise with no page stayed below 0.05. (The stock model needed 0.8.)
const minCornerConfidence = 0.5;

/// Heatmap values below this are background, as in DocAligner's own
/// post-processing.
const _heatThreshold = 0.3;

/// [image] as the model's input: resized to 256 x 256 (bilinear), channels
/// first, red, green, blue, scaled to 0..1.
Float32List cornerModelInput(RgbImage image) {
  const n = cornerModelInputSize;
  final out = Float32List(3 * n * n);
  final w = image.width, h = image.height, d = image.data;
  final sx = w / n, sy = h / n;
  for (var y = 0; y < n; y++) {
    final fy = math.max(0.0, (y + 0.5) * sy - 0.5);
    final y0 = math.min(h - 1, fy.floor()), y1 = math.min(h - 1, y0 + 1);
    final ty = fy - y0;
    for (var x = 0; x < n; x++) {
      final fx = math.max(0.0, (x + 0.5) * sx - 0.5);
      final x0 = math.min(w - 1, fx.floor()), x1 = math.min(w - 1, x0 + 1);
      final tx = fx - x0;
      final a = (y0 * w + x0) * 3, b = (y0 * w + x1) * 3, c = (y1 * w + x0) * 3, e = (y1 * w + x1) * 3;
      for (var ch = 0; ch < 3; ch++) {
        final top = d[a + ch] + (d[b + ch] - d[a + ch]) * tx;
        final bottom = d[c + ch] + (d[e + ch] - d[c + ch]) * tx;
        out[ch * n * n + y * n + x] = (top + (bottom - top) * ty) / 255;
      }
    }
  }
  return out;
}

/// A second or third place for a corner counts from this height.
const _minOtherPeak = 0.25;

/// Two places for one corner lie at least this far apart, as a share of
/// the frame. Nearer than that they are one corner seen a little blurred.
const _peaksApart = 0.08;

/// One place a corner may be: a blob of its heatmap.
class CornerPeak {
  const CornerPeak(this.point, this.height);

  /// The blob's centre of mass, as a fraction of the frame.
  final NormPoint point;

  /// The blob's highest value, 0..1.
  final double height;
}

/// The places a corner may be, read from its heatmap ([size] x [size],
/// values 0..1): the strongest blob first, then up to [most] - 1 others
/// that stand out on their own. Empty when the corner was not found.
///
/// With an open book in view a corner often has two: the top right corner
/// of the page is at the spine if the page meant is the left one, and at
/// the far edge if it is the whole spread. Each blob is read by itself, as
/// the centre of mass of the cells joined to its peak; reading all of them
/// as one would put the corner between the two, on neither.
List<CornerPeak> readCornerPeaks(Float32List map, int size, {int most = 3}) {
  final left = Float32List.fromList(map);
  final peaks = <CornerPeak>[];
  final apart = (_peaksApart * size).round();
  final stack = <int>[];
  while (peaks.length < most) {
    var height = 0.0, at = -1;
    for (var i = 0; i < left.length; i++) {
      if (left[i] > height) {
        height = left[i];
        at = i;
      }
    }
    final least = peaks.isEmpty ? _heatThreshold : _minOtherPeak;
    if (height < least) break;
    // The cells joined to the peak that are at least half its height.
    final cut = math.max(least, height / 2);
    var sx = 0.0, sy = 0.0, sw = 0.0;
    stack.add(at);
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final v = left[i];
      if (v < cut) continue;
      left[i] = 0;
      final x = i % size, y = i ~/ size;
      sx += x * v;
      sy += y * v;
      sw += v;
      if (x > 0) stack.add(i - 1);
      if (x < size - 1) stack.add(i + 1);
      if (y > 0) stack.add(i - size);
      if (y < size - 1) stack.add(i + size);
    }
    peaks.add(CornerPeak(NormPoint(sx / sw / (size - 1), sy / sw / (size - 1)).clamp(), height));
    // The blob's skirt is not another place.
    final px = at % size, py = at ~/ size;
    for (var y = math.max(0, py - apart); y <= math.min(size - 1, py + apart); y++) {
      for (var x = math.max(0, px - apart); x <= math.min(size - 1, px + apart); x++) {
        if ((x - px) * (x - px) + (y - py) * (y - py) <= apart * apart) left[y * size + x] = 0;
      }
    }
  }
  return peaks;
}

/// One outline the model's maps allow, with what speaks for it.
class PageReading {
  const PageReading(this.quad, this.confidence, this.strength, this.agreement);

  final CropQuad quad;

  /// The weakest of its four corner peaks.
  final double confidence;

  /// The mean of its four corner peaks.
  final double strength;

  /// How well it matches the model's own map of the page's area, 0..1:
  /// their overlap (intersection over union). Null for a model with corner
  /// maps only.
  final double? agreement;

  /// What ranks one reading against another: how strongly the corners
  /// stand out, times how well the outline fits the area map or, without
  /// one, how nearly its opposite sides run the same way.
  double get score => strength * (agreement ?? _parallel(quad));
}

/// 1 when both pairs of opposite sides of [q] run the same way, less as
/// either pair opens up, squared.
double _parallel(CropQuad q) {
  double along(NormPoint a, NormPoint b, NormPoint c, NormPoint d) {
    final ux = b.x - a.x, uy = b.y - a.y, vx = d.x - c.x, vy = d.y - c.y;
    final n = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
    return n < 1e-12 ? 0 : (ux * vx + uy * vy) / n;
  }

  final least = math.max(0.0, math.min(along(q.tl, q.tr, q.bl, q.br), along(q.tl, q.bl, q.tr, q.br)));
  return least * least;
}

/// Every outline the model's maps allow, best first ([PageReading.score]).
///
/// [maps] are the model's output maps, each [size] x [size] with values
/// 0..1: the four corner heatmaps, then, for a model that has them, the
/// page's area and its outline (`docs/edge-model.md`, phase 2). Each corner
/// may be in more than one place ([readCornerPeaks]); every choice of one
/// place a corner that makes a sound outline is a reading. Empty when a
/// corner was not found at all.
List<PageReading> readPageOutlines(List<Float32List> maps, int size) {
  final places = [for (final map in maps.take(4)) readCornerPeaks(map, size)];
  if (places.length < 4 || places.any((p) => p.isEmpty)) return const [];
  final area = maps.length > 4 ? maps[4] : null;
  final readings = <PageReading>[];
  for (final a in places[0]) {
    for (final b in places[1]) {
      for (final c in places[2]) {
        for (final d in places[3]) {
          final quad = _roundTheMiddle([a.point, b.point, c.point, d.point]);
          if (!quad.isValid()) continue;
          final heights = [a.height, b.height, c.height, d.height];
          readings.add(
            PageReading(
              quad,
              heights.reduce(math.min),
              heights.reduce((x, y) => x + y) / 4,
              area == null ? null : _overlap(quad, area, size),
            ),
          );
        }
      }
    }
  }
  return readings..sort((x, y) => y.score.compareTo(x.score));
}

/// Overlap of [quad] with the area map: the map's weight inside the quad,
/// over the quad's own cells plus the map's weight outside it. Read at
/// every other cell.
double _overlap(CropQuad quad, Float32List area, int size) {
  final p = quad.points;
  var inside = 0.0, cells = 0, outside = 0.0;
  for (var y = 0; y < size; y += 2) {
    final fy = y / (size - 1);
    for (var x = 0; x < size; x += 2) {
      final fx = x / (size - 1);
      var within = true;
      for (var k = 0; k < 4 && within; k++) {
        final a = p[k], b = p[(k + 1) % 4];
        within = (b.x - a.x) * (fy - a.y) - (b.y - a.y) * (fx - a.x) >= 0;
      }
      final v = area[y * size + x];
      if (within) {
        inside += v;
        cells++;
      } else {
        outside += v;
      }
    }
  }
  final union = cells + outside;
  return union <= 0 ? 0 : inside / union;
}

/// The four points as an outline, ordered round their middle with the top
/// left first, whatever order they came in.
CropQuad _roundTheMiddle(List<NormPoint> pts) {
  final cx = pts.fold(0.0, (s, p) => s + p.x) / 4, cy = pts.fold(0.0, (s, p) => s + p.y) / 4;
  // atan2 order starts at the left (-pi) and runs top left, top right,
  // bottom right, bottom left in screen coordinates (y down).
  final sorted = [...pts]..sort((a, b) => math.atan2(a.y - cy, a.x - cx).compareTo(math.atan2(b.y - cy, b.x - cx)));
  final start = [for (var k = 0; k < 4; k++) k]
      .reduce((a, b) => sorted[a].x + sorted[a].y <= sorted[b].x + sorted[b].y ? a : b);
  final o = [for (var k = 0; k < 4; k++) sorted[(start + k) % 4]];
  return CropQuad(o[0], o[1], o[2], o[3]);
}

/// The best page outline read from the model's maps ([readPageOutlines]),
/// with its confidence: the weakest corner's peak. Null when a corner was
/// not found or no choice of corners makes a sound outline.
(CropQuad, double)? readCornerHeatmaps(List<Float32List> maps, int size) {
  final readings = readPageOutlines(maps, size);
  return readings.isEmpty ? null : (readings.first.quad, readings.first.confidence);
}

/// Lowest corner peak for an outline of both pages in Book mode. The far
/// page's corners are the second place in their heatmaps and stand out
/// less than the first; among the sample spreads they reach 0.4 to 0.9.
const minSpreadCornerConfidence = 0.4;

/// Both pages together are at least this many times the size of one.
const _spreadGrowth = 1.5;

/// An outline whose weakest corner is under [minCornerConfidence] is still
/// used when it matches the model's map of the page's area this well: the
/// corner is under a thumb or off the frame, but the page itself is plain.
const minAreaAgreement = 0.87;

/// An outline the corners are sure of is dropped when it matches the area
/// map less than this: corners with no page between them.
const _leastAreaAgreement = 0.5;

/// The page the model's [maps] show, or null when the model is not sure
/// and the hand-made detector should decide.
///
/// The best reading ([readPageOutlines]) is used when every corner stands
/// out ([minCornerConfidence]) or, for a model with an area map, when the
/// corners and the area map agree on the page ([minAreaAgreement]).
///
/// With [spread] (Book mode, where both pages of an open book are wanted)
/// the widest reading that reaches across the middle of the frame is taken
/// instead, when every one of its corners stands out: left to itself the
/// model more often marks one page of the two.
CropQuad? pageOutline(List<Float32List> maps, int size, {bool spread = false}) {
  final readings = readPageOutlines(maps, size);
  if (readings.isEmpty) return null;
  if (spread) {
    // Both pages: a reading across the middle of the frame and clearly
    // larger than the first choice, which is then one page of the two.
    final one = readings.first.quad.area;
    PageReading? both;
    double rank(PageReading r) => r.strength * _parallel(r.quad);
    for (final r in readings) {
      final q = r.quad;
      if (r.confidence < minSpreadCornerConfidence || q.area < one * _spreadGrowth) continue;
      if (!(q.tl.x < 0.4 && q.bl.x < 0.4 && q.tr.x > 0.6 && q.br.x > 0.6)) continue;
      if (both == null || rank(r) > rank(both)) both = r;
    }
    if (both != null) return both.quad;
  }
  final best = readings.first, agreement = best.agreement;
  if (agreement == null) return best.confidence >= minCornerConfidence ? best.quad : null;
  if (agreement < _leastAreaAgreement) return null;
  return best.confidence >= minCornerConfidence || agreement >= minAreaAgreement ? best.quad : null;
}
