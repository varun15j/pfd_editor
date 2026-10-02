import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/models.dart';
import 'rgb_image.dart';

/// Perspective-corrects [src] so the quad becomes an upright rectangle.
/// Output size follows the longer opposite edges, which keeps text scale.
RgbImage warpPerspective(RgbImage src, CropQuad quad) {
  if (quad.isFull) return src;

  final sw = src.width - 1.0, sh = src.height - 1.0;
  final pts = quad.points.map((p) => (p.x * sw, p.y * sh)).toList();
  double dist((double, double) a, (double, double) b) =>
      math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

  final outW = math.max(dist(pts[0], pts[1]), dist(pts[3], pts[2])).round().clamp(1, 20000);
  final outH = math.max(dist(pts[0], pts[3]), dist(pts[1], pts[2])).round().clamp(1, 20000);

  // Homography from the output rectangle to the source quad.
  final h = _homography(
    [(0.0, 0.0), (outW - 1.0, 0.0), (outW - 1.0, outH - 1.0), (0.0, outH - 1.0)],
    pts,
  );

  final out = RgbImage(outW, outH);
  final s = src.data, d = out.data;
  final maxX = src.width - 1, maxY = src.height - 1;
  var o = 0;
  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      final w = h[6] * x + h[7] * y + 1.0;
      final fx = ((h[0] * x + h[1] * y + h[2]) / w).clamp(0.0, maxX.toDouble());
      final fy = ((h[3] * x + h[4] * y + h[5]) / w).clamp(0.0, maxY.toDouble());
      final x0 = fx.floor(), y0 = fy.floor();
      final x1 = x0 < maxX ? x0 + 1 : x0, y1 = y0 < maxY ? y0 + 1 : y0;
      final ax = fx - x0, ay = fy - y0;
      final i00 = (y0 * src.width + x0) * 3, i10 = (y0 * src.width + x1) * 3;
      final i01 = (y1 * src.width + x0) * 3, i11 = (y1 * src.width + x1) * 3;
      for (var c = 0; c < 3; c++) {
        final top = s[i00 + c] + (s[i10 + c] - s[i00 + c]) * ax;
        final bottom = s[i01 + c] + (s[i11 + c] - s[i01 + c]) * ax;
        d[o++] = (top + (bottom - top) * ay).round();
      }
    }
  }
  return out;
}

/// Rotates clockwise by 90° × [turns].
RgbImage rotateQuarterTurns(RgbImage src, int turns) {
  final t = turns % 4;
  if (t == 0) return src;
  final w = src.width, h = src.height;
  final outW = t.isOdd ? h : w, outH = t.isOdd ? w : h;
  final out = RgbImage(outW, outH);
  final s = src.data, d = out.data;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final int nx, ny;
      switch (t) {
        case 1:
          nx = h - 1 - y;
          ny = x;
        case 2:
          nx = w - 1 - x;
          ny = h - 1 - y;
        default:
          nx = y;
          ny = w - 1 - x;
      }
      final si = (y * w + x) * 3, di = (ny * outW + nx) * 3;
      d[di] = s[si];
      d[di + 1] = s[si + 1];
      d[di + 2] = s[si + 2];
    }
  }
  return out;
}

/// Solves the 8 homography coefficients mapping [from] to [to].
Float64List _homography(List<(double, double)> from, List<(double, double)> to) {
  final a = List.generate(8, (_) => Float64List(9));
  for (var i = 0; i < 4; i++) {
    final (x, y) = from[i];
    final (u, v) = to[i];
    a[i * 2].setAll(0, [x, y, 1, 0, 0, 0, -u * x, -u * y, u]);
    a[i * 2 + 1].setAll(0, [0, 0, 0, x, y, 1, -v * x, -v * y, v]);
  }
  // Gaussian elimination with partial pivoting.
  for (var col = 0; col < 8; col++) {
    var pivot = col;
    for (var r = col + 1; r < 8; r++) {
      if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
    }
    final tmp = a[col];
    a[col] = a[pivot];
    a[pivot] = tmp;
    final p = a[col][col];
    if (p.abs() < 1e-12) throw StateError('Degenerate crop quad');
    for (var c = col; c < 9; c++) {
      a[col][c] /= p;
    }
    for (var r = 0; r < 8; r++) {
      if (r == col) continue;
      final f = a[r][col];
      if (f == 0) continue;
      for (var c = col; c < 9; c++) {
        a[r][c] -= f * a[col][c];
      }
    }
  }
  return Float64List.fromList([for (var r = 0; r < 8; r++) a[r][8]]);
}
