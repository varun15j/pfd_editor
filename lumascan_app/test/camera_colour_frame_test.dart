import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/features/batch_capture/camera_frame.dart';
import 'package:lumascan/imaging/rgb_image.dart';

/// [photo] as an NV21 preview frame (full range BT.601), as Android sends it.
CameraFrame _nv21(RgbImage photo) {
  final w = photo.width & ~1, h = photo.height & ~1;
  final bytes = Uint8List(w * h + w * h ~/ 2);
  final d = photo.data;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * photo.width + x) * 3;
      bytes[y * w + x] = (0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2]).round().clamp(0, 255);
    }
  }
  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x < w; x += 2) {
      final i = (y * photo.width + x) * 3;
      final r = d[i], g = d[i + 1], b = d[i + 2];
      final c = w * h + (y >> 1) * w + x;
      bytes[c] = (128 + 0.5 * r - 0.4187 * g - 0.0813 * b).round().clamp(0, 255);
      bytes[c + 1] = (128 - 0.1687 * r - 0.3313 * g + 0.5 * b).round().clamp(0, 255);
    }
  }
  return CameraFrame(width: w, height: h, bytesPerRow: w, bytes: bytes, pixels: FramePixels.nv21);
}

/// [photo] as a BGRA preview frame, as iOS sends it.
CameraFrame _bgra(RgbImage photo) {
  final bytes = Uint8List(photo.width * photo.height * 4);
  for (var p = 0; p < photo.width * photo.height; p++) {
    bytes[p * 4] = photo.data[p * 3 + 2];
    bytes[p * 4 + 1] = photo.data[p * 3 + 1];
    bytes[p * 4 + 2] = photo.data[p * 3];
    bytes[p * 4 + 3] = 255;
  }
  return CameraFrame(
    width: photo.width,
    height: photo.height,
    bytesPerRow: photo.width * 4,
    bytes: bytes,
    pixels: FramePixels.bgra,
  );
}

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

double _iou(CropQuad a, CropQuad b) {
  var both = 0, either = 0;
  for (var j = 0; j < 133; j++) {
    for (var i = 0; i < 100; i++) {
      final x = (i + 0.5) / 100, y = (j + 0.5) / 133;
      final inA = _inside(a, x, y), inB = _inside(b, x, y);
      if (inA && inB) both++;
      if (inA || inB) either++;
    }
  }
  return either == 0 ? 0 : both / either;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an NV21 frame comes out in colour, close to the photo', () {
    final photo = RgbImage(8, 8);
    for (var p = 0; p < 64; p++) {
      photo.data[p * 3] = 200;
      photo.data[p * 3 + 1] = 60;
      photo.data[p * 3 + 2] = 90;
    }
    final frame = _nv21(photo);
    expect(frame.hasColour, isTrue);
    final colour = frame.uprightColour(size: 8);
    expect(colour.data[0], closeTo(200, 3));
    expect(colour.data[1], closeTo(60, 3));
    expect(colour.data[2], closeTo(90, 3));
    // Brightness alone, as before, for everything but outlines.
    expect(frame.uprightGray(size: 8).data[0], closeTo(0.299 * 200 + 0.587 * 60 + 0.114 * 90, 1));
  });

  test('a frame of brightness only has no colour', () {
    final frame = CameraFrame.gray(4, 4, Uint8List(16));
    expect(frame.hasColour, isFalse);
    // An NV21 frame cut short of its colour plane is read as grey too.
    final short = CameraFrame(width: 4, height: 4, bytesPerRow: 4, bytes: Uint8List(16), pixels: FramePixels.nv21);
    expect(short.hasColour, isFalse);
  });

  test('a coloured page as bright as the table is outlined from a colour preview frame', () async {
    // c02: a colour page with a white margin on a light beige table. In grey
    // the margin and the table are nearly the same shade.
    final corners = jsonDecode(await rootBundle.loadString('sample_photos/edge/corners.json')) as Map<String, dynamic>;
    final sample = (corners['samples'] as List).firstWhere((s) => (s['file'] as String).startsWith('c02'));
    final p = [
      for (final c in (sample['pages'] as List).first as List)
        NormPoint((c[0] as num).toDouble(), (c[1] as num).toDouble()),
    ];
    final truth = CropQuad(p[0], p[1], p[2], p[3]);
    final photo = RgbImage.decode(
      (await rootBundle.load('sample_photos/edge/${sample['file']}')).buffer.asUint8List(),
      maxDimension: 480,
    );

    // The same frame as brightness only, as the preview was read before.
    final grey = analyzeFrame(CameraFrame.gray(photo.width & ~1, photo.height & ~1, _nv21(photo).luma())).quad;
    final greyScore = grey == null ? 0.0 : _iou(grey, truth);
    for (final frame in [_nv21(photo), _bgra(photo)]) {
      final found = analyzeFrame(frame).quad;
      expect(found, isNotNull, reason: frame.pixels.name);
      // 0.85 for both on 2026-10-26, where the grey frame found no page.
      final score = _iou(found!, truth);
      expect(score, greaterThan(0.8), reason: frame.pixels.name);
      expect(score, greaterThan(greyScore + 0.2), reason: '${frame.pixels.name}, grey $greyScore');
    }
  });
}
