import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/imaging/page_detector.dart';
import 'package:lumascan/imaging/rgb_image.dart';

typedef _Rgb = (int, int, int);

/// A photo of a page made of [bands] of colour (top to bottom, or left to
/// right with [across]) lying on a plain [background], tilted by [tilt]
/// radians. Light noise stands in for paper grain and sensor noise.
(RgbImage, CropQuad) _photo({
  required _Rgb background,
  required List<_Rgb> bands,
  bool across = false,
  double tilt = 0,
  double left = 0.18,
  double top = 0.12,
  double right = 0.82,
  double bottom = 0.9,
  int seed = 1,
}) {
  const w = 480, h = 640;
  final im = RgbImage(w, h);
  final rnd = math.Random(seed);
  final cx = (left + right) / 2 * w, cy = (top + bottom) / 2 * h;
  final c = math.cos(tilt), s = math.sin(tilt);
  // Page space (u, v in 0..1) to image pixels, rotated about the centre.
  (double, double) toImage(double u, double v) {
    final x = (left + (right - left) * u) * w - cx, y = (top + (bottom - top) * v) * h - cy;
    return (cx + x * c - y * s, cy + x * s + y * c);
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      // Back to page space.
      final dx = x - cx, dy = y - cy;
      final px = cx + dx * c + dy * s, py = cy - dx * s + dy * c;
      final u = (px / w - left) / (right - left), v = (py / h - top) / (bottom - top);
      _Rgb colour = background;
      if (u >= 0 && u < 1 && v >= 0 && v < 1) {
        colour = bands[((across ? u : v) * bands.length).floor().clamp(0, bands.length - 1)];
      }
      final n = rnd.nextInt(9) - 4;
      final i = (y * w + x) * 3;
      im.data[i] = (colour.$1 + n).clamp(0, 255);
      im.data[i + 1] = (colour.$2 + n).clamp(0, 255);
      im.data[i + 2] = (colour.$3 + n).clamp(0, 255);
    }
  }
  NormPoint p(double u, double v) {
    final (x, y) = toImage(u, v);
    return NormPoint(x / w, y / h);
  }

  return (im, CropQuad(p(0, 0), p(1, 0), p(1, 1), p(0, 1)));
}

double _iou(CropQuad a, CropQuad b) {
  bool inside(CropQuad q, double x, double y) {
    final p = q.points;
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final s = ((p[(i + 1) % 4].x - p[i].x) * (y - p[i].y) - (p[(i + 1) % 4].y - p[i].y) * (x - p[i].x)).sign.toInt();
      if (s == 0) continue;
      if (sign == 0) sign = s;
      if (s != sign) return false;
    }
    return true;
  }

  var both = 0, either = 0;
  for (var j = 0; j < 160; j++) {
    for (var i = 0; i < 120; i++) {
      final x = (i + 0.5) / 120, y = (j + 0.5) / 160;
      final inA = inside(a, x, y), inB = inside(b, x, y);
      if (inA && inB) both++;
      if (inA || inB) either++;
    }
  }
  return either == 0 ? 0 : both / either;
}

const _white = (240, 240, 236), _pink = (236, 160, 172), _blue = (156, 198, 236);
const _yellow = (240, 224, 120), _green = (150, 205, 150), _orange = (225, 125, 50);
const _wood = (120, 86, 58), _grey = (92, 92, 96), _dark = (40, 40, 44), _beige = (200, 180, 150);

void main() {
  // Pages printed or made of two or three colours: before 2026-10-12 only
  // the band in the middle, or the white one, was found.
  final cases = <String, (RgbImage, CropQuad)>{
    'white, pink and blue bands on wood': _photo(background: _wood, bands: [_white, _pink, _blue]),
    'pink, white and blue bands on wood': _photo(background: _wood, bands: [_pink, _white, _blue]),
    'yellow, white and green bands on grey': _photo(background: _grey, bands: [_yellow, _white, _green]),
    'side by side white, pink and blue on a dark desk': _photo(
      background: _dark,
      bands: [_white, _pink, _blue],
      across: true,
    ),
    'orange header over a white page on beige': _photo(background: _beige, bands: [_orange, _white, _white, _white]),
    'tilted three-colour page on wood': _photo(background: _wood, bands: [_blue, _white, _yellow], tilt: 0.12, seed: 3),
    'white page with a coloured footer on grey': _photo(background: _grey, bands: [_white, _white, _white, _green]),
  };
  for (final MapEntry(key: name, value: (photo, page)) in cases.entries) {
    test('finds the whole page: $name', () {
      for (final (work, minArea) in [(320, 0.1), (160, 0.2)]) {
        final quad = detectPageQuad(photo, workSize: work, minArea: minArea);
        expect(quad, isNotNull, reason: 'work size $work');
        expect(_iou(quad!, page), greaterThan(0.9), reason: "work size $work: $quad");
      }
    });
  }

  test('a plain white page on wood is still found', () {
    final (photo, page) = _photo(background: _wood, bands: [_white]);
    expect(_iou(detectPageQuad(photo)!, page), greaterThan(0.9));
  });
}
