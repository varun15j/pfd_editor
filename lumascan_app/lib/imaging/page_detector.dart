import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/models.dart';
import 'page_focus.dart';
import 'rgb_image.dart';

/// Finds the paper page in a photo and returns its four corners, or null when
/// no page-like region stands out.
///
/// Pure Dart, so it runs the same in tests, in an isolate and on both
/// platforms. On device the live scanner still comes from the native document
/// scanner; this is for imported photos and as a starting quad for manual
/// crop.
///
/// The photo is shrunk to [workSize] on its long edge, then:
/// 1. Two masks of what may be the page are made: pixels that look like
///    white paper (a "paper score" of brightness, raised for cool white and
///    lowered for warm tones, above an Otsu cut, and nearly colourless), and
///    pixels the colour of the paper in the middle of the frame, where the
///    page is held, which finds cream, yellowed or coloured paper too.
/// 2. Each mask is eroded to cut thin bridges to other pages and fingers,
///    one region is kept (the largest, or the one nearest the middle), and
///    it is grown back.
/// 3. The corners start as the largest-area quadrilateral on the region's
///    convex hull, so fingers or tears that bite into an edge do not pull a
///    corner inwards, and are then nudged off any background the hull
///    bridged over.
/// 4. The outlines found are rated by the contrast across their edges
///    (paper on one side, background on the other) and by how near the
///    middle of the frame they are, and the best is kept.
/// 5. A second page that is only partly in view, joined to the page at a
///    gutter or a sheet edge, is cut off ([focusOnePage]).
///
/// Known limit: paper touching the page with no gap (a stack of loose sheets,
/// the facing page of a notebook) can be taken in with it. The quad is a
/// starting point the user can still adjust in the crop screen.
CropQuad? detectPageQuad(RgbImage src, {int workSize = 320, double minArea = 0.1}) {
  final scale = workSize / math.max(src.width, src.height);
  final w = math.max(8, (src.width * math.min(1.0, scale)).round());
  final h = math.max(8, (src.height * math.min(1.0, scale)).round());
  final work = _Work.of(src, w, h);

  final candidates = <CropQuad>{
    ..._outlines(work.paperMask(), w, h, central: const [false, true]),
    ..._outlines(work.seededMask(), w, h, central: const [true]),
  }..removeWhere((q) => !q.isValid(minArea: minArea) || !_pageShaped(q, src));
  final rated = {for (final c in candidates) c: work.rate(c)}..removeWhere((_, rate) => rate <= 0);
  if (rated.isEmpty) return null;
  final quad = rated.keys.reduce((a, b) => rated[b]! > rated[a]! ? b : a);
  final page = focusOnePage(src, quad);
  return page.isValid(minArea: minArea / 2) && _pageShaped(page, src) ? page : quad;
}

/// Outlines of regions of [mask]: for each of [central], the largest
/// region, or with true the one nearest the middle of the frame, where the
/// page being scanned is held.
Iterable<CropQuad> _outlines(Uint8List? mask, int w, int h, {required List<bool> central}) sync* {
  if (mask == null) return;
  // Erode to cut thin bridges to fingers and other paper, keep one region,
  // and grow it back.
  final erosions = math.max(1, (math.min(w, h) / 80).round());
  var eroded = mask;
  for (var i = 0; i < erosions; i++) {
    eroded = _erode(eroded, w, h);
  }
  for (final middle in central) {
    var region = _pickComponent(eroded, w, h, central: middle);
    for (var i = 0; i < erosions; i++) {
      region = _dilate(region, w, h);
    }
    final hull = _convexHull(_boundary(region, w, h));
    if (hull.length < 4) continue;
    final corners = _refine(mask, w, h, _largestQuad(hull));
    NormPoint norm((double, double) p) => NormPoint(p.$1 / (w - 1), p.$2 / (h - 1)).clamp();
    yield _ordered([for (final c in corners) norm(c)]);
  }
}

/// Narrowest page shape accepted: the short side at least this share of the
/// long side. Paper is 0.7 (A4) to 0.6 (a paperback page), and a tilted page
/// photographed at an angle can look about half as wide; a thinner shape is
/// a strip of a page, such as the edge of an open book's facing page.
const _minPageAspect = 0.28;

bool _pageShaped(CropQuad q, RgbImage src) {
  double dist(NormPoint a, NormPoint b) =>
      math.sqrt(math.pow((a.x - b.x) * src.width, 2) + math.pow((a.y - b.y) * src.height, 2));
  final across = (dist(q.tl, q.tr) + dist(q.bl, q.br)) / 2;
  final down = (dist(q.tl, q.bl) + dist(q.tr, q.br)) / 2;
  return math.min(across, down) >= _minPageAspect * math.max(across, down);
}

/// Paper is close to grey; skin, wood and coloured covers are not.
const _maxPaperSaturation = 0.22;

/// Paper under daylight or a phone flash reads slightly blue, while floors,
/// desks and skin read warm, so blue minus red is added to the brightness.
const _coolBonus = 2.0;

/// The photo shrunk to the work size, as per-pixel measures the page is
/// told apart by.
class _Work {
  _Work(this.w, this.h, this.luma, this.score, this.sat, this.redGreen, this.yellowBlue);

  final int w, h;

  /// Brightness, 0..255.
  final Uint8List luma;

  /// Paper score (0..255): brightness raised for cool white, lowered for
  /// warm tones.
  final Uint8List score;

  /// Saturation, 0..1.
  final Float32List sat;

  /// Colour, as red minus green and yellow minus blue.
  final Int16List redGreen, yellowBlue;

  static _Work of(RgbImage src, int w, int h) {
    final luma = Uint8List(w * h), score = Uint8List(w * h);
    final sat = Float32List(w * h);
    final redGreen = Int16List(w * h), yellowBlue = Int16List(w * h);
    final fx = src.width / w, fy = src.height / h;
    final d = src.data;
    for (var y = 0; y < h; y++) {
      final y0 = (y * fy).floor(), y1 = math.max(y0 + 1, ((y + 1) * fy).floor());
      for (var x = 0; x < w; x++) {
        final x0 = (x * fx).floor(), x1 = math.max(x0 + 1, ((x + 1) * fx).floor());
        var r = 0, g = 0, b = 0, n = 0;
        // Box average, sampling every other pixel; plenty for a 320 px mask.
        for (var sy = y0; sy < y1 && sy < src.height; sy += 2) {
          var i = (sy * src.width + x0) * 3;
          for (var sx = x0; sx < x1 && sx < src.width; sx += 2, i += 6) {
            r += d[i];
            g += d[i + 1];
            b += d[i + 2];
            n++;
          }
        }
        r ~/= n;
        g ~/= n;
        b ~/= n;
        final i = y * w + x;
        final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
        final l = 0.299 * r + 0.587 * g + 0.114 * b;
        luma[i] = l.round().clamp(0, 255);
        score[i] = (l + _coolBonus * (b - r)).round().clamp(0, 255);
        sat[i] = mx == 0 ? 0 : (mx - mn) / mx;
        redGreen[i] = r - g;
        yellowBlue[i] = (r + g) ~/ 2 - b;
      }
    }
    return _Work(w, h, luma, score, sat, redGreen, yellowBlue);
  }

  /// Bright, nearly colourless pixels: white paper.
  Uint8List paperMask() {
    final threshold = _otsu(score);
    final mask = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      if (score[i] > threshold && sat[i] < _maxPaperSaturation) mask[i] = 1;
    }
    return mask;
  }

  /// Pixels the colour of the paper in the middle of the frame, where the
  /// page is held: finds cream, yellowed or coloured paper the white-paper
  /// test misses, against a background of another colour or brightness.
  /// Null when the middle is too dark to be paper.
  Uint8List? seededMask() {
    // The paper in the middle: the brighter half of a central window, so
    // print and pictures on the page do not count.
    final window = <int>[];
    for (var y = (h * 0.35).round(); y < (h * 0.65).round(); y++) {
      for (var x = (w * 0.35).round(); x < (w * 0.65).round(); x++) {
        window.add(y * w + x);
      }
    }
    window.sort((a, b) => luma[a].compareTo(luma[b]));
    final bright = window.sublist(window.length ~/ 2);
    int median(List<int> values) => (values..sort())[values.length ~/ 2];
    final l0 = median([for (final i in bright) luma[i]]);
    if (l0 < _minSeedLuma) return null;
    final rg0 = median([for (final i in bright) redGreen[i]]);
    final yb0 = median([for (final i in bright) yellowBlue[i]]);
    // Shade on curved paper changes brightness far more than colour.
    final distance = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      final dl = (luma[i] - l0).abs() * (luma[i] < l0 ? 0.5 : 0.8);
      final dc = 2.0 * ((redGreen[i] - rg0).abs() + (yellowBlue[i] - yb0).abs());
      distance[i] = (dl + dc).round().clamp(0, 255);
    }
    final cut = _otsu(distance).clamp(_minColourCut, _maxColourCut);
    final mask = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      if (distance[i] <= cut) mask[i] = 1;
    }
    return _close(mask, w, h);
  }

  /// How much [quad] looks like the page being scanned: strong contrast
  /// across its edges (paper on one side, background on the other), close
  /// to the middle of the frame, and a page-like share of it.
  double rate(CropQuad quad) {
    var sum = 0.0;
    final pts = quad.points;
    final cx = pts.fold(0.0, (s, p) => s + p.x) / 4 * (w - 1);
    final cy = pts.fold(0.0, (s, p) => s + p.y) / 4 * (h - 1);
    var seen = false;
    for (var k = 0; k < 4; k++) {
      final edge = _edgeContrast(pts[k], pts[(k + 1) % 4], cx, cy);
      if (edge != null) {
        sum += edge;
        seen |= edge >= _minEdge;
      } else {
        sum += _borderEdge;
      }
    }
    // Some edge of a page must stand out from what lies beside it.
    if (!seen) return 0;
    final dx = cx / (w - 1) - 0.5, dy = cy / (h - 1) - 0.5;
    final central = 1 - math.min(1.0, math.sqrt(dx * dx + dy * dy) / 0.5);
    final area = quad.area;
    final size = area < 0.15 ? area / 0.15 : 1.0;
    // The page being scanned is held over the middle of the frame.
    final holdsMiddle = _contains(quad, 0.5, 0.5) ? 1.0 : 0.5;
    return sum / 4 * (0.6 + 0.4 * central) * size * holdsMiddle;
  }

  /// Contrast between just inside and just outside the edge from [a] to
  /// [b]: the median along it, so a finger or a shadow over part of the
  /// edge does not decide it. Null for an edge along the frame border, with
  /// no outside to see.
  double? _edgeContrast(NormPoint a, NormPoint b, double cx, double cy) {
    const samples = 24, offset = 3.0;
    final ax = a.x * (w - 1), ay = a.y * (h - 1), bx = b.x * (w - 1), by = b.y * (h - 1);
    final len = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    if (len < 1) return 0;
    var nx = -(by - ay) / len, ny = (bx - ax) / len;
    // Normal pointing away from the middle of the quad.
    if (nx * ((ax + bx) / 2 - cx) + ny * ((ay + by) / 2 - cy) < 0) {
      nx = -nx;
      ny = -ny;
    }
    final values = <double>[];
    var border = 0;
    for (var j = 0; j < samples; j++) {
      final t = 0.1 + 0.8 * j / (samples - 1);
      final px = ax + (bx - ax) * t, py = ay + (by - ay) * t;
      final ox = (px + nx * offset).round(), oy = (py + ny * offset).round();
      final ix = (px - nx * offset).round(), iy = (py - ny * offset).round();
      if (ox < 0 || oy < 0 || ox >= w || oy >= h) {
        border++;
        continue;
      }
      if (ix < 0 || iy < 0 || ix >= w || iy >= h) continue;
      final o = oy * w + ox, i = iy * w + ix;
      values.add(
        (luma[i] - luma[o]).abs() +
            (redGreen[i] - redGreen[o]).abs() +
            (yellowBlue[i] - yellowBlue[o]).abs().toDouble(),
      );
    }
    if (border > samples / 2) return null;
    if (values.isEmpty) return 0;
    values.sort();
    return values[values.length ~/ 2];
  }
}

bool _contains(CropQuad q, double x, double y) {
  final pts = q.points;
  for (var i = 0; i < 4; i++) {
    final a = pts[i], b = pts[(i + 1) % 4];
    if ((b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x) < 0) return false;
  }
  return true;
}

/// The middle of the frame must be at least this bright to seed paper.
const _minSeedLuma = 70;

/// Bounds on the colour distance that still counts as the seeded paper.
const _minColourCut = 14, _maxColourCut = 60;

/// Contrast at least one edge of a page must show.
const _minEdge = 6.0;

/// Contrast an edge along the frame border scores: a page running off the
/// frame is common, so it is neither a strong nor a missing edge.
const _borderEdge = 30.0;

/// Fills print and small gaps in a mask: two steps of dilation, then two of
/// erosion.
Uint8List _close(Uint8List m, int w, int h) {
  var out = m;
  for (var i = 0; i < 2; i++) {
    out = _dilate(out, w, h);
  }
  for (var i = 0; i < 2; i++) {
    out = _erode(out, w, h);
  }
  return out;
}

int _otsu(Uint8List values) {
  final hist = List<int>.filled(256, 0);
  for (final v in values) {
    hist[v]++;
  }
  final total = values.length;
  var sumAll = 0.0;
  for (var i = 0; i < 256; i++) {
    sumAll += i * hist[i];
  }
  var sumB = 0.0, wB = 0, best = 0.0, threshold = 127;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB, mF = (sumAll - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      threshold = t;
    }
  }
  return threshold;
}

Uint8List _erode(Uint8List m, int w, int h) => _morph(m, w, h, erode: true);
Uint8List _dilate(Uint8List m, int w, int h) => _morph(m, w, h, erode: false);

/// One step of 3x3 erosion or dilation. Pixels outside the image count as
/// paper when eroding, so a page cut off by the frame keeps its edge.
Uint8List _morph(Uint8List m, int w, int h, {required bool erode}) {
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var hit = erode ? 1 : 0;
      for (var dy = -1; dy <= 1 && hit == (erode ? 1 : 0); dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          final v = m[yy * w + xx];
          if (erode && v == 0) {
            hit = 0;
            break;
          }
          if (!erode && v == 1) {
            hit = 1;
            break;
          }
        }
      }
      out[y * w + x] = hit;
    }
  }
  return out;
}

/// Keeps one 4-connected region of [m]: the largest, or with [central] the
/// one that best combines size with closeness to the middle of the frame.
Uint8List _pickComponent(Uint8List m, int w, int h, {required bool central}) {
  final label = Int32List(w * h);
  final stack = Int32List(w * h);
  var next = 0, bestLabel = 0;
  var bestSize = 0.0;
  for (var start = 0; start < w * h; start++) {
    if (m[start] == 0 || label[start] != 0) continue;
    next++;
    var size = 0, top = 0;
    var sumX = 0.0, sumY = 0.0;
    var holdsMiddle = false;
    stack[top++] = start;
    label[start] = next;
    while (top > 0) {
      final i = stack[--top];
      size++;
      final x = i % w, y = i ~/ w;
      sumX += x;
      sumY += y;
      if ((x - w / 2).abs() <= w * 0.05 && (y - h / 2).abs() <= h * 0.05) holdsMiddle = true;
      void visit(int j) {
        if (m[j] == 1 && label[j] == 0) {
          label[j] = next;
          stack[top++] = j;
        }
      }

      if (x > 0) visit(i - 1);
      if (x < w - 1) visit(i + 1);
      if (y > 0) visit(i - w);
      if (y < h - 1) visit(i + w);
    }
    var weight = size.toDouble();
    if (central && !holdsMiddle) {
      // Off the middle: weighed down by how far its centre lies from it.
      final dx = (sumX / size - w / 2) / w, dy = (sumY / size - h / 2) / h;
      weight /= 1 + 32 * (dx * dx + dy * dy);
    }
    if (weight > bestSize) {
      bestSize = weight;
      bestLabel = next;
    }
  }
  final out = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    if (label[i] == bestLabel && bestLabel != 0) out[i] = 1;
  }
  return out;
}

/// Outer pixels of the region: the leftmost and rightmost set pixel of every
/// row and the top and bottom one of every column are enough for the hull.
List<(double, double)> _boundary(Uint8List m, int w, int h) {
  final pts = <(double, double)>[];
  for (var y = 0; y < h; y++) {
    var first = -1, last = -1;
    for (var x = 0; x < w; x++) {
      if (m[y * w + x] == 1) {
        if (first < 0) first = x;
        last = x;
      }
    }
    if (first >= 0) {
      pts
        ..add((first.toDouble(), y.toDouble()))
        ..add((last.toDouble(), y.toDouble()));
    }
  }
  for (var x = 0; x < w; x++) {
    var first = -1, last = -1;
    for (var y = 0; y < h; y++) {
      if (m[y * w + x] == 1) {
        if (first < 0) first = y;
        last = y;
      }
    }
    if (first >= 0) {
      pts
        ..add((x.toDouble(), first.toDouble()))
        ..add((x.toDouble(), last.toDouble()));
    }
  }
  return pts;
}

/// Andrew's monotone chain. Returns the hull in clockwise order in image
/// coordinates (y down).
List<(double, double)> _convexHull(List<(double, double)> points) {
  final pts = points.toSet().toList()..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  if (pts.length < 3) return pts;
  double cross((double, double) o, (double, double) a, (double, double) b) =>
      (a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);
  final lower = <(double, double)>[];
  for (final p in pts) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <(double, double)>[];
  for (final p in pts.reversed) {
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  return [...lower..removeLast(), ...upper..removeLast()];
}

/// Moves the corners one pixel step at a time while that raises
/// (paper inside) - [_backgroundPenalty] x (background inside). Pulls a
/// corner off a neighbouring page or a strip of floor the hull bridged over.
List<(double, double)> _refine(Uint8List mask, int w, int h, List<(double, double)> start) {
  final q = [...start];
  var best = _quadScore(mask, w, h, q);
  for (var step = 8.0; step >= 1; step /= 2) {
    var improved = true;
    while (improved) {
      improved = false;
      for (var k = 0; k < 4; k++) {
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]) {
          final p = q[k];
          final moved = ((p.$1 + dx * step).clamp(0.0, w - 1.0), (p.$2 + dy * step).clamp(0.0, h - 1.0));
          if (moved == p) continue;
          final trial = [...q]..[k] = moved;
          final score = _quadScore(mask, w, h, trial);
          if (score > best) {
            best = score;
            q[k] = moved;
            improved = true;
          }
        }
      }
    }
  }
  return q;
}

const _backgroundPenalty = 2;

int _quadScore(Uint8List mask, int w, int h, List<(double, double)> q) {
  var minY = h, maxY = 0;
  for (final p in q) {
    minY = math.min(minY, p.$2.floor());
    maxY = math.max(maxY, p.$2.ceil());
  }
  var score = 0;
  // Scanline fill: for each row find where it enters and leaves the quad.
  for (var y = math.max(0, minY); y <= math.min(h - 1, maxY); y++) {
    var left = double.infinity, right = -double.infinity;
    for (var k = 0; k < 4; k++) {
      final a = q[k], b = q[(k + 1) % 4];
      if ((a.$2 <= y && b.$2 >= y) || (b.$2 <= y && a.$2 >= y)) {
        final x = a.$2 == b.$2 ? math.min(a.$1, b.$1) : a.$1 + (y - a.$2) * (b.$1 - a.$1) / (b.$2 - a.$2);
        final x2 = a.$2 == b.$2 ? math.max(a.$1, b.$1) : x;
        left = math.min(left, x);
        right = math.max(right, x2);
      }
    }
    if (left > right) continue;
    final row = y * w;
    for (var x = math.max(0, left.ceil()); x <= math.min(w - 1, right.floor()); x++) {
      score += mask[row + x] == 1 ? 1 : -_backgroundPenalty;
    }
  }
  return score;
}

double _quadArea(List<(double, double)> q) {
  var s = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = q[i], b = q[(i + 1) % 4];
    s += a.$1 * b.$2 - b.$1 * a.$2;
  }
  return s.abs() / 2;
}

/// Largest-area quadrilateral with corners on the hull. Starts from the
/// diagonal extremes and moves one corner at a time while the area grows;
/// with a convex hull this settles in a few rounds.
List<(double, double)> _largestQuad(List<(double, double)> hull) {
  final n = hull.length;
  int argBest(double Function((double, double)) f) {
    var best = 0;
    for (var i = 1; i < n; i++) {
      if (f(hull[i]) > f(hull[best])) best = i;
    }
    return best;
  }

  final idx = [
    argBest((p) => -p.$1 - p.$2), // top left
    argBest((p) => p.$1 - p.$2), // top right
    argBest((p) => p.$1 + p.$2), // bottom right
    argBest((p) => -p.$1 + p.$2), // bottom left
  ];
  var area = _quadArea([for (final i in idx) hull[i]]);
  for (var round = 0; round < 20; round++) {
    var improved = false;
    for (var k = 0; k < 4; k++) {
      for (var j = 0; j < n; j++) {
        if (idx.contains(j)) continue;
        final trial = [...idx]..[k] = j;
        // Keep the corners in hull order so the quad never self-intersects.
        if (!_cyclicallyOrdered(trial, n)) continue;
        final a = _quadArea([for (final i in trial) hull[i]]);
        if (a > area + 1e-9) {
          area = a;
          idx[k] = j;
          improved = true;
        }
      }
    }
    if (!improved) break;
  }
  return [for (final i in idx) hull[i]];
}

bool _cyclicallyOrdered(List<int> idx, int n) {
  var steps = 0;
  for (var i = 0; i < 4; i++) {
    steps += (idx[(i + 1) % 4] - idx[i] + n) % n;
  }
  return steps == n;
}

/// Puts four corners into TL, TR, BR, BL order around their centre.
CropQuad _ordered(List<NormPoint> pts) {
  final cx = pts.fold(0.0, (s, p) => s + p.x) / 4;
  final cy = pts.fold(0.0, (s, p) => s + p.y) / 4;
  final sorted = [...pts]..sort((a, b) => math.atan2(a.y - cy, a.x - cx).compareTo(math.atan2(b.y - cy, b.x - cx)));
  // atan2 with y down runs clockwise from the right; rotate so TL is first.
  var start = 0;
  for (var i = 1; i < 4; i++) {
    if (sorted[i].x + sorted[i].y < sorted[start].x + sorted[start].y) start = i;
  }
  final o = [for (var i = 0; i < 4; i++) sorted[(start + i) % 4]];
  return CropQuad(o[0], o[1], o[2], o[3]);
}
