import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/app/theme.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/photo_import.dart';
import 'package:lumascan/domain/scanner_service.dart';
import 'package:lumascan/features/crop/crop_screen.dart';
import 'package:lumascan/features/pages/scan_controller.dart';
import 'package:lumascan/imaging/page_renderer.dart';
import 'package:lumascan/imaging/render_service.dart';

import 'support/fake_photos.dart';

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

class _NoPageAnalyzer implements PhotoAnalyzer {
  @override
  Future<CropQuad?> analyze(String path) async => null;
}

void main() {
  late Directory tmp;
  late ProviderContainer container;
  var ready = false;

  Future<void> setUpContainer(PhotoAnalyzer analyzer) async {
    tmp = Directory.systemTemp.createTempSync('lumascan_crop');
    final path = (File('${tmp.path}/scan.jpg')..writeAsBytesSync(img.encodeJpg(img.Image(width: 30, height: 40)))).path;
    final store = PageStore(rootDir: () async => tmp);
    container = ProviderContainer(
      overrides: [
        scannerServiceProvider.overrideWithValue(_FakeScanner([path])),
        pageStoreProvider.overrideWithValue(store),
        renderServiceProvider.overrideWithValue(_NoRender(store)),
        photoAnalyzerProvider.overrideWithValue(analyzer),
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

  CropQuad savedCrop() => container.read(scanControllerProvider).pages.single.recipe.crop;

  Future<void> pumpCrop(WidgetTester tester, {PhotoAnalyzer? analyzer, double textScale = 1}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(() => setUpContainer(analyzer ?? FakePhotoAnalyzer()));
    final pageId = container.read(scanControllerProvider).pages.single.id;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildLumaTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CropScreen(pageId: pageId))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Let the page image load, then draw it.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
  }

  Finder handle(String label) => find.bySemanticsLabel(label);

  Finder byType(String name) => find.byWidgetPredicate((w) => w.runtimeType.toString() == name);

  Future<void> apply(WidgetTester tester) async {
    await tester.tap(find.text('Apply crop'));
    await tester.pumpAndSettle();
  }

  testWidgets('dragging a corner moves it and shows a magnifier only while dragging', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpCrop(tester);
    expect(byType('_Loupe'), findsNothing);

    final gesture = await tester.startGesture(tester.getCenter(handle('Top left corner')));
    // The first move only gets past the drag slop; the later ones move the corner.
    await gesture.moveBy(const Offset(40, 40));
    await gesture.moveBy(const Offset(30, 30));
    await tester.pump();
    expect(byType('_Loupe'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(byType('_Loupe'), findsNothing);

    await apply(tester);
    final crop = savedCrop();
    expect(crop.tl.x, greaterThan(0.05));
    expect(crop.tl.y, greaterThan(0.05));
    expect(crop.tr, CropQuad.full.tr);
    semantics.dispose();
  });

  testWidgets('a side handle moves both of its corners together', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpCrop(tester);

    final gesture = await tester.startGesture(tester.getCenter(handle('Top side')));
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveBy(const Offset(0, 40));
    await gesture.up();
    await tester.pumpAndSettle();

    await apply(tester);
    final crop = savedCrop();
    expect(crop.tl.y, greaterThan(0.05));
    expect(crop.tl.y, closeTo(crop.tr.y, 1e-9));
    expect(crop.tl.x, 0);
    expect(crop.tr.x, 1);
    expect(crop.bl, CropQuad.full.bl);
    semantics.dispose();
  });

  testWidgets('a side only slides across the page, not along it', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpCrop(tester);

    final gesture = await tester.startGesture(tester.getCenter(handle('Left side')));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(0, 60));
    await gesture.up();
    await tester.pumpAndSettle();

    await apply(tester);
    final crop = savedCrop();
    expect(crop.tl.x, greaterThan(0.05));
    expect(crop.tl.y, 0);
    expect(crop.bl.y, 1);
    semantics.dispose();
  });

  testWidgets('handles keep their size when zoomed in', (tester) async {
    await pumpCrop(tester);
    Size cornerOnScreen() {
      final f = byType('_CornerHandle').first;
      return Size(
        tester.getBottomRight(f).dx - tester.getTopLeft(f).dx,
        tester.getBottomRight(f).dy - tester.getTopLeft(f).dy,
      );
    }

    final before = cornerOnScreen();
    final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    viewer.transformationController!.value = Matrix4.identity()..scaleByDouble(4, 4, 1, 1);
    await tester.pump();

    final after = cornerOnScreen();
    expect(after.width, closeTo(before.width, 0.5));
    expect(after.height, closeTo(before.height, 0.5));
    expect(before.width, closeTo(16, 0.5));
  });

  testWidgets('side handles stay clear of the system back gesture strips', (tester) async {
    final semantics = tester.ensureSemantics();
    // Gesture navigation: a 30 dp back gesture strip on each side.
    tester.view.systemGestureInsets = const FakeViewPadding(left: 78, right: 78);
    await pumpCrop(tester);

    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(tester.getRect(handle('Left side')).left, greaterThanOrEqualTo(30));
    expect(tester.getRect(handle('Right side')).right, lessThanOrEqualTo(width - 30));
    expect(tester.getRect(handle('Top left corner')).left, greaterThanOrEqualTo(30));
    semantics.dispose();
  });

  testWidgets('Reset to detected restores the detected page quad', (tester) async {
    await pumpCrop(tester);
    await tester.tap(find.text('Reset to detected'));
    await tester.pumpAndSettle();
    await apply(tester);
    expect(savedCrop(), FakePhotoAnalyzer.quad);
  });

  testWidgets('Reset to detected says so when no page edges are found', (tester) async {
    await pumpCrop(tester, analyzer: _NoPageAnalyzer());
    await tester.tap(find.text('Reset to detected'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining("Couldn't find the page edges"), findsOneWidget);
    await apply(tester);
    expect(savedCrop(), CropQuad.full);
  });

  testWidgets('Full page after a drag goes back to the whole image', (tester) async {
    await pumpCrop(tester);
    await tester.tap(find.text('Reset to detected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full page'));
    await tester.pumpAndSettle();
    await apply(tester);
    expect(savedCrop(), CropQuad.full);
  });

  testWidgets('fits at 200% text size', (tester) async {
    await pumpCrop(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Apply crop'), findsOneWidget);
    expect(find.text('Reset to detected'), findsOneWidget);
  });

  group('CropQuad.translateEdge', () {
    const quad = CropQuad(NormPoint(0.2, 0.2), NormPoint(0.8, 0.2), NormPoint(0.8, 0.8), NormPoint(0.2, 0.8));

    test('moves both corners of the side', () {
      final moved = quad.translateEdge(0, 0, 0.1);
      expect(moved.tl.y, closeTo(0.3, 1e-9));
      expect(moved.tr.y, closeTo(0.3, 1e-9));
      expect(moved.tl.x, 0.2);
      expect(moved.bl, quad.bl);
    });

    test('stops at the image border without squashing the side', () {
      final moved = quad.translateEdge(1, 0.5, 0);
      expect(moved.tr.x, closeTo(1, 1e-9));
      expect(moved.br.x, closeTo(1, 1e-9));
      expect(moved.tr.y, 0.2);
      expect(moved.br.y, 0.8);
    });

    test('the closing side joins the last corner to the first', () {
      final moved = quad.translateEdge(3, 0.1, 0);
      expect(moved.bl.x, closeTo(0.3, 1e-9));
      expect(moved.tl.x, closeTo(0.3, 1e-9));
      expect(moved.tr, quad.tr);
    });
  });
}
