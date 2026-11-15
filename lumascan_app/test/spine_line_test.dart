import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/imaging/book_split.dart';
import 'package:lumascan/imaging/rgb_image.dart';

import 'support/edge_model_fixture.dart';

/// A 300 x 400 picture of an open book filling the frame: the left page
/// [left] grey, the right page [right] grey, and the spine running from
/// [top] to [bottom] (fractions of the width), [notch] darker than both for
/// 3 pixels. Text-like dark bars cross both pages.
RgbImage _spread({required int left, required int right, required double top, required double bottom, int notch = 0}) {
  const w = 300, h = 400;
  final image = RgbImage(w, h);
  final d = image.data;
  for (var y = 0; y < h; y++) {
    final spine = (top + (bottom - top) * y / (h - 1)) * (w - 1);
    for (var x = 0; x < w; x++) {
      var v = x < spine ? left : right;
      if ((x - spine).abs() < 1.5) v = math.min(left, right) - notch;
      // Lines of "text" with a margin either side of the spine.
      if (y % 12 < 4 && (x - spine).abs() > 14 && x > 12 && x < w - 12) v -= 70;
      final i = (y * w + x) * 3;
      d[i] = d[i + 1] = d[i + 2] = v.clamp(0, 255);
    }
  }
  return image;
}

void main() {
  group('spineLine', () {
    test('finds a spine that is only a step between two differently lit pages', () {
      final (top, bottom) = spineLine(_spread(left: 150, right: 205, top: 0.58, bottom: 0.58), CropQuad.full);
      expect(top, closeTo(0.58, 0.015));
      expect(bottom, closeTo(0.58, 0.015));
    });

    test('follows a spine that leans', () {
      final (top, bottom) = spineLine(_spread(left: 150, right: 205, top: 0.47, bottom: 0.53), CropQuad.full);
      expect(top, closeTo(0.47, 0.02));
      expect(bottom, closeTo(0.53, 0.02));
    });

    test('finds a spine that is only a dark gutter between two pages lit alike', () {
      final (top, bottom) = spineLine(_spread(left: 200, right: 200, top: 0.44, bottom: 0.46, notch: 60), CropQuad.full);
      expect(top, closeTo(0.44, 0.02));
      expect(bottom, closeTo(0.46, 0.02));
    });

    test('splits down the middle when nothing looks like a spine', () {
      final blank = RgbImage(300, 400)..data.fillRange(0, 300 * 400 * 3, 190);
      expect(spineLine(blank, CropQuad.full), (0.5, 0.5));
    });

    test('a picture edge beside the spine does not win: it is not there along the whole page', () {
      final image = _spread(left: 190, right: 205, top: 0.5, bottom: 0.5, notch: 40);
      // A dark picture on the left page, a fifth of the page high.
      for (var y = 120; y < 200; y++) {
        for (var x = 100; x < 126; x++) {
          final i = (y * 300 + x) * 3;
          image.data[i] = image.data[i + 1] = image.data[i + 2] = 20;
        }
      }
      final (top, bottom) = spineLine(image, CropQuad.full);
      expect(top, closeTo(0.5, 0.015));
      expect(bottom, closeTo(0.5, 0.015));
    });
  });

  // The open books among the sample photos where both pages are marked:
  // four real book photos, one odds book photo and three made spreads.
  // The darkest column in the middle third (the spine finder until
  // 2026-11-14) was 7.9% of the photo width off on average, and 11 to 27%
  // off on book photos 18, 19 and 20, where the left page lies in shadow.
  test('the spine of the marked open books is found to about 2% of the photo width', () {
    final fixture = EdgeModelFixture.load('v1_heldback');
    final errors = <String>[];
    var sum = 0.0, worst = 0.0;
    for (final p in fixture.photos) {
      final pages = _pages(p.marks);
      if (pages == null) continue;
      final (left, right) = pages;
      final spread = CropQuad(left.tl, right.tr, right.br, left.bl);
      final (s, t) = spineLine(p.load(), spread);
      final topX = spread.tl.x + (spread.tr.x - spread.tl.x) * s, bottomX = spread.bl.x + (spread.br.x - spread.bl.x) * t;
      final error = ((topX - (left.tr.x + right.tl.x) / 2).abs() + (bottomX - (left.br.x + right.bl.x) / 2).abs()) / 2;
      sum += error;
      worst = math.max(worst, error);
      errors.add('${p.name.substring(0, 3)}:${(error * 100).toStringAsFixed(1)}%');
    }
    expect(errors, hasLength(8));
    expect(sum / errors.length, lessThan(0.022), reason: errors.join(' '));
    expect(worst, lessThan(0.04), reason: errors.join(' '));
  });
}

/// The left and right page among a photo's marks, when both are marked.
(CropQuad, CropQuad)? _pages(List<CropQuad> marks) {
  for (final a in marks) {
    for (final b in marks) {
      if ((a.tr.x - b.tl.x).abs() < 0.05 &&
          (a.br.x - b.bl.x).abs() < 0.08 &&
          a.tl.x < b.tl.x - 0.2 &&
          b.tr.x > a.tr.x + 0.2) {
        return (a, b);
      }
    }
  }
  return null;
}
