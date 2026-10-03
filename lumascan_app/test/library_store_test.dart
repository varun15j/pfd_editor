import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/library_store.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/scanner_service.dart';
import 'package:lumascan/export/pdf_exporter.dart';
import 'package:lumascan/features/library/document_tile.dart';
import 'package:lumascan/features/library/library_controller.dart';
import 'package:lumascan/features/pages/scan_controller.dart';
import 'package:path/path.dart' as path;

class FakeScanner implements ScannerService {
  FakeScanner(this.paths);
  final List<String> paths;

  @override
  Future<List<String>> scan({required ScanSource source, int maxPages = 100}) async => paths;

  @override
  Future<void> cleanUp() async {}
}

void main() {
  late Directory tmp;
  late List<String> scanned;
  final containers = <ProviderContainer>[];

  /// A fresh app process: new providers over the same private folder.
  ProviderContainer launch() {
    final c = ProviderContainer(
      overrides: [
        scannerServiceProvider.overrideWithValue(FakeScanner(scanned)),
        pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
      ],
    );
    containers.add(c);
    return c;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lumascan_library');
    final cache = Directory('${tmp.path}/scanner_cache')..createSync();
    scanned = [
      for (var i = 0; i < 3; i++)
        (File('${cache.path}/page$i.jpg')..writeAsBytesSync(
              img.encodeJpg(img.Image(width: 120, height: 160)..clear(img.ColorRgb8(240, 235 - i * 40, 225))),
            ))
            .path,
    ];
  });

  tearDown(() {
    for (final c in containers) {
      c.dispose();
    }
    containers.clear();
    tmp.deleteSync(recursive: true);
  });

  group('page model JSON', () {
    test('a page keeps its crop, rotation and filter, and resolves its file against the current folder', () {
      const recipe = EditRecipe(
        crop: CropQuad(NormPoint(0.1, 0.05), NormPoint(0.9, 0.1), NormPoint(0.95, 0.9), NormPoint(0.05, 0.95)),
        quarterTurns: 3,
        filter: DocumentFilter.blackWhite,
      );
      const page = ScanPage(id: 'p1', originalPath: '/old/root/pages/p1.jpg', recipe: recipe);
      final back = ScanPage.fromJson(page.toJson(), originalsDir: '/new/root/pages');
      expect(back.id, 'p1');
      expect(back.originalPath, path.join('/new/root/pages', 'p1.jpg'));
      expect(back.recipe, recipe);
      expect(EditRecipe.fromJson(const EditRecipe().toJson()), const EditRecipe());
    });

    test('library index stores paths relative to the private root', () {
      final doc = SavedDocument(
        id: 'd1',
        name: 'Receipt',
        pdfPath: path.join('/a', 'exports', 'Receipt.pdf'),
        thumbnailPath: path.join('/a', 'thumbnails', 'd1.jpg'),
        pageCount: 2,
        type: ScanType.idCard,
        createdAt: DateTime(2026, 10, 1, 9),
        modifiedAt: DateTime(2026, 10, 2, 9),
        folderId: 'f1',
        tags: const ['tax'],
        sizeBytes: 1234,
      );
      final index = const LibraryIndex().copyWith(
        documents: [doc],
        folders: const [LibraryFolder(id: 'f1', name: 'Bills')],
      );
      final json = index.toJson('/a');
      expect((json['documents']! as List).first, containsPair('pdf', path.join('exports', 'Receipt.pdf')));

      final moved = LibraryIndex.fromJson(json, '/b').documents.single;
      expect(moved.pdfPath, path.join('/b', 'exports', 'Receipt.pdf'));
      expect(moved.thumbnailPath, path.join('/b', 'thumbnails', 'd1.jpg'));
      expect(moved.type, ScanType.idCard);
      expect(moved.createdAt, doc.createdAt);
      expect(moved.modifiedAt, doc.modifiedAt);
      expect(moved.folderId, 'f1');
      expect(moved.tags, ['tax']);
      expect(LibraryIndex.fromJson(json, '/b').folders.single.name, 'Bills');
    });
  });

  group('draft autosave (US-09.1)', () {
    test('the draft survives the app being killed, with its order and edits', () async {
      final first = launch();
      final controller = first.read(scanControllerProvider.notifier);
      await controller.draftSaved;
      await controller.scan(ScanSource.camera);
      final pages = first.read(scanControllerProvider).pages;
      controller.rotate(pages[0].id);
      controller.applyFilterToAll(DocumentFilter.grayscale);
      controller.move(2, 0);
      final expected = first.read(scanControllerProvider).pages;
      await controller.draftSaved;
      expect(File(path.join(tmp.path, DraftStore.draftFile)).existsSync(), isTrue);

      // No clean shutdown: the next launch just reads what is on disk.
      final second = launch();
      final restored = second.read(scanControllerProvider.notifier);
      await restored.draftSaved;
      final state = second.read(scanControllerProvider);
      expect([for (final p in state.pages) p.id], [for (final p in expected) p.id]);
      expect([for (final p in state.pages) p.recipe], [for (final p in expected) p.recipe]);
      expect([for (final p in state.pages) p.originalPath], [for (final p in expected) p.originalPath]);
      expect(state.canUndo, isFalse);
    });

    test('undo is saved too', () async {
      final first = launch();
      final controller = first.read(scanControllerProvider.notifier);
      await controller.scan(ScanSource.camera);
      controller.remove(first.read(scanControllerProvider).pages.first.id);
      controller.undo();
      await controller.draftSaved;

      final second = launch();
      await second.read(scanControllerProvider.notifier).draftSaved;
      expect(second.read(scanControllerProvider).pages, hasLength(3));
    });

    test('pages whose image is gone are dropped on restore', () async {
      final first = launch();
      final controller = first.read(scanControllerProvider.notifier);
      await controller.scan(ScanSource.camera);
      await controller.draftSaved;
      File(first.read(scanControllerProvider).pages[1].originalPath).deleteSync();

      final second = launch();
      await second.read(scanControllerProvider.notifier).draftSaved;
      expect(second.read(scanControllerProvider).pages, hasLength(2));
    });

    test('discarding the draft removes it from disk', () async {
      final first = launch();
      final controller = first.read(scanControllerProvider.notifier);
      await controller.scan(ScanSource.camera);
      await controller.clear();
      await controller.draftSaved;
      expect(File(path.join(tmp.path, DraftStore.draftFile)).existsSync(), isFalse);

      final second = launch();
      await second.read(scanControllerProvider.notifier).draftSaved;
      expect(second.read(scanControllerProvider).pages, isEmpty);
    });

    test('an unreadable draft file starts an empty draft', () async {
      File(path.join(tmp.path, DraftStore.draftFile))
        ..createSync(recursive: true)
        ..writeAsStringSync('{not json');
      final c = launch();
      await c.read(scanControllerProvider.notifier).draftSaved;
      expect(c.read(scanControllerProvider).pages, isEmpty);
    });
  });

  group('library (US-02.1)', () {
    Future<(ProviderContainer, SavedDocument)> exportScan({String? fileName}) async {
      final c = launch();
      final scan = c.read(scanControllerProvider.notifier);
      await scan.scan(ScanSource.camera);
      final pages = c.read(scanControllerProvider).pages;
      final pdf = await c.read(pdfExporterProvider).export(pages, ExportOptions(fileName: fileName ?? 'Lease.pdf'));
      final doc = await c.read(libraryProvider.notifier).addScan(pdf, pages);
      return (c, doc);
    }

    test('an exported scan is listed with its thumbnail and metadata, and still there after restart', () async {
      final (c, doc) = await exportScan();
      expect(doc.name, 'Lease');
      expect(doc.pageCount, 3);
      expect(doc.type, ScanType.document);
      expect(doc.sizeBytes, File(doc.pdfPath).lengthSync());
      expect(File(doc.thumbnailPath!).existsSync(), isTrue);
      final thumb = img.decodeJpg(File(doc.thumbnailPath!).readAsBytesSync())!;
      expect(thumb.height, lessThanOrEqualTo(LibraryStore.thumbnailSize));
      expect(c.read(savedDocumentsProvider).single.id, doc.id);
      expect(c.read(savedDocumentProvider(doc.id))?.name, 'Lease');

      final next = launch();
      final index = await next.read(libraryProvider.future);
      expect(index.documents.single.id, doc.id);
      expect(index.documents.single.thumbnailPath, doc.thumbnailPath);
      expect(next.read(savedDocumentProvider('missing')), isNull);
    });

    test('newest documents come first', () async {
      final (c, older) = await exportScan(fileName: 'A.pdf');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final pages = c.read(scanControllerProvider).pages;
      final pdf = await c.read(pdfExporterProvider).export(pages, const ExportOptions(fileName: 'B.pdf'));
      final newer = await c.read(libraryProvider.notifier).addScan(pdf, pages);
      expect([for (final d in c.read(savedDocumentsProvider)) d.id], [newer.id, older.id]);
    });

    test('saving over the same file updates its entry instead of adding another', () async {
      final (c, doc) = await exportScan();
      final pages = c.read(scanControllerProvider).pages.take(2).toList();
      final pdf = await c.read(pdfExporterProvider).export(pages, const ExportOptions(fileName: 'Lease.pdf'));
      final again = await c.read(libraryProvider.notifier).addScan(pdf, pages);
      expect(again.id, doc.id);
      expect(again.createdAt, doc.createdAt);
      expect(again.pageCount, 2);
      expect(c.read(savedDocumentsProvider), hasLength(1));
    });

    test('an edited PDF is listed as a PDF', () async {
      final c = launch();
      final pdf = File(path.join(tmp.path, 'exports', 'Signed.pdf'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      final doc = await c.read(libraryProvider.notifier).addPdf(pdf, pageCount: 4);
      expect(doc.type, ScanType.pdf);
      expect(doc.pageCount, 4);
      expect(doc.thumbnailPath, isNull);
    });

    test('rename renames the file too and avoids name clashes', () async {
      final (c, doc) = await exportScan();
      File(path.join(path.dirname(doc.pdfPath), 'Contract.pdf')).writeAsBytesSync([0]);
      await c.read(libraryProvider.notifier).rename(doc.id, 'Contract');
      final renamed = c.read(savedDocumentProvider(doc.id))!;
      expect(renamed.name, 'Contract (2)');
      expect(path.basename(renamed.pdfPath), 'Contract (2).pdf');
      expect(File(renamed.pdfPath).existsSync(), isTrue);
      expect(File(doc.pdfPath).existsSync(), isFalse);
      expect(renamed.modifiedAt.isBefore(doc.modifiedAt), isFalse);
    });

    test('delete removes the entry, the PDF and the thumbnail', () async {
      final (c, doc) = await exportScan();
      await c.read(libraryProvider.notifier).delete(doc.id);
      expect(c.read(savedDocumentsProvider), isEmpty);
      expect(File(doc.pdfPath).existsSync(), isFalse);
      expect(File(doc.thumbnailPath!).existsSync(), isFalse);
      expect((await launch().read(libraryProvider.future)).documents, isEmpty);
    });

    test('folders and tags are stored; deleting a folder moves its documents to the root', () async {
      final (c, doc) = await exportScan();
      final library = c.read(libraryProvider.notifier);
      final folder = await library.createFolder(' Home ');
      await library.moveToFolder(doc.id, folder.id);
      await library.setTags(doc.id, ['tax', ' tax', '', '2026']);
      await library.renameFolder(folder.id, 'House');

      final reloaded = await launch().read(libraryProvider.future);
      expect(reloaded.folders.single.name, 'House');
      expect(reloaded.documents.single.folderId, folder.id);
      expect(reloaded.documents.single.tags, ['tax', '2026']);

      await library.deleteFolder(folder.id);
      expect(c.read(libraryProvider).value!.folders, isEmpty);
      expect(c.read(savedDocumentProvider(doc.id))!.folderId, isNull);
    });

    test('a damaged index is set aside and the library opens empty', () async {
      final indexFile = File(path.join(tmp.path, LibraryStore.indexFile))
        ..createSync(recursive: true)
        ..writeAsStringSync('{"documents": [{"id": 1}]}');
      final index = await launch().read(libraryProvider.future);
      expect(index.documents, isEmpty);
      expect(indexFile.existsSync(), isFalse);
      expect(indexFile.parent.listSync().map((f) => path.basename(f.path)), contains(startsWith('index.corrupt-')));
    });
  });

  test('modified times read naturally', () {
    final now = DateTime(2026, 10, 2, 15, 30);
    expect(formatModified(now.subtract(const Duration(seconds: 20)), now), 'Just now');
    expect(formatModified(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
    expect(formatModified(DateTime(2026, 10, 2, 9, 5), now), 'Today 09:05');
    expect(formatModified(DateTime(2026, 10, 1, 22), now), 'Yesterday');
    expect(formatModified(DateTime(2026, 3, 7), now), '7 Mar 2026');
  });
}
