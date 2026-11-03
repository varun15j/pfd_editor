import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/export_state_store.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/library_query.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/saved_export.dart';
import 'package:lumascan/domain/scan_document.dart';
import 'package:lumascan/features/export/saved_exports.dart';
import 'package:lumascan/features/home/home_documents.dart';
import 'package:lumascan/features/library/library_controller.dart';
import 'package:lumascan/features/pages/scan_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/memory_stores.dart';
import 'support/temp_dir.dart';

const page = ScanPage(id: 'p1', originalPath: '/x/p1.jpg');

SavedDocument pdf(String id, ScanType type) => SavedDocument(
  id: id,
  name: id,
  pdfPath: '/nowhere/$id.pdf',
  pageCount: 1,
  type: type,
  createdAt: DateTime(2026, 11, 1),
  modifiedAt: DateTime(2026, 11, 1),
);

SavedExport export(String path, {String key = 'scan-1', ExportFormat format = ExportFormat.pdf, String fp = 'a'}) =>
    SavedExport(
      docKey: key,
      format: format,
      path: path,
      fingerprint: fp,
      name: 'Lease',
      pageCount: 1,
      sizeBytes: 3,
      exportedAt: DateTime(2026, 11, 2, 10),
      libraryId: format == ExportFormat.word ? null : 'lib1',
    );

void main() {
  sqfliteFfiInit();

  group('fingerprint', () {
    test('is the same for the same pages, name and options', () {
      final a = exportFingerprint([page], fileName: 'Lease.pdf', options: {'q': 'medium'});
      expect(a, hasLength(16));
      expect(exportFingerprint([page], fileName: 'Lease.pdf', options: {'q': 'medium'}), a);
    });

    test('changes with an edit, a mark, the name or the options', () {
      final a = exportFingerprint([page], fileName: 'Lease.pdf');
      final rotated = ScanPage(id: 'p1', originalPath: '/x/p1.jpg', recipe: const EditRecipe(quarterTurns: 1));
      expect(exportFingerprint([rotated], fileName: 'Lease.pdf'), isNot(a));
      expect(exportFingerprint([page, page], fileName: 'Lease.pdf'), isNot(a));
      expect(exportFingerprint([page], fileName: 'Rent.pdf'), isNot(a));
      expect(exportFingerprint([page], fileName: 'Lease.pdf', options: {'q': 'high'}), isNot(a));
    });

    test('a scan keeps its key when renamed', () {
      final info = ScanDocInfo(name: 'A', createdAt: DateTime(2026, 11, 3, 9, 30));
      expect(scanDocKey(info.copyWith(name: 'B')), scanDocKey(info));
    });
  });

  group('Docs, Saved and All', () {
    final docs = [pdf('edited', ScanType.pdf), pdf('exported', ScanType.document), pdf('id', ScanType.idCard)];
    List<String> ids(DocScope s) => [for (final d in LibraryQuery(scope: s).apply(docs, DateTime(2026, 11, 3))) d.id];

    test('Docs is the default and leaves exported PDFs out', () {
      expect(const LibraryQuery().scope, DocScope.docs);
      expect(ids(DocScope.docs), ['edited']);
      expect(ids(DocScope.saved), unorderedEquals(['exported', 'id']));
      expect(ids(DocScope.all), hasLength(3));
    });

    test('Home lists scans in Docs and Word files in Saved', () {
      final scan = ScanState(
        pages: const [page],
        info: ScanDocInfo(name: 'Scan', createdAt: DateTime(2026, 11, 3)),
      );
      final words = [export('/e/Saved/Lease.docx', format: ExportFormat.word)];
      List<String> keys(DocScope s) => [for (final d in homeDocuments(scan, docs, scope: s, words: words)) d.key];
      expect(keys(DocScope.docs), ['scan-current', 'pdf-edited']);
      expect(keys(DocScope.saved), unorderedEquals(['pdf-exported', 'pdf-id', 'word-/e/Saved/Lease.docx']));
      expect(keys(DocScope.all), hasLength(5));
    });
  });

  group('SQLite export state', () {
    late Directory tmp;
    late PageStore files;
    late SqliteExportStateStore store;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lumascan_export_state');
      files = PageStore(rootDir: () async => tmp);
      store = SqliteExportStateStore(files, factory: databaseFactoryFfi, path: () async => '${tmp.path}/state.db');
    });

    tearDown(() async {
      await store.close();
      deleteTemp(tmp);
    });

    test('keeps one export per scan and kind, and survives reopening', () async {
      final saved = (await files.savedDir).path;
      await store.put(export('$saved/Lease.pdf'));
      await store.put(export('$saved/Lease.pdf', fp: 'b'));
      await store.put(export('$saved/Lease.docx', format: ExportFormat.word));
      expect((await store.find('scan-1', ExportFormat.pdf))!.fingerprint, 'b');
      expect(await store.all(), hasLength(2));
      await store.close();

      final reopened = SqliteExportStateStore(
        files,
        factory: databaseFactoryFfi,
        path: () async => '${tmp.path}/state.db',
      );
      expect(await reopened.find('scan-1', ExportFormat.pdf), export('$saved/Lease.pdf', fp: 'b'));
      await reopened.removePath('$saved/Lease.docx');
      expect(await reopened.find('scan-1', ExportFormat.word), isNull);
      await reopened.close();
    });

    test('a new step in migrations upgrades an existing database and keeps its rows', () async {
      final saved = (await files.savedDir).path;
      await store.put(export('$saved/Lease.pdf'));
      await store.close();
      expect(SqliteExportStateStore.schemaVersion, 1);

      SqliteExportStateStore.migrations.add((db) => db.execute('ALTER TABLE exports ADD COLUMN note TEXT'));
      try {
        final upgraded = SqliteExportStateStore(
          files,
          factory: databaseFactoryFfi,
          path: () async => '${tmp.path}/state.db',
        );
        expect(await upgraded.find('scan-1', ExportFormat.pdf), isNotNull);
        await upgraded.close();
        final db = await databaseFactoryFfi.openDatabase('${tmp.path}/state.db');
        expect(await db.getVersion(), 2);
        final columns = [for (final c in await db.rawQuery('PRAGMA table_info(exports)')) c['name']];
        expect(columns, contains('note'));
        await db.close();
      } finally {
        SqliteExportStateStore.migrations.removeLast();
      }
    });

    test('falls back to memory when the database cannot open', () async {
      final broken = SqliteExportStateStore(files, path: () async => throw StateError('no plugin'));
      await broken.put(export('/e/a.pdf'));
      expect(await broken.find('scan-1', ExportFormat.pdf), isNotNull);
    });
  });

  group('plan and record', () {
    late Directory tmp;
    late ProviderContainer container;
    late MemoryExportStateStore store;
    late String saved;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('lumascan_saved_exports');
      store = MemoryExportStateStore();
      container = ProviderContainer(
        overrides: [
          pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
          exportStateStoreProvider.overrideWithValue(store),
          libraryStoreProvider.overrideWithValue(MemoryLibraryStore()),
        ],
      );
      saved = (await container.read(pageStoreProvider).savedDir).path;
    });

    tearDown(() {
      container.dispose();
      deleteTemp(tmp);
    });

    Future<ExportPlan> plan(String fp, {String name = 'Lease.pdf'}) => container
        .read(savedExportsProvider.notifier)
        .plan(docKey: 'scan-1', format: ExportFormat.pdf, fingerprint: fp, fileName: name);

    test('first export goes to the Saved folder', () async {
      final p = await plan('a');
      expect(p, isA<ExportNew>().having((n) => n.fileName, 'fileName', 'Saved/Lease.pdf'));
    });

    test('same fingerprint and file still there: reuse; otherwise replace', () async {
      File('$saved/Lease.pdf').writeAsBytesSync([1]);
      await container.read(savedExportsProvider.notifier).record(export('$saved/Lease.pdf'));
      expect(await plan('a'), isA<ExportReuse>());

      final changed = await plan('b');
      expect(changed, isA<ExportNew>().having((n) => n.fileName, 'fileName', 'Saved/Lease.pdf'));
      expect((changed as ExportNew).previous, isNotNull);

      File('$saved/Lease.pdf').deleteSync();
      expect(await plan('a'), isA<ExportNew>(), reason: 'a deleted file is made again');
    });

    test('another scan\'s file with the same name is never replaced', () async {
      File('$saved/Lease.pdf').writeAsBytesSync([1]);
      expect(await plan('a'), isA<ExportNew>().having((n) => n.fileName, 'fileName', 'Saved/Lease (2).pdf'));
    });

    test('a renamed scan replaces its old file', () async {
      File('$saved/Lease.pdf').writeAsBytesSync([1]);
      final notifier = container.read(savedExportsProvider.notifier);
      await notifier.record(export('$saved/Lease.pdf'));
      final p = await plan('b', name: 'Rent.pdf') as ExportNew;
      File('$saved/Rent.pdf').writeAsBytesSync([2]);
      await notifier.record(export('$saved/Rent.pdf', fp: 'b'), previous: p.previous);
      expect(File('$saved/Lease.pdf').existsSync(), isFalse);
      expect(store.rows.single.path, '$saved/Rent.pdf');
    });

    test('Library keeps one entry when an export replaces another', () async {
      final library = container.read(libraryProvider.notifier);
      final first = await library.addScan(File('$saved/Lease.pdf')..writeAsBytesSync([1]), const []);
      await library.setFavorite([first.id], true);
      final second = await library.addScan(
        File('$saved/Rent.pdf')..writeAsBytesSync([2]),
        const [],
        replaceId: first.id,
      );
      final docs = (await container.read(libraryProvider.future)).documents;
      expect(docs, hasLength(1));
      expect(second.id, first.id);
      expect(docs.single.favorite, isTrue);
      expect(File('$saved/Lease.pdf').existsSync(), isFalse);
    });
  });
}
