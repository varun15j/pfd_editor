import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/app/theme.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/scanner_service.dart';
import 'package:lumascan/features/pages/page_gallery.dart';
import 'package:lumascan/features/pages/page_single_view.dart';
import 'package:lumascan/features/pages/pages_screen.dart';
import 'package:lumascan/features/pages/scan_controller.dart';
import 'package:lumascan/imaging/page_renderer.dart';
import 'package:lumascan/imaging/render_service.dart';

class _FakeScanner implements ScannerService {
  _FakeScanner(this.paths);
  final List<String> paths;

  @override
  Future<List<String>> scan({required ScanSource source, int maxPages = 100}) async => paths;

  @override
  Future<void> cleanUp() async {}
}

/// Skips the render isolate and shows the original file, so widget tests settle.
class _NoRender extends RenderService {
  _NoRender(super.store);

  @override
  Future<RenderedImage> render(ScanPage page, {EditRecipe? recipe, int maxDimension = RenderService.previewSize}) =>
      Future.value(RenderedImage(page.originalPath, 30, 40));
}

void main() {
  late Directory tmp;
  late ProviderContainer container;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lumascan_gallery');
    final paths = [
      for (var i = 0; i < 3; i++)
        (File('${tmp.path}/scan$i.jpg')..writeAsBytesSync(img.encodeJpg(img.Image(width: 30, height: 40)))).path,
    ];
    final store = PageStore(rootDir: () async => tmp);
    container = ProviderContainer(
      overrides: [
        scannerServiceProvider.overrideWithValue(_FakeScanner(paths)),
        pageStoreProvider.overrideWithValue(store),
        renderServiceProvider.overrideWithValue(_NoRender(store)),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  List<String> ids() => container.read(scanControllerProvider).pages.map((p) => p.id).toList();

  Future<void> pumpPages(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => container.read(scanControllerProvider.notifier).scan(ScanSource.camera));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildLumaTheme(Brightness.light), home: const PagesScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectLayout(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Change view'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<PagesLayout>, label));
    await tester.pumpAndSettle();
  }

  testWidgets('app bar menu switches between list and gallery', (tester) async {
    await pumpPages(tester);
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.byType(PageGallery), findsNothing);

    await selectLayout(tester, 'Gallery view');
    expect(find.byType(PageGallery), findsOneWidget);
    expect(find.byType(ReorderableListView), findsNothing);
    for (final label in ['Page 1', 'Page 2', 'Page 3']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Phones fit three thumbnails per row.
    expect(tester.getTopLeft(find.text('Page 3')).dy, tester.getTopLeft(find.text('Page 1')).dy);

    await selectLayout(tester, 'List view');
    expect(find.byType(ReorderableListView), findsOneWidget);
  });

  testWidgets('tapping a gallery page opens its actions', (tester) async {
    await pumpPages(tester);
    await selectLayout(tester, 'Gallery view');

    await tester.tap(find.text('Page 2'));
    await tester.pumpAndSettle();
    for (final action in ['Filters', 'Crop', 'Rotate', 'Delete page']) {
      expect(find.text(action), findsOneWidget, reason: action);
    }
    await tester.tap(find.text('Rotate'));
    await tester.pumpAndSettle();
    expect(container.read(scanControllerProvider).pages[1].recipe.quarterTurns, 1);

    final before = ids();
    await tester.tap(find.text('Page 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete page'));
    await tester.pumpAndSettle();
    expect(ids(), before.take(2));
    expect(find.text('Page 3 deleted'), findsOneWidget);
  });

  testWidgets('long-press and drag moves a page in the gallery', (tester) async {
    await pumpPages(tester);
    await selectLayout(tester, 'Gallery view');
    final before = ids();

    final gesture = await tester.startGesture(tester.getCenter(find.text('Page 1')));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(find.text('Page 3')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(ids(), [before[1], before[2], before[0]]);
  });

  testWidgets('page view shows one page with arrows, counter and numbered strip', (tester) async {
    await pumpPages(tester);
    await selectLayout(tester, 'Page view');
    expect(find.byType(PageSingleView), findsOneWidget);
    expect(find.text('Page 1 of 3'), findsOneWidget);
    for (final n in ['1', '2', '3']) {
      expect(find.text(n), findsOneWidget, reason: 'strip badge $n');
    }
    final prev = find.widgetWithIcon(IconButton, Icons.chevron_left);
    expect(tester.widget<IconButton>(prev).onPressed, isNull);

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(find.text('Page 3 of 3'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed, isNull);

    await tester.tap(find.text('Rotate'));
    await tester.pumpAndSettle();
    expect(container.read(scanControllerProvider).pages[2].recipe.quarterTurns, 1);

    // Deleting the last page falls back to the new last page.
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(ids(), hasLength(2));
    expect(find.text('Page 2 of 2'), findsOneWidget);
  });

  testWidgets('every view fits at 200% text size', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpPages(tester);
    for (final view in ['Gallery view', 'Page view', 'List view']) {
      await selectLayout(tester, view);
      expect(tester.takeException(), isNull, reason: view);
    }
  });
}
