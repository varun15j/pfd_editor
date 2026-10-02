import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/scanner_service.dart';
import 'package:lumascan/export/pdf_exporter.dart';
import 'package:lumascan/features/pages/scan_controller.dart';
import 'package:path/path.dart' as path;

class FakeScanner implements ScannerService {
  FakeScanner(this.next);
  Future<List<String>> Function() next;
  int cleanUps = 0;

  @override
  Future<List<String>> scan({required ScanSource source, int maxPages = 100}) => next();

  @override
  Future<void> cleanUp() async => cleanUps++;
}

void main() {
  late Directory tmp;
  late List<String> scanned;
  late FakeScanner scanner;
  late ProviderContainer container;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lumascan_test');
    final cache = Directory('${tmp.path}/scanner_cache')..createSync();
    scanned = [
      for (var i = 0; i < 3; i++)
        (File('${cache.path}/page$i.jpg')
              ..writeAsBytesSync(img.encodeJpg(img.Image(width: 120 + i, height: 160)..clear(img.ColorRgb8(240, 235, 225)))))
            .path,
    ];
    scanner = FakeScanner(() async => scanned);
    container = ProviderContainer(overrides: [
      scannerServiceProvider.overrideWithValue(scanner),
      pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
    ]);
  });

  tearDown(() {
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  ScanController controller() => container.read(scanControllerProvider.notifier);
  ScanState state() => container.read(scanControllerProvider);

  test('scan copies pages into private storage and cleans the scanner cache', () async {
    final outcome = await controller().scan(ScanSource.camera);
    expect(outcome, isA<ScanAdded>().having((o) => o.count, 'count', 3));
    expect(state().pages, hasLength(3));
    expect(state().busy, isFalse);
    for (final p in state().pages) {
      expect(p.originalPath, startsWith('${path.join(tmp.path, 'pages')}${path.separator}'));
      expect(File(p.originalPath).existsSync(), isTrue);
    }
    expect(scanner.cleanUps, 1);
  });

  test('second scan appends pages (multi-page capture)', () async {
    await controller().scan(ScanSource.camera);
    await controller().scan(ScanSource.gallery);
    expect(state().pages, hasLength(6));
  });

  test('cancel adds nothing', () async {
    scanner.next = () async => [];
    expect(await controller().scan(ScanSource.camera), isA<ScanCancelled>());
    expect(state().pages, isEmpty);
  });

  test('permission denial is reported, not thrown', () async {
    scanner.next = () async => throw const ScannerPermissionDenied(permanently: true);
    final outcome = await controller().scan(ScanSource.camera);
    expect(outcome, isA<ScanPermissionBlocked>().having((o) => o.permanently, 'permanently', isTrue));
    expect(state().busy, isFalse);
  });

  test('edits, reorder, delete and undo', () async {
    await controller().scan(ScanSource.camera);
    final ids = state().pages.map((p) => p.id).toList();

    controller().rotate(ids[0]);
    expect(state().pages[0].recipe.quarterTurns, 1);
    controller().rotate(ids[0], clockwise: false);
    expect(state().pages[0].recipe.quarterTurns, 0);

    controller().applyFilterToAll(DocumentFilter.blackWhite);
    expect(state().pages.every((p) => p.recipe.filter == DocumentFilter.blackWhite), isTrue);

    controller().move(0, 2);
    expect(state().pages.map((p) => p.id), [ids[1], ids[2], ids[0]]);

    controller().remove(ids[1]);
    expect(state().pages, hasLength(2));
    controller().undo();
    expect(state().pages.map((p) => p.id), [ids[1], ids[2], ids[0]]);
  });

  test('clear deletes originals', () async {
    await controller().scan(ScanSource.camera);
    final paths = state().pages.map((p) => p.originalPath).toList();
    await controller().clear();
    expect(state().pages, isEmpty);
    expect(paths.any((p) => File(p).existsSync()), isFalse);
  });

  test('export writes a PDF with one page per scan', () async {
    await controller().scan(ScanSource.camera);
    controller().applyFilterToAll(DocumentFilter.grayscale);
    final progress = <double>[];
    final file = await container.read(pdfExporterProvider).export(
          state().pages,
          const ExportOptions(quality: ExportQuality.small, fileName: 'test.pdf'),
          onProgress: (d, t) => progress.add(d / t),
        );
    final bytes = file.readAsBytesSync();
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    expect(RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(bytes)).length, 3);
    expect(progress.last, 1.0);
    expect(File('${file.path}.part').existsSync(), isFalse);
  });

  test('fit-to-image page size follows image aspect ratio', () async {
    final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 300, height: 150)));
    final pdf = await buildPdfFromJpegs([(jpeg, 300, 150)], PdfPageSize.fitImage);
    expect(String.fromCharCodes(pdf), matches(RegExp(r'/MediaBox\s*\[0 0 144 72\]')));
  });
}
