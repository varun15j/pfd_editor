import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lumascan/domain/models.dart';
import 'package:lumascan/imaging/rgb_image.dart';

/// One marked sample photo with the corner model's raw output for it.
class ModelPhoto {
  ModelPhoto(this.file, this.group, this.heldBack, this.marks, this.maps);

  /// Path of the photo from the app folder, such as
  /// `sample_photos/book/01_contents.jpg`.
  final String file;

  /// `book`, `colour_book`, `edge`, `notebook` or `odds`.
  final String group;

  /// One of the photos kept back from training when the fixture's model was
  /// trained without them (every 4th marked photo, and the odds book).
  final bool heldBack;

  /// The outlines that count as the page, marked by hand.
  final List<CropQuad> marks;

  /// The model's output maps, each `size` x `size`, values 0..1.
  final List<Float32List> maps;

  String get name => file.split('/').last;

  RgbImage load({int maxDimension = 640}) => RgbImage.decode(File(file).readAsBytesSync(), maxDimension: maxDimension);
}

/// The corner model's output for every marked sample photo, written by
/// `tool/corner_model_training/dump_heatmaps.py`. The ONNX model cannot run
/// inside `flutter test`, so the tests read its maps from here and run the
/// app's own reading code on them.
class EdgeModelFixture {
  EdgeModelFixture(this.about, this.size, this.photos);

  factory EdgeModelFixture.load(String stem) {
    final index = jsonDecode(File('test/fixtures/edge_model/$stem.json').readAsStringSync()) as Map<String, dynamic>;
    final bytes = Uint8List.fromList(gzip.decode(File('test/fixtures/edge_model/$stem.bin.gz').readAsBytesSync()));
    final size = index['size'] as int, channels = index['channels'] as int;
    final photos = <ModelPhoto>[];
    var at = 0;
    for (final p in index['photos'] as List) {
      final maps = <Float32List>[];
      for (var c = 0; c < channels; c++) {
        final map = Float32List(size * size);
        for (var i = 0; i < map.length; i++) {
          map[i] = bytes[at++] / 255;
        }
        maps.add(map);
      }
      photos.add(
        ModelPhoto(
          p['file'] as String,
          p['group'] as String,
          p['heldBack'] as bool,
          [for (final m in p['marks'] as List) CropQuad.fromJson(m)],
          maps,
        ),
      );
    }
    return EdgeModelFixture(index['about'] as String, size, photos);
  }

  final String about;

  /// Side of each output map.
  final int size;
  final List<ModelPhoto> photos;
}

bool _inside(CropQuad q, double x, double y) {
  final pts = q.points;
  for (var i = 0; i < 4; i++) {
    final a = pts[i], b = pts[(i + 1) % 4];
    if ((b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x) < 0) return false;
  }
  return true;
}

/// Overlap of two outlines, as intersection over union, on a 200 x 200 grid.
double quadIou(CropQuad a, CropQuad b) {
  var both = 0, either = 0;
  for (var j = 0; j < 200; j++) {
    for (var i = 0; i < 200; i++) {
      final x = (i + 0.5) / 200, y = (j + 0.5) / 200;
      final inA = _inside(a, x, y), inB = _inside(b, x, y);
      if (inA && inB) both++;
      if (inA || inB) either++;
    }
  }
  return either == 0 ? 0 : both / either;
}

/// The best overlap of [quad] with any of [marks]; 0 for no outline.
double bestIou(CropQuad? quad, List<CropQuad> marks) =>
    quad == null ? 0 : marks.map((m) => quadIou(quad, m)).reduce((a, b) => a > b ? a : b);

/// Mean of each group's values, with `all` for the lot.
Map<String, double> groupMeans(Map<String, List<double>> byGroup) {
  final all = [for (final v in byGroup.values) ...v];
  return {
    for (final e in byGroup.entries) e.key: e.value.reduce((a, b) => a + b) / e.value.length,
    'all': all.reduce((a, b) => a + b) / all.length,
  };
}
