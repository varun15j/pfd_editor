import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/features/batch_capture/batch_capture_screen.dart';
import 'package:lumascan/features/batch_edit/batch_review_screen.dart';
import 'package:lumascan/features/pages/scan_controller.dart';

import 'support/fake_batch_camera.dart';
import 'support/memory_stores.dart';
import 'support/screen_harness.dart';

/// A draft store whose saves wait for the test, and can fail.
class _GatedDraftStore extends MemoryDraftStore {
  Completer<void>? gate;
  bool fail = false;

  @override
  Future<void> save(List<ScanPage> pages) async {
    await gate?.future;
    if (fail) throw StateError('disk full');
    await super.save(pages);
  }
}

void main() {
  group('draft save status', () {
    late _GatedDraftStore store;
    late ProviderContainer container;

    setUp(() async {
      store = _GatedDraftStore()..pages = [const ScanPage(id: 'a', originalPath: '/a.jpg')];
      container = ProviderContainer(overrides: [draftStoreProvider.overrideWithValue(store)]);
      container.read(scanControllerProvider);
      await container.read(scanControllerProvider.notifier).draftSaved;
    });

    tearDown(() => container.dispose());

    DraftSaveStatus status() => container.read(draftSaveStatusProvider);

    test('says saved only after the draft is written', () async {
      store.gate = Completer<void>();
      container.read(scanControllerProvider.notifier).rotatePages({'a'});
      expect(status(), DraftSaveStatus.saving);

      store.gate!.complete();
      await container.read(scanControllerProvider.notifier).draftSaved;
      expect(status(), DraftSaveStatus.saved);
      expect(store.pages.single.recipe.quarterTurns, 1);
    });

    test('reports a failed save, and recovers on the next good one', () async {
      store.fail = true;
      container.read(scanControllerProvider.notifier).rotatePages({'a'});
      await container.read(scanControllerProvider.notifier).draftSaved;
      expect(status(), DraftSaveStatus.failed);

      store.fail = false;
      container.read(scanControllerProvider.notifier).rotatePages({'a'});
      await container.read(scanControllerProvider.notifier).draftSaved;
      expect(status(), DraftSaveStatus.saved);
    });
  });

  group('Done in Batch Review', () {
    final harness = ScreenHarness();
    late Directory shots;
    tearDown(() {
      harness.dispose();
      shots.deleteSync(recursive: true);
    });

    Future<void> openDone(WidgetTester tester) async {
      shots = Directory.systemTemp.createTempSync('lumascan_shots');
      await tester.runAsync(
        () => harness.setUp(
          pageCount: 2,
          overrides: [batchCameraProvider.overrideWithValue(() => FakeBatchCamera(shots))],
        ),
      );
      await harness.pumpRoute(tester, (_) => const BatchReviewScreen());
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers camera, review and export, and shows the draft is saved', (tester) async {
      await openDone(tester);
      expect(find.text('Return to camera'), findsOneWidget);
      expect(find.text('Review document'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.bySemanticsLabel('Draft: Saved on this device'), findsWidgets);
    });

    testWidgets('Review document leaves Batch Review', (tester) async {
      await openDone(tester);
      await tester.tap(find.text('Review document'));
      await tester.pumpAndSettle();
      expect(find.text('Batch review'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('Return to camera opens Batch capture into the same draft and keeps the selection', (tester) async {
      await openDone(tester);
      await tester.tap(find.text('Return to camera'));
      await harness.settle(tester);
      expect(find.byType(BatchCaptureScreen), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Take photo'));
      await harness.settle(tester);
      await tester.tap(find.text('Review'));
      await harness.settle(tester);

      expect(harness.pages, hasLength(3));
      expect(find.byType(BatchCaptureScreen), findsNothing);
      expect(find.text('Batch review'), findsOneWidget);
      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('Export PDF opens the export settings', (tester) async {
      await openDone(tester);
      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Save as PDF'), findsOneWidget);
    });
  });
}
