import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../pdf_edit/annotations.dart';
import 'rgb_image.dart';

/// Paints each mask as a solid box into [image]'s pixels, so what it hides
/// is gone from the picture itself and not just covered in a layer above.
/// Edges are rounded outwards, so a mask never leaves a sliver showing.
void burnMasks(RgbImage image, Iterable<MaskAnnotation> masks) {
  final w = image.width, h = image.height, data = image.data;
  for (final m in masks) {
    final x0 = (m.left * w).floor().clamp(0, w), x1 = (m.right * w).ceil().clamp(0, w);
    final y0 = (m.top * h).floor().clamp(0, h), y1 = (m.bottom * h).ceil().clamp(0, h);
    final r = (m.color >> 16) & 0xFF, g = (m.color >> 8) & 0xFF, b = m.color & 0xFF;
    for (var y = y0; y < y1; y++) {
      for (var i = (y * w + x0) * 3, end = (y * w + x1) * 3; i < end; i += 3) {
        data[i] = r;
        data[i + 1] = g;
        data[i + 2] = b;
      }
    }
  }
}

/// [jpeg] with [masks] burned in, encoded again at [quality]. Returns
/// [jpeg] itself when there are no masks.
Uint8List burnMasksIntoJpeg(Uint8List jpeg, Iterable<MaskAnnotation> masks, {int quality = 90}) {
  if (masks.isEmpty) return jpeg;
  final decoded = img.decodeJpg(jpeg);
  if (decoded == null) throw const FormatException('Could not read the page picture to mask it');
  final image = RgbImage.fromImage(decoded);
  burnMasks(image, masks);
  return image.encodeJpg(quality: quality);
}
