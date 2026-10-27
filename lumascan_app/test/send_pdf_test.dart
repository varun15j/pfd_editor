import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/export/pdf_exporter.dart';
import 'package:lumascan/export/pdf_shrinker.dart';
import 'package:lumascan/features/library/library_actions.dart';
import 'package:lumascan/features/share/pdf_sharer.dart';
import 'package:lumascan/features/share/send_pdf_sheet.dart';
import 'package:lumascan/pdf_edit/pdf_edit_controller.dart';
import 'package:lumascan/pdf_edit/pdf_saver.dart';
import 'package:lumascan/ui/file_size.dart';

class _FakeSharer implements PdfSharer {
  final sent = <String>[];
  SendOutcome outcome = SendOutcome.sent;
  Object? failure;

  @override
  Future<SendOutcome> send(String path, {Rect? origin}) async {
    if (failure != null) throw failure!;
    sent.add(path);
    return outcome;
  }
}

/// Renders every page as a flat image of the given size, so the smaller copy
/// is as big or as small as a test needs.
class _FakeRasterizer implements PdfRasterizer {
  _FakeRasterizer(this.side);
  final int side;
  final requests = <List<int>>[];

  @override
  Stream<RasterPage> renderPages(
    String path,
    List<int> pageNumbers, {
    required int longEdge,
    required int jpegQuality,
    String? password,
  }) async* {
    requests.add(pageNumbers);
    for (final _ in pageNumbers) {
      yield RasterPage(
        Uint8List.fromList(img.encodeJpg(img.Image(width: side, height: side)..clear(img.ColorRgb8(200, 200, 200)))),
        side,
        side,
        widthPt: 612,
        heightPt: 792,
      );
    }
  }
}

/// Renders noisy pages whose size follows the requested resolution and
/// quality, like a real photo, at a quarter of the requested long edge so the
/// tests stay quick. With [fixedSide] every page is the same noisy image,
/// whatever is asked, so no step can make it smaller.
class _ScalingRasterizer implements PdfRasterizer {
  _ScalingRasterizer({this.fixedSide});
  final int? fixedSide;
  final requests = <(int, int)>[];

  @override
  Stream<RasterPage> renderPages(
    String path,
    List<int> pageNumbers, {
    required int longEdge,
    required int jpegQuality,
    String? password,
  }) async* {
    requests.add((longEdge, jpegQuality));
    final side = fixedSide ?? longEdge ~/ 4;
    final random = math.Random(side);
    final image = img.Image(width: side, height: side);
    for (final px in image) {
      final v = random.nextInt(256);
      px
        ..r = v
        ..g = v
        ..b = v;
    }
    final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: fixedSide == null ? jpegQuality : 95));
    for (final _ in pageNumbers) {
      yield RasterPage(jpeg, side, side, widthPt: 595, heightPt: 842);
    }
  }
}

/// A PDF whose pages are noisy photos, so it is large.
Future<Uint8List> _bigPdf(int pages) {
  final random = math.Random(1);
  final image = img.Image(width: 900, height: 1200);
  for (final px in image) {
    px
      ..r = random.nextInt(256)
      ..g = random.nextInt(256)
      ..b = random.nextInt(256);
  }
  final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 95));
  return buildPdfFromJpegs([for (var i = 0; i < pages; i++) (jpeg, 900, 1200)], PdfPageSize.a4);
}

void main() {
  late Directory tmp;
  late File original;
  late _FakeSharer sharer;
  late ProviderContainer container;
  var ready = false;

  Future<void> setUpContainer({
    int pages = 3,
    int copySide = 120,
    bool tinyOriginal = false,
    PdfRasterizer? rasterizer,
    AppPlan plan = AppPlan.basic,
  }) async {
    tmp = Directory.systemTemp.createTempSync('lumascan_send');
    original = File('${tmp.path}/Lease.pdf')
      ..writeAsBytesSync(
        tinyOriginal
            ? await buildPdfFromJpegs([
                (Uint8List.fromList(img.encodeJpg(img.Image(width: 60, height: 80))), 60, 80),
              ], PdfPageSize.a4)
            : await _bigPdf(pages),
      );
    sharer = _FakeSharer();
    ready = true;
    container = ProviderContainer(
      overrides: [
        pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
        pdfRasterizerProvider.overrideWithValue(rasterizer ?? _FakeRasterizer(copySide)),
        planProvider.overrideWithValue(plan),
        pdfSharerProvider.overrideWithValue(sharer),
      ],
    );
  }

  tearDown(() {
    if (!ready) return;
    ready = false;
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pumpSheet(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSendPdfSheet(context, pdfPath: original.path, name: 'Lease', pageCount: 3),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  // The copy is built on an isolate and written to disk, which the fake clock
  // does not wait for.
  Future<void> tapSmaller(WidgetTester tester) async {
    await tester.tap(find.text('Send smaller copy'));
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      if (find.text('Making a smaller copy…').evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  group('Send PDF', () {
    testWidgets('shows the file name and size for the PDF and for the smaller copy', (tester) async {
      await tester.runAsync(setUpContainer);
      await pumpSheet(tester);
      expect(find.text('Send PDF'), findsNWidgets(2)); // title and option
      expect(find.text('Lease.pdf · ${formatFileSize(original.lengthSync())}'), findsOneWidget);
      expect(find.textContaining('Lease (small).pdf · about '), findsOneWidget);
    });

    testWidgets('Send PDF hands the saved file to the share sheet and reports it', (tester) async {
      await tester.runAsync(setUpContainer);
      final before = original.readAsBytesSync();
      await pumpSheet(tester);
      await tester.tap(find.text('Lease.pdf · ${formatFileSize(original.lengthSync())}'));
      await tester.pumpAndSettle();
      expect(sharer.sent, [original.path]);
      expect(find.text('PDF shared'), findsOneWidget);
      expect(find.text('Send smaller copy'), findsNothing, reason: 'the sheet closes after sending');
      expect(original.readAsBytesSync(), before);
    });

    testWidgets('Send smaller copy makes a separate, smaller file and shares that one', (tester) async {
      await tester.runAsync(setUpContainer);
      final before = original.readAsBytesSync();
      await pumpSheet(tester);
      await tapSmaller(tester);

      final copy = sharer.sent.single;
      expect(copy, isNot(original.path));
      expect(copy, endsWith('share/Lease (small).pdf'));
      expect(File(copy).lengthSync(), lessThan(original.lengthSync()));
      expect(File(copy).readAsBytesSync().sublist(0, 4), [0x25, 0x50, 0x44, 0x46], reason: 'a PDF');
      expect(find.text('Smaller copy shared'), findsOneWidget);
      expect(original.readAsBytesSync(), before, reason: 'the saved PDF is untouched');
    });

    testWidgets('the copy keeps every page and the real page size', (tester) async {
      await tester.runAsync(setUpContainer);
      final rasterizer = container.read(pdfRasterizerProvider) as _FakeRasterizer;
      await pumpSheet(tester);
      await tapSmaller(tester);
      expect(rasterizer.requests.single, [1, 2, 3]);
      final text = String.fromCharCodes(File(sharer.sent.single).readAsBytesSync());
      expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 3);
      expect(text, contains('/MediaBox[0 0 612 792]'));
    });

    testWidgets('a copy that is not smaller is not sent, and says so', (tester) async {
      await tester.runAsync(() => setUpContainer(copySide: 1600, tinyOriginal: true));
      await pumpSheet(tester);
      await tapSmaller(tester);
      expect(sharer.sent, isEmpty);
      expect(find.textContaining('would not be smaller'), findsOneWidget);
      expect(find.text('Send smaller copy'), findsOneWidget, reason: 'the sheet stays open');
      expect(Directory('${tmp.path}/share').listSync().whereType<File>(), isEmpty);
    });

    testWidgets('closing the share sheet without choosing keeps the sheet open and says nothing', (tester) async {
      await tester.runAsync(setUpContainer);
      sharer.outcome = SendOutcome.dismissed;
      await pumpSheet(tester);
      await tester.tap(find.text('Lease.pdf · ${formatFileSize(original.lengthSync())}'));
      await tester.pumpAndSettle();
      expect(find.text('Send smaller copy'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a share sheet that cannot open is reported and the file is untouched', (tester) async {
      await tester.runAsync(setUpContainer);
      final before = original.readAsBytesSync();
      sharer.failure = StateError('no share target');
      await pumpSheet(tester);
      await tester.tap(find.text('Lease.pdf · ${formatFileSize(original.lengthSync())}'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not open the share sheet'), findsOneWidget);
      expect(find.textContaining('no share target'), findsOneWidget);
      expect(original.readAsBytesSync(), before);
    });

    testWidgets('a PDF that is gone is reported, not shared', (tester) async {
      await tester.runAsync(setUpContainer);
      await pumpSheet(tester);
      original.deleteSync();
      await tester.tap(find.textContaining('Lease.pdf ·'));
      await tester.pumpAndSettle();
      expect(find.text('This PDF is no longer on this device.'), findsOneWidget);
      expect(sharer.sent, isEmpty);
    });

    testWidgets('fits at 200% text size', (tester) async {
      await tester.runAsync(setUpContainer);
      await pumpSheet(tester, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('Fit under a size', () {
    // Like tapSmaller: the copies are built on an isolate.
    Future<void> tapTarget(WidgetTester tester, TargetSize target) async {
      await tester.tap(find.byKey(ValueKey('fit-${target.name}')));
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        if (find.textContaining('Fitting under').evaluate().isEmpty) break;
      }
      await tester.pumpAndSettle();
    }

    testWidgets('on Basic it is shown with a Pro badge and opens the upgrade pop-up', (tester) async {
      await tester.runAsync(setUpContainer);
      await pumpSheet(tester);
      expect(find.text('Fit under a size'), findsOneWidget);
      // Send with password has its own Pro badge on Basic.
      expect(
        find.descendant(of: find.widgetWithText(ListTile, 'Fit under a size'), matching: find.text('Pro')),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(ActionChip, '200 KB'));
      await tester.pumpAndSettle();
      expect(find.text('Upgrade to Pro'), findsWidgets);
      expect(sharer.sent, isEmpty);
    });

    testWidgets('on Pro it shares a separate copy no larger than the limit', (tester) async {
      final rasterizer = _ScalingRasterizer();
      await tester.runAsync(() => setUpContainer(rasterizer: rasterizer, plan: AppPlan.pro));
      final before = original.readAsBytesSync();
      await pumpSheet(tester);
      expect(find.text('Pro'), findsNothing);
      await tapTarget(tester, TargetSize.kb200);

      final copy = File(sharer.sent.single);
      expect(copy.path, endsWith('share/Lease (under 200 KB).pdf'));
      expect(copy.lengthSync(), lessThanOrEqualTo(200 * 1000));
      expect(rasterizer.requests.length, lessThanOrEqualTo(PdfShrinker.maxAttempts));
      final text = String.fromCharCodes(copy.readAsBytesSync());
      expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 3);
      expect(find.textContaining('Copy under 200 KB shared'), findsOneWidget);
      expect(original.readAsBytesSync(), before, reason: 'the saved PDF is untouched');
    });

    testWidgets('a PDF already under the limit is shared as it is', (tester) async {
      final rasterizer = _ScalingRasterizer();
      await tester.runAsync(() => setUpContainer(tinyOriginal: true, rasterizer: rasterizer, plan: AppPlan.gold));
      await pumpSheet(tester);
      await tapTarget(tester, TargetSize.kb200);
      expect(sharer.sent, [original.path]);
      expect(rasterizer.requests, isEmpty);
      expect(find.text('Already under 200 KB, PDF shared as it is'), findsOneWidget);
    });

    testWidgets('when it cannot fit, it says how small it got and a second tap sends it', (tester) async {
      await tester.runAsync(() => setUpContainer(rasterizer: _ScalingRasterizer(fixedSide: 700), plan: AppPlan.pro));
      await pumpSheet(tester);
      await tapTarget(tester, TargetSize.kb200);
      expect(sharer.sent, isEmpty);
      expect(find.textContaining('still over 200 KB'), findsOneWidget);
      expect(find.textContaining('200 KB · '), findsOneWidget, reason: 'the chip shows the size reached');
      await tapTarget(tester, TargetSize.kb200);
      expect(sharer.sent.single, endsWith('share/Lease (under 200 KB).pdf'));
    });

    testWidgets('fits at 200% text size', (tester) async {
      await tester.runAsync(() => setUpContainer(plan: AppPlan.pro));
      await pumpSheet(tester, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('target-size search', () {
    // Sizes that follow the ladder's own model, scaled by [scale].
    Future<int> Function(int) model(double scale, List<int> tried) => (i) async {
      tried.add(i);
      return (CompressionStep.ladder[i].estimateBytes(1) * scale).round();
    };

    test('keeps the best step that fits, within the attempt limit', () async {
      for (final scale in [0.05, 0.3, 1.0, 3.0, 10.0]) {
        for (final target in TargetSize.values) {
          final tried = <int>[];
          final r = await PdfShrinker.findStep(target: target, pageCount: 1, measure: model(scale, tried));
          expect(tried.length, lessThanOrEqualTo(PdfShrinker.maxAttempts));
          final ladder = CompressionStep.ladder;
          final size = (ladder[r.index].estimateBytes(1) * scale).round();
          if (r.fits) {
            expect(size, lessThanOrEqualTo(target.bytes));
            if (r.index > 0) {
              final better = (ladder[r.index - 1].estimateBytes(1) * scale).round();
              // The step above is too big, or within the headroom kept.
              expect(better, greaterThan(target.bytes * 0.9), reason: 'scale $scale, $target');
            }
          } else {
            expect(r.index, ladder.length - 1);
            expect(size, greaterThan(target.bytes));
          }
        }
      }
    });

    test('a real page smaller than the estimate moves up the ladder', () async {
      final tried = <int>[];
      final r = await PdfShrinker.findStep(target: TargetSize.mb1, pageCount: 1, measure: model(0.02, tried));
      expect(r.fits, isTrue);
      expect(r.index, 0);
    });

    test('names the copy after the document and the size', () {
      expect(PdfShrinker.targetCopyName('Lease.pdf', TargetSize.kb200), 'Lease (under 200 KB).pdf');
      expect(PdfShrinker.targetCopyName('Lease', TargetSize.mb1), 'Lease (under 1 MB).pdf');
    });

    test('Pro and Gold include it, Basic does not', () {
      expect(AppPlan.basic.includes(PlanFeature.targetSize), isFalse);
      expect(AppPlan.pro.includes(PlanFeature.targetSize), isTrue);
      expect(AppPlan.gold.includes(PlanFeature.targetSize), isTrue);
    });
  });

  group('where it opens', () {
    testWidgets('sharing one library document opens the send sheet; several go straight to the system', (tester) async {
      await tester.runAsync(setUpContainer);
      SavedDocument doc(String id) => SavedDocument(
        id: id,
        name: 'Doc $id',
        pdfPath: original.path,
        pageCount: 3,
        type: ScanType.document,
        createdAt: DateTime(2026),
        modifiedAt: DateTime(2026),
      );
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(onPressed: () => shareDocuments(context, [doc('a')]), child: const Text('share one')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('share one'));
      await tester.pumpAndSettle();
      expect(find.text('Send smaller copy'), findsOneWidget);
      expect(find.text('Lease (small).pdf · ', findRichText: false), findsNothing);
      expect(find.textContaining('Doc a (small).pdf'), findsOneWidget);
    });
  });

  group('PdfShrinker', () {
    test('names the copy after the document', () {
      expect(PdfShrinker.copyName('Lease'), 'Lease (small).pdf');
      expect(PdfShrinker.copyName('Lease.pdf'), 'Lease (small).pdf');
      expect(PdfShrinker.copyName('a/b:c'), 'a_b_c (small).pdf');
    });

    test('estimates less than the medium export of the same pages', () {
      expect(PdfShrinker.estimateBytes(4), lessThan(PdfExporter.estimateBytes(4, ExportQuality.medium)));
    });
  });
}
