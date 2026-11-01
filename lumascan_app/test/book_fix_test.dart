import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/imaging/book_fix.dart';
import 'package:lumascan/imaging/geometry.dart';
import 'package:lumascan/imaging/rgb_image.dart';

const _paper = 235;
const _skin = (224, 168, 136);

/// A page of text lines, each [bow] (x from 0 to 1) rows lower than it
/// would be on a flat page, like a book page curving towards its spine.
RgbImage _page({double Function(double x)? bow, int w = 600, int h = 800}) {
  final image = RgbImage(w, h)..data.fillRange(0, w * h * 3, _paper);
  for (var line = 0; line * 26 + 60 < h - 60; line++) {
    final base = 60 + line * 26;
    for (var x = 40; x < w - 40; x++) {
      // Words of 30 pixels with gaps of 8.
      if ((x + line * 13) % 38 > 30) continue;
      final top = base + (bow?.call(x / (w - 1)) ?? 0).round();
      for (var y = top; y < top + 7; y++) {
        final i = (y * w + x) * 3;
        image.data[i] = image.data[i + 1] = image.data[i + 2] = 30;
      }
    }
  }
  return image;
}

/// Middle row of the ink in the column band around [x], within rows lo..hi.
double _inkRow(RgbImage image, int x, int lo, int hi) {
  var sum = 0.0, n = 0;
  for (var y = lo; y < hi; y++) {
    for (var dx = -15; dx <= 15; dx++) {
      final i = (y * image.width + x + dx) * 3;
      if (image.data[i] < 100) {
        sum += y;
        n++;
      }
    }
  }
  return n == 0 ? double.nan : sum / n;
}

void _paint(RgbImage image, bool Function(int x, int y) where, (int, int, int) colour) {
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (!where(x, y)) continue;
      final i = (y * image.width + x) * 3;
      image.data[i] = colour.$1;
      image.data[i + 1] = colour.$2;
      image.data[i + 2] = colour.$3;
    }
  }
}

int _skinPixels(RgbImage image) {
  var n = 0;
  for (var i = 0; i < image.data.length; i += 3) {
    if (isSkin(image.data[i], image.data[i + 1], image.data[i + 2])) n++;
  }
  return n;
}

void main() {
  group('flattening', () {
    test('lines that bow towards the spine come out straight', () {
      // 12 rows of dip at the right edge, growing towards it: less than
      // half the line spacing, so each line stays in its own rows.
      final curved = _page(bow: (x) => 12 * x * x);
      final flat = flattenBookPage(curved);
      expect(identical(flat, curved), isFalse);

      // A line in the middle of the page, measured near each side.
      // Line 13 starts at row 398.
      double tilt(RgbImage image) => _inkRow(image, 520, 392, 418) - _inkRow(image, 80, 392, 418);
      expect(tilt(curved), greaterThan(6));
      expect(tilt(flat).abs(), lessThan(2.5));
    });

    test('a flat page, a blank page and a tiny page are left as they are', () {
      final straight = _page();
      expect(identical(flattenBookPage(straight), straight), isTrue);
      final blank = RgbImage(400, 500)..data.fillRange(0, 400 * 500 * 3, _paper);
      expect(identical(flattenBookPage(blank), blank), isTrue);
      final tiny = RgbImage(20, 20);
      expect(identical(flattenBookPage(tiny), tiny), isTrue);
    });

    test('the page keeps its size', () {
      final curved = _page(bow: (x) => 20 * math.sin(x * math.pi));
      final flat = flattenBookPage(curved);
      expect((flat.width, flat.height), (curved.width, curved.height));
    });
  });

  group('finger removal', () {
    test('a finger coming in from the side is painted the colour of the paper', () {
      final page = _page();
      // A thumb from the left edge, about 50 x 30 pixels.
      _paint(page, (x, y) => math.pow((x - 10) / 45, 2) + math.pow((y - 400) / 28, 2) <= 1, _skin);
      expect(_skinPixels(page), greaterThan(1000));

      final fixed = removeFingers(page);
      expect(_skinPixels(fixed), 0);
      final i = (400 * fixed.width + 15) * 3;
      expect(fixed.data[i], closeTo(_paper, 10));
    });

    test('a finger at the bottom is removed too, and text outside it is kept', () {
      final page = _page();
      _paint(page, (x, y) => math.pow((x - 300) / 30, 2) + math.pow((y - 799) / 50, 2) <= 1, _skin);
      final fixed = removeFingers(page);
      expect(_skinPixels(fixed), 0);
      // The first line of text is untouched.
      expect(_inkRow(fixed, 300, 50, 80), closeTo(_inkRow(page, 300, 50, 80), 0.5));
    });

    test('skin colour in the middle of the page, or along a whole side, is kept', () {
      final middle = _page();
      _paint(middle, (x, y) => (x - 300).abs() < 40 && (y - 400).abs() < 40, _skin);
      expect(identical(removeFingers(middle), middle), isTrue);

      final desk = _page();
      _paint(desk, (x, y) => x < 20, _skin);
      expect(identical(removeFingers(desk), desk), isTrue);
    });

    test('paper and wooden desks are not skin; skin of every tone is', () {
      expect(isSkin(_paper, _paper, _paper), isFalse);
      expect(isSkin(240, 230, 200), isFalse); // cream paper
      expect(isSkin(30, 30, 30), isFalse);
      expect(isSkin(224, 168, 136), isTrue);
      expect(isSkin(141, 85, 60), isTrue);
      expect(isSkin(255, 220, 190), isTrue);
    });
  });

  test('the book fix is kept in the page recipe and changes its cache key', () {
    const plain = EditRecipe();
    final book = plain.copyWith(bookFix: true);
    expect(EditRecipe.fromJson(book.toJson()).bookFix, isTrue);
    expect(plain.toJson().containsKey('bookFix'), isFalse);
    expect(EditRecipe.fromJson(plain.toJson()).bookFix, isFalse);
    expect(book.cacheKey, isNot(plain.cacheKey));
    expect(book, isNot(plain));
  });

  test('on the book photos, the fix runs in good time and leaves the size alone', () {
    // Page 13 of the book set: an open book, a curved page, a thumb.
    final file = File('sample_photos/book/13_light_meter.jpg');
    final photos = Directory('sample_photos/book').listSync().whereType<File>().toList();
    final source = file.existsSync() ? file : photos.firstWhere((f) => f.path.contains('/13_'));
    final photo = RgbImage.decode(source.readAsBytesSync(), maxDimension: 1400);
    const quad = CropQuad(NormPoint(0.04, 0.15), NormPoint(0.68, 0.24), NormPoint(0.73, 0.86), NormPoint(0, 0.88));
    final page = warpPerspective(photo, quad);
    final watch = Stopwatch()..start();
    final fixed = fixBookPage(page);
    expect(watch.elapsedMilliseconds, lessThan(3000));
    expect(identical(fixed, page), isFalse);
    expect((fixed.width, fixed.height), (page.width, page.height));
  });
}
