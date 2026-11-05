import 'dart:io';
import 'dart:typed_data';

import '../../domain/models.dart';
import '../../domain/ocr.dart';
import '../../imaging/ocr_figures.dart';
import '../../imaging/page_renderer.dart';
import '../../imaging/rgb_image.dart';
import '../../pdf_edit/annotations.dart';

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

/// The parts of [page] to add as pictures to its Word page: the same
/// figure finder as the text PDF ([findFigures]), which takes the bands
/// between the text blocks that have something on them. A page with no
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
  final found = blocks.isEmpty
      ? [OcrFigure(top: 0, image: picture, bottom: 1)]
      : findFigures(picture, [for (final b in blocks) (b.top, b.bottom)]);
  return [
    for (final f in found)
      // Ruled lines and the page border are not pictures.
      if (!_onlyLines(f.image))
        OcrWordFigure(
          left: f.left,
          top: f.top,
          right: f.right,
          bottom: f.bottom,
          jpeg: f.image.encodeJpg(quality: 85),
          pixelWidth: f.image.width,
          pixelHeight: f.image.height,
        ),
  ];
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

/// True when all that is on [image] is straight lines: rows or columns that
/// are inked most of the way across, such as a rule under a header or the
/// sides of a page border. Ink off those lines (a photo, a drawing, chart
/// bars, text) makes it a picture.
bool _onlyLines(RgbImage image) {
  final w = image.width, h = image.height, d = image.data;
  if (w == 0 || h == 0) return true;
  final ink = List<bool>.filled(w * h, false);
  final luma = List<int>.filled(w * h, 0);
  for (var i = 0; i < w * h; i++) {
    luma[i] = (d[i * 3] * 77 + d[i * 3 + 1] * 150 + d[i * 3 + 2] * 29) >> 8;
  }
  // The paper: the crop has a margin of it all round, so the middle value
  // along the edge is the paper, even when a filled box fills the middle.
  final edge = [
    for (var x = 0; x < w; x++) ...[luma[x], luma[(h - 1) * w + x]],
    for (var y = 0; y < h; y++) ...[luma[y * w], luma[y * w + w - 1]],
  ]..sort();
  final background = edge[edge.length ~/ 2];
  for (var i = 0; i < w * h; i++) {
    ink[i] = (luma[i] - background).abs() > 40;
  }
  // A line is a long unbroken run of ink: a third of the way across (or
  // down) or more. Text and chart bars break up; rules and borders don't.
  final lineRow = List.filled(h, false), lineCol = List.filled(w, false);
  for (var y = 0; y < h; y++) {
    var run = 0;
    for (var x = 0; x < w && !lineRow[y]; x++) {
      run = ink[y * w + x] ? run + 1 : 0;
      if (run >= w / 3) lineRow[y] = true;
    }
  }
  for (var x = 0; x < w; x++) {
    var run = 0;
    for (var y = 0; y < h && !lineCol[x]; y++) {
      run = ink[y * w + x] ? run + 1 : 0;
      if (run >= h / 3) lineCol[x] = true;
    }
  }
  // Many of them make a filled area (a coloured box, a photo), not lines.
  if (lineRow.where((l) => l).length > h * 0.15 || lineCol.where((l) => l).length > w * 0.15) return false;
  var off = 0;
  for (var y = 0; y < h; y++) {
    if (lineRow[y]) continue;
    for (var x = 0; x < w; x++) {
      if (ink[y * w + x] && !lineCol[x]) off++;
    }
  }
  return off < w * h * 0.005;
}
