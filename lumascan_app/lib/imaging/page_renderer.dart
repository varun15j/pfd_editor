import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/models.dart';
import 'filters.dart';
import 'geometry.dart';
import 'rgb_image.dart';

/// Render pipeline from LLD section 7:
/// decode → orientation → perspective warp → quarter turns → filter →
/// brightness and contrast → encode.
RgbImage renderRecipe(Uint8List original, EditRecipe recipe, {int? maxDimension}) {
  var image = RgbImage.decode(original, maxDimension: maxDimension);
  image = warpPerspective(image, recipe.crop);
  image = rotateQuarterTurns(image, recipe.quarterTurns);
  image = applyFilter(image, recipe.filter);
  return adjustBrightnessContrast(image, brightness: recipe.brightness, contrast: recipe.contrast);
}

class RenderedImage {
  const RenderedImage(this.path, this.width, this.height);
  final String path;
  final int width;
  final int height;
}

/// Renders a page to a JPEG file on a background isolate.
Future<RenderedImage> renderToFile({
  required String originalPath,
  required EditRecipe recipe,
  required String outPath,
  required int maxDimension,
  int quality = 85,
}) {
  return Isolate.run(() {
    final bytes = File(originalPath).readAsBytesSync();
    final image = renderRecipe(bytes, recipe, maxDimension: maxDimension);
    _writeJpg(image, outPath, quality);
    return RenderedImage(outPath, image.width, image.height);
  });
}

/// The two small copies of a captured photo that every screen works from.
class WorkingCopies {
  const WorkingCopies(this.preview, this.small);

  /// Upright and uncropped, for the editor, filters and crop.
  final RenderedImage preview;

  /// The same picture smaller, for thumbnails in grids and strips.
  final RenderedImage small;
}

/// Decodes the full-resolution [originalPath] once, on a background isolate,
/// and writes an upright, uncropped [previewPath] (long side at most
/// [previewSize]) and [smallPath] (at most [smallSize]). Crop corners are
/// relative to the upright image, so a recipe renders the same from these as
/// from the original, only smaller.
///
/// This is the slow, pure Dart path; [RenderService] first tries the
/// platform decoder and hands its pixels to [writeWorkingCopies].
Future<WorkingCopies> makeWorkingCopies({
  required String originalPath,
  required String previewPath,
  required String smallPath,
  required int previewSize,
  required int smallSize,
}) {
  return Isolate.run(() {
    final preview = RgbImage.decode(File(originalPath).readAsBytesSync(), maxDimension: previewSize);
    return _writeWorkingCopies(preview, previewPath, smallPath, smallSize);
  });
}

/// Writes the working copies from an upright, already shrunk RGBA picture,
/// on a background isolate.
Future<WorkingCopies> writeWorkingCopies({
  required Uint8List rgba,
  required int width,
  required int height,
  required String previewPath,
  required String smallPath,
  required int smallSize,
}) {
  final pixels = TransferableTypedData.fromList([rgba]);
  return Isolate.run(() {
    final bytes = pixels.materialize().asUint8List();
    final rgb = Uint8List(width * height * 3);
    for (var i = 0, j = 0; j < rgb.length; i += 4, j += 3) {
      rgb[j] = bytes[i];
      rgb[j + 1] = bytes[i + 1];
      rgb[j + 2] = bytes[i + 2];
    }
    return _writeWorkingCopies(RgbImage(width, height, rgb), previewPath, smallPath, smallSize);
  });
}

WorkingCopies _writeWorkingCopies(RgbImage preview, String previewPath, String smallPath, int smallSize) {
  final scale = smallSize / math.max(preview.width, preview.height);
  final small = scale >= 1
      ? preview
      : RgbImage.fromImage(
          img.copyResize(
            preview.toImage(),
            width: math.max(1, (preview.width * scale).round()),
            height: math.max(1, (preview.height * scale).round()),
            interpolation: img.Interpolation.average,
          ),
        );
  _writeJpg(preview, previewPath, 90);
  _writeJpg(small, smallPath, 85);
  return WorkingCopies(
    RenderedImage(previewPath, preview.width, preview.height),
    RenderedImage(smallPath, small.width, small.height),
  );
}

/// Writes through a temp file and a rename, so a crash never leaves a
/// half-written picture that would be reused on the next launch.
void _writeJpg(RgbImage image, String path, int quality) {
  final tmp = File('$path.part');
  tmp.writeAsBytesSync(image.encodeJpg(quality: quality), flush: true);
  tmp.renameSync(path);
}

/// Reads a JPEG this app wrote earlier, without decoding its pixels. Returns
/// null when the file is missing or unreadable, so it is rendered again.
Future<RenderedImage?> readRendered(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  try {
    final size = jpegSize(await file.readAsBytes());
    return size == null ? null : RenderedImage(path, size.$1, size.$2);
  } on FileSystemException {
    return null;
  }
}

/// Width and height from a JPEG's frame header, or null if there is none.
(int, int)? jpegSize(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) return null;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++;
      continue;
    }
    final length = (b[i + 2] << 8) | b[i + 3];
    // SOF0..SOF15, except DHT (C4), JPG (C8) and DAC (CC).
    if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
      final height = (b[i + 5] << 8) | b[i + 6];
      final width = (b[i + 7] << 8) | b[i + 8];
      return width > 0 && height > 0 ? (width, height) : null;
    }
    i += 2 + length;
  }
  return null;
}

/// Decodes only orientation and size, for the crop screen (no crop/filter).
Future<RenderedImage> renderSourcePreview({
  required String originalPath,
  required String outPath,
  int maxDimension = 1600,
}) =>
    renderToFile(originalPath: originalPath, recipe: const EditRecipe(), outPath: outPath, maxDimension: maxDimension);
