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
import 'package:lumascan/features/pages/scan_controller.dart';
import 'package:lumascan/imaging/page_renderer.dart';
import 'package:lumascan/imaging/render_service.dart';

import 'memory_stores.dart';

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

/// A draft of three plain pages behind in-memory stores, for tests that open
/// one screen of the scanning flow on its own (accessibility and golden tests).
class ScreenHarness {
  late Directory tmp;
  late ProviderContainer container;

  /// Creates the draft. Call inside `tester.runAsync`, and `dispose` in a tearDown.
  Future<void> setUp({int pageCount = 3}) async {
    tmp = Directory.systemTemp.createTempSync('lumascan_screens');
    final paper = img.Image(width: 300, height: 400)..clear(img.ColorRgb8(236, 232, 222));
    final paths = [
      for (var i = 0; i < pageCount; i++) (File('${tmp.path}/scan$i.jpg')..writeAsBytesSync(img.encodeJpg(paper))).path,
    ];
    final store = PageStore(rootDir: () async => tmp);
    container = ProviderContainer(
      overrides: [
        scannerServiceProvider.overrideWithValue(_FakeScanner(paths)),
        pageStoreProvider.overrideWithValue(store),
        renderServiceProvider.overrideWithValue(_NoRender(store)),
        libraryStoreProvider.overrideWithValue(MemoryLibraryStore()),
      ],
    );
    await container.read(scanControllerProvider.notifier).scan(ScanSource.camera);
  }

  void dispose() {
    container.dispose();
    tmp.deleteSync(recursive: true);
  }

  List<ScanPage> get pages => container.read(scanControllerProvider).pages;

  /// Phone-sized screen, text scale and brightness, then [home] on top of the
  /// harness providers.
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildLumaTheme(brightness), home: home),
      ),
    );
    await settle(tester);
  }

  /// Pushes [builder] over a plain route, so Back works as in the app.
  Future<void> pumpRoute(
    WidgetTester tester,
    WidgetBuilder builder, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: builder)),
            child: const Text('open'),
          ),
        ),
      ),
      brightness: brightness,
      textScale: textScale,
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  /// Lets page images load and draw. A fixed number of frames, because these
  /// screens keep animating.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}
