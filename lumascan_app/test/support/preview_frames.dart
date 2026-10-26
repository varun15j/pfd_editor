import 'dart:typed_data';

import 'package:lumascan/features/batch_capture/camera_frame.dart';
import 'package:lumascan/imaging/rgb_image.dart';

CameraFrame bgraFrame(RgbImage image, {int rotation = 0, int padding = 0}) {
  final stride = image.width * 4 + padding;
  final bytes = Uint8List(stride * image.height);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final i = (y * image.width + x) * 3, o = y * stride + x * 4;
      bytes[o] = image.data[i + 2];
      bytes[o + 1] = image.data[i + 1];
      bytes[o + 2] = image.data[i];
      bytes[o + 3] = 255;
    }
  }
  return CameraFrame(
    width: image.width,
    height: image.height,
    bytesPerRow: stride,
    bytes: bytes,
    pixels: FramePixels.bgra,
    rotation: rotation,
  );
}

CameraFrame nv21Frame(RgbImage image, {int rotation = 0, int padding = 0}) {
  assert(image.width.isEven && image.height.isEven);
  final stride = image.width + padding;
  final bytes = Uint8List(stride * image.height * 3 ~/ 2);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final i = (y * image.width + x) * 3;
      final r = image.data[i], g = image.data[i + 1], b = image.data[i + 2];
      bytes[y * stride + x] = (((66 * r + 129 * g + 25 * b + 128) >> 8) + 16).clamp(0, 255);
      if (x.isEven && y.isEven) {
        final o = stride * image.height + (y ~/ 2) * stride + x;
        bytes[o] = (((112 * r - 94 * g - 18 * b + 128) >> 8) + 128).clamp(0, 255);
        bytes[o + 1] = (((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128).clamp(0, 255);
      }
    }
  }
  return CameraFrame(
    width: image.width,
    height: image.height,
    bytesPerRow: stride,
    bytes: bytes,
    pixels: FramePixels.nv21,
    rotation: rotation,
  );
}
