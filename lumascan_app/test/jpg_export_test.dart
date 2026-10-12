import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/export/jpg_exporter.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late PageStore store;
  late List<ScanPage> pages;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lumascan_jpg');
    store = PageStore(rootDir: () async => tmp);
    pages = [
      for (var i = 0; i < 3; i++)
        ScanPage(
          id: 'p$i',
          originalPath:
              (File(p.join(tmp.path, 'src$i.jpg'))..writeAsBytesSync(
                    img.encodeJpg(img.Image(width: 40, height: 60)..clear(img.ColorRgb8(200, 190, 180))),
                  ))
                  .path,
          recipe: i == 1 ? const EditRecipe(quarterTurns: 1) : const EditRecipe(filter: DocumentFilter.magicColor),
        ),
    ];
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('one JPG per page, in order, with the page edits, in a folder named after the scan', () async {
    final progress = <int>[];
    final files = await JpgExporter(store).export(pages, '2026-10-11 Scan', onProgress: (d, _) => progress.add(d));
    expect(files.map((f) => p.basename(f.path)), [
      '2026-10-11 Scan 01.jpg',
      '2026-10-11 Scan 02.jpg',
      '2026-10-11 Scan 03.jpg',
    ]);
    expect(p.basename(files.first.parent.path), '2026-10-11 Scan');
    expect(progress, [1, 2, 3]);
    // The rotated page is landscape.
    final second = img.decodeJpg(files[1].readAsBytesSync())!;
    expect(second.width, greaterThan(second.height));
    // The scan's own images are not touched.
    expect(pages.every((page) => File(page.originalPath).existsSync()), isTrue);
  });

  test('a second export keeps the first one', () async {
    final exporter = JpgExporter(store);
    final first = await exporter.export(pages, 'Bills');
    final second = await exporter.export(pages, 'Bills');
    expect(p.basename(second.first.parent.path), 'Bills (2)');
    expect(first.every((f) => f.existsSync()), isTrue);
  });

  test('names that file systems reject are made safe', () {
    expect(JpgExporter.safeStem(' a/b:c '), 'a_b_c');
    expect(JpgExporter.safeStem('   '), 'Scan');
  });

  test('a page that cannot be read leaves no half-finished folder', () async {
    final broken = [...pages, const ScanPage(id: 'x', originalPath: '/nowhere/x.jpg')];
    await expectLater(JpgExporter(store).export(broken, 'Broken'), throwsA(anything));
    expect(Directory(p.join(tmp.path, 'exports', 'Broken')).existsSync(), isFalse);
  });
}
