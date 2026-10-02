import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Minimal packed 8-bit RGB buffer. Filters and the perspective warp work on
/// raw bytes because per-pixel calls through package:image are several times
/// slower on 12 MP camera images.
class RgbImage {
  RgbImage(this.width, this.height, [Uint8List? data])
      : data = data ?? Uint8List(width * height * 3) {
    assert(this.data.length == width * height * 3);
  }

  final int width;
  final int height;
  final Uint8List data;

  /// Decodes JPEG/PNG/HEIC-free formats, applies EXIF orientation exactly
  /// once and downsamples so the longest side is at most [maxDimension].
  static RgbImage decode(Uint8List bytes, {int? maxDimension}) {
    var image = img.decodeImage(bytes);
    if (image == null) {
      throw const FormatException('Unsupported or corrupt image');
    }
    image = img.bakeOrientation(image);
    if (maxDimension != null) {
      final longest = math.max(image.width, image.height);
      if (longest > maxDimension) {
        final scale = maxDimension / longest;
        image = img.copyResize(
          image,
          width: (image.width * scale).round(),
          height: (image.height * scale).round(),
          interpolation: img.Interpolation.average,
        );
      }
    }
    return fromImage(image);
  }

  static RgbImage fromImage(img.Image image) {
    final rgb = image.numChannels == 3 && image.bitsPerChannel == 8 && !image.hasPalette
        ? image
        : image.convert(numChannels: 3, format: img.Format.uint8);
    final bytes = rgb.getBytes(order: img.ChannelOrder.rgb);
    return RgbImage(image.width, image.height, Uint8List.fromList(bytes));
  }

  img.Image toImage() => img.Image.fromBytes(
        width: width,
        height: height,
        bytes: data.buffer,
        numChannels: 3,
        order: img.ChannelOrder.rgb,
      );

  Uint8List encodeJpg({int quality = 90}) => img.encodeJpg(toImage(), quality: quality);
}
