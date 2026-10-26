import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/debug/sample_pages.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/imaging/page_detector.dart';
import 'package:lumascan/imaging/rgb_image.dart';

CropQuad _quad(List<dynamic> corners) {
  final p = [for (final c in corners) NormPoint((c[0] as num).toDouble(), (c[1] as num).toDouble())];
  return CropQuad(p[0], p[1], p[2], p[3]);
}

CropQuad _q(double a, double b, double c, double d, double e, double f, double g, double h) =>
    CropQuad(NormPoint(a, b), NormPoint(c, d), NormPoint(e, f), NormPoint(g, h));

/// The page in each odds book photo (a colour book, `sample_scan_img/odds_book/`),
/// marked by hand to about 2% of the frame. Where the spread or the facing
/// page is as much the page in view, each is listed.
final _oddsMarked = <String, List<CropQuad>>{
  '01': [_q(0, 0.165, 0.81, 0.145, 0.82, 0.83, 0, 0.77), _q(0, 0.165, 1, 0.15, 1, 0.82, 0, 0.77)],
  '02': [_q(0.075, 0.235, 0.79, 0.21, 0.93, 0.725, 0.05, 0.765)],
  '03': [
    _q(0.055, 0.333, 0.63, 0.305, 0.69, 0.815, 0.1, 0.8),
    _q(0.055, 0.333, 1, 0.31, 1, 0.8, 0.1, 0.8),
  ],
  '04': [_q(0.01, 0.35, 0.67, 0.3, 0.885, 0.785, 0, 0.87)],
  '05': [_q(0.01, 0.235, 0.735, 0.21, 0.925, 0.735, 0, 0.8)],
  '06': [
    _q(0, 0.125, 0.63, 0.18, 0.66, 0.6, 0, 0.57),
    _q(0.63, 0.18, 1, 0.17, 1, 0.63, 0.66, 0.6),
    _q(0, 0.125, 1, 0.17, 1, 0.63, 0, 0.57),
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

/// Overlap of two outlines, as intersection over union, on a grid 100 wide
/// and [rows] high (the photo's shape). Only the part inside the frame
/// counts, so a page that runs off the edge is compared by what is in view.
double _iou(CropQuad a, CropQuad b, int rows) {
  var both = 0, either = 0;
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < 100; i++) {
      final x = (i + 0.5) / 100, y = (j + 0.5) / rows;
      final inA = _inside(a, x, y), inB = _inside(b, x, y);
      if (inA && inB) both++;
      if (inA || inB) either++;
    }
  }
  return either == 0 ? 0 : both / either;
}

/// How well [found] matches the best of the [marked] outlines.
double _best(CropQuad? found, List<CropQuad> marked, {int rows = 133}) =>
    found == null ? 0 : marked.map((m) => _iou(found, m, rows)).reduce((a, b) => a > b ? a : b);

class _Sample {
  _Sample(this.file, this.group, this.pages);

  final String file;
  final String group;
  final List<CropQuad> pages;
}

Future<List<_Sample>> _samples() async {
  final json = jsonDecode(await rootBundle.loadString('sample_photos/edge/corners.json')) as Map<String, dynamic>;
  return [
    for (final s in json['samples'] as List)
      _Sample(s['file'] as String, s['group'] as String, [for (final p in s['pages'] as List) _quad(p as List)]),
  ];
}

Future<RgbImage> _load(String asset, int size) async =>
    RgbImage.decode((await rootBundle.load(asset)).buffer.asUint8List(), maxDimension: size);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every edge test page is bundled, listed in the debug set and has its corners', () async {
    final samples = await _samples();
    expect(samples, hasLength(edgeSamples.assets.length));
    expect(edgeSamples.assets, [for (final s in samples) 'sample_photos/edge/${s.file}']);
    expect(samples.map((s) => s.group).toSet(), {'colour', 'bw', 'book'});
    for (final s in samples) {
      final photo = await _load('sample_photos/edge/${s.file}', 4000);
      expect((photo.width, photo.height), (1080, 1440), reason: s.file);
      expect(s.pages, isNotEmpty, reason: s.file);
    }
  });

  // Measured 2026-10-26 (640 px): colour 0.97, black and white 0.75,
  // book 0.92. The weak pages, kept as targets for the detector:
  // b02 (a shadow across the page, 0.71), b05 (a narrow slip, rejected as a
  // strip, 0), b07 (a colour page on wood in a greyscale photo, 0.66).
  const weak = {'b02', 'b05', 'b07'};

  test('the page is found in the edge test pages, at the photo and the preview size', () async {
    final samples = await _samples();
    for (final (size, work, minArea) in [(640, 320, 0.1), (200, 160, 0.2)]) {
      final sums = <String, double>{}, counts = <String, int>{};
      final scores = <String>[];
      final low = <String>[];
      for (final s in samples) {
        final id = s.file.substring(0, 3);
        final quad = detectPageQuad(await _load('sample_photos/edge/${s.file}', size), workSize: work, minArea: minArea);
        final iou = _best(quad, s.pages);
        sums[s.group] = (sums[s.group] ?? 0) + iou;
        counts[s.group] = (counts[s.group] ?? 0) + 1;
        scores.add('$id:${iou.toStringAsFixed(2)}');
        if (!weak.contains(id) && iou < 0.85) low.add(id);
      }
      double mean(String g) => sums[g]! / counts[g]!;
      final reason = 'size $size: ${scores.join(' ')}';
      expect(low, isEmpty, reason: reason);
      expect(mean('colour'), greaterThanOrEqualTo(0.93), reason: reason);
      expect(mean('bw'), greaterThanOrEqualTo(0.7), reason: reason);
      expect(mean('book'), greaterThanOrEqualTo(0.85), reason: reason);
    }
  });

  // Measured 2026-10-26: mean 0.83; 03 (the facing page and a laptop
  // behind, 0.67) and 05 (a cable over the edge, 0.71) are the weak ones.
  test('the page is found in the odds book photos (colour book)', () async {
    final scores = <String>[];
    var sum = 0.0, worst = 1.0;
    for (final asset in oddsBookSamples.assets) {
      final name = asset.split('/').last.substring(0, 2);
      final iou = _best(detectPageQuad(await _load(asset, 640)), _oddsMarked[name]!, rows: 178);
      sum += iou;
      if (iou < worst) worst = iou;
      scores.add('$name:${iou.toStringAsFixed(2)}');
    }
    expect(sum / oddsBookSamples.assets.length, greaterThanOrEqualTo(0.8), reason: scores.join(' '));
    expect(worst, greaterThanOrEqualTo(0.6), reason: scores.join(' '));
  });
}
