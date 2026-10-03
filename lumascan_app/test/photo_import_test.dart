import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/photo_import.dart';
import 'package:lumascan/domain/ui_prefs.dart';
import 'package:lumascan/features/capture/scan_tips.dart';
import 'package:lumascan/features/pages/scan_controller.dart';

import 'support/fake_photos.dart';
import 'support/memory_stores.dart';
import 'support/pump_app.dart';

/// The draft screen keeps animating while page images load, so wait a fixed
/// time instead of for it to settle.
Future<void> pumpFor(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

PickedPhoto photo(String name) => PickedPhoto(path: '/nowhere/$name', name: name);

void main() {
  group('importPhotos', () {
    late Directory tmp;
    late ProviderContainer container;

    /// A white page on a dark table, so the detector has something to find.
    String pagePhoto(String name) {
      final image = img.Image(width: 300, height: 400)..clear(img.ColorRgb8(40, 38, 36));
      img.fillRect(image, x1: 60, y1: 70, x2: 240, y2: 330, color: img.ColorRgb8(245, 243, 238));
      return (File('${tmp.path}/$name')..writeAsBytesSync(img.encodeJpg(image))).path;
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lumascan_import');
      container = ProviderContainer(
        overrides: [
          pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
          draftStoreProvider.overrideWithValue(MemoryDraftStore()),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      tmp.deleteSync(recursive: true);
    });

    ScanController controller() => container.read(scanControllerProvider.notifier);
    List<ScanPage> pages() => container.read(scanControllerProvider).pages;

    test('auto-crop starts each page at the detected page edges', () async {
      final result = await controller().importPhotos([
        PickedPhoto(path: pagePhoto('a.jpg'), name: 'a.jpg'),
      ], autoCrop: true);
      expect(result.added, 1);
      final crop = pages().single.recipe.crop;
      expect(crop.isFull, isFalse);
      expect(crop.tl.x, closeTo(0.2, 0.05));
      expect(crop.br.y, closeTo(0.825, 0.05));
    });

    test('without auto-crop the whole photo is kept', () async {
      await controller().importPhotos([PickedPhoto(path: pagePhoto('a.jpg'), name: 'a.jpg')], autoCrop: false);
      expect(pages().single.recipe.crop.isFull, isTrue);
    });

    test('unreadable photos are named and the good ones still added, in order', () async {
      final broken = (File('${tmp.path}/broken.jpg')..writeAsStringSync('not an image')).path;
      final result = await controller().importPhotos([
        PickedPhoto(path: pagePhoto('one.jpg'), name: 'one.jpg'),
        PickedPhoto(path: broken, name: 'broken.jpg'),
        PickedPhoto(path: pagePhoto('two.jpg'), name: 'two.jpg'),
      ], autoCrop: true);
      expect(result.added, 2);
      expect(result.unreadable, ['broken.jpg']);
      expect(pages(), hasLength(2));
      expect(File(pages()[0].originalPath).existsSync(), isTrue);
      expect(container.read(scanControllerProvider).busy, isFalse);
    });
  });

  group('import screen', () {
    late FakePhotoPicker picker;

    Future<void> openImport(WidgetTester tester, {Set<String> unreadable = const {}}) async {
      await pumpApp(
        tester,
        prefs: MemoryUiPrefsStore(const UiPrefs(dismissedCards: {scanTipsId})),
        overrides: [
          photoPickerProvider.overrideWithValue(picker),
          photoAnalyzerProvider.overrideWithValue(FakePhotoAnalyzer(unreadable: unreadable)),
          pageStoreProvider.overrideWithValue(NoCopyPageStore()),
        ],
      );
      await tester.tap(find.bySemanticsLabel('Import'));
      await tester.pumpAndSettle();
    }

    List<String> draftNames(WidgetTester tester) {
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      return [for (final p in container.read(scanControllerProvider).pages) p.originalPath.split('/').last];
    }

    setUp(() => picker = FakePhotoPicker([photo('a.jpg'), photo('b.jpg'), photo('c.jpg')]));

    testWidgets('photos are numbered in pick order and added in that order', (tester) async {
      await openImport(tester);
      expect(find.text('3 of 3 selected'), findsOneWidget);
      expect(find.bySemanticsLabel('a.jpg, page 1'), findsOneWidget);
      expect(find.bySemanticsLabel('c.jpg, page 3'), findsOneWidget);
      await tester.tap(find.text('Add 3 pages'));
      await pumpFor(tester);
      expect(draftNames(tester), ['a.jpg', 'b.jpg', 'c.jpg']);
      expect(find.text('Added 3 pages'), findsOneWidget);
    });

    testWidgets('tapping a photo out and back in moves it to the end', (tester) async {
      await openImport(tester);
      await tester.tap(find.bySemanticsLabel('a.jpg, page 1'));
      await tester.pump();
      expect(find.bySemanticsLabel('a.jpg, not added'), findsOneWidget);
      expect(find.bySemanticsLabel('b.jpg, page 1'), findsOneWidget);
      expect(find.text('Add 2 pages'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('a.jpg, not added'));
      await tester.pump();
      expect(find.bySemanticsLabel('a.jpg, page 3'), findsOneWidget);
      await tester.tap(find.text('Add 3 pages'));
      await pumpFor(tester);
      expect(draftNames(tester), ['b.jpg', 'c.jpg', 'a.jpg']);
    });

    testWidgets('auto-crop toggle decides whether pages start cropped', (tester) async {
      await openImport(tester);
      await tester.tap(find.text('Auto-crop pages'));
      await tester.pump();
      await tester.tap(find.text('Add 3 pages'));
      await pumpFor(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      expect(container.read(scanControllerProvider).pages.every((p) => p.recipe.crop.isFull), isTrue);
    });

    testWidgets('with nothing selected the add button is off', (tester) async {
      picker.photos = [photo('a.jpg')];
      await openImport(tester);
      await tester.tap(find.bySemanticsLabel('a.jpg, page 1'));
      await tester.pump();
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Select photos to add'));
      expect(button.onPressed, isNull);
    });

    testWidgets('unreadable photos are reported and the rest are kept', (tester) async {
      await openImport(tester, unreadable: {'b.jpg'});
      await tester.tap(find.text('Add 3 pages'));
      await pumpFor(tester);
      expect(draftNames(tester), ['a.jpg', 'c.jpg']);
      expect(find.text("Added 2 pages. This photo couldn't be read: b.jpg"), findsOneWidget);
    });

    testWidgets('Add pages on a draft offers camera or photos and appends', (tester) async {
      await openImport(tester);
      await tester.tap(find.text('Add 3 pages'));
      await pumpFor(tester);
      picker.photos = [photo('d.jpg')];
      await tester.tap(find.text('Add pages'));
      await pumpFor(tester);
      expect(find.text('Scan with camera'), findsOneWidget);
      await tester.tap(find.text('Import photos'));
      await pumpFor(tester);
      await tester.tap(find.text('Add 1 page'));
      await pumpFor(tester);
      expect(draftNames(tester), ['a.jpg', 'b.jpg', 'c.jpg', 'd.jpg']);
    });

    testWidgets('import screen fits at 200% text', (tester) async {
      await pumpApp(tester, textScale: 2, overrides: [photoPickerProvider.overrideWithValue(picker)]);
      await tester.tap(find.bySemanticsLabel('Import'));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
