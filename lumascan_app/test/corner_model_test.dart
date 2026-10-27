import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/features/batch_capture/camera_frame.dart';
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

    test('is not used without smart scanning', () {
      final model = _FakeModel(quad);
      analyzeFrame(frame, smart: false, model: model);
      expect(model.calls, 0);
    });
  });
}
