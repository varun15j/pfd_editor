// Draws test/fixtures/id_card_photocopy.jpg: a photo of a photocopied ID
// card, made up, with no one's details. The card is only a thin grey
// outline (fainter on the right, as in a real copy) and a grey footer band
// on white paper, with a darker table at the left edge of the frame, at the
// size and place of a real photo where ID card mode cropped a strip of text.
//
//   dart run tool/make_id_card_sample.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  const w = 900, h = 553;
  final rand = math.Random(7);
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(214, 214, 212));
  // The sheet of paper, its left edge in view over a darker table.
  img.fillRect(im, x1: 0, y1: 0, x2: 30, y2: h - 1, color: img.ColorRgb8(176, 176, 174));
  img.fillRect(im, x1: 40, y1: 0, x2: w - 1, y2: h - 1, color: img.ColorRgb8(226, 226, 224));
  // A header line printed on the copy above the card.
  _text(im, rand, 75, 18, 60, 8);
  _text(im, rand, 420, 18, 130, 8);

  // The card, from (85, 45) to (815, 515): 1.55 wide to high.
  const left = 85, top = 45, right = 815, bottom = 515, band = 450;
  img.fillRect(im, x1: left, y1: band, x2: right, y2: bottom, color: img.ColorRgb8(196, 196, 194));
  final line = img.ColorRgb8(150, 150, 148), faint = img.ColorRgb8(212, 212, 210);
  img.drawLine(im, x1: left + 14, y1: top, x2: right - 14, y2: top, color: line, thickness: 2);
  img.drawLine(im, x1: left, y1: top + 14, x2: left, y2: bottom - 4, color: line, thickness: 2);
  img.drawLine(im, x1: left, y1: bottom, x2: right - 60, y2: bottom, color: line, thickness: 2);
  // The right side is barely there, as in the copy.
  img.drawLine(im, x1: right, y1: top + 14, x2: right, y2: bottom, color: faint, thickness: 1);
  img.drawLine(im, x1: left, y1: band - 6, x2: right, y2: band - 6, color: line, thickness: 2);
  // Photo box, text blocks and a code square inside.
  img.drawRect(im, x1: 100, y1: 170, x2: 280, y2: 410, color: img.ColorRgb8(90, 90, 90));
  img.fillRect(im, x1: 130, y1: 200, x2: 250, y2: 405, color: img.ColorRgb8(150, 150, 150));
  _text(im, rand, 260, 75, 330, 22);
  _text(im, rand, 260, 112, 330, 22);
  for (var r = 0; r < 4; r++) {
    _text(im, rand, 295, 185 + r * 28, 200 + rand.nextInt(80), 16);
  }
  _text(im, rand, 295, 392, 300, 26);
  _text(im, rand, 295, 428, 290, 12);
  for (var y = 250; y < 440; y += 6) {
    for (var x = 612; x < 805; x += 6) {
      if (rand.nextBool()) img.fillRect(im, x1: x, y1: y, x2: x + 5, y2: y + 5, color: img.ColorRgb8(40, 40, 40));
    }
  }
  _text(im, rand, 195, 470, 500, 30);

  // Camera noise and a soft focus, then saved as a phone would.
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = im.getPixel(x, y);
      final n = rand.nextInt(7) - 3;
      im.setPixelRgb(x, y, (p.r + n).clamp(0, 255), (p.g + n).clamp(0, 255), (p.b + n).clamp(0, 255));
    }
  }
  final out = img.gaussianBlur(im, radius: 1);
  File('test/fixtures/id_card_photocopy.jpg').writeAsBytesSync(img.encodeJpg(out, quality: 80));
}

/// A line of made-up print: dark strokes of random widths.
void _text(img.Image im, math.Random rand, int x, int y, int width, int height) {
  var cx = x;
  while (cx < x + width) {
    final stroke = 2 + rand.nextInt(4);
    img.fillRect(
      im,
      x1: cx,
      y1: y + rand.nextInt(height ~/ 3),
      x2: cx + stroke,
      y2: y + height,
      color: img.ColorRgb8(60, 60, 60),
    );
    cx += stroke + 2 + rand.nextInt(6);
  }
}
