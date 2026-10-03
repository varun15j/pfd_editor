import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/imaging/filters.dart';
import 'package:lumascan/imaging/geometry.dart';
import 'package:lumascan/imaging/page_renderer.dart';
import 'package:lumascan/imaging/rgb_image.dart';

RgbImage solid(int w, int h, int r, int g, int b) {
  final im = RgbImage(w, h);
  for (var i = 0; i < w * h * 3; i += 3) {
    im.data[i] = r;
    im.data[i + 1] = g;
    im.data[i + 2] = b;
  }
  return im;
}

(int, int, int) px(RgbImage im, int x, int y) {
  final i = (y * im.width + x) * 3;
  return (im.data[i], im.data[i + 1], im.data[i + 2]);
}

void setPx(RgbImage im, int x, int y, int v) {
  final i = (y * im.width + x) * 3;
  im.data[i] = im.data[i + 1] = im.data[i + 2] = v;
}

void main() {
  group('CropQuad', () {
    test('full quad is valid', () => expect(CropQuad.full.isValid(), isTrue));

    test('self-intersecting quad is rejected', () {
      const bowtie = CropQuad(NormPoint(0, 0), NormPoint(1, 1), NormPoint(1, 0), NormPoint(0, 1));
      expect(bowtie.isValid(), isFalse);
    });

    test('mirrored corner order is rejected', () {
      const mirrored = CropQuad(NormPoint(1, 0), NormPoint(0, 0), NormPoint(0, 1), NormPoint(1, 1));
      expect(mirrored.isValid(), isFalse);
    });

    test('concave quad is rejected', () {
      final dented = CropQuad.full.withPoint(2, const NormPoint(.3, .3));
      expect(dented.isValid(), isFalse);
    });

    test('tiny quad is rejected', () {
      const q = CropQuad(NormPoint(.5, .5), NormPoint(.55, .5), NormPoint(.55, .55), NormPoint(.5, .55));
      expect(q.isValid(), isFalse);
    });

    test('points are clamped to the image', () {
      expect(CropQuad.full.withPoint(0, const NormPoint(-1, 2)).tl, const NormPoint(0, 1));
    });
  });

  group('geometry', () {
    test('rotating clockwise moves the top-left pixel to the top-right', () {
      final im = solid(4, 2, 255, 255, 255);
      setPx(im, 0, 0, 0);
      final r = rotateQuarterTurns(im, 1);
      expect((r.width, r.height), (2, 4));
      expect(px(r, 1, 0), (0, 0, 0));
      expect(px(rotateQuarterTurns(im, 4), 0, 0), (0, 0, 0));
    });

    test('four quarter turns return the original', () {
      final im = solid(5, 3, 10, 20, 30);
      setPx(im, 4, 2, 200);
      var r = im;
      for (var i = 0; i < 4; i++) {
        r = rotateQuarterTurns(r, 1);
      }
      expect(r.data, im.data);
    });

    test('warp of an axis-aligned quad equals a plain crop', () {
      final im = RgbImage(100, 100);
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 100; x++) {
          setPx(im, x, y, x < 50 ? 0 : 255);
        }
      }
      // Right half only: (50..99) → should be white everywhere.
      const q = CropQuad(NormPoint(50 / 99, 0), NormPoint(1, 0), NormPoint(1, 1), NormPoint(50 / 99, 1));
      final out = warpPerspective(im, q);
      expect(out.width, closeTo(49, 1));
      expect(out.height, 99);
      expect(out.data.every((v) => v == 255), isTrue);
    });

    test('a perspective quad is straightened', () {
      // Draw a white trapezoid on black, then warp it to a rectangle.
      const w = 200, h = 200;
      final im = solid(w, h, 0, 0, 0);
      const q = CropQuad(NormPoint(.3, .2), NormPoint(.7, .2), NormPoint(.9, .8), NormPoint(.1, .8));
      for (var y = 0; y < h; y++) {
        final t = (y / (h - 1) - .2) / .6;
        if (t < 0 || t > 1) continue;
        final left = (.3 - .2 * t) * (w - 1), right = (.7 + .2 * t) * (w - 1);
        for (var x = left.ceil(); x <= right.floor(); x++) {
          setPx(im, x, y, 255);
        }
      }
      final out = warpPerspective(im, q);
      final inner = <int>[];
      for (var y = 3; y < out.height - 3; y++) {
        for (var x = 3; x < out.width - 3; x++) {
          inner.add(px(out, x, y).$1);
        }
      }
      expect(inner.where((v) => v < 128).length / inner.length, lessThan(0.01));
    });
  });

  group('filters', () {
    test('grayscale makes channels equal', () {
      final im = solid(10, 10, 200, 120, 40);
      setPx(im, 0, 0, 0);
      final out = grayscale(im);
      for (var i = 0; i < out.data.length; i += 3) {
        expect(out.data[i], out.data[i + 1]);
        expect(out.data[i + 1], out.data[i + 2]);
      }
    });

    test('B&W keeps text dark and shaded paper white', () {
      // Paper with a left-to-right lighting gradient and a dark text bar.
      const w = 240, h = 120;
      final im = RgbImage(w, h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final paper = 120 + (x * 110 ~/ w); // 120 (shadow) .. 230 (bright)
          setPx(im, x, y, (y >= 55 && y < 62) ? paper - 90 : paper);
        }
      }
      final out = blackAndWhite(im);
      final values = {for (var i = 0; i < out.data.length; i += 3) out.data[i]};
      expect(values.difference({0, 255}), isEmpty);
      // Shadowed paper on the left stays white; a global threshold would fail.
      expect(px(out, 10, 20).$1, 255);
      expect(px(out, 10, 58).$1, 0);
      expect(px(out, 230, 58).$1, 0);
      expect(px(out, 230, 100).$1, 255);
    });

    test('B&W removes isolated speckles', () {
      final im = solid(60, 60, 220, 220, 220);
      setPx(im, 30, 30, 20);
      expect(px(blackAndWhite(im), 30, 30).$1, 255);
    });

    test('Magic Color whitens tinted paper and keeps ink dark', () {
      final im = solid(50, 50, 215, 200, 170); // yellowish paper
      for (var x = 10; x < 40; x++) {
        final i = (25 * 50 + x) * 3;
        im.data[i] = 40;
        im.data[i + 1] = 40;
        im.data[i + 2] = 40;
      }
      final out = magicColor(im);
      final (r, g, b) = px(out, 2, 2);
      expect(r, greaterThan(245));
      expect(g, greaterThan(245));
      expect(b, greaterThan(245));
      expect(px(out, 20, 25).$1, lessThan(30));
    });

    test('Whiteboard evens out lighting and keeps marker strokes', () {
      // A board lit from the left (dark grey) to the right (near white), with a
      // blue marker line and a black one.
      final im = RgbImage(120, 60);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 120; x++) {
          final v = 110 + (x * 130 / 119).round();
          final i = (y * 120 + x) * 3;
          im.data[i] = v;
          im.data[i + 1] = v;
          im.data[i + 2] = v;
        }
      }
      for (var x = 30; x < 50; x++) {
        final i = (30 * 120 + x) * 3;
        im.data[i] = 20;
        im.data[i + 1] = 40;
        im.data[i + 2] = 160;
      }
      for (var x = 80; x < 100; x++) {
        setPx(im, x, 30, 25);
      }

      final out = whiteboard(im);
      // The board is white on both the dim and the bright side.
      expect(px(out, 10, 10).$1, greaterThan(235));
      expect(px(out, 110, 10).$1, greaterThan(235));
      // The black stroke stays dark; the blue one stays dark and blue.
      expect(px(out, 90, 30).$1, lessThan(90));
      final (r, g, b) = px(out, 40, 30);
      expect(b, greaterThan(r + 40));
      expect(r, lessThan(120));
    });

    test('Whiteboard keeps the input untouched', () {
      final im = solid(20, 20, 120, 120, 120);
      whiteboard(im);
      expect(px(im, 5, 5), (120, 120, 120));
    });

    test('Original returns the input untouched', () {
      final im = solid(4, 4, 1, 2, 3);
      expect(identical(applyFilter(im, DocumentFilter.original), im), isTrue);
    });
  });

  group('brightness and contrast', () {
    test('zero adjustments return the same image', () {
      final im = solid(4, 4, 90, 120, 150);
      expect(identical(adjustBrightnessContrast(im), im), isTrue);
    });

    test('brightness lightens and darkens', () {
      final im = solid(4, 4, 100, 100, 100);
      expect(px(adjustBrightnessContrast(im, brightness: 0.5), 1, 1).$1, 164);
      expect(px(adjustBrightnessContrast(im, brightness: -0.5), 1, 1).$1, 36);
      expect(px(adjustBrightnessContrast(im, brightness: 1), 1, 1).$1, 228);
    });

    test('contrast pushes values away from mid grey, or towards it', () {
      final im = solid(2, 1, 100, 100, 100);
      setPx(im, 1, 0, 160);
      final more = adjustBrightnessContrast(im, contrast: 0.5);
      expect(px(more, 0, 0).$1, lessThan(100));
      expect(px(more, 1, 0).$1, greaterThan(160));
      final flat = adjustBrightnessContrast(im, contrast: -1);
      expect(px(flat, 0, 0).$1, 128);
      expect(px(flat, 1, 0).$1, 128);
    });

    test('values are clamped to 0..255', () {
      final im = solid(2, 2, 250, 5, 128);
      final out = adjustBrightnessContrast(im, contrast: 1);
      expect(px(out, 0, 0), (255, 0, 128));
    });

    test('the render pipeline applies them after the filter', () {
      final src = img.Image(width: 60, height: 40);
      img.fill(src, color: img.ColorRgb8(100, 100, 100));
      final jpeg = Uint8List.fromList(img.encodeJpg(src, quality: 100));
      final plain = renderRecipe(jpeg, const EditRecipe());
      final lighter = renderRecipe(jpeg, const EditRecipe(brightness: 0.5));
      expect(px(lighter, 20, 20).$1, greaterThan(px(plain, 20, 20).$1 + 40));
    });

    test('they are saved in the recipe, omitted when zero, and change its cache key', () {
      const recipe = EditRecipe(brightness: 0.25, contrast: -0.5, filter: DocumentFilter.whiteboard);
      expect(EditRecipe.fromJson(recipe.toJson()), recipe);
      expect(const EditRecipe().toJson().keys, isNot(contains('brightness')));
      expect(const EditRecipe().toJson().keys, isNot(contains('contrast')));
      expect(recipe.cacheKey, isNot(const EditRecipe(filter: DocumentFilter.whiteboard).cacheKey));
      expect(recipe.hasAdjustments, isTrue);
      expect(const EditRecipe().hasAdjustments, isFalse);
      // Recipes saved before these existed still load.
      expect(EditRecipe.fromJson({'quarterTurns': 1, 'filter': 'grayscale'}).brightness, 0);
    });
  });

  test('full pipeline renders an encoded JPEG with recipe applied', () {
    final src = img.Image(width: 300, height: 200);
    img.fill(src, color: img.ColorRgb8(230, 220, 200));
    final jpeg = Uint8List.fromList(img.encodeJpg(src));
    final out = renderRecipe(
      jpeg,
      const EditRecipe(quarterTurns: 1, filter: DocumentFilter.grayscale),
      maxDimension: 150,
    );
    expect((out.width, out.height), (100, 150));
    final (r, g, b) = px(out, 50, 50);
    expect(r == g && g == b, isTrue);
  });
}
