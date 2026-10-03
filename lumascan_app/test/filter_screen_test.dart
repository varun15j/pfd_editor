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
import 'package:lumascan/features/filters/filter_screen.dart';
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

/// Shows the original file so widget tests settle without the render isolate.
class _NoRender extends RenderService {
  _NoRender(super.store);

  @override
  Future<RenderedImage> render(ScanPage page, {EditRecipe? recipe, int maxDimension = RenderService.previewSize}) =>
      Future.value(RenderedImage(page.originalPath, 300, 400));
}

void main() {
  late Directory tmp;
  late ProviderContainer container;
  var ready = false;

  Future<void> setUpContainer(int pageCount) async {
    tmp = Directory.systemTemp.createTempSync('lumascan_enhance');
    final paths = [
      for (var i = 0; i < pageCount; i++)
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
    await container.read(scanControllerProvider.notifier).scan(ScanSource.camera);
    ready = true;
  }

  tearDown(() {
    if (!ready) return;
    ready = false;
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  List<ScanPage> pages() => container.read(scanControllerProvider).pages;

  /// Opens the enhance screen for the page at [index], on top of a home route.
  Future<void> pumpEnhance(WidgetTester tester, {int pageCount = 3, int index = 0, double textScale = 1}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(() => setUpContainer(pageCount));
    final pageId = pages()[index].id;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildLumaTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => FilterScreen(pageId: pageId))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pump();
  }

  testWidgets('the carousel offers the five presets in order', (tester) async {
    await pumpEnhance(tester);
    final labels = ['Original', 'Auto colour', 'Grayscale', 'B&W', 'Whiteboard'];
    for (final label in labels) {
      await tester.ensureVisible(find.text(label));
      expect(find.text(label), findsOneWidget, reason: label);
    }
    final lefts = [for (final l in labels) tester.getTopLeft(find.text(l)).dx];
    expect(lefts, orderedEquals([...lefts]..sort()));
  });

  testWidgets('the selected preset has a border and a check, and only one does', (tester) async {
    await pumpEnhance(tester);
    // Original starts selected.
    expect(find.byIcon(Icons.check), findsOneWidget);

    await choose(tester, 'Grayscale');
    expect(find.byIcon(Icons.check), findsOneWidget);
    final selected = find.ancestor(of: find.byIcon(Icons.check), matching: find.byType(Stack)).first;
    final box = find.descendant(of: selected, matching: find.byType(Container));
    final borders = tester
        .widgetList<Container>(box)
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.border != null && d.border!.top.color != Colors.transparent);
    expect(borders, hasLength(1));
    // The check sits in Grayscale's tile, not Original's.
    expect(tester.getCenter(find.byIcon(Icons.check)).dx, greaterThan(tester.getCenter(find.text('Original')).dx));
  });

  testWidgets('press and hold shows the original and letting go restores the edit', (tester) async {
    await pumpEnhance(tester);
    await choose(tester, 'B&W');
    expect(find.text('Press and hold the page to see the original'), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(Image).first));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Showing original'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(find.text('Showing original'), findsNothing);
    expect(find.text('Press and hold the page to see the original'), findsOneWidget);
  });

  testWidgets('brightness and contrast sliders apply, and Reset clears them', (tester) async {
    await pumpEnhance(tester, pageCount: 1);
    final reset = find.widgetWithText(TextButton, 'Reset adjustments');
    expect(tester.widget<TextButton>(reset).onPressed, isNull);

    await tester.ensureVisible(find.byType(Slider).first);
    await tester.drag(find.byType(Slider).first, const Offset(60, 0));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Slider).last);
    await tester.drag(find.byType(Slider).last, const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(reset).onPressed, isNotNull);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final recipe = pages().single.recipe;
    expect(recipe.brightness, greaterThan(0));
    expect(recipe.contrast, lessThan(0));
  });

  testWidgets('Reset adjustments puts both sliders back to zero', (tester) async {
    await pumpEnhance(tester, pageCount: 1);
    await tester.ensureVisible(find.byType(Slider).first);
    await tester.drag(find.byType(Slider).first, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(find.text('0%'), findsOneWidget);

    await tester.ensureVisible(find.text('Reset adjustments'));
    await tester.tap(find.text('Reset adjustments'));
    await tester.pumpAndSettle();
    expect(find.text('0%'), findsNWidgets(2));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(pages().single.recipe.hasAdjustments, isFalse);
  });

  testWidgets('a one-page document applies straight away, with no scope question', (tester) async {
    await pumpEnhance(tester, pageCount: 1);
    await choose(tester, 'Whiteboard');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Apply to'), findsNothing);
    expect(pages().single.recipe.filter, DocumentFilter.whiteboard);
  });

  testWidgets('scope: this page changes only the current page', (tester) async {
    await pumpEnhance(tester, index: 1);
    await choose(tester, 'Grayscale');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Apply to'), findsOneWidget);
    expect(find.text('This page'), findsOneWidget);
    expect(find.text('Selected pages'), findsOneWidget);
    expect(find.text('All 3 pages'), findsOneWidget);
    await tester.tap(find.text('Apply to this page'));
    await tester.pumpAndSettle();

    expect(
      [for (final p in pages()) p.recipe.filter],
      [DocumentFilter.original, DocumentFilter.grayscale, DocumentFilter.original],
    );
    expect(find.text('Changes applied to this page'), findsOneWidget);
  });

  testWidgets('scope: all pages copies the filter and keeps each rotation', (tester) async {
    await pumpEnhance(tester);
    container.read(scanControllerProvider.notifier).rotate(pages()[2].id);
    await choose(tester, 'B&W');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All 3 pages'));
    await tester.pump();
    await tester.tap(find.text('Apply to all pages'));
    await tester.pumpAndSettle();

    expect(pages().every((p) => p.recipe.filter == DocumentFilter.blackWhite), isTrue);
    expect(pages()[2].recipe.quarterTurns, 1);
    expect(find.text('Changes applied to 3 pages'), findsOneWidget);
  });

  testWidgets('scope: selected pages changes only the ones ticked', (tester) async {
    await pumpEnhance(tester);
    await choose(tester, 'Whiteboard');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selected pages'));
    await tester.pump();

    // The current page starts ticked.
    expect(find.text('Apply to 1 page'), findsOneWidget);
    await tester.tap(find.text('Page 3'));
    await tester.pump();
    expect(find.text('Apply to 2 pages'), findsOneWidget);
    await tester.tap(find.text('Apply to 2 pages'));
    await tester.pumpAndSettle();

    expect(
      [for (final p in pages()) p.recipe.filter],
      [DocumentFilter.whiteboard, DocumentFilter.original, DocumentFilter.whiteboard],
    );
  });

  testWidgets('selected pages cannot be applied with nothing ticked', (tester) async {
    await pumpEnhance(tester);
    await choose(tester, 'Whiteboard');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selected pages'));
    await tester.pump();
    await tester.tap(find.text('Page 1'));
    await tester.pump();
    final apply = find.widgetWithText(FilledButton, 'Apply to 0 pages');
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
  });

  testWidgets('cancelling the scope question applies nothing and stays on the screen', (tester) async {
    await pumpEnhance(tester);
    await choose(tester, 'Grayscale');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    expect(find.byType(FilterScreen), findsOneWidget);
    expect(pages().every((p) => p.recipe.filter == DocumentFilter.original), isTrue);
  });

  testWidgets('Undo on the confirmation reverts every page that changed', (tester) async {
    await pumpEnhance(tester);
    await choose(tester, 'Grayscale');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All 3 pages'));
    await tester.pump();
    await tester.tap(find.text('Apply to all pages'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(pages().every((p) => p.recipe.filter == DocumentFilter.original), isTrue);
  });

  testWidgets('fits at 200% text size', (tester) async {
    await pumpEnhance(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Apply'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Apply to'), findsOneWidget);
  });
}
