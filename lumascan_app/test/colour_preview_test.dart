import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/features/batch_capture/camera_frame.dart';
import 'package:lumascan/imaging/rgb_image.dart';

import 'support/preview_frames.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('BGRA and NV21 retain colour, row padding and all four rotations', () {
    final photo = RgbImage(8, 8);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final i = (y * 8 + x) * 3;
        photo.data[i] = x < 4 ? 210 : 40;
        photo.data[i + 1] = y < 4 ? 100 : 190;
        photo.data[i + 2] = 110;
      }
    }
    for (final rotation in [0, 90, 180, 270]) {
      for (final frame in [
        bgraFrame(photo, rotation: rotation, padding: 8),
        nv21Frame(photo, rotation: rotation, padding: 8),
      ]) {
        final rgb = frame.uprightRgb(size: 8);
        for (var y = 0; y < 8; y++) {
          for (var x = 0; x < 8; x++) {
            final (ox, oy) = switch (rotation) {
              90 => (7 - y, x),
              180 => (7 - x, 7 - y),
              270 => (y, 7 - x),
              _ => (x, y),
            };
            for (var c = 0; c < 3; c++) {
              expect(rgb.data[(oy * 8 + ox) * 3 + c], closeTo(photo.data[(y * 8 + x) * 3 + c], 3));
            }
          }
        }
        expect(frame.luma().length, 64);
      }
    }
  });

  test('NV21 with only a Y plane falls back without an out-of-range read', () {
    final frame = CameraFrame(
      width: 4,
      height: 4,
      bytesPerRow: 4,
      bytes: Uint8List(16)..fillRange(0, 16, 123),
      pixels: FramePixels.nv21,
    );
    expect(frame.uprightRgb().data.every((v) => v == 123), isTrue);
  });

  test('colour detection keeps brightness-based tracking and low-light semantics', () {
    final photo = RgbImage(120, 160);
    for (var i = 0; i < photo.data.length; i += 3) {
      photo.data[i] = i < photo.data.length ~/ 2 ? 210 : 40;
      photo.data[i + 1] = 100;
      photo.data[i + 2] = 110;
    }
    for (final frame in [bgraFrame(photo), nv21Frame(photo)]) {
      final colour = analyzeFrame(frame);
      final gray = analyzeFrame(CameraFrame.gray(frame.width, frame.height, frame.luma()));
      expect(colour.scene, orderedEquals(gray.scene!));
      expect(colour.brightness, gray.brightness);
      expect(colour.tooDark, gray.tooDark);
    }
  });
  test('plain scenes do not produce page outlines', () {
    for (final value in [0, 80, 128, 240, 255]) {
      final image = RgbImage(120, 160)..data.fillRange(0, 120 * 160 * 3, value);
      expect(analyzeFrame(bgraFrame(image)).quad, isNull);
      expect(analyzeFrame(nv21Frame(image)).quad, isNull);
    }
  });

  test('bundled colour and B&W samples detect through both real preview formats', () async {
    final entries = jsonDecode(await rootBundle.loadString('sample_photos/edge_cases/manifest.json')) as List;
    final timings = <int>[];
    final report = <Map<String, Object?>>[];
    for (final entry in entries) {
      final asset = entry['asset'] as String;
      final bytes = await rootBundle.load(asset);
      final photo = RgbImage.decode(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      final points = (entry['quad'] as List)
          .map((p) => NormPoint((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList();
      for (final frame in [bgraFrame(photo), nv21Frame(photo)]) {
        // Warm-up separately; timing includes sampling, detection and signatures.
        analyzeFrame(frame);
        final watch = Stopwatch()..start();
        final analysis = analyzeFrame(frame);
        watch.stop();
        timings.add(watch.elapsedMicroseconds);
        expect(analysis.quad, isNotNull, reason: '$asset ${frame.pixels}');
        for (var i = 0; i < 4; i++) {
          expect(analysis.quad!.points[i].x, closeTo(points[i].x, .035), reason: '$asset ${frame.pixels} corner $i');
          expect(analysis.quad!.points[i].y, closeTo(points[i].y, .035), reason: '$asset ${frame.pixels} corner $i');
        }
        report.add({
          'asset': asset,
          'format': frame.pixels.name,
          'microseconds': watch.elapsedMicroseconds,
          'quad': [
            for (final p in analysis.quad!.points) [p.x, p.y],
          ],
        });
      }
      if (asset.contains('equal_luma')) {
        expect(
          analyzeFrame(CameraFrame.gray(photo.width, photo.height, bgraFrame(photo).luma())).quad,
          isNull,
          reason: 'This fixture must reproduce the old grayscale failure',
        );
      }
    }
    timings.sort();
    final output = File('build/edge_detection/synthetic_preview.json')..parent.createSync(recursive: true);
    output.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'runtime': 'Flutter test on host; not phone FPS; excludes isolate startup and transfer',
        'median_ms': timings[timings.length ~/ 2] / 1000,
        'p95_ms': timings[((timings.length - 1) * .95).ceil()] / 1000,
        'samples': report,
      }),
    );
  });
}
