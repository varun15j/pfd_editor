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
/// 1. Pixels that look like paper are marked: a "paper score" (brightness,
///    raised for cool white and lowered for warm tones) above an Otsu cut,
///    and nearly colourless, so grey concrete, wood and skin drop out.
/// 2. The mask is eroded to cut thin bridges to other pages and fingers, the
///    largest region is kept, and it is grown back.
/// 3. The corners start as the largest-area quadrilateral on the region's
///    convex hull, so fingers or tears that bite into an edge do not pull a
///    corner inwards, and are then nudged off any background the hull
///    bridged over.
/// 4. A second page that is only partly in view, joined to the page at a
///    gutter or a sheet edge, is cut off ([focusOnePage]).
///
/// Known limit: paper touching the page with no gap (a stack of loose sheets,
/// the facing page of a notebook) can be taken in with it. The quad is a
/// starting point the user can still adjust in the crop screen.
CropQuad? detectPageQuad(RgbImage src, {int workSize = 320, double minArea = 0.1}) {
  final scale = workSize / math.max(src.width, src.height);
  final w = math.max(8, (src.width * math.min(1.0, scale)).round());
  final h = math.max(8, (src.height * math.min(1.0, scale)).round());
  final (score, sat) = _paperScore(src, w, h);

  final threshold = _otsu(score);
  final paper = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    if (score[i] > threshold && sat[i] < _maxPaperSaturation) paper[i] = 1;
  }

  // Erode to cut thin bridges to fingers and other paper, keep the largest
  // region, and grow it back.
  final erosions = math.max(1, (math.min(w, h) / 80).round());
  var region = paper;
  for (var i = 0; i < erosions; i++) {
    region = _erode(region, w, h);
  }
  region = _largestComponent(region, w, h);
  for (var i = 0; i < erosions; i++) {
    region = _dilate(region, w, h);
  }
  final hull = _convexHull(_boundary(region, w, h));
  if (hull.length < 4) return null;
  final corners = _refine(paper, w, h, _largestQuad(hull));

  NormPoint norm((double, double) p) => NormPoint(p.$1 / (w - 1), p.$2 / (h - 1)).clamp();
  final quad = _ordered([for (final c in corners) norm(c)]);
  if (!quad.isValid(minArea: minArea)) return null;
  final page = focusOnePage(src, quad);
  return page.isValid(minArea: minArea / 2) ? page : quad;
}

/// Paper is close to grey; skin, wood and coloured covers are not.
const _maxPaperSaturation = 0.22;

/// Paper under daylight or a phone flash reads slightly blue, while floors,
/// desks and skin read warm, so blue minus red is added to the brightness.
const _coolBonus = 2.0;

/// Per work pixel: the paper score (0..255) and the saturation (0..1).
(Uint8List, Float32List) _paperScore(RgbImage src, int w, int h) {
  final score = Uint8List(w * h);
  final sat = Float32List(w * h);
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
      final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
      score[y * w + x] = (0.299 * r + 0.587 * g + 0.114 * b + _coolBonus * (b - r)).round().clamp(0, 255);
      sat[y * w + x] = mx == 0 ? 0 : (mx - mn) / mx;
    }
  }
  return (score, sat);
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

Uint8List _largestComponent(Uint8List m, int w, int h) {
  final label = Int32List(w * h);
  final stack = Int32List(w * h);
  var next = 0, bestLabel = 0, bestSize = 0;
  for (var start = 0; start < w * h; start++) {
    if (m[start] == 0 || label[start] != 0) continue;
    next++;
    var size = 0, top = 0;
    stack[top++] = start;
    label[start] = next;
    while (top > 0) {
      final i = stack[--top];
      size++;
      final x = i % w, y = i ~/ w;
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
    if (size > bestSize) {
      bestSize = size;
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
