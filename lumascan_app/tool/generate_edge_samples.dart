import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

// Deterministic synthetic camera scenes, not photographs. No external assets.
void main() {
  final dir = Directory('sample_photos/edge_cases')..createSync(recursive: true);
  const cases = <String, (List<(int, int, int)>, (int, int, int))>{
    'white_on_dark': ([(240, 240, 236)], (40, 40, 44)),
    'black_on_light': ([(35, 35, 40)], (225, 225, 220)),
    'yellow_paper': ([(240, 224, 120)], (92, 92, 96)),
    'pink_paper': ([(236, 160, 172)], (120, 86, 58)),
    'blue_paper': ([(156, 198, 236)], (92, 92, 96)),
    'green_paper': ([(150, 205, 150)], (40, 40, 44)),
    'multicolour_form': ([(236, 160, 172), (240, 240, 236), (156, 198, 236)], (120, 86, 58)),
    'equal_luma_colour': ([(210, 100, 110)], (105, 155, 100)),
  };
  final manifest = <Map<String, Object>>[];
  const w = 480, h = 640;
  for (final entry in cases.entries) {
    final image = img.Image(width: w, height: h);
    final random = math.Random(17);
    final bands = entry.value.$1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final inside = x >= 96 && x < 384 && y >= 64 && y < 576;
        var c = inside ? bands[((y - 64) * bands.length ~/ 512)] : entry.value.$2;
        // Printed lines, including reversed white print on the black sheet.
        if (inside && x >= 120 && x < 350 && y > 110 && y < 530 && y % 32 < 2) {
          c = entry.key == 'black_on_light' ? (220, 220, 220) : (55, 55, 55);
        }
        final noise = random.nextInt(5) - 2;
        image.setPixelRgb(
          x,
          y,
          (c.$1 + noise).clamp(0, 255),
          (c.$2 + noise).clamp(0, 255),
          (c.$3 + noise).clamp(0, 255),
        );
      }
    }
    final path = '${dir.path}/${entry.key}.png';
    File(path).writeAsBytesSync(img.encodePng(image));
    manifest.add({
      'asset': path,
      'kind': 'synthetic',
      'quad': [
        [.2, .1],
        [.8, .1],
        [.8, .9],
        [.2, .9],
      ],
    });
  }
  File('${dir.path}/manifest.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
}
