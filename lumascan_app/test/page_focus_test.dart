import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/imaging/page_detector.dart';
import 'package:lumascan/imaging/page_focus.dart';
import 'package:lumascan/imaging/rgb_image.dart';

/// A grey desk with paper from [left] to [right] across and 10% to 90% down,
/// a gutter shadow at each of [seams], and lines of text on the paper.
RgbImage _photo({required double left, required double right, List<double> seams = const []}) {
  const w = 300, h = 400;
  final image = RgbImage(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final u = x / w, v = y / h;
      var value = 60;
      if (u >= left && u <= right && v >= 0.1 && v <= 0.9) {
        value = 225;
        // Text: short dark lines, with margins next to every seam.
        final nearSeam = seams.any((s) => (u - s).abs() < 0.05);
        final inText = u > left + 0.04 && u < right - 0.04 && v > 0.15 && v < 0.85;
        if (!nearSeam && inText && (y ~/ 6) % 2 == 0 && (x ~/ 9) % 4 != 3) value = 170;
        for (final s in seams) {
          final d = (u - s).abs();
          if (d < 0.015) value = (150 + 75 * d / 0.015).round();
        }
      }
      final o = (y * w + x) * 3;
      image.data
        ..[o] = value
        ..[o + 1] = value
        ..[o + 2] = value;
    }
  }
  return image;
}

void main() {
  test('a page with half of the next page beside it is outlined alone', () {
    // Left page from 5% to 65%; about half of the right page shows before
    // it runs off the frame.
    final quad = detectPageQuad(_photo(left: 0.05, right: 1, seams: [0.65]), minArea: 0.2)!;
    expect(quad.tl.x, closeTo(0.05, 0.03));
    expect(quad.tr.x, closeTo(0.65, 0.03));
    expect(quad.br.x, closeTo(0.65, 0.03));
  });

  test('the same holds with the cut-off page on the left', () {
    final quad = detectPageQuad(_photo(left: 0, right: 0.95, seams: [0.4]), minArea: 0.2)!;
    expect(quad.tl.x, closeTo(0.4, 0.03));
    expect(quad.tr.x, closeTo(0.95, 0.03));
  });

  test('a whole spread with both pages in view is kept together', () {
    final quad = detectPageQuad(_photo(left: 0.05, right: 0.95, seams: [0.5]), minArea: 0.2)!;
    expect(quad.tl.x, closeTo(0.05, 0.03));
    expect(quad.tr.x, closeTo(0.95, 0.03));
  });

  test('a single page of text is left as it is', () {
    final photo = _photo(left: 0.1, right: 0.9);
    const page = CropQuad(NormPoint(0.1, 0.1), NormPoint(0.9, 0.1), NormPoint(0.9, 0.9), NormPoint(0.1, 0.9));
    expect(focusOnePage(photo, page), page);
    // Running off the frame does not make text columns look like a seam.
    const offEdge = CropQuad(NormPoint(0.1, 0.1), NormPoint(1, 0.1), NormPoint(1, 0.9), NormPoint(0.1, 0.9));
    expect(focusOnePage(_photo(left: 0.1, right: 1), offEdge), offEdge);
  });
}
