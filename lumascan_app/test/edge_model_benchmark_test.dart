import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/imaging/corner_model.dart';
import 'package:lumascan/imaging/page_detector.dart';

import 'support/edge_model_fixture.dart';

/// The page outline as the app makes it from the model's maps: the model's
/// outline when it is sure, else the hand-made detector's.
CropQuad? _outline(ModelPhoto p, int size) {
  return pageOutline(p.maps, size) ?? detectPageQuad(p.load());
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
  for (final (stem, least) in [('v1_heldback', 0.86), ('v2_heldback', 0.89)]) {
    test('the page is found in photos the model was not trained on ($stem)', () {
      final fixture = EdgeModelFixture.load(stem);
      final lines = <String>[];
      final means = _score(fixture.photos.where((p) => p.heldBack), fixture.size, lines);
      // ignore: avoid_print
      print(means.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(3)}').join('  '));
      // ignore: avoid_print
      print(lines.join('\n'));
      expect(means['all'], greaterThanOrEqualTo(least), reason: lines.join('\n'));
    });
  }

  // docs/edge-model.md, phase 3. The eight sample photos of an open book
  // with both pages marked. Asked the usual way the model marks one page of
  // a real book (overlap with the spread about 0.5); Book mode asks for
  // both. Only two of the eight are held back (book 20, odds 06).
  test('Book mode finds both pages of the marked open books', () {
    final fixture = EdgeModelFixture.load('v2_heldback');
    final lines = <String>[];
    var usual = 0.0, book = 0.0, n = 0;
    for (final p in fixture.photos) {
      final pages = _pages(p.marks);
      if (pages == null) continue;
      final spread = [CropQuad(pages.$1.tl, pages.$2.tr, pages.$2.br, pages.$1.bl)];
      final one = bestIou(pageOutline(p.maps, fixture.size), spread);
      final both = bestIou(pageOutline(p.maps, fixture.size, spread: true), spread);
      lines.add('${p.name} ${one.toStringAsFixed(3)} -> ${both.toStringAsFixed(3)}');
      usual += one;
      book += both;
      n++;
    }
    // ignore: avoid_print
    print('spreads: usual ${(usual / n).toStringAsFixed(3)}  Book mode ${(book / n).toStringAsFixed(3)}');
    expect(n, 8);
    expect(book / n, greaterThanOrEqualTo(0.88), reason: lines.join('\n'));
  });

  test('Book mode leaves a photo of one page as it is', () {
    final fixture = EdgeModelFixture.load('v2_heldback');
    final moved = <String>[];
    for (final p in fixture.photos) {
      if (_pages(p.marks) != null) continue;
      final usual = pageOutline(p.maps, fixture.size);
      if (usual == null) continue;
      final book = pageOutline(p.maps, fixture.size, spread: true);
      if ((bestIou(usual, p.marks) - bestIou(book, p.marks)).abs() > 0.01) moved.add(p.name);
    }
    // Book photo 12 is an open book with only its right page marked: Book
    // mode takes both pages, as it should.
    expect(moved, ['12_lemon_soda.jpg']);
  });
}

/// The left and right page among a photo's marks, when both are marked.
(CropQuad, CropQuad)? _pages(List<CropQuad> marks) {
  for (final a in marks) {
    for (final b in marks) {
      if ((a.tr.x - b.tl.x).abs() < 0.05 &&
          (a.br.x - b.bl.x).abs() < 0.08 &&
          a.tl.x < b.tl.x - 0.2 &&
          b.tr.x > a.tr.x + 0.2) {
        return (a, b);
      }
    }
  }
  return null;
}
