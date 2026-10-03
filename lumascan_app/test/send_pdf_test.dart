import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/models.dart';
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

  Future<void> setUpContainer({int pages = 3, int copySide = 120, bool tinyOriginal = false}) async {
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
        pdfRasterizerProvider.overrideWithValue(_FakeRasterizer(copySide)),
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
