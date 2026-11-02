import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/models.dart';
import 'rgb_image.dart';

/// Whether a page [found] in a camera shot is the card in the [guide], not a
/// table edge or a small label: valid, and not far smaller or larger.
bool isCardLike(CropQuad found, CropQuad guide) {
  if (!found.isValid()) return false;
  final ratio = found.area / guide.area;
  return ratio > 0.35 && ratio < 2.2;
}

/// Whether [q], on a photo [width] by [height] pixels, has the shape of a
/// document [aspect] wide to high, in either orientation: its long sides over
/// its short sides within a factor of [tolerance] of the document's. Enough
/// for a card photographed a little at an angle, not for a text block or a
/// strip of a page.
bool cardShaped(CropQuad q, int width, int height, double aspect, {double tolerance = 1.2}) {
  if (!q.isValid()) return false;
  double dist(NormPoint a, NormPoint b) =>
      math.sqrt(math.pow((a.x - b.x) * width, 2) + math.pow((a.y - b.y) * height, 2));
  final across = (dist(q.tl, q.tr) + dist(q.bl, q.br)) / 2;
  final down = (dist(q.tl, q.bl) + dist(q.tr, q.br)) / 2;
  if (math.min(across, down) <= 0) return false;
  final ratio = math.max(across, down) / math.min(across, down);
  final target = math.max(aspect, 1 / aspect);
  return ratio >= target / tolerance && ratio <= target * tolerance;
}

/// Finds a card by its outline in a photocopy or print of it: [aspect] wide
/// to high in either orientation, covering at least [minArea] of [src].
/// There the page detector sees only the sheet of paper and the corner
/// model is not sure, as the card's edge is only a faint printed line or a
/// faint step from the card's grey to the white paper.
///
/// 1. Edge pixels are thin dark lines (darker than both neighbours two or
///    three pixels across) and faint steps, level and upright apart.
/// 2. They are gathered into straight lines within 15 degrees of level or
///    upright by a Hough vote, and each line is kept as its longest drawn
///    stretch, a quarter of the frame or more.
/// 3. Where two level lines both end at about the same place, as the top
///    and bottom of a card do when its upright side is too faint to see in
///    the copy, the line through their ends is a side too (and the same
///    across upright lines).
/// 4. Every two level and two upright lines make a quad. One in the card's
///    shape whose sides are each mostly drawn and whose lines reach its
///    corners, but for one corner under a finger or a fold, is the card:
///    the largest one, so the outline wins over lines inside the card (a
///    photo box, the line over a footer band). Lines that must reach the
///    corners keep out the sheet's own edge beside the card.
///
/// A card cut by the frame on one side is found by its other three, with
/// the frame edge as the fourth. Null when no such outline is found.
CropQuad? findCardOutline(RgbImage src, {required double aspect, double minArea = 0.15}) {
  final w = src.width, h = src.height;
  if (w < 32 || h < 32) return null;
  final grey = Uint8List(w * h);
  for (var i = 0, j = 0; i < grey.length; i++, j += 3) {
    grey[i] = (src.data[j] * 77 + src.data[j + 1] * 150 + src.data[j + 2] * 29) >> 8;
  }
  final reach = 0.035 * math.max(w, h);
  final drawnRows = _lines(_edges(grey, w, h, across: w), w, h, level: true);
  final drawnCols = _lines(_edges(grey, w, h, across: 1), w, h, level: false);
  final rows = [
    ...drawnRows,
    ..._joins(drawnCols, w, h, reach),
    _Line.frame(0, level: true),
    _Line.frame(h - 1.0, level: true),
  ];
  final cols = [
    ...drawnCols,
    ..._joins(drawnRows, w, h, reach),
    _Line.frame(0, level: false),
    _Line.frame(w - 1.0, level: false),
  ];
  final target = math.max(aspect, 1 / aspect);

  // Whether [line] reaches the corner at [at] along it, which it makes with
  // [other]: a frame edge or a join always does, and nothing need reach the
  // frame.
  bool reaches(_Line line, _Line other, double at, {required bool start}) =>
      line.drawn == null || other.isFrame || (start ? line.start <= at + reach : line.end >= at - reach);
  bool corner(_Line row, _Line col, (double, double) p, {required bool left, required bool top}) =>
      reaches(row, col, p.$1, start: left) && reaches(col, row, p.$2, start: top);

  // First outlines with all four sides in view, then ones cut by the frame.
  for (final cut in const [0, 1]) {
    CropQuad? best;
    var bestArea = 0.0;
    for (final top in rows) {
      for (final bottom in rows) {
        final high = bottom.offset - top.offset;
        if (high < 0.15 * h) continue;
        final rowFrames = (top.isFrame ? 1 : 0) + (bottom.isFrame ? 1 : 0);
        if (rowFrames > cut) continue;
        for (final left in cols) {
          for (final right in cols) {
            final wide = right.offset - left.offset;
            if (wide < 0.15 * w) continue;
            if (rowFrames + (left.isFrame ? 1 : 0) + (right.isFrame ? 1 : 0) != cut) continue;
            // A rough size and shape from the lines' offsets, before the
            // corners are worked out: the lines are within 15 degrees.
            final rough = high * wide / (w * h);
            final shape = math.max(wide, high) / math.min(wide, high);
            if (rough < 0.8 * math.max(minArea, bestArea) || shape < target / 1.5 || shape > target * 1.5) continue;
            final tl = _meet(top, left, w, h), tr = _meet(top, right, w, h);
            final br = _meet(bottom, right, w, h), bl = _meet(bottom, left, w, h);
            var missed = 0;
            if (!corner(top, left, tl, left: true, top: true)) missed++;
            if (!corner(top, right, tr, left: false, top: true)) missed++;
            if (!corner(bottom, right, br, left: false, top: false)) missed++;
            if (!corner(bottom, left, bl, left: true, top: false)) missed++;
            if (missed > 1) continue;
            final quad = CropQuad(
              NormPoint(tl.$1 / (w - 1), tl.$2 / (h - 1)),
              NormPoint(tr.$1 / (w - 1), tr.$2 / (h - 1)),
              NormPoint(br.$1 / (w - 1), br.$2 / (h - 1)),
              NormPoint(bl.$1 / (w - 1), bl.$2 / (h - 1)),
            );
            if (quad.area <= bestArea || !quad.isValid(minArea: minArea) || !cardShaped(quad, w, h, aspect)) continue;
            if (!top.drawnBetween(tl.$1, tr.$1) || !bottom.drawnBetween(bl.$1, br.$1)) continue;
            if (!left.drawnBetween(tl.$2, bl.$2) || !right.drawnBetween(tr.$2, br.$2)) continue;
            best = quad;
            bestArea = quad.area;
          }
        }
      }
    }
    if (best != null) return best;
  }
  return null;
}

/// Edge pixels in [grey] for lines running across [across] (the image
/// width for level lines, 1 for upright ones): a thin dark line, at least
/// this much darker than the lighter of its neighbours two or three pixels
/// away, or the steepest point of a step of at least this much over four
/// pixels.
Uint8List _edges(Uint8List grey, int w, int h, {required int across}) {
  const minDepth = 12;
  final out = Uint8List(w * h);
  int step(int i) => (grey[i + 2 * across] - grey[i - 2 * across]).abs();
  for (var y = 3; y < h - 3; y++) {
    for (var x = 3; x < w - 3; x++) {
      final i = y * w + x;
      final v = grey[i];
      if (v <= grey[i - across] && v <= grey[i + across]) {
        final ridge = math.max(
          math.min(grey[i - 2 * across], grey[i + 2 * across]) - v,
          math.min(grey[i - 3 * across], grey[i + 3 * across]) - v,
        );
        if (ridge >= minDepth) {
          out[i] = 1;
          continue;
        }
      }
      final s = step(i);
      if (s >= minDepth && s >= step(i - across) && s > step(i + across)) out[i] = 1;
    }
  }
  return out;
}

/// Share of a side that must be drawn: the rest may be under a finger, a
/// fold or a rounded corner, or too faint in the copy.
const _minDrawn = 0.55;

/// A straight line within 15 degrees of level (y = offset + slope * (x - mid
/// width)) or upright (x = offset + slope * (y - mid height)), drawn from
/// [start] to [end] along it (x for a level line, y for an upright one).
/// An edge of the frame stands in for a card side out of view, and a join
/// for a side too faint to see, between the ends of two lines across it.
class _Line {
  const _Line(this.offset, this.slope, this.start, this.end, {required this.level, required this.drawn})
    : isFrame = false;

  const _Line.frame(this.offset, {required this.level})
    : slope = 0,
      start = 0,
      end = double.infinity,
      isFrame = true,
      drawn = null;

  const _Line.join(this.offset, this.slope, this.start, this.end, {required this.level})
    : isFrame = false,
      drawn = null;

  final double offset;
  final double slope;
  final double start;
  final double end;
  final bool level;
  final bool isFrame;

  /// For a line found in the photo, how many of its points up to each one
  /// along it are drawn; null for a frame edge or a join, taken as drawn.
  final Int32List? drawn;

  /// Where the line is across at [along] (y for a level line at x), on a
  /// frame [size] long along it.
  double at(double along, int size) => offset + slope * (along - size / 2);

  /// Whether the line is mostly drawn from [a] to [b] along it, its ends,
  /// where a card's corner is rounded, left out.
  bool drawnBetween(double a, double b) {
    final drawn = this.drawn;
    if (drawn == null) return true;
    final from = (a + 0.06 * (b - a)).round().clamp(0, drawn.length - 1);
    final to = (b - 0.06 * (b - a)).round().clamp(0, drawn.length - 1);
    if (to <= from) return false;
    return (drawn[to] - drawn[from]) / (to - from) >= _minDrawn;
  }
}

/// Sides across [lines] where two of them, apart by at least 15% of the
/// frame, both start (or both end) within [reach] of each other, as the top
/// and bottom of a card do when its upright sides are too faint to see.
List<_Line> _joins(List<_Line> lines, int w, int h, double reach) {
  if (lines.isEmpty) return const [];
  final level = !lines.first.level;
  final size = level ? w : h, across = level ? h : w;
  final maxSlope = math.tan(15 * math.pi / 180);
  final joins = <_Line>[];
  for (final a in lines) {
    for (final b in lines) {
      if (b.offset - a.offset < 0.15 * across) continue;
      for (final start in const [true, false]) {
        final u1 = start ? a.start : a.end, u2 = start ? b.start : b.end;
        if ((u1 - u2).abs() >= reach) continue;
        // Points as (along the join, across it).
        final v1 = a.at(u1, across), v2 = b.at(u2, across);
        final slope = (u2 - u1) / (v2 - v1);
        if (slope.abs() > maxSlope) continue;
        final offset = u1 + slope * (size / 2 - v1);
        // Text lines that start together make many joins in one place.
        if (joins.any((j) => (j.offset - offset).abs() < 3 && (j.slope - slope).abs() < 0.02)) continue;
        joins.add(_Line.join(offset, slope, v1, v2, level: level));
      }
    }
  }
  return joins;
}

/// The strongest straight lines through the [mask] pixels, level or upright,
/// by a Hough vote over slopes within 15 degrees, each a few pixels from
/// any stronger one and drawn for a quarter of the frame or more.
List<_Line> _lines(Uint8List mask, int w, int h, {required bool level}) {
  const maxLines = 16;
  final along = level ? w : h, span = level ? h : w;
  final slopes = [for (var a = -30; a <= 30; a++) math.tan(a * 0.5 * math.pi / 180)];
  final n = slopes.length;
  final pad = (along * 0.3).ceil();
  final bins = span + 2 * pad;
  final votes = Int32List(n * bins);
  // Each slope's line through a point u along: its offset less the point's
  // place across, padded to stay positive.
  final shift = Int32List(along * n);
  for (var u = 0; u < along; u++) {
    for (var s = 0; s < n; s++) {
      shift[u * n + s] = pad - (slopes[s] * (u - along / 2)).round();
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (mask[y * w + x] == 0) continue;
      final u = level ? x : y, v = level ? y : x;
      for (var s = 0; s < n; s++) {
        final b = v + shift[u * n + s];
        if (b >= 0 && b < bins) votes[s * bins + b]++;
      }
    }
  }
  // The best slope at each offset, then the strongest offsets in turn.
  final peak = Int32List(bins), peakSlope = Int32List(bins);
  for (var s = 0; s < n; s++) {
    for (var b = 0; b < bins; b++) {
      if (votes[s * bins + b] > peak[b]) {
        peak[b] = votes[s * bins + b];
        peakSlope[b] = s;
      }
    }
  }
  final minVotes = (along * 0.2).round();
  final found = <_Line>[];
  for (var tries = 0; tries < 3 * maxLines && found.length < maxLines; tries++) {
    var b = -1, bestVotes = minVotes - 1;
    for (var i = 0; i < bins; i++) {
      if (peak[i] > bestVotes) {
        b = i;
        bestVotes = peak[i];
      }
    }
    if (b < 0) break;
    peak.fillRange(math.max(0, b - 4), math.min(bins, b + 5), 0);
    final line = _traced(mask, w, h, (b - pad).toDouble(), slopes[peakSlope[b]], level: level);
    if (line.end - line.start >= 0.25 * along) found.add(line);
  }
  return found;
}

/// The line ([offset], [slope]) through [mask], with the points along it
/// that have a mask pixel within three pixels across, and as its start and
/// end its longest stretch drawn over gaps of up to 2% of the frame.
_Line _traced(Uint8List mask, int w, int h, double offset, double slope, {required bool level}) {
  final along = level ? w : h;
  final maxGap = math.max(4, (0.02 * along).round());
  final drawn = Int32List(along + 1);
  var bestStart = 0, bestEnd = -1, start = -1, last = -maxGap - 1;
  for (var u = 0; u < along; u++) {
    final v = (offset + slope * (u - along / 2)).round();
    var hit = false;
    for (var d = -3; d <= 3 && !hit; d++) {
      final x = level ? u : v + d, y = level ? v + d : u;
      hit = x >= 0 && y >= 0 && x < w && y < h && mask[y * w + x] != 0;
    }
    drawn[u + 1] = drawn[u] + (hit ? 1 : 0);
    if (!hit) continue;
    if (u - last > maxGap) start = u;
    last = u;
    if (last - start > bestEnd - bestStart) {
      bestStart = start;
      bestEnd = last;
    }
  }
  return _Line(offset, slope, bestStart.toDouble(), bestEnd.toDouble(), level: level, drawn: drawn);
}

/// Where a level and an upright line cross, in pixels.
(double, double) _meet(_Line a, _Line b, int w, int h) {
  final row = a.level ? a : b, col = a.level ? b : a;
  // y = r0 + rs * (x - w/2); x = c0 + cs * (y - h/2).
  final r0 = row.offset, rs = row.slope, c0 = col.offset, cs = col.slope;
  final y = (r0 + rs * (c0 - cs * h / 2 - w / 2)) / (1 - rs * cs);
  final x = c0 + cs * (y - h / 2);
  return (x, y);
}
