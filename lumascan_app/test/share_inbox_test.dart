import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/share_inbox_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/photo_import.dart';
import 'package:lumascan/domain/share_inbox.dart';
import 'package:lumascan/features/capture/photo_import_screen.dart';
import 'package:lumascan/features/pages/scan_controller.dart';

import 'support/fake_photos.dart';
import 'support/memory_stores.dart';
import 'support/pump_app.dart';

/// Holds shares in memory and records which were discarded.
class FakeShareInbox implements ShareInbox {
  FakeShareInbox([List<SharedBatch>? batches]) : batches = batches ?? [];

  final List<SharedBatch> batches;
  final discarded = <String>[];

  @override
  Future<List<SharedBatch>> pending() async => List.of(batches);

  @override
  Future<void> discard(SharedBatch batch) async {
    batches.removeWhere((b) => b.id == batch.id);
    discarded.add(batch.id);
  }
}

SharedBatch batch(String id, List<String> names) => SharedBatch(
  id: id,
  photos: [for (final n in names) PickedPhoto(path: '/shared/$id/$n', name: n)],
);

Future<void> pumpFor(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('DirectoryShareInbox', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('share_inbox'));
    tearDown(() => tmp.deleteSync(recursive: true));

    void share(String folder, List<String> files) {
      final dir = Directory('${tmp.path}/$folder')..createSync();
      for (final f in files) {
        File('${dir.path}/$f').writeAsStringSync(f);
      }
    }

    test('lists finished shares oldest first, images in the order sent', () async {
      share('1700000000200', ['002.jpg', '001.png']);
      share('1700000000100', ['001.jpg']);
      share('.incoming-1700000000300', ['001.jpg']);
      final batches = await DirectoryShareInbox(() async => tmp).pending();
      expect(batches.map((b) => b.id.split('/').last), ['1700000000100', '1700000000200']);
      expect(batches[1].photos.map((p) => p.name), ['001.png', '002.jpg']);
    });

    test('discard deletes the share', () async {
      share('1700000000100', ['001.jpg']);
      final inbox = DirectoryShareInbox(() async => tmp);
      await inbox.discard((await inbox.pending()).single);
      expect(await inbox.pending(), isEmpty);
      expect(Directory('${tmp.path}/1700000000100').existsSync(), isFalse);
    });

    test('no inbox folder means nothing waiting', () async {
      expect(await DirectoryShareInbox(() async => null).pending(), isEmpty);
      expect(await DirectoryShareInbox(() async => Directory('${tmp.path}/missing')).pending(), isEmpty);
    });
  });

  group('shared images', () {
    late MemoryDraftStore draft;

    Future<FakeShareInbox> open(WidgetTester tester, FakeShareInbox inbox) async {
      await pumpApp(
        tester,
        draft: draft,
        overrides: [
          shareInboxProvider.overrideWithValue(inbox),
          photoAnalyzerProvider.overrideWithValue(FakePhotoAnalyzer()),
          pageStoreProvider.overrideWithValue(NoCopyPageStore()),
        ],
      );
      return inbox;
    }

    List<String> draftNames(WidgetTester tester) {
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      return [for (final p in container.read(scanControllerProvider).pages) p.originalPath.split('/').last];
    }

    setUp(() => draft = MemoryDraftStore());

    testWidgets('a share waiting at start opens import and becomes a new document', (tester) async {
      draft = MemoryDraftStore([const ScanPage(id: 'old', originalPath: '/old/old.jpg')]);
      final inbox = await open(
        tester,
        FakeShareInbox([
          batch('a', ['001.jpg', '002.jpg']),
          batch('b', ['001.png']),
        ]),
      );
      expect(find.byType(ImportPhotosScreen), findsOneWidget);
      expect(find.text('3 of 3 selected'), findsOneWidget);
      await tester.tap(find.text('Add 3 pages'));
      await pumpFor(tester);
      expect(draftNames(tester), ['001.jpg', '002.jpg', '001.png']);
      // The document on screen before is kept to open again.
      expect(draft.parkedPages.values.single.$2.single.id, 'old');
      expect(inbox.discarded, ['a', 'b']);
    });

    testWidgets('closing the import screen drops the share', (tester) async {
      final inbox = await open(
        tester,
        FakeShareInbox([
          batch('a', ['001.jpg']),
        ]),
      );
      await tester.pageBack();
      await pumpFor(tester);
      expect(find.byType(ImportPhotosScreen), findsNothing);
      expect(draftNames(tester), isEmpty);
      expect(inbox.discarded, ['a']);
    });

    testWidgets('a share arriving while the app is open is picked up when it resumes', (tester) async {
      final inbox = await open(tester, FakeShareInbox());
      expect(find.byType(ImportPhotosScreen), findsNothing);
      inbox.batches.add(batch('a', ['001.jpg']));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFor(tester);
      expect(find.text('1 of 1 selected'), findsOneWidget);
    });
  });
}
