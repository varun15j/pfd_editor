import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/credits.dart';

/// The saved credits: the balance and every change to it.
abstract interface class CreditStore {
  /// The balance, or null when no account exists yet (a new install).
  Future<int?> balance();

  /// Every ledger entry, newest first.
  Future<List<CreditEntry>> history();

  /// Adds [entry] and sets the balance to its [CreditEntry.balanceAfter], in
  /// one step. Returns false, changing nothing, when an entry with the same
  /// [CreditEntry.purchaseId] is already in the ledger.
  Future<bool> add(CreditEntry entry);
}

/// Keeps credits in a SQLite database (`credits.db`) with two tables:
/// `credit_account`, one row with the balance and when the account was made,
/// and `credit_ledger`, one row per change. When the database can't be
/// opened (as in widget tests, which have no sqflite plugin), credits are
/// kept in memory for this run instead.
///
/// The database lives in the app's own data, so uninstalling the app (or
/// clearing its data) starts a new account. Stopping that needs a server.
class SqliteCreditStore implements CreditStore {
  SqliteCreditStore({this.factory, Future<String> Function()? path})
    : _path = path ?? (() async => p.join(await getDatabasesPath(), fileName));

  static const fileName = 'credits.db';

  /// The database factory; the platform's sqflite one when null. Tests pass
  /// the ffi one.
  final DatabaseFactory? factory;
  final Future<String> Function() _path;
  Future<Database?>? _db;
  final _fallback = MemoryCreditStore();

  Future<Database?> get _open => _db ??= _openDb();

  Future<Database?> _openDb() async {
    try {
      return await (factory ?? databaseFactory).openDatabase(
        await _path(),
        options: OpenDatabaseOptions(
          version: schemaVersion,
          onCreate: (db, version) => _migrate(db, 0, version),
          onUpgrade: _migrate,
        ),
      );
    } on Object catch (e) {
      debugPrint('Credits database not available, keeping credits in memory: $e');
      return null;
    }
  }

  /// Schema steps, oldest first: step i takes the database from version i
  /// to version i + 1. To change the schema, add a step at the end (never
  /// edit a released one).
  static final List<Future<void> Function(DatabaseExecutor db)> migrations = [
    (db) async {
      await db.execute('''
        CREATE TABLE credit_account (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          balance INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        )''');
      await db.execute('''
        CREATE TABLE credit_ledger (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          reason TEXT NOT NULL,
          amount INTEGER NOT NULL,
          balance_after INTEGER NOT NULL,
          at INTEGER NOT NULL,
          note TEXT,
          purchase_id TEXT UNIQUE
        )''');
    },
  ];

  static int get schemaVersion => migrations.length;

  static Future<void> _migrate(Database db, int from, int to) async {
    for (var v = from; v < to; v++) {
      await migrations[v](db);
    }
  }

  @override
  Future<int?> balance() async {
    final db = await _open;
    if (db == null) return _fallback.balance();
    final rows = await db.query('credit_account', columns: ['balance'], where: 'id = 1');
    return rows.isEmpty ? null : (rows.single['balance']! as num).toInt();
  }

  @override
  Future<List<CreditEntry>> history() async {
    final db = await _open;
    if (db == null) return _fallback.history();
    final rows = await db.query('credit_ledger', orderBy: 'id DESC');
    return [for (final row in rows) ?_fromRow(row)];
  }

  @override
  Future<bool> add(CreditEntry entry) async {
    final db = await _open;
    if (db == null) return _fallback.add(entry);
    return db.transaction((txn) async {
      if (entry.purchaseId != null) {
        final seen = await txn.query('credit_ledger', where: 'purchase_id = ?', whereArgs: [entry.purchaseId]);
        if (seen.isNotEmpty) return false;
      }
      await txn.insert('credit_ledger', {
        'reason': entry.reason.name,
        'amount': entry.amount,
        'balance_after': entry.balanceAfter,
        'at': entry.at.toUtc().millisecondsSinceEpoch,
        'note': entry.note,
        'purchase_id': entry.purchaseId,
      });
      await txn.insert('credit_account', {
        'id': 1,
        'balance': entry.balanceAfter,
        'created_at': entry.at.toUtc().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.update('credit_account', {'balance': entry.balanceAfter}, where: 'id = 1');
      return true;
    });
  }

  Future<void> close() async => (await _db)?.close();

  static CreditEntry? _fromRow(Map<String, Object?> row) {
    final reason = CreditReason.values.asNameMap()[row['reason']];
    if (reason == null) return null;
    return CreditEntry(
      reason: reason,
      amount: (row['amount']! as num).toInt(),
      balanceAfter: (row['balance_after']! as num).toInt(),
      at: DateTime.fromMillisecondsSinceEpoch((row['at']! as num).toInt(), isUtc: true).toLocal(),
      note: row['note'] as String?,
      purchaseId: row['purchase_id'] as String?,
    );
  }
}

/// Credits kept in memory, for tests and as the fallback.
class MemoryCreditStore implements CreditStore {
  MemoryCreditStore({int? balance, List<CreditEntry>? entries}) : _balance = balance, entries = entries ?? [];

  int? _balance;

  /// Oldest first.
  final List<CreditEntry> entries;

  @override
  Future<int?> balance() async => _balance;

  @override
  Future<List<CreditEntry>> history() async => entries.reversed.toList();

  @override
  Future<bool> add(CreditEntry entry) async {
    if (entry.purchaseId != null && entries.any((e) => e.purchaseId == entry.purchaseId)) return false;
    entries.add(entry);
    _balance = entry.balanceAfter;
    return true;
  }
}
