import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'profile_location.dart';
import 'profile_sample.dart';

/// Where image-loading profile samples are kept.
abstract interface class ProfileStore {
  Future<void> add(ProfileSample sample);

  /// Averages per kind, and per screen for shown pictures, slowest first.
  Future<List<ProfileSummaryRow>> summary();

  /// The newest samples first.
  Future<List<ProfileSample>> recent({int limit = 50});

  Future<int> count();
  Future<void> clear();

  /// A saved switch, such as whether profiling is on.
  Future<bool?> readFlag(String name);
  Future<void> writeFlag(String name, bool value);
}

/// Keeps samples in a SQLite database, so a profile survives restarts (cold
/// starts are often the slowest case) and, where [ProfileLocation] allows,
/// reinstalls.
class SqliteProfileStore implements ProfileStore {
  SqliteProfileStore({this.factory, Future<String> Function()? path})
    : _path = path ?? (() async => p.join(await getDatabasesPath(), ProfileLocation.fileName));

  /// The database factory; the platform's sqflite one when null. Tests pass
  /// the ffi one.
  final DatabaseFactory? factory;
  final Future<String> Function() _path;
  Future<Database>? _db;

  static const _stageColumns = profileStages;

  Future<Database> get _open => _db ??= _openDb();

  /// The file in use, once opened.
  Future<String?> get openPath async => (await _db)?.path;

  /// Closes the database so the next use opens it again, from wherever the
  /// path now points (after shared storage was allowed).
  Future<void> reopen() async {
    final db = _db;
    _db = null;
    await (await db)?.close();
  }

  Future<Database> _openDb() async => (factory ?? databaseFactory).openDatabase(
    await _path(),
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE samples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            at INTEGER NOT NULL,
            kind TEXT NOT NULL,
            screen TEXT,
            page_id TEXT,
            origin TEXT,
            filter TEXT,
            source_bytes INTEGER NOT NULL,
            width INTEGER NOT NULL,
            height INTEGER NOT NULL,
            max_dimension INTEGER NOT NULL,
            wait_ms REAL NOT NULL,
            total_ms REAL NOT NULL,
            ${_stageColumns.map((s) => '${s}_ms REAL').join(',\n            ')}
          )''');
        await db.execute('CREATE INDEX samples_kind ON samples(kind, screen)');
        await db.execute('CREATE TABLE flags (name TEXT PRIMARY KEY, value INTEGER NOT NULL)');
      },
    ),
  );

  @override
  Future<void> add(ProfileSample s) async {
    final db = await _open;
    await db.insert('samples', {
      'at': s.at.millisecondsSinceEpoch,
      'kind': s.kind.id,
      'screen': s.screen,
      'page_id': s.pageId,
      'origin': s.origin?.id,
      'filter': s.filter,
      'source_bytes': s.sourceBytes,
      'width': s.width,
      'height': s.height,
      'max_dimension': s.maxDimension,
      'wait_ms': s.waitMs,
      'total_ms': s.totalMs,
      for (final stage in _stageColumns) '${stage}_ms': s.stageMs[stage],
    });
  }

  @override
  Future<List<ProfileSummaryRow>> summary() async {
    final db = await _open;
    final rows = await db.rawQuery('''
      SELECT kind, screen, COUNT(*) AS n, AVG(total_ms) AS avg_ms, MIN(total_ms) AS min_ms,
             MAX(total_ms) AS max_ms, AVG(wait_ms) AS avg_wait, AVG(source_bytes) AS avg_bytes,
             ${_stageColumns.map((s) => 'AVG(${s}_ms) AS avg_$s').join(', ')}
      FROM samples
      GROUP BY kind, screen
      ORDER BY avg_ms DESC''');
    return [
      for (final r in rows)
        ProfileSummaryRow(
          kind: ProfileKind.fromId(r['kind']! as String),
          screen: r['screen'] as String?,
          count: r['n']! as int,
          avgMs: _d(r['avg_ms']),
          minMs: _d(r['min_ms']),
          maxMs: _d(r['max_ms']),
          avgWaitMs: _d(r['avg_wait']),
          avgSourceMb: _d(r['avg_bytes']) / (1024 * 1024),
          avgStageMs: {
            for (final s in _stageColumns)
              if (r['avg_$s'] != null) s: _d(r['avg_$s']),
          },
        ),
    ];
  }

  @override
  Future<List<ProfileSample>> recent({int limit = 50}) async {
    final db = await _open;
    final rows = await db.query('samples', orderBy: 'id DESC', limit: limit);
    return [
      for (final r in rows)
        ProfileSample(
          at: DateTime.fromMillisecondsSinceEpoch(r['at']! as int),
          kind: ProfileKind.fromId(r['kind']! as String),
          screen: r['screen'] as String?,
          pageId: r['page_id'] as String?,
          origin: ProfileOrigin.fromId(r['origin'] as String?),
          filter: r['filter'] as String?,
          sourceBytes: r['source_bytes']! as int,
          width: r['width']! as int,
          height: r['height']! as int,
          maxDimension: r['max_dimension']! as int,
          waitMs: _d(r['wait_ms']),
          totalMs: _d(r['total_ms']),
          stageMs: {
            for (final s in _stageColumns)
              if (r['${s}_ms'] != null) s: _d(r['${s}_ms']),
          },
        ),
    ];
  }

  @override
  Future<int> count() async {
    final db = await _open;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM samples')) ?? 0;
  }

  @override
  Future<void> clear() async {
    final db = await _open;
    await db.delete('samples');
  }

  @override
  Future<bool?> readFlag(String name) async {
    final db = await _open;
    final rows = await db.query('flags', where: 'name = ?', whereArgs: [name]);
    return rows.isEmpty ? null : rows.first['value'] == 1;
  }

  @override
  Future<void> writeFlag(String name, bool value) async {
    final db = await _open;
    await db.insert('flags', {'name': name, 'value': value ? 1 : 0}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> close() async => (await _db)?.close();

  static double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
}

/// Keeps samples in memory, for tests and when the database cannot open.
class MemoryProfileStore implements ProfileStore {
  final samples = <ProfileSample>[];
  final _flags = <String, bool>{};

  @override
  Future<void> add(ProfileSample sample) async => samples.add(sample);

  @override
  Future<List<ProfileSummaryRow>> summary() async {
    final groups = <(ProfileKind, String?), List<ProfileSample>>{};
    for (final s in samples) {
      groups.putIfAbsent((s.kind, s.screen), () => []).add(s);
    }
    double avg(Iterable<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
    final rows = [
      for (final MapEntry(key: (kind, screen), value: list) in groups.entries)
        ProfileSummaryRow(
          kind: kind,
          screen: screen,
          count: list.length,
          avgMs: avg(list.map((s) => s.totalMs)),
          minMs: list.map((s) => s.totalMs).reduce((a, b) => a < b ? a : b),
          maxMs: list.map((s) => s.totalMs).reduce((a, b) => a > b ? a : b),
          avgWaitMs: avg(list.map((s) => s.waitMs)),
          avgSourceMb: avg(list.map((s) => s.sourceMb)),
          avgStageMs: {
            for (final stage in profileStages)
              if (list.any((s) => s.stageMs.containsKey(stage))) stage: avg([for (final s in list) ?s.stageMs[stage]]),
          },
        ),
    ]..sort((a, b) => b.avgMs.compareTo(a.avgMs));
    return rows;
  }

  @override
  Future<List<ProfileSample>> recent({int limit = 50}) async => samples.reversed.take(limit).toList();

  @override
  Future<int> count() async => samples.length;

  @override
  Future<void> clear() async => samples.clear();

  @override
  Future<bool?> readFlag(String name) async => _flags[name];

  @override
  Future<void> writeFlag(String name, bool value) async => _flags[name] = value;
}
