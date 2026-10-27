import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/models.dart';
import 'rgb_image.dart';

/// Finds the four corners of a page with a small neural network, as a first
/// try before the hand-made detector ([detectPageQuad]).
///
/// The model is DocAligner's LCNet heatmap model (DocsaidLab/DocAligner,
/// Apache-2.0, `assets/models/`): a 256 x 256 RGB photo in, one 128 x 128
/// heatmap per corner out. It is sure of itself on a whole page in view,
/// whatever its colour or the surface under it, and finds nothing when a
/// corner is out of the frame, as with an open book filling the frame. So
/// its answer is used only when every corner stands out
/// ([minCornerConfidence]); otherwise the hand-made detector decides.
abstract class CornerModel {
  /// The page in [image], or null when the model is not sure of all four
  /// corners.
  CropQuad? find(RgbImage image);
}

/// Side of the square photo the model reads.
const cornerModelInputSize = 256;

/// Lowest heatmap peak, for every corner, at which the model's outline is
/// used. Measured on LumaScan's marked photos (2026-10-27): at 0.8 and above
/// the outline overlapped the true page by 0.84 to 0.99; below it, the model
/// is often wrong or has a corner off the frame.
const minCornerConfidence = 0.8;

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

/// The page outline read from the model's four corner heatmaps (each
/// [size] x [size], values 0..1), with its confidence: the weakest corner's
/// peak. Each corner is the centre of mass of its heatmap around the peak.
/// Null when a heatmap is empty.
(CropQuad, double)? readCornerHeatmaps(List<Float32List> maps, int size) {
  final pts = <NormPoint>[];
  var confidence = 1.0;
  for (final map in maps.take(4)) {
    var peak = 0.0;
    for (final v in map) {
      if (v > peak) peak = v;
    }
    if (peak < _heatThreshold) return null;
    confidence = math.min(confidence, peak);
    final cut = math.max(_heatThreshold, peak / 2);
    var sx = 0.0, sy = 0.0, sw = 0.0;
    for (var i = 0; i < map.length; i++) {
      final v = map[i];
      if (v < cut) continue;
      sx += (i % size) * v;
      sy += (i ~/ size) * v;
      sw += v;
    }
    pts.add(NormPoint(sx / sw / (size - 1), sy / sw / (size - 1)).clamp());
  }
  if (pts.length < 4) return null;
  // Order the corners round the middle, top left first, whatever order
  // the model gave them in.
  final cx = pts.fold(0.0, (s, p) => s + p.x) / 4, cy = pts.fold(0.0, (s, p) => s + p.y) / 4;
  pts.sort((a, b) => math.atan2(a.y - cy, a.x - cx).compareTo(math.atan2(b.y - cy, b.x - cx)));
  // atan2 order starts at the left (-pi) and runs top left, top right,
  // bottom right, bottom left in screen coordinates (y down).
  final start = [for (var k = 0; k < 4; k++) k].reduce((a, b) => pts[a].x + pts[a].y <= pts[b].x + pts[b].y ? a : b);
  final o = [for (var k = 0; k < 4; k++) pts[(start + k) % 4]];
  return (CropQuad(o[0], o[1], o[2], o[3]), confidence);
}
