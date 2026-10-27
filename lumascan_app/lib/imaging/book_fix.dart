import 'dart:math' as math;
import 'dart:typed_data';

import 'rgb_image.dart';

/// Book page fix (improvement.md #9, Pro): a page photographed from a thick
/// book, already cropped to its corners, is flattened and cleared of the
/// fingers holding it open. Both steps leave a page alone when they find
/// nothing to fix, so a flat sheet comes out as it went in.
RgbImage fixBookPage(RgbImage page) => removeFingers(flattenBookPage(page));

/// Flattens the curve of a page photographed from an open book.
///
/// After the perspective crop the page's corners sit at the corners of the
/// picture, but near the spine its lines of text still bow up or down. The
/// page is cut into narrow vertical strips and the dark rows of each strip
/// (its lines of text) are matched with the strip beside it, separately in
/// four bands from top to bottom. That gives how far each strip has moved
/// up or down in each band, which is smoothed with a cubic across the page
/// and undone, so the lines come out straight.
///
/// Returns [page] itself when it is not sure: too little text to follow,
/// strips that do not match, or lines already straight.
RgbImage flattenBookPage(RgbImage page) {
  final w = page.width, h = page.height;
  if (w < 64 || h < 64) return page;
  final scale = math.min(1.0, 900 / math.max(w, h));
  final sw = math.max(32, (w * scale).round()), sh = math.max(32, (h * scale).round());
  final ink = _inkMap(_smallLuma(page, sw, sh), sw, sh);

  const strips = 28;
  final x0 = (sw * 0.04).round(), x1 = (sw * 0.96).round();
  final stripWidth = (x1 - x0) / strips;
  final profiles = [
    for (var k = 0; k < strips; k++) _profile(ink, sw, sh, (x0 + k * stripWidth).round(), (x0 + (k + 1) * stripWidth).round()),
  ];
  final centre = strips ~/ 2;
  // Line spacing from the strips around the middle; a picture in one of
  // them must not hide the lines.
  final spacings = [
    for (var k = centre - 4; k <= centre + 4; k += 2) ?_lineSpacing(profiles[k], sh),
  ]..sort();
  final spacing = spacings.length < 2 ? null : spacings[spacings.length ~/ 2];
  if (spacing == null) return page;

  // Bands of rows matched separately, top to bottom, since the lines near
  // the top of a curved page bow the other way from those near the bottom.
  const bands = [(0.04, 0.30), (0.26, 0.52), (0.48, 0.74), (0.70, 0.96)];

  // Outside the strips that matched, the shift is held at the last value
  // found rather than extended by the cubic.
  List<double>? fit(List<double?> shifts) {
    final xs = <double>[], ys = <double>[];
    for (var k = 0; k < strips; k++) {
      final v = shifts[k];
      if (v == null) continue;
      xs.add((x0 + (k + 0.5) * stripWidth) / (sw - 1));
      ys.add(v / sh);
    }
    if (xs.length < strips * 0.4) return null;
    final c = _robustCubic(xs, ys);
    if (c == null) return null;
    return [...c, xs.first, xs.last];
  }

  // For each band that could be followed: its middle row (full size) and
  // the shift of every column there.
  final rows = <double>[];
  final shifts = <Float64List>[];
  var bend = 0.0;
  for (final (lo, hi) in bands) {
    final c = fit(_chainShifts(profiles, centre, (sh * lo).round(), (sh * hi).round(), spacing ~/ 2));
    if (c == null) continue;
    final at = Float64List(w);
    for (var x = 0; x < w; x++) {
      at[x] = _eval(c, (x / (w - 1)).clamp(c[4], c[5])) * h;
    }
    final range = at.reduce(math.max) - at.reduce(math.min);
    // Over a tenth of the page is a mismatch, not a curve.
    if (range > h * 0.1) return page;
    bend = math.max(bend, range);
    rows.add((lo + hi) / 2 * h);
    shifts.add(at);
  }
  // Under half a percent is straight already.
  if (rows.length < 2 || bend < h * 0.005) return page;

  final out = RgbImage(w, h);
  for (var y = 0; y < h; y++) {
    // The bands either side of this row, and how far between them it is.
    var j = 0;
    while (j < rows.length - 2 && y > rows[j + 1]) {
      j++;
    }
    final f = ((y - rows[j]) / (rows[j + 1] - rows[j])).clamp(0.0, 1.0);
    final a = shifts[j], b = shifts[j + 1];
    for (var x = 0; x < w; x++) {
      final fy = y + a[x] + (b[x] - a[x]) * f;
      _sample(page, x.toDouble(), fy, out.data, (y * w + x) * 3);
    }
  }
  return out;
}

/// The page shrunk to [sw] x [sh], as brightness.
Uint8List _smallLuma(RgbImage page, int sw, int sh) {
  final out = Uint8List(sw * sh);
  final d = page.data;
  for (var y = 0; y < sh; y++) {
    final sy = (y * (page.height - 1) / math.max(1, sh - 1)).round();
    for (var x = 0; x < sw; x++) {
      final sx = (x * (page.width - 1) / math.max(1, sw - 1)).round();
      final i = (sy * page.width + sx) * 3;
      out[y * sw + x] = (d[i] * 77 + d[i + 1] * 150 + d[i + 2] * 29) >> 8;
    }
  }
  return out;
}

/// 1 where a pixel is clearly darker than the paper around it (ink), from
/// a local mean over a window about 3% of the page wide.
Uint8List _inkMap(Uint8List luma, int w, int h) {
  final sum = Int64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0;
    for (var x = 0; x < w; x++) {
      row += luma[y * w + x];
      sum[(y + 1) * (w + 1) + x + 1] = sum[y * (w + 1) + x + 1] + row;
    }
  }
  final r = math.max(4, (math.max(w, h) * 0.015).round());
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final ya = math.max(0, y - r), yb = math.min(h, y + r + 1);
    for (var x = 0; x < w; x++) {
      final xa = math.max(0, x - r), xb = math.min(w, x + r + 1);
      final total = sum[yb * (w + 1) + xb] - sum[ya * (w + 1) + xb] - sum[yb * (w + 1) + xa] + sum[ya * (w + 1) + xa];
      final mean = total / ((yb - ya) * (xb - xa));
      if (luma[y * w + x] < mean - 18) out[y * w + x] = 1;
    }
  }
  return out;
}

/// Ink per row between columns [xa] and [xb], lightly smoothed.
Float64List _profile(Uint8List ink, int w, int h, int xa, int xb) {
  final raw = Float64List(h);
  for (var y = 0; y < h; y++) {
    var n = 0;
    for (var x = xa; x < xb; x++) {
      n += ink[y * w + x];
    }
    raw[y] = n.toDouble();
  }
  final out = Float64List(h);
  for (var y = 0; y < h; y++) {
    var s = 0.0;
    for (var k = -1; k <= 1; k++) {
      s += raw[(y + k).clamp(0, h - 1)];
    }
    out[y] = s / 3;
  }
  return out;
}

/// Distance between lines of text in [profile], from its autocorrelation,
/// or null when the strip shows no regular lines (a picture, a blank page).
int? _lineSpacing(Float64List profile, int h) {
  final mean = profile.reduce((a, b) => a + b) / h;
  final centred = [for (final v in profile) v - mean];
  double corr(int lag) {
    var s = 0.0;
    for (var y = 0; y + lag < h; y++) {
      s += centred[y] * centred[y + lag];
    }
    return s;
  }

  final zero = corr(0);
  if (zero <= 0) return null;
  final lo = math.max(4, h ~/ 120), hi = h ~/ 8;
  int? best;
  var bestScore = 0.15;
  for (var lag = lo; lag <= hi; lag++) {
    final c = corr(lag) / zero;
    if (c > bestScore && c >= corr(lag - 1) / zero && c >= corr(lag + 1) / zero) {
      best = lag;
      bestScore = c;
      break;
    }
  }
  return best;
}

/// How far each strip's lines sit below the centre strip's, in rows
/// [lo]..[hi], found by matching each strip with its neighbour towards the
/// centre (at most [limit] rows apart). Null for a strip that does not match
/// clearly; the chain carries on past it.
List<double?> _chainShifts(List<Float64List> profiles, int centre, int lo, int hi, int limit) {
  final n = profiles.length;
  final shifts = List<double?>.filled(n, null);
  shifts[centre] = 0;
  void walk(int step) {
    var reference = centre;
    for (var k = centre + step; k >= 0 && k < n; k += step) {
      final (delta, score) = _bestShift(profiles[reference], profiles[k], lo, hi, limit);
      if (score < 0.55) continue;
      shifts[k] = shifts[reference]! + delta;
      reference = k;
    }
  }

  walk(1);
  walk(-1);
  return shifts;
}

/// The shift (rows) that best lines [b] up with [a] in rows [lo]..[hi],
/// at most [limit] rows either way, and how well they match (correlation,
/// -1 to 1).
(int, double) _bestShift(Float64List a, Float64List b, int lo, int hi, int limit) {
  var best = 0;
  var bestScore = -2.0;
  for (var d = -limit; d <= limit; d++) {
    var sab = 0.0, saa = 0.0, sbb = 0.0, sa = 0.0, sb = 0.0;
    var count = 0;
    for (var y = lo; y < hi; y++) {
      final yb = y + d;
      if (yb < 0 || yb >= b.length) continue;
      final va = a[y], vb = b[yb];
      sa += va;
      sb += vb;
      sab += va * vb;
      saa += va * va;
      sbb += vb * vb;
      count++;
    }
    if (count < (hi - lo) ~/ 2) continue;
    final cov = sab - sa * sb / count;
    final varA = saa - sa * sa / count, varB = sbb - sb * sb / count;
    if (varA <= 0 || varB <= 0) continue;
    final score = cov / math.sqrt(varA * varB);
    if (score > bestScore) {
      bestScore = score;
      best = d;
    }
  }
  return (best, bestScore);
}

/// Paints over fingers holding a book open: skin-coloured patches that
/// reach in from the side or bottom edge of the page, within the outer
/// margin, are filled with the colour of the paper around them.
///
/// Returns [page] itself when there are none. Patches in the middle of the
/// page, or so large they are more likely a photo on the page, are kept.
RgbImage removeFingers(RgbImage page) {
  final w = page.width, h = page.height;
  if (w < 16 || h < 16) return page;
  final band = (math.min(w, h) * 0.18).round();
  bool inBand(int x, int y) => x < band || x >= w - band || y >= h - band;

  final d = page.data;
  final skin = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!inBand(x, y)) continue;
      final i = (y * w + x) * 3;
      if (isSkin(d[i], d[i + 1], d[i + 2])) skin[y * w + x] = 1;
    }
  }

  // Keep only patches that come in from the left, right or bottom edge, as
  // a finger does, and enter narrowly: a patch along most of a side is the
  // desk or the book's cover, not a finger.
  final mask = Uint8List(w * h);
  final seen = Uint8List(w * h);
  var filled = 0;
  void follow(int start) {
    if (skin[start] == 0 || seen[start] == 1) return;
    final patch = <int>[start];
    seen[start] = 1;
    var edge = 0;
    for (var n = 0; n < patch.length; n++) {
      final i = patch[n];
      final x = i % w, y = i ~/ w;
      if (x == 0 || x == w - 1 || y == h - 1) edge++;
      for (final j in [if (x > 0) i - 1, if (x < w - 1) i + 1, if (y > 0) i - w, if (y < h - 1) i + w]) {
        if (skin[j] == 1 && seen[j] == 0) {
          seen[j] = 1;
          patch.add(j);
        }
      }
    }
    if (patch.length < w * h * 0.0005 || edge > math.min(w, h) * 0.3) return;
    for (final i in patch) {
      mask[i] = 1;
    }
    filled += patch.length;
  }

  for (var y = 0; y < h; y++) {
    follow(y * w);
    follow(y * w + w - 1);
  }
  for (var x = 0; x < w; x++) {
    follow((h - 1) * w + x);
  }
  // Nothing found, or so much it is more likely part of the page.
  if (filled == 0 || filled > w * h * 0.08) return page;

  // Grow the patch a little to cover the finger's soft edge and shadow.
  final grow = math.max(2, (math.min(w, h) * 0.012).round());
  final cover = _dilate(mask, w, h, grow);

  final out = RgbImage(w, h, Uint8List.fromList(d));
  final paper = _paperColours(page, cover, band);
  const strips = _paperStrips;
  for (var y = 0; y < h; y++) {
    final colour = paper[math.min(strips - 1, y * strips ~/ h)];
    for (var x = 0; x < w; x++) {
      if (cover[y * w + x] == 0) continue;
      final i = (y * w + x) * 3;
      out.data[i] = colour[0];
      out.data[i + 1] = colour[1];
      out.data[i + 2] = colour[2];
    }
  }
  return out;
}

/// Whether a colour is in the range of human skin, light to dark, under
/// ordinary indoor light (YCbCr rule with a red-dominance check, so cream
/// paper and wooden desks do not count).
bool isSkin(int r, int g, int b) {
  final y = 0.299 * r + 0.587 * g + 0.114 * b;
  final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
  final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
  return y > 45 && y < 235 && cr >= 138 && cr <= 178 && cb >= 77 && cb <= 125 && r > g && r > b && r - b > 25;
}

const _paperStrips = 24;

/// The paper's colour in each horizontal strip of the page, from the margin
/// pixels that are not covered: the middle of the brighter three quarters,
/// since text is dark.
List<List<int>> _paperColours(RgbImage page, Uint8List cover, int band) {
  final w = page.width, h = page.height, d = page.data;
  final result = <List<int>>[];
  List<int>? last;
  for (var s = 0; s < _paperStrips; s++) {
    final y0 = s * h ~/ _paperStrips, y1 = (s + 1) * h ~/ _paperStrips;
    final samples = <List<int>>[];
    for (var y = y0; y < y1; y += 2) {
      for (var x = 0; x < w; x += 2) {
        if (cover[y * w + x] == 1) continue;
        if (x >= band * 2 && x < w - band * 2) continue;
        final i = (y * w + x) * 3;
        if (isSkin(d[i], d[i + 1], d[i + 2])) continue;
        samples.add([d[i], d[i + 1], d[i + 2]]);
      }
    }
    if (samples.isEmpty) {
      result.add(last ?? const [245, 245, 245]);
      continue;
    }
    samples.sort((a, b) => (b[0] + b[1] + b[2]).compareTo(a[0] + a[1] + a[2]));
    final c = samples[(samples.length * 0.375).floor()];
    result.add(c);
    last = c;
  }
  return result;
}

Uint8List _dilate(Uint8List mask, int w, int h, int r) {
  // Two passes of a square grow: rows, then columns.
  final rows = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    var last = -1 << 30;
    for (var x = 0; x < w; x++) {
      if (mask[y * w + x] == 1) last = x;
      if (x - last <= r) rows[y * w + x] = 1;
    }
    last = 1 << 30;
    for (var x = w - 1; x >= 0; x--) {
      if (mask[y * w + x] == 1) last = x;
      if (last - x <= r) rows[y * w + x] = 1;
    }
  }
  final out = Uint8List(w * h);
  for (var x = 0; x < w; x++) {
    var last = -1 << 30;
    for (var y = 0; y < h; y++) {
      if (rows[y * w + x] == 1) last = y;
      if (y - last <= r) out[y * w + x] = 1;
    }
    last = 1 << 30;
    for (var y = h - 1; y >= 0; y--) {
      if (rows[y * w + x] == 1) last = y;
      if (last - y <= r) out[y * w + x] = 1;
    }
  }
  return out;
}

/// Least-squares cubic through the points, fitted twice: the second time
/// without points far from the first fit (a finger or a stray mark on the
/// edge). Null when the points cannot hold a cubic.
List<double>? _robustCubic(List<double> xs, List<double> ys) {
  var fit = _cubic(xs, ys);
  if (fit == null) return null;
  final residuals = [for (var i = 0; i < xs.length; i++) (ys[i] - _eval(fit, xs[i])).abs()];
  final sorted = [...residuals]..sort();
  final limit = math.max(sorted[sorted.length ~/ 2] * 3, 0.004);
  final keepX = <double>[], keepY = <double>[];
  for (var i = 0; i < xs.length; i++) {
    if (residuals[i] <= limit) {
      keepX.add(xs[i]);
      keepY.add(ys[i]);
    }
  }
  if (keepX.length >= 8) fit = _cubic(keepX, keepY) ?? fit;
  return fit;
}

List<double>? _cubic(List<double> xs, List<double> ys) {
  const n = 4;
  final a = List.generate(n, (_) => List.filled(n + 1, 0.0));
  for (var i = 0; i < xs.length; i++) {
    final p = [1.0, xs[i], xs[i] * xs[i], xs[i] * xs[i] * xs[i]];
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        a[r][c] += p[r] * p[c];
      }
      a[r][n] += p[r] * ys[i];
    }
  }
  // Gaussian elimination with partial pivoting.
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var r = col + 1; r < n; r++) {
      if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
    }
    if (a[pivot][col].abs() < 1e-12) return null;
    final tmp = a[col];
    a[col] = a[pivot];
    a[pivot] = tmp;
    for (var r = 0; r < n; r++) {
      if (r == col) continue;
      final f = a[r][col] / a[col][col];
      for (var c = col; c <= n; c++) {
        a[r][c] -= f * a[col][c];
      }
    }
  }
  return [for (var r = 0; r < n; r++) a[r][n] / a[r][r]];
}

double _eval(List<double> c, double x) => c[0] + x * (c[1] + x * (c[2] + x * c[3]));

void _sample(RgbImage src, double fx, double fy, Uint8List out, int o) {
  final w = src.width, h = src.height, s = src.data;
  final x = fx.clamp(0.0, w - 1.0), y = fy.clamp(0.0, h - 1.0);
  final x0 = x.floor(), y0 = y.floor();
  final x1 = math.min(x0 + 1, w - 1), y1 = math.min(y0 + 1, h - 1);
  final ax = x - x0, ay = y - y0;
  final i00 = (y0 * w + x0) * 3, i10 = (y0 * w + x1) * 3;
  final i01 = (y1 * w + x0) * 3, i11 = (y1 * w + x1) * 3;
  for (var c = 0; c < 3; c++) {
    final top = s[i00 + c] + (s[i10 + c] - s[i00 + c]) * ax;
    final bottom = s[i01 + c] + (s[i11 + c] - s[i01 + c]) * ax;
    out[o + c] = (top + (bottom - top) * ay).round();
  }
}
