import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/features/cloud/drive_sync.dart';
import 'package:path/path.dart' as p;

import 'support/temp_dir.dart';

/// Exports are not kept by the app: they are made in the Outbox, saved where
/// the user picks or shared, and cleared later.
void main() {
  late Directory root;
  late PageStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lumascan_outbox');
    store = PageStore(rootDir: () async => root);
  });
  tearDown(() => deleteTemp(root));

  test('each export gets its own Outbox folder and keeps the name typed', () async {
    final a = await store.outboxName('Lease.pdf');
    final b = await store.outboxName('Lease.pdf');

    expect(p.posix.basename(a), 'Lease.pdf');
    expect(p.posix.basename(b), 'Lease.pdf');
    expect(a, isNot(b));
    expect(a, startsWith('${PageStore.outboxFolder}/'));

    final file = await store.writeExportAtomically(a, [1, 2, 3]);
    expect(p.isWithin((await store.outboxDir).path, file.path), isTrue);
    // Never in the Saved folder, which held the exports the app used to keep.
    expect(p.isWithin((await store.savedDir).path, file.path), isFalse);
  });

  test('moveToOutbox moves an export made in the exports folder', () async {
    final made = await store.writeExportAtomically('Table.xlsx', [1]);

    final moved = await store.moveToOutbox(made);

    expect(made.existsSync(), isFalse);
    expect(p.basename(moved.path), 'Table.xlsx');
    expect(p.isWithin((await store.outboxDir).path, moved.path), isTrue);
    expect(await store.moveToOutbox(moved), same(moved));
  });

  test('clearOutbox keeps exports just made and removes older ones', () async {
    final first = await store.writeExportAtomically(await store.outboxName('Old.pdf'), [1]);
    final second = await store.writeExportAtomically(await store.outboxName('New.pdf'), [1]);

    // Just made: a share target may still be reading them.
    await store.clearOutbox();
    expect(first.existsSync(), isTrue);
    expect(second.existsSync(), isTrue);

    await store.clearOutbox(olderThan: Duration.zero);
    expect(first.existsSync(), isFalse);
    expect(second.existsSync(), isFalse);
  });

  test('a Drive upload keeps its own copy until it is uploaded', () async {
    final queue = PageStoreSyncQueue(store);
    final export = await store.writeExportAtomically(await store.outboxName('Lease.pdf'), [1, 2]);

    final waiting = await queue.keep(export);
    expect(p.isWithin((await store.syncQueueDir).path, waiting), isTrue);
    // The Outbox can be cleared meanwhile.
    await store.clearOutbox(olderThan: Duration.zero);
    expect(File(waiting).readAsBytesSync(), [1, 2]);

    await queue.release(waiting);
    expect(File(waiting).existsSync(), isFalse);
  });

  test('release leaves files outside the queue alone', () async {
    final queue = PageStoreSyncQueue(store);
    final other = await store.writeExportAtomically('Keep.pdf', [1]);

    await queue.release(other.path);

    expect(other.existsSync(), isTrue);
  });
}
