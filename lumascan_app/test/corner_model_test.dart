import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/features/batch_capture/camera_frame.dart';
import 'package:lumascan/data/photo_import_services.dart';
import 'package:lumascan/imaging/book_split.dart';
import 'package:lumascan/imaging/corner_model.dart';
import 'package:lumascan/imaging/rgb_image.dart';

/// A heatmap with one soft peak of [height] at ([x], [y]) (0..1).
Float32List _peak(double x, double y, double height, {int size = 128}) {
  final map = Float32List(size * size);
  for (var j = 0; j < size; j++) {
    for (var i = 0; i < size; i++) {
      final dx = i - x * (size - 1), dy = j - y * (size - 1);
      map[j * size + i] = height * math.exp(-(dx * dx + dy * dy) / 8);
    }
  }
  return map;
}

class _FakeModel implements CornerModel {
  _FakeModel(this.quad);

  final CropQuad? quad;
  var calls = 0;

  @override
  CropQuad? find(RgbImage image) {
    calls++;
    return quad;
  }
}

void main() {
  test('the corners are read from the heatmaps, top left first, with the weakest peak as confidence', () {
    // Given in the model's order or any other: here bottom right first.
    final found = readCornerHeatmaps([
      _peak(0.8, 0.85, 0.95),
      _peak(0.15, 0.1, 0.9),
      _peak(0.2, 0.9, 0.85),
      _peak(0.85, 0.12, 0.92),
    ], 128);
    expect(found, isNotNull);
    final (quad, confidence) = found!;
    void near(NormPoint p, double x, double y) {
      expect(p.x, closeTo(x, 0.01));
      expect(p.y, closeTo(y, 0.01));
    }

    near(quad.tl, 0.15, 0.1);
    near(quad.tr, 0.85, 0.12);
    near(quad.br, 0.8, 0.85);
    near(quad.bl, 0.2, 0.9);
    // The peak falls between grid points, so a little below 0.85.
    expect(confidence, closeTo(0.85, 0.05));
  });

  test('a corner the model did not find gives no outline', () {
    expect(
      readCornerHeatmaps([
        _peak(0.1, 0.1, 0.9),
        _peak(0.9, 0.1, 0.9),
        _peak(0.9, 0.9, 0.9),
        Float32List(128 * 128),
      ], 128),
      isNull,
    );
  });

  test('the model input is 256 x 256, channels first, scaled to 0..1', () {
    final image = RgbImage(90, 160);
    for (var i = 0; i < 90 * 160; i++) {
      image.data[i * 3] = 255; // red
      image.data[i * 3 + 2] = 51; // a little blue
    }
    final input = cornerModelInput(image);
    const n = cornerModelInputSize;
    expect(input, hasLength(3 * n * n));
    expect(input[0], closeTo(1, 1e-6));
    expect(input[n * n + 1000], 0);
    expect(input[2 * n * n + 5000], closeTo(0.2, 1e-6));
  });

  group('analyzeFrame with the corner model', () {
    final frame = CameraFrame.gray(120, 160, Uint8List(120 * 160));
    final quad = CropQuad(
      const NormPoint(0.1, 0.1),
      const NormPoint(0.9, 0.1),
      const NormPoint(0.9, 0.9),
      const NormPoint(0.1, 0.9),
    );

    test('takes the model outline when the model is sure', () {
      final model = _FakeModel(quad);
      expect(analyzeFrame(frame, model: model).quad, quad);
      expect(model.calls, 1);
    });

    test('falls back to the detector when the model is not sure', () {
      // A plain black frame: the detector finds nothing either.
      expect(analyzeFrame(frame, model: _FakeModel(null)).quad, isNull);
    });

    test('is used on Basic too (no smart scanning)', () {
      final model = _FakeModel(quad);
      expect(analyzeFrame(frame, smart: false, model: model).quad, quad);
      expect(model.calls, 1);
    });
  });

  group('the corner model in every scan path', () {
    late Directory tmp;
    late String photo;
    final quad = CropQuad(
      const NormPoint(0.2, 0.15),
      const NormPoint(0.8, 0.15),
      const NormPoint(0.8, 0.85),
      const NormPoint(0.2, 0.85),
    );

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lumascan_corners');
      // A plain grey photo: the hand-made detector finds no page in it.
      photo = (File(
        '${tmp.path}/card.jpg',
      )..writeAsBytesSync(img.encodeJpg(img.Image(width: 400, height: 300)..clear(img.ColorRgb8(128, 128, 128))))).path;
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('a photo (shot, import, ID card side, Auto crop) takes the model outline first', () {
      final model = _FakeModel(quad);
      expect(PhotoCornerJob(photo).run(model), quad);
      expect(model.calls, 1);
    });

    test('a photo falls back to the hand-made detector when the model is not sure or fails', () {
      expect(PhotoCornerJob(photo).run(_FakeModel(null)), isNull);
      expect(PhotoCornerJob(photo).run(null), isNull);
    });

    test('Basic (no smart scanning) asks the model too, with the plain detector as fallback', () {
      final model = _FakeModel(quad);
      expect(PhotoCornerJob(photo, smart: false).run(model), quad);
      expect(model.calls, 1);
    });

    test('an unreadable photo still throws, so imports can say which one failed', () {
      final bad = (File('${tmp.path}/bad.jpg')..writeAsStringSync('not a picture')).path;
      expect(() => PhotoCornerJob(bad).run(_FakeModel(quad)), throwsA(anything));
    });

    test('a book spread found by the model is split at its spine', () {
      final spread = CropQuad(
        const NormPoint(0.05, 0.1),
        const NormPoint(0.95, 0.1),
        const NormPoint(0.95, 0.9),
        const NormPoint(0.05, 0.9),
      );
      final model = _FakeModel(spread);
      final (left, right) = splitSpread(RgbImage.decode(File(photo).readAsBytesSync()), model: model);
      expect(model.calls, 1);
      expect(left.tl.x, closeTo(0.05, 0.001));
      expect(right.tr.x, closeTo(0.95, 0.001));
      expect(left.tr.x, right.tl.x, reason: 'the two pages meet at the spine');
    });

    test('jobs for frames and spreads carry the model to the detector', () {
      final model = _FakeModel(quad);
      expect(FrameCornerJob(CameraFrame.gray(120, 160, Uint8List(120 * 160))).run(model).quad, quad);
      expect(SpreadCornerJob(photo).run(model), isA<(CropQuad, CropQuad)>());
      expect(model.calls, 2);
    });

    test('the photo analyzer finds pages on its own when the model cannot run', () async {
      final none = DetectorPhotoAnalyzer(worker: () async => null);
      expect(await none.analyze(photo), isNull);
    });
  });
}
