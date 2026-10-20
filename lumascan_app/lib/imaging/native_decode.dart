import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Upright RGBA pixels, four bytes per pixel.
class RgbaPixels {
  const RgbaPixels(this.bytes, this.width, this.height, {this.sourceBytes = 0, this.stageMicros = const {}});
  final Uint8List bytes;
  final int width;
  final int height;

  /// Size of the file decoded, and the time spent reading and decoding it.
  final int sourceBytes;
  final Map<String, int> stageMicros;
}

/// Decodes [path] with the platform's image decoder, upright (EXIF
/// orientation applied) and with its long side at most [maxDimension].
///
/// The engine decodes JPEGs at a reduced scale directly, off the UI thread,
/// which is about ten times faster than decoding the full photo in Dart and
/// never holds the full-size bitmap in Dart memory.
Future<RgbaPixels> decodeUpright(String path, int maxDimension) async {
  final sw = Stopwatch()..start();
  final encoded = await File(path).readAsBytes();
  final readMicros = sw.elapsedMicroseconds;
  final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale = math.min(1.0, maxDimension / math.max(descriptor.width, descriptor.height));
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw const FormatException('The image could not be read');
    return RgbaPixels(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      image.width,
      image.height,
      sourceBytes: encoded.length,
      // The platform decoder shrinks while it decodes, so both are "decode".
      stageMicros: {'read': readMicros, 'decode': sw.elapsedMicroseconds - readMicros},
    );
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
