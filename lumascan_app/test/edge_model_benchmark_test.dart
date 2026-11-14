import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/imaging/corner_model.dart';
import 'package:lumascan/imaging/page_detector.dart';

import 'support/edge_model_fixture.dart';

/// The page outline as the app makes it from the model's maps: the model's
/// outline when it is sure, else the hand-made detector's.
CropQuad? _outline(ModelPhoto p, int size) {
  final read = readCornerHeatmaps(p.maps, size);
  if (read != null && read.$2 >= minCornerConfidence) return read.$1;
  return detectPageQuad(p.load());
}

/// Mean overlap with the hand-marked page for each group of [photos].
Map<String, double> _score(Iterable<ModelPhoto> photos, int size, List<String> lines) {
  final by = <String, List<double>>{};
  for (final p in photos) {
    final iou = bestIou(_outline(p, size), p.marks);
    by.putIfAbsent(p.group, () => []).add(iou);
    lines.add('${p.group} ${p.name} ${iou.toStringAsFixed(3)}');
  }
  return groupMeans(by);
}

void main() {
  // docs/edge-model.md, "How it is measured". The model behind this fixture
  // never saw these 22 photos (every 4th marked photo and the six odds book
  // photos), so this is the fair score of the whole crop.
  test('the page is found in photos the model was not trained on', () {
    final fixture = EdgeModelFixture.load('v1_heldback');
    final lines = <String>[];
    final means = _score(fixture.photos.where((p) => p.heldBack), fixture.size, lines);
    // ignore: avoid_print
    print(means.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(3)}').join('  '));
    expect(means['all'], greaterThanOrEqualTo(0.85), reason: lines.join('\n'));
  });
}
