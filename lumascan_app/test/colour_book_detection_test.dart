import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/debug/sample_pages.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/imaging/page_detector.dart';
import 'package:lumascan/imaging/rgb_image.dart';

CropQuad _q(double a, double b, double c, double d, double e, double f, double g, double h) =>
    CropQuad(NormPoint(a, b), NormPoint(c, d), NormPoint(e, f), NormPoint(g, h));

/// The page in each of the 22 colour book photos, marked by hand (to about
/// 2% of the frame): the right-hand page, then the spread with the facing
/// page as far as it is in view. 03 and 16 are pages being turned, with
/// only the page itself marked.
final _marked = <String, List<CropQuad>>{
  '01': [_q(0.16, 0.29, 0.81, 0.265, 0.9, 0.813, 0.16, 0.827), _q(0, 0.27, 0.81, 0.265, 0.9, 0.813, 0, 0.845)],
  '02': [_q(0.087, 0.283, 0.74, 0.262, 0.818, 0.812, 0.093, 0.827), _q(0, 0.27, 0.74, 0.262, 0.818, 0.812, 0, 0.84)],
  '03': [_q(0, 0.265, 0.32, 0.222, 0.57, 0.765, 0, 0.87)],
  '04': [_q(0.14, 0.257, 0.8, 0.228, 0.86, 0.787, 0.146, 0.798), _q(0, 0.24, 0.8, 0.228, 0.86, 0.787, 0, 0.8)],
  '05': [_q(0.13, 0.205, 0.87, 0.19, 0.89, 0.8, 0.126, 0.8), _q(0, 0.19, 0.87, 0.19, 0.89, 0.8, 0, 0.8)],
  '06': [_q(0.107, 0.205, 0.797, 0.173, 0.878, 0.787, 0.12, 0.792), _q(0, 0.19, 0.797, 0.173, 0.878, 0.787, 0, 0.8)],
  '07': [_q(0.053, 0.217, 0.773, 0.18, 0.83, 0.779, 0.063, 0.787), _q(0, 0.2, 0.773, 0.18, 0.83, 0.779, 0, 0.79)],
  '08': [_q(0.018, 0.226, 0.787, 0.18, 0.83, 0.787, 0.069, 0.804), _q(0, 0.2, 0.787, 0.18, 0.83, 0.787, 0, 0.8)],
  '09': [_q(0.05, 0.209, 0.755, 0.177, 0.8, 0.779, 0.057, 0.784), _q(0, 0.2, 0.755, 0.177, 0.8, 0.779, 0, 0.79)],
  '10': [_q(0.081, 0.177, 0.824, 0.152, 0.858, 0.773, 0.093, 0.764), _q(0, 0.16, 0.824, 0.152, 0.858, 0.773, 0, 0.77)],
  '11': [_q(0.053, 0.137, 0.844, 0.105, 0.864, 0.73, 0.083, 0.741), _q(0, 0.13, 0.844, 0.105, 0.864, 0.73, 0, 0.75)],
  '12': [_q(0.039, 0.157, 0.775, 0.12, 0.83, 0.73, 0.069, 0.741), _q(0, 0.13, 0.775, 0.12, 0.83, 0.73, 0, 0.75)],
  '13': [_q(0.081, 0.336, 0.73, 0.31, 0.82, 0.884, 0.091, 0.9), _q(0, 0.32, 0.73, 0.31, 0.82, 0.884, 0, 0.91)],
  '14': [_q(0.107, 0.285, 0.776, 0.277, 0.817, 0.857, 0.075, 0.855), _q(0, 0.27, 0.776, 0.277, 0.817, 0.857, 0, 0.86)],
  '15': [_q(0.083, 0.291, 0.763, 0.242, 0.813, 0.829, 0.073, 0.844), _q(0, 0.29, 0.763, 0.242, 0.813, 0.829, 0, 0.85)],
  '16': [_q(0.018, 0.29, 0.27, 0.265, 0.507, 0.827, 0.004, 0.895)],
  '17': [_q(0.187, 0.277, 0.862, 0.262, 0.903, 0.827, 0.187, 0.836), _q(0, 0.225, 0.862, 0.262, 0.903, 0.827, 0, 0.87)],
  '18': [_q(0.28, 0.249, 0.933, 0.237, 0.945, 0.798, 0.28, 0.81), _q(0, 0.215, 0.933, 0.237, 0.945, 0.798, 0, 0.85)],
  '19': [_q(0.252, 0.299, 0.864, 0.283, 0.884, 0.832, 0.252, 0.841), _q(0, 0.25, 0.864, 0.283, 0.884, 0.832, 0, 0.89)],
  '20': [_q(0.14, 0.306, 0.673, 0.268, 0.82, 0.804, 0.211, 0.844), _q(0, 0.24, 0.673, 0.268, 0.82, 0.804, 0, 0.86)],
  '21': [_q(0.142, 0.285, 0.69, 0.268, 0.734, 0.827, 0.158, 0.829), _q(0, 0.2, 0.69, 0.268, 0.734, 0.827, 0, 0.9)],
  '22': [_q(0.154, 0.262, 0.823, 0.245, 0.892, 0.8, 0.178, 0.819), _q(0, 0.24, 0.823, 0.245, 0.892, 0.8, 0, 0.86)],
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

  test('the 22 colour book photos are bundled at 1080 x 1920, each with its page marked', () async {
    expect(colourBookSamples.assets, hasLength(22));
    for (final asset in colourBookSamples.assets) {
      final photo = RgbImage.decode((await rootBundle.load(asset)).buffer.asUint8List());
      expect((photo.width, photo.height), (1080, 1920), reason: asset);
      expect(_marked, contains(asset.split('/').last.substring(0, 2)), reason: asset);
    }
  });

  // Measured 2026-10-26: mean 0.84 in the photo and 0.79 in a colour
  // preview frame, 13 and 14 pages at 0.9 or better. Before the edge
  // outlines the photo mean was 0.82 (17, a spread of colour photos, found
  // nothing). Weak: 03 and 16 (a page being turned, blurred), 04 (taken to
  // the scroll border inside the page), 17, 18, 22 (a big photo or a
  // coloured panel splits the page).
  test('the page is found in the colour book photos, in a photo and in a camera preview frame', () async {
    for (final (size, work, minArea, mean) in const [(640, 320, 0.1, 0.82), (200, 160, 0.2, 0.77)]) {
      var sum = 0.0, good = 0;
      final scores = <String>[];
      for (final asset in colourBookSamples.assets) {
        final name = asset.split('/').last.substring(0, 2);
        final photo = RgbImage.decode((await rootBundle.load(asset)).buffer.asUint8List(), maxDimension: size);
        final quad = detectPageQuad(photo, workSize: work, minArea: minArea);
        final iou = quad == null ? 0.0 : _marked[name]!.map((m) => _iou(quad, m)).reduce((a, b) => a > b ? a : b);
        sum += iou;
        if (iou >= 0.9) good++;
        scores.add('$name:${iou.toStringAsFixed(2)}');
      }
      final reason = 'size $size: ${scores.join(' ')}';
      expect(sum / colourBookSamples.assets.length, greaterThanOrEqualTo(mean), reason: reason);
      expect(good, greaterThanOrEqualTo(12), reason: reason);
    }
  });
}
