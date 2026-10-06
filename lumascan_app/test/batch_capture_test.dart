import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/features/batch_capture/batch_capture_screen.dart';
import 'package:lumascan/features/batch_edit/batch_review_screen.dart';
import 'package:lumascan/features/pages/scan_controller.dart';

import 'support/fake_batch_camera.dart';
import 'support/fake_photos.dart';
import 'support/memory_stores.dart';
import 'support/screen_harness.dart';

void main() {
  group('ScanController captures', () {
    late Directory tmp;
    late ProviderContainer container;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('lumascan_capture');
      container = ProviderContainer(
        overrides: [
          pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
          draftStoreProvider.overrideWithValue(MemoryDraftStore()),
        ],
      );
      container.read(scanControllerProvider);
      await container.read(scanControllerProvider.notifier).draftSaved;
    });

    tearDown(() {
      container.dispose();
      tmp.deleteSync(recursive: true);
    });

    ScanController controller() => container.read(scanControllerProvider.notifier);
    List<ScanPage> pages() => container.read(scanControllerProvider).pages;
    String photo(String name) => (File('${tmp.path}/$name')..writeAsStringSync(name)).path;

    test('adds pages in shutter order and moves each photo into the draft', () async {
      final shots = [for (var i = 0; i < 5; i++) photo('shot$i.jpg')];
      final added = await Future.wait([for (final s in shots) controller().addCapture(s)]);

      expect([for (final p in pages()) p.id], [for (final p in added) p!.id]);
      for (var i = 0; i < 5; i++) {
        expect(File(shots[i]).existsSync(), isFalse, reason: 'moved, not copied');
        expect(File(pages()[i].originalPath).readAsStringSync(), 'shot$i.jpg');
      }
    });

    test('a retake replaces only that page, in its place, and can be undone', () async {
      for (var i = 0; i < 3; i++) {
        await controller().addCapture(photo('shot$i.jpg'));
      }
      final before = [for (final p in pages()) p.id];

      final retake = await controller().addCapture(photo('retake.jpg'), replacing: before[2]);

      expect([for (final p in pages()) p.id], [before[0], before[1], retake!.id]);
      expect(File(pages()[2].originalPath).readAsStringSync(), 'retake.jpg');
      controller().undo();
      expect([for (final p in pages()) p.id], before);
    });

    test('a detected crop adds no undo step and survives undoing a later capture', () async {
      final first = await controller().addCapture(photo('a.jpg'));
      await controller().addCapture(photo('b.jpg'));
      final undoDepth = container.read(scanControllerProvider).undoStack.length;

      controller().applyDetectedCrop(first!.id, FakePhotoAnalyzer.quad);
      expect(container.read(scanControllerProvider).undoStack, hasLength(undoDepth));
      expect(pages().first.recipe.crop, FakePhotoAnalyzer.quad);

      controller().undo();
      expect(pages(), hasLength(1));
      expect(pages().first.recipe.crop, FakePhotoAnalyzer.quad);
    });

    test('a detected crop never overrides a crop the user made', () async {
      final page = await controller().addCapture(photo('a.jpg'));
      const own = CropQuad(NormPoint(0.2, 0.2), NormPoint(0.8, 0.2), NormPoint(0.8, 0.8), NormPoint(0.2, 0.8));
      controller().updateRecipe(page!.id, page.recipe.copyWith(crop: own));

      controller().applyDetectedCrop(page.id, FakePhotoAnalyzer.quad);
      expect(pages().single.recipe.crop, own);
    });
  });

  group('Batch capture screen', () {
    final harness = ScreenHarness();
    late Directory shots;
    late FakeBatchCamera camera;

    tearDown(() {
      harness.dispose();
      shots.deleteSync(recursive: true);
    });

    Future<void> open(WidgetTester tester, {int pageCount = 0, bool deny = false}) async {
      shots = Directory.systemTemp.createTempSync('lumascan_shots');
      camera = FakeBatchCamera(shots, deny: deny);
      await tester.runAsync(
        () => harness.setUp(
          pageCount: pageCount,
          overrides: [
            batchCameraProvider.overrideWithValue(() => camera),
            photoAnalyzerProvider.overrideWithValue(FakePhotoAnalyzer()),
          ],
        ),
      );
      await harness.pumpRoute(tester, (_) => const BatchCaptureScreen());
    }

    Future<void> shoot(WidgetTester tester, {int times = 1}) async {
      for (var i = 0; i < times; i++) {
        await tester.tap(find.bySemanticsLabel(RegExp(r'^Take (the new )?photo$')));
        await tester.pump();
      }
      await harness.settle(tester);
    }

    Future<void> openPhotos(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Open preview of \d+ captured photos?$')));
      await harness.settle(tester);
    }

    Future<void> review(WidgetTester tester) async {
      await openPhotos(tester);
      await tester.tap(find.textContaining(RegExp(r'^Review all \d+ pages?$')));
      await harness.settle(tester);
    }

    Future<void> retake(WidgetTester tester, int page) async {
      await openPhotos(tester);
      await tester.tap(find.bySemanticsLabel('Retake page $page'));
      await harness.settle(tester);
    }

    testWidgets('each shot is saved and the camera is ready again, with no confirmation', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget);

      await shoot(tester, times: 3);

      expect(camera.shots, 3);
      expect(harness.pages, hasLength(3));
      expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.bySemanticsLabel('3 pages captured'), findsOneWidget);
      expect(find.bySemanticsLabel('Open preview of 3 captured photos'), findsOneWidget);
    });

    testWidgets('quick taps while a photo is being taken are queued, not lost', (tester) async {
      await open(tester);
      camera.gate = Completer<void>();
      final shutter = find.bySemanticsLabel('Take photo');
      for (var i = 0; i < 3; i++) {
        await tester.tap(shutter);
        await tester.pump();
      }
      camera.gate!.complete();
      await harness.settle(tester);

      expect(harness.pages, hasLength(3));
    });

    testWidgets('new pages are cropped to the page found in them', (tester) async {
      await open(tester);
      await shoot(tester);
      expect(harness.pages.single.recipe.crop, FakePhotoAnalyzer.quad);
    });

    testWidgets('Auto crop off in Camera settings keeps the whole photo', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Camera settings'));
      await harness.settle(tester);
      await tester.tap(find.text('Auto crop'));
      await harness.settle(tester);
      await tester.tap(find.byTooltip('Close'));
      await harness.settle(tester);
      await shoot(tester);
      expect(harness.pages.single.recipe.crop.isFull, isTrue);
    });

    testWidgets('Retake from Captured photos swaps that photo for the next one', (tester) async {
      await open(tester);
      await shoot(tester, times: 2);
      final before = [for (final p in harness.pages) p.id];

      await retake(tester, 2);
      expect(find.text('Retaking page 2. Take the new photo.'), findsOneWidget);

      await shoot(tester);
      final after = [for (final p in harness.pages) p.id];
      expect(after, hasLength(2));
      expect(after.first, before.first);
      expect(after.last, isNot(before.last));
      expect(find.textContaining('Retaking'), findsNothing);

      // The next shot is a new page again.
      await shoot(tester);
      expect(harness.pages, hasLength(3));
    });

    testWidgets('Retake can be cancelled', (tester) async {
      await open(tester);
      await shoot(tester);
      await retake(tester, 1);
      await tester.tap(find.text('Cancel').first);
      await tester.pump();
      await shoot(tester);
      expect(harness.pages, hasLength(2));
    });

    testWidgets('Review all opens Batch Review over the camera, and Back resumes it', (tester) async {
      await open(tester);
      await shoot(tester, times: 2);

      await review(tester);
      expect(find.byType(BatchReviewScreen), findsOneWidget);
      expect(find.text('2 selected'), findsOneWidget);
      expect(camera.pauses, 1);

      await tester.pageBack();
      await harness.settle(tester);
      expect(find.byType(BatchReviewScreen), findsNothing);
      expect(camera.resumes, 1);
      await shoot(tester);
      expect(harness.pages, hasLength(3));
    });

    testWidgets('Return to camera from Batch Review keeps shooting into the same draft', (tester) async {
      await open(tester, pageCount: 1);
      await shoot(tester);
      await review(tester);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Return to camera'));
      await harness.settle(tester);

      expect(find.byType(BatchCaptureScreen), findsOneWidget);
      await shoot(tester);
      expect(harness.pages, hasLength(3));
    });

    testWidgets('Review document from Batch Review closes the camera', (tester) async {
      await open(tester);
      await shoot(tester);
      await review(tester);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review document'));
      await harness.settle(tester);

      expect(find.byType(BatchCaptureScreen), findsNothing);
      expect(camera.closed, isTrue);
    });

    testWidgets('Continue scanning closes Captured photos and keeps the camera open', (tester) async {
      await open(tester);
      await shoot(tester, times: 2);
      await openPhotos(tester);
      expect(find.text('Captured photos'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Retake page \d$')), findsNWidgets(2));

      await tester.tap(find.text('Continue scanning'));
      await harness.settle(tester);
      expect(find.text('Captured photos'), findsNothing);
      await shoot(tester);
      expect(harness.pages, hasLength(3));
    });

    testWidgets('the cross asks first, and Discard photos removes this visit\'s photos', (tester) async {
      await open(tester, pageCount: 1);
      final kept = harness.pages.single.id;
      await shoot(tester, times: 2);

      await tester.tap(find.bySemanticsLabel('Discard all captured photos and changes'));
      await harness.settle(tester);
      expect(find.text('Discard the photos?'), findsOneWidget);
      await tester.tap(find.text('Keep photos'));
      await harness.settle(tester);
      expect(find.byType(BatchCaptureScreen), findsOneWidget);
      expect(harness.pages, hasLength(3));

      await tester.tap(find.bySemanticsLabel('Discard all captured photos and changes'));
      await harness.settle(tester);
      await tester.tap(find.text('Discard photos'));
      await harness.settle(tester);
      expect(find.byType(BatchCaptureScreen), findsNothing);
      expect([for (final p in harness.pages) p.id], [kept]);
    });

    testWidgets('the cross closes straight away when no photo was taken', (tester) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('Discard all captured photos and changes'));
      await harness.settle(tester);
      expect(find.text('Discard the photos?'), findsNothing);
      expect(find.byType(BatchCaptureScreen), findsNothing);
    });

    testWidgets('Batch off opens Batch Review after each photo', (tester) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('Batch On'));
      await tester.pump();
      expect(find.bySemanticsLabel('Batch Off'), findsOneWidget);

      await shoot(tester);
      expect(find.byType(BatchReviewScreen), findsOneWidget);
    });

    testWidgets('Camera settings switches stay in step with the quick controls', (tester) async {
      await open(tester);
      expect(find.bySemanticsLabel('Auto On'), findsOneWidget);
      await tester.tap(find.byTooltip('Camera settings'));
      await harness.settle(tester);
      expect(find.text('Camera settings'), findsOneWidget);

      await tester.tap(find.text('Auto capture'));
      await tester.tap(find.text('Alignment grid'));
      await harness.settle(tester);
      await tester.tap(find.byTooltip('Close'));
      await harness.settle(tester);

      expect(find.bySemanticsLabel('Auto Off'), findsOneWidget);
    });

    testWidgets('blocked camera access explains itself and links to Settings', (tester) async {
      await open(tester, deny: true);
      expect(find.text('Camera access needed'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.bySemanticsLabel('Take photo'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Take photo'));
      await harness.settle(tester);
      expect(camera.shots, 0);
    });
  });
}
