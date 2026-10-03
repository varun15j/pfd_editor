import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

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
    File(outPath).writeAsBytesSync(image.encodeJpg(quality: quality), flush: true);
    return RenderedImage(outPath, image.width, image.height);
  });
}

/// Decodes only orientation and size, for the crop screen (no crop/filter).
Future<RenderedImage> renderSourcePreview({
  required String originalPath,
  required String outPath,
  int maxDimension = 1600,
}) =>
    renderToFile(
      originalPath: originalPath,
      recipe: const EditRecipe(),
      outPath: outPath,
      maxDimension: maxDimension,
    );
