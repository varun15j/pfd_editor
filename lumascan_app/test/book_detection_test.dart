import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/debug/sample_pages.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/imaging/page_detector.dart';
import 'package:lumascan/imaging/rgb_image.dart';

CropQuad _q(double a, double b, double c, double d, double e, double f, double g, double h) =>
    CropQuad(NormPoint(a, b), NormPoint(c, d), NormPoint(e, f), NormPoint(g, h));

/// The page in each of the 20 book photos, marked by hand (to about 2% of
/// the frame), by the photo's number. Where two pages, or the whole spread,
/// are equally the page in view, each is listed.
final _marked = <String, List<CropQuad>>{
  '01': [_q(0, 0.21, 0.71, 0.28, 0.72, 1, 0, 0.94)],
  '02': [_q(0.2, 0.18, 0.83, 0.105, 0.97, 0.88, 0.37, 1)],
  '03': [_q(0.11, 0.26, 0.8, 0.2, 0.92, 0.86, 0.13, 0.93)],
  '04': [_q(0, 0.13, 0.63, 0.13, 0.66, 0.82, 0.02, 0.83)],
  '05': [_q(0.19, 0.29, 0.74, 0.33, 0.74, 0.95, 0, 0.9)],
  '06': [_q(0, 0.24, 0.83, 0.28, 0.83, 1, 0, 1)],
  '07': [_q(0.21, 0.19, 0.73, 0.27, 0.73, 0.77, 0.08, 0.73)],
  '08': [_q(0.14, 0.16, 0.86, 0.14, 0.94, 0.69, 0.22, 0.72)],
  '09': [_q(0.15, 0.24, 0.77, 0.3, 0.88, 1, 0.03, 1)],
  '10': [_q(0, 0.42, 0.7, 0.29, 0.77, 1, 0, 1)],
  '11': [_q(0.04, 0.53, 0.73, 0.3, 0.75, 1, 0, 1)],
  '12': [_q(0.25, 0.24, 0.89, 0.12, 1, 0.76, 0.36, 0.87)],
  '13': [_q(0.04, 0.15, 0.68, 0.24, 0.73, 0.86, 0, 0.88)],
  '14': [_q(0.11, 0.2, 0.76, 0.2, 0.78, 0.88, 0.04, 0.88)],
  '15': [_q(0.43, 0.25, 0.99, 0.06, 1, 0.78, 0.5, 0.82), _q(0, 0.14, 0.43, 0.25, 0.5, 0.82, 0, 0.85)],
  '16': [_q(0.21, 0.36, 0.72, 0.36, 0.75, 0.93, 0.2, 0.92)],
  '17': [_q(0.16, 0.37, 0.7, 0.37, 0.72, 0.93, 0.15, 0.92)],
  '18': [
    _q(0, 0.35, 0.58, 0.35, 0.59, 0.89, 0, 0.88),
    _q(0.56, 0.32, 0.97, 0.22, 0.97, 0.86, 0.6, 0.88),
    _q(0, 0.35, 0.97, 0.22, 0.97, 0.86, 0, 0.88),
  ],
  '19': [
    _q(0, 0.34, 0.58, 0.34, 0.59, 0.9, 0, 0.88),
    _q(0.56, 0.33, 0.96, 0.24, 0.96, 0.88, 0.6, 0.9),
    _q(0, 0.34, 0.96, 0.24, 0.96, 0.88, 0, 0.88),
  ],
  '20': [
    _q(0, 0.25, 0.47, 0.27, 0.5, 0.9, 0, 0.92),
    _q(0.47, 0.25, 0.91, 0.18, 0.92, 0.86, 0.53, 0.9),
    _q(0, 0.25, 0.91, 0.18, 0.92, 0.86, 0, 0.92),
  ],
};

bool _inside(CropQuad q, double x, double y) {
  final p = q.points;
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final a = p[i], b = p[(i + 1) % 4];
    final s = ((b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x)).sign.toInt();
    if (s == 0) continue;
    if (sign == 0) sign = s;
    if (s != sign) return false;
  }
  return true;
}

/// Overlap of two outlines, as intersection over union, on a 100 x 178 grid.
double _iou(CropQuad a, CropQuad b) {
  var both = 0, either = 0;
  for (var j = 0; j < 178; j++) {
    for (var i = 0; i < 100; i++) {
      final x = (i + 0.5) / 100, y = (j + 0.5) / 178;
      final inA = _inside(a, x, y), inB = _inside(b, x, y);
      if (inA && inB) both++;
      if (inA || inB) either++;
    }
  }
  return either == 0 ? 0 : both / either;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Before the colour-seeded mask, edge rating and centre preference
  // (2026-10-07) the mean was 0.54, with 2 of 20 photos at 0.85 or better.
  test('the page is found in the book photos, at the photo and the preview size', () async {
    for (final (size, work, minArea) in [(640, 320, 0.1), (200, 160, 0.2)]) {
      var sum = 0.0, good = 0;
      final scores = <String>[];
      for (final asset in bookSamples.assets) {
        final name = asset.split('/').last.substring(0, 2);
        final photo = RgbImage.decode((await rootBundle.load(asset)).buffer.asUint8List(), maxDimension: size);
        final quad = detectPageQuad(photo, workSize: work, minArea: minArea);
        final iou = quad == null ? 0.0 : _marked[name]!.map((m) => _iou(quad, m)).reduce((a, b) => a > b ? a : b);
        sum += iou;
        if (iou >= 0.85) good++;
        scores.add('$name:${iou.toStringAsFixed(2)}');
      }
      final mean = sum / bookSamples.assets.length;
      expect(mean, greaterThanOrEqualTo(0.8), reason: 'size $size: ${scores.join(' ')}');
      expect(good, greaterThanOrEqualTo(8), reason: 'size $size: ${scores.join(' ')}');
    }
  });
}
