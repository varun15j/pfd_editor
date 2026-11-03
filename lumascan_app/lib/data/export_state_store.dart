import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/saved_export.dart';
import 'page_store.dart';

/// Remembers what was exported from each scan, so an unchanged scan reuses
/// its saved file and a changed one replaces it (see [SavedExport]).
abstract interface class ExportStateStore {
  /// The saved file of [format] for scan [docKey], or null.
  Future<SavedExport?> find(String docKey, ExportFormat format);

  /// Every saved export, newest first.
  Future<List<SavedExport>> all();

  /// Adds [export], replacing the one of the same scan and format.
  Future<void> put(SavedExport export);

  /// Forgets the export saved at [path], such as when its file is deleted.
  Future<void> removePath(String path);
}

/// Keeps export state in a SQLite database (`export_state.db`). When the
/// database can't be opened (as in widget tests, which have no sqflite
/// plugin), it keeps the state in memory for this run instead, so exporting
/// still works and only reuse across restarts is lost.
class SqliteExportStateStore implements ExportStateStore {
  SqliteExportStateStore(this._files, {this.factory, Future<String> Function()? path})
    : _path = path ?? (() async => p.join(await getDatabasesPath(), fileName));

  static const fileName = 'export_state.db';

  final PageStore _files;

  /// The database factory; the platform's sqflite one when null. Tests pass
  /// the ffi one.
  final DatabaseFactory? factory;
  final Future<String> Function() _path;
  Future<Database?>? _db;
  final _fallback = MemoryExportStateStore();

  Future<Database?> get _open => _db ??= _openDb();

  Future<Database?> _openDb() async {
    try {
      return await (factory ?? databaseFactory).openDatabase(
        await _path(),
        options: OpenDatabaseOptions(
          version: schemaVersion,
          // A new install runs every step; an update runs only the steps
          // after the version it has.
          onCreate: (db, version) => _migrate(db, 0, version),
          onUpgrade: _migrate,
          // A newer app wrote this file and the user went back to an older
          // one: start again rather than misread it. Saved files stay;
          // they are only exported once more.
          onDowngrade: onDatabaseDowngradeDelete,
        ),
      );
    } on Object catch (e) {
      debugPrint('Export state database not available, keeping it in memory: $e');
      return null;
    }
  }

  /// Schema steps, oldest first: step i takes the database from version i
  /// to version i + 1. To change the schema, add a step at the end (never
  /// edit a released one); [schemaVersion] follows.
  static final List<Future<void> Function(DatabaseExecutor db)> migrations = [
    // 1: one row per scan and kind of export.
    (db) async {
      await db.execute('''
        CREATE TABLE exports (
          doc_key TEXT NOT NULL,
          format TEXT NOT NULL,
          path TEXT NOT NULL,
          fingerprint TEXT NOT NULL,
          name TEXT NOT NULL,
          page_count INTEGER NOT NULL,
          size_bytes INTEGER NOT NULL,
          exported_at INTEGER NOT NULL,
          library_id TEXT,
          PRIMARY KEY (doc_key, format)
        )''');
      await db.execute('CREATE INDEX exports_path ON exports(path)');
    },
  ];

  static int get schemaVersion => migrations.length;

  /// sqflite already runs onCreate and onUpgrade in one transaction, so a
  /// failed step leaves the database as it was.
  static Future<void> _migrate(Database db, int from, int to) async {
    for (var v = from; v < to; v++) {
      await migrations[v](db);
    }
  }

  Future<String> get _exports async => (await _files.exportsDir).path;

  @override
  Future<SavedExport?> find(String docKey, ExportFormat format) async {
    final db = await _open;
    if (db == null) return _fallback.find(docKey, format);
    final rows = await db.query(
      'exports',
      where: 'doc_key = ? AND format = ?',
      whereArgs: [docKey, format.id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single, await _exports);
  }

  @override
  Future<List<SavedExport>> all() async {
    final db = await _open;
    if (db == null) return _fallback.all();
    final root = await _exports;
    return [for (final row in await db.query('exports', orderBy: 'exported_at DESC')) ?_fromRow(row, root)];
  }

  @override
  Future<void> put(SavedExport e) async {
    final db = await _open;
    if (db == null) return _fallback.put(e);
    await db.insert('exports', {
      'doc_key': e.docKey,
      'format': e.format.id,
      'path': p.relative(e.path, from: await _exports),
      'fingerprint': e.fingerprint,
      'name': e.name,
      'page_count': e.pageCount,
      'size_bytes': e.sizeBytes,
      'exported_at': e.exportedAt.toUtc().millisecondsSinceEpoch,
      'library_id': e.libraryId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> removePath(String path) async {
    final db = await _open;
    if (db == null) return _fallback.removePath(path);
    await db.delete(
      'exports',
      where: 'path = ?',
      whereArgs: [p.relative(path, from: await _exports)],
    );
  }

  Future<void> close() async => (await _db)?.close();

  static SavedExport? _fromRow(Map<String, Object?> row, String root) {
    final format = ExportFormat.fromId(row['format'] as String?);
    if (format == null) return null;
    return SavedExport(
      docKey: row['doc_key']! as String,
      format: format,
      path: p.join(root, row['path']! as String),
      fingerprint: row['fingerprint']! as String,
      name: row['name']! as String,
      pageCount: (row['page_count']! as num).toInt(),
      sizeBytes: (row['size_bytes']! as num).toInt(),
      exportedAt: DateTime.fromMillisecondsSinceEpoch((row['exported_at']! as num).toInt(), isUtc: true).toLocal(),
      libraryId: row['library_id'] as String?,
    );
  }
}

/// Export state kept in memory, for tests and as the fallback.
class MemoryExportStateStore implements ExportStateStore {
  final rows = <SavedExport>[];

  @override
  Future<SavedExport?> find(String docKey, ExportFormat format) async =>
      rows.where((r) => r.docKey == docKey && r.format == format).firstOrNull;

  @override
  Future<List<SavedExport>> all() async => [...rows]..sort((a, b) => b.exportedAt.compareTo(a.exportedAt));

  @override
  Future<void> put(SavedExport export) async {
    rows
      ..removeWhere((r) => r.docKey == export.docKey && r.format == export.format)
      ..add(export);
  }

  @override
  Future<void> removePath(String path) async => rows.removeWhere((r) => r.path == path);
}
