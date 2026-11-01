import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../pdf_edit/annotations.dart';
import 'rgb_image.dart';

/// Paints each mask into [image]'s pixels, so what it hides is gone from the
/// picture itself and not just covered in a layer above. Edges are rounded
/// outwards, so a mask never leaves a sliver showing.
///
/// A solid mask is filled with its colour. A mask that crosses out
/// characters is filled with the colour of the paper around it and gets one
/// X per hidden character, in a dark ink on light paper or a light one on
/// dark paper.
void burnMasks(RgbImage image, Iterable<MaskAnnotation> masks) {
  final w = image.width, h = image.height, data = image.data;
  for (final m in masks) {
    final x0 = (m.left * w).floor().clamp(0, w), x1 = (m.right * w).ceil().clamp(0, w);
    final y0 = (m.top * h).floor().clamp(0, h), y1 = (m.bottom * h).ceil().clamp(0, h);
    if (x1 <= x0 || y1 <= y0) continue;
    final fill = m.crossesOut ? paperAround(image, x0, y0, x1, y1) : m.color;
    _fill(data, w, x0, y0, x1, y1, fill);
    if (m.crossesOut) {
      final luma = 0.299 * ((fill >> 16) & 0xFF) + 0.587 * ((fill >> 8) & 0xFF) + 0.114 * (fill & 0xFF);
      final ink = luma >= 128 ? crossInkOnLight : crossInkOnDark;
      for (final c in crossCells(x0.toDouble(), y0.toDouble(), x1.toDouble(), y1.toDouble(), m.crosses)) {
        _cross(data, w, h, c, ink);
      }
    }
  }
}

/// X colours: near-black on light paper, near-white on dark paper.
const crossInkOnLight = 0xFF202124;
const crossInkOnDark = 0xFFF1F3F4;

/// The box of each X when [count] crosses share the box from ([x0], [y0])
/// to ([x1], [y1]): equal cells across, each X a little inside its cell.
/// Shared by the burned-in picture and the on-screen preview.
List<({double left, double top, double right, double bottom, double stroke})> crossCells(
  double x0,
  double y0,
  double x1,
  double y1,
  int count,
) {
  if (count <= 0) return const [];
  final cell = (x1 - x0) / count, height = y1 - y0;
  // Keep each X about as wide as it is tall, as a character would be.
  final xw = cell * 0.7 < height * 0.6 ? cell * 0.7 : height * 0.6;
  final xh = height * 0.6;
  final stroke = (xh * 0.14).clamp(1.0, double.infinity);
  return [
    for (var i = 0; i < count; i++)
      (
        left: x0 + cell * i + (cell - xw) / 2,
        top: y0 + (height - xh) / 2,
        right: x0 + cell * i + (cell + xw) / 2,
        bottom: y0 + (height + xh) / 2,
        stroke: stroke,
      ),
  ];
}

/// The colour of the paper just outside a box: the median of a ring of
/// pixels around it, so a stray letter beside the number does not darken it.
int paperAround(RgbImage image, int x0, int y0, int x1, int y1) {
  final w = image.width, h = image.height, data = image.data;
  final ring = 3;
  final rs = <int>[], gs = <int>[], bs = <int>[];
  void sample(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final i = (y * w + x) * 3;
    rs.add(data[i]);
    gs.add(data[i + 1]);
    bs.add(data[i + 2]);
  }

  final step = ((x1 - x0 + y1 - y0) ~/ 60).clamp(1, 1 << 20);
  for (var d = 1; d <= ring; d++) {
    for (var x = x0 - d; x < x1 + d; x += step) {
      sample(x, y0 - d);
      sample(x, y1 - 1 + d);
    }
    for (var y = y0; y < y1; y += step) {
      sample(x0 - d, y);
      sample(x1 - 1 + d, y);
    }
  }
  if (rs.isEmpty) return 0xFFFFFFFF;
  int median(List<int> v) => (v..sort())[v.length ~/ 2];
  return 0xFF000000 | (median(rs) << 16) | (median(gs) << 8) | median(bs);
}

void _fill(Uint8List data, int w, int x0, int y0, int x1, int y1, int argb) {
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  for (var y = y0; y < y1; y++) {
    for (var i = (y * w + x0) * 3, end = (y * w + x1) * 3; i < end; i += 3) {
      data[i] = r;
      data[i + 1] = g;
      data[i + 2] = b;
    }
  }
}

/// Both strokes of one X: every pixel close enough to either diagonal.
void _cross(
  Uint8List data,
  int w,
  int h,
  ({double left, double top, double right, double bottom, double stroke}) c,
  int argb,
) {
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  final dx = c.right - c.left, dy = c.bottom - c.top;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len == 0) return;
  final half = c.stroke / 2;
  final xs = (c.left - half).floor().clamp(0, w), xe = (c.right + half).ceil().clamp(0, w);
  final ys = (c.top - half).floor().clamp(0, h), ye = (c.bottom + half).ceil().clamp(0, h);
  for (var y = ys; y < ye; y++) {
    for (var x = xs; x < xe; x++) {
      final px = x + 0.5 - c.left, py = y + 0.5 - c.top;
      // Distance to the line top-left to bottom-right, and to the other one.
      final d1 = (px * dy - py * dx).abs() / len;
      final d2 = (px * dy - (dy - py) * dx).abs() / len;
      if (d1 <= half || d2 <= half) {
        final i = (y * w + x) * 3;
        data[i] = r;
        data[i + 1] = g;
        data[i + 2] = b;
      }
    }
  }
}

/// [jpeg] with [masks] burned in, encoded again at [quality]. Returns
/// [jpeg] itself when there are no masks.
Uint8List burnMasksIntoJpeg(Uint8List jpeg, Iterable<MaskAnnotation> masks, {int quality = 90}) {
  if (masks.isEmpty) return jpeg;
  final decoded = img.decodeJpg(jpeg);
  if (decoded == null) throw const FormatException('Could not read the page picture to mask it');
  final image = RgbImage.fromImage(decoded);
  burnMasks(image, masks);
  return image.encodeJpg(quality: quality);
}
