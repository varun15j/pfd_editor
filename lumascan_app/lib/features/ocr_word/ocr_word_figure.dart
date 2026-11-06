import 'dart:io';
import 'dart:typed_data';

import '../../domain/models.dart';
import '../../domain/ocr.dart';
import '../../imaging/page_renderer.dart';
import '../../imaging/rgb_image.dart';
import '../../pdf_edit/annotations.dart';
import 'ocr_word_regions.dart';

/// A part of a scanned page that text recognition did not read (a photo, a
/// drawing, a stamp, a table it could not make out), cut out of the page to
/// go in the Word file where it sat. Box in fractions of the page (0 to 1).
class OcrWordFigure {
  const OcrWordFigure({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.jpeg,
    required this.pixelWidth,
    required this.pixelHeight,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
  final Uint8List jpeg;
  final int pixelWidth;
  final int pixelHeight;
}

/// The parts of [page] to add as pictures to its Word page: whatever is on
/// the paper besides the recognised text, beside it or between it
/// ([findPictureBoxes]). A page with no
/// text at all goes in as one picture. A page with text but no layout gets
/// none, as there is nowhere to place them. Pure Dart, for an isolate.
///
/// [image] is the page as text recognition read it (cropped, filtered,
/// masked; see `ocrPageImageProvider`), so the pictures are cut from the
/// very image the text positions came from, and the full-size photo is not
/// drawn again. Without it the page is drawn from the photo.
List<OcrWordFigure> ocrWordFigures(ScanPage page, {required String text, OcrLayout? layout, RenderedImage? image}) {
  final blocks = layout?.blocks ?? const <OcrBlock>[];
  if (blocks.isEmpty && text.trim().isNotEmpty) return const [];
  final jpeg = image == null ? null : _bytesOf(image.path);
  if (blocks.isEmpty && jpeg != null && image != null) {
    // Nothing was read: the page goes in whole, as the finished JPEG it is.
    return [
      OcrWordFigure(
        left: 0,
        top: 0,
        right: 1,
        bottom: 1,
        jpeg: jpeg,
        pixelWidth: image.width,
        pixelHeight: image.height,
      ),
    ];
  }
  final picture = jpeg != null
      ? RgbImage.decode(jpeg, maxDimension: 1600)
      : renderRecipe(
          File(page.originalPath).readAsBytesSync(),
          page.recipe,
          maxDimension: 1600,
          masks: masksIn(page.annotations),
        );
  if (blocks.isEmpty) {
    return [_figure(picture, (x0: 0, y0: 0, x1: picture.width, y1: picture.height))];
  }
  // Pictures are looked for in both directions, beside the text as well as
  // between it, with the recognised lines painted out first.
  final lines = [
    for (final b in blocks) ...(b.lines.isEmpty ? <OcrBox>[b] : b.lines),
  ];
  return [for (final box in findPictureBoxes(picture, lines)) _figure(picture, box)];
}

OcrWordFigure _figure(RgbImage page, PictureBox b) {
  final crop = cropPicture(page, b);
  return OcrWordFigure(
    left: b.x0 / page.width,
    top: b.y0 / page.height,
    right: b.x1 / page.width,
    bottom: b.y1 / page.height,
    jpeg: crop.encodeJpg(quality: 85),
    pixelWidth: crop.width,
    pixelHeight: crop.height,
  );
}

/// One page's figure job: everything [ocrWordFigures] needs, as plain data
/// that can go to another isolate.
typedef OcrWordFigureJob = ({ScanPage page, String text, OcrLayout? layout, RenderedImage? image});

/// [ocrWordFigures] for one job. A top-level function, so passing it to an
/// isolate sends nothing else along with it.
List<OcrWordFigure> ocrWordFiguresOf(OcrWordFigureJob job) =>
    ocrWordFigures(job.page, text: job.text, layout: job.layout, image: job.image);

Uint8List? _bytesOf(String path) {
  try {
    final bytes = File(path).readAsBytesSync();
    return bytes.isEmpty ? null : bytes;
  } on FileSystemException {
    return null;
  }
}
