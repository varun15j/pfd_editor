import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/imaging/geometry.dart';
import 'package:lumascan/imaging/page_detector.dart';
import 'package:lumascan/imaging/rgb_image.dart';

/// The raw phone photos in sample_photos/ and the cleaned scans of the same
/// pages in sample_scan_img/ share file names, so photo N belongs to scan N.
const samples = [
  '01_revision1_palindrome_lengths.jpg',
  '02_revision2_multiplication.jpg',
  '03_revision3_conversions_shapes.jpg',
  '04_revision4_lengths.jpg',
  '05_revision_grocery_table.jpg',
];

/// Grey thumbnail size used for comparing page layouts. Small enough that
/// blur, lighting and a few percent of crop difference wash out, large
/// enough to keep the layout of text blocks, tables and margins.
const thumbW = 24, thumbH = 32;

/// Zero-mean, unit-length grey thumbnail.
Float64List signature(RgbImage im) {
  final small = img.copyResize(im.toImage(), width: thumbW, height: thumbH, interpolation: img.Interpolation.average);
  final v = Float64List(thumbW * thumbH);
  var i = 0;
  for (final p in small) {
    v[i++] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
  }
  final mean = v.reduce((a, b) => a + b) / v.length;
  var norm = 0.0;
  for (var k = 0; k < v.length; k++) {
    v[k] -= mean;
    norm += v[k] * v[k];
  }
  norm = math.sqrt(norm);
  for (var k = 0; k < v.length; k++) {
    v[k] /= norm == 0 ? 1 : norm;
  }
  return v;
}

/// Normalized cross-correlation of two signatures, -1..1.
double similarity(Float64List a, Float64List b) {
  var s = 0.0;
  for (var k = 0; k < a.length; k++) {
    s += a[k] * b[k];
  }
  return s;
}

RgbImage load(String path) => RgbImage.decode(File(path).readAsBytesSync(), maxDimension: 1000);

void main() {
  group('page edge detection on sample photos', () {
    final photos = [for (final s in samples) load('sample_photos/$s')];
    final scans = [for (final s in samples) load('sample_scan_img/$s')];
    final quads = <CropQuad>[];
    final pages = <RgbImage>[];

    setUpAll(() {
      for (final photo in photos) {
        final quad = detectPageQuad(photo);
        expect(quad, isNotNull);
        quads.add(quad!);
        pages.add(warpPerspective(photo, quad));
      }
      final out = Platform.environment['PAGE_DETECT_OUT'];
      if (out != null) {
        for (var i = 0; i < samples.length; i++) {
          File('$out/${samples[i]}').writeAsBytesSync(pages[i].encodeJpg());
        }
      }
    });

    test('finds a valid page quad in every photo', () {
      for (var i = 0; i < samples.length; i++) {
        final q = quads[i];
        expect(q.isValid(minArea: 0.3), isTrue, reason: '${samples[i]}: ${q.points}');
        // Every photo shows background around at least part of the page, so
        // the detector must not just return the whole frame.
        expect(q.isFull, isFalse, reason: samples[i]);
        expect(q.area, lessThan(0.97), reason: samples[i]);
      }
    });

    test('straightened pages match their reference scans', () {
      final scanSigs = [for (final s in scans) signature(s)];
      final pageSigs = [for (final p in pages) signature(p)];
      final photoSigs = [for (final p in photos) signature(p)];

      final table = StringBuffer('photo vs scan similarity (rows: photos, cols: scans)\n');
      for (var i = 0; i < samples.length; i++) {
        final row = [for (final s in scanSigs) similarity(pageSigs[i], s)];
        table.writeln(
          '${samples[i].substring(0, 2)}  ${row.map((v) => v.toStringAsFixed(2)).join('  ')}'
          '   raw ${similarity(photoSigs[i], scanSigs[i]).toStringAsFixed(2)}',
        );
      }
      // ignore: avoid_print
      print(table);

      for (var i = 0; i < samples.length; i++) {
        final own = similarity(pageSigs[i], scanSigs[i]);
        final raw = similarity(photoSigs[i], scanSigs[i]);
        expect(own, greaterThan(minSimilarity), reason: '${samples[i]}\n$table');
        expect(own, greaterThan(raw), reason: 'straightening should bring ${samples[i]} closer to its scan\n$table');
        for (var j = 0; j < samples.length; j++) {
          if (j == i) continue;
          expect(
            own,
            greaterThan(similarity(pageSigs[i], scanSigs[j])),
            reason: '${samples[i]} looks more like ${samples[j]}\n$table',
          );
        }
      }
    });

    test('straightened pages have the reference page shape', () {
      for (var i = 0; i < samples.length; i++) {
        final got = pages[i].width / pages[i].height;
        final want = scans[i].width / scans[i].height;
        // The references were cropped by hand and the warp sizes the page
        // from its longer opposite edges, so only the rough shape must agree.
        expect(
          got / want,
          inInclusiveRange(1 / maxAspectRatioError, maxAspectRatioError),
          reason: '${samples[i]}: ${got.toStringAsFixed(3)} vs ${want.toStringAsFixed(3)}',
        );
      }
    });
  });

  group('detectPageQuad on synthetic images', () {
    test('finds a tilted white sheet on a dark floor', () {
      final im = RgbImage(300, 400);
      const corners = [(60.0, 50.0), (250.0, 80.0), (230.0, 360.0), (40.0, 330.0)];
      for (var y = 0; y < im.height; y++) {
        for (var x = 0; x < im.width; x++) {
          final inside = _inside(corners, x + 0.5, y + 0.5);
          final i = (y * im.width + x) * 3;
          im.data[i] = inside ? 228 : 110;
          im.data[i + 1] = inside ? 230 : 104;
          im.data[i + 2] = inside ? 235 : 92;
        }
      }
      final q = detectPageQuad(im)!;
      final want = [for (final c in corners) NormPoint(c.$1 / 299, c.$2 / 399)];
      for (var k = 0; k < 4; k++) {
        expect(q.points[k].x, closeTo(want[k].x, 0.02), reason: 'corner $k');
        expect(q.points[k].y, closeTo(want[k].y, 0.02), reason: 'corner $k');
      }
    });

    test('returns null when there is no page', () {
      final im = RgbImage(200, 200);
      for (var i = 0; i < im.data.length; i += 3) {
        im.data[i] = 120;
        im.data[i + 1] = 90;
        im.data[i + 2] = 60;
      }
      expect(detectPageQuad(im), isNull);
    });
  });
}

/// Lowest similarity accepted between a straightened photo and its own scan.
/// Measured on these samples: 0.38 (grocery table, which keeps a strip of the
/// facing page) to 0.84.
const minSimilarity = 0.3;

/// Largest accepted ratio between the straightened page's width/height and
/// the reference scan's. Measured: 0.87 to 1.17.
const maxAspectRatioError = 1.25;

bool _inside(List<(double, double)> q, double x, double y) {
  for (var k = 0; k < 4; k++) {
    final a = q[k], b = q[(k + 1) % 4];
    if ((b.$1 - a.$1) * (y - a.$2) - (b.$2 - a.$2) * (x - a.$1) < 0) return false;
  }
  return true;
}
