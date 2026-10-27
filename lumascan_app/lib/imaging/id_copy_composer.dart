import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// Dots per inch of a composed page: sharp enough to print small card text,
/// and an A4 page is still only 1654 × 2339 pixels.
const composeDpi = 200;

/// Paints [text] once across [slot], turned up to the right, in a grey that
/// leaves what is under it readable. The review screen and the saved page
/// both call this, so the preview shows exactly what is printed.
void paintWatermark(Canvas canvas, Rect slot, String text) {
  if (text.trim().isEmpty || slot.isEmpty) return;
  const angle = -0.38;
  // Long enough to cross the card on its diagonal, without running off it.
  final span = math.min(slot.width, slot.height) * 0.4 + math.max(slot.width, slot.height) * 0.6;
  TextPainter layout(double size) => TextPainter(
    text: TextSpan(
      text: text.trim(),
      style: TextStyle(
        color: const Color(0x80606060),
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: size * 0.04,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    maxLines: 2,
  )..layout(maxWidth: span);
  var size = slot.shortestSide * 0.2;
  var painter = layout(size);
  // Shrink a long purpose until it fits on two lines across the card.
  while ((painter.didExceedMaxLines || painter.height > slot.shortestSide * 0.6) && size > 4) {
    painter.dispose();
    size *= 0.85;
    painter = layout(size);
  }
  canvas
    ..save()
    ..clipRect(slot)
    ..translate(slot.center.dx, slot.center.dy)
    ..rotate(angle);
  painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
  canvas.restore();
  painter.dispose();
}

/// Lays out pictures on one sheet of paper and saves it as a JPEG: the ID
/// copy (front and back at their real size) and collages.
///
/// [slots] are normalized to the paper, one per picture in [imagePaths].
/// Each picture is fitted inside its slot, keeping its shape, and centred.
/// With [watermark], it is printed across every picture. Pictures should
/// already have their masks burned in, so nothing hidden reaches the page.
Future<Uint8List> composePage({
  required ui.Size paperMm,
  required List<Rect> slots,
  required List<String> imagePaths,
  String? watermark,
  int dpi = composeDpi,
  int quality = 90,
}) async {
  assert(slots.length == imagePaths.length);
  final width = (paperMm.width / 25.4 * dpi).round();
  final height = (paperMm.height / 25.4 * dpi).round();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
  canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
  final paint = Paint()
    ..filterQuality = FilterQuality.high
    ..isAntiAlias = true;
  for (var i = 0; i < slots.length; i++) {
    final slot = Rect.fromLTRB(
      slots[i].left * width,
      slots[i].top * height,
      slots[i].right * width,
      slots[i].bottom * height,
    );
    final image = await _decode(imagePaths[i]);
    final fitted = fitContain(Size(image.width.toDouble(), image.height.toDouble()), slot);
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), fitted, paint);
    image.dispose();
    if (watermark != null) paintWatermark(canvas, slot, watermark);
  }
  final picture = recorder.endRecording();
  final page = await picture.toImage(width, height);
  picture.dispose();
  final data = await page.toByteData();
  page.dispose();
  if (data == null) throw StateError('Could not read the composed page');
  final rgba = data.buffer.asUint8List();
  return Isolate.run(
    () => img.encodeJpg(
      img.Image.fromBytes(width: width, height: height, bytes: rgba.buffer, numChannels: 4),
      quality: quality,
    ),
  );
}

/// [size] scaled to fit inside [box], keeping its shape, and centred in it.
Rect fitContain(Size size, Rect box) {
  final scale = math.min(box.width / size.width, box.height / size.height);
  final w = size.width * scale, h = size.height * scale;
  return Rect.fromLTWH(box.left + (box.width - w) / 2, box.top + (box.height - h) / 2, w, h);
}

Future<ui.Image> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}
