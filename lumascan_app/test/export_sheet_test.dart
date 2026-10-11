import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/app/theme.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/domain/scanner_service.dart';
import 'package:lumascan/export/ocr_pdf_builder.dart';
import 'package:lumascan/export/pdf_exporter.dart';
import 'package:lumascan/export/text_pdf_service.dart';
import 'package:lumascan/features/export/export_sheet.dart';
import 'package:lumascan/features/pages/scan_controller.dart';

import 'support/memory_stores.dart';

class _FakeScanner implements ScannerService {
  _FakeScanner(this.paths);
  final List<String> paths;

  @override
  Future<List<String>> scan({required ScanSource source, int maxPages = 100}) async => paths;

  @override
  Future<void> cleanUp() async {}
}

/// Holds the export open until [finish] or [fail] so the saving state can be inspected.
class _FakeExporter implements PdfExporter {
  _FakeExporter(this.output);
  final File output;
  final calls = <ExportOptions>[];
  final Completer<File> _gate = Completer();

  void finish() => _gate.complete(output);

  /// Makes the next export fail straight away.
  bool failNext = false;

  @override
  Future<File> export(List<ScanPage> pages, ExportOptions options, {void Function(int done, int total)? onProgress}) {
    calls.add(options);
    if (failNext) return Future.error(StateError('disk full'));
    onProgress?.call(1, 2);
    return _gate.future;
  }
}

/// Makes a "text PDF" at once, noting what it was asked to read.
class _FakeTextPdf implements TextPdfService {
  _FakeTextPdf(this.output);
  final File output;
  final names = <String>[];

  @override
  Future<OcrPdfFile> fromPages(
    List<ScanPage> pages, {
    required String fileName,
    String languageCode = 'en',
    void Function(double fraction)? onProgress,
  }) async {
    names.add(fileName);
    onProgress?.call(0.5);
    return OcrPdfFile(output, 7);
  }

  @override
  Future<OcrPdfFile> fromPdf(
    String sourcePath, {
    required int pageCount,
    required String fileName,
    String languageCode = 'en',
    void Function(double fraction)? onProgress,
  }) => throw UnimplementedError();
}

void main() {
  var plan = AppPlan.basic;
  late _FakeTextPdf textPdf;
  late Directory tmp;
  late _FakeExporter exporter;
  late ProviderContainer container;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lumascan_export');
    final paths = [
      for (var i = 0; i < 4; i++)
        (File('${tmp.path}/scan$i.jpg')..writeAsBytesSync(img.encodeJpg(img.Image(width: 30, height: 40)))).path,
    ];
    plan = AppPlan.basic;
    textPdf = _FakeTextPdf(File('${tmp.path}/text.pdf')..writeAsBytesSync(List.filled(4096, 0)));
    exporter = _FakeExporter(File('${tmp.path}/out.pdf')..writeAsBytesSync(List.filled(2048, 0)));
    container = ProviderContainer(
      overrides: [
        scannerServiceProvider.overrideWithValue(_FakeScanner(paths)),
        pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
        pdfExporterProvider.overrideWithValue(exporter),
        textPdfServiceProvider.overrideWithValue(textPdf),
        planProvider.overrideWith((ref) => plan),
        libraryStoreProvider.overrideWithValue(MemoryLibraryStore()),
      ],
    );
    await container.read(scanControllerProvider.notifier).scan(ScanSource.camera);
  });

  tearDown(() {
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildLumaTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () => showExportSheet(context), child: const Text('open')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Taps Save and waits for the real file-system check that picks a free name.
  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('Save PDF'));
    await tester.pump();
    // Each file-system step resumes in fake time, so give every one a pump.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  String nameField(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).controller!.text;

  FilledButton saveButton(WidgetTester tester) => tester.widget<FilledButton>(find.byType(FilledButton));

  testWidgets('offers a default name like "Scan 2026-10-03 14.30"', (tester) async {
    await pumpSheet(tester);
    expect(nameField(tester), matches(RegExp(r'^Scan \d{4}-\d{2}-\d{2} \d{2}\.\d{2}$')));
    expect(find.text('.pdf'), findsOneWidget);
  });

  testWidgets('on Basic the Text PDF choice is shown with Pro, and tapping it offers the upgrade', (tester) async {
    await pumpSheet(tester);
    expect(find.text('Text PDF · Pro'), findsOneWidget);

    await tester.tap(find.text('Text PDF · Pro'));
    await tester.pumpAndSettle();

    expect(find.text('Upgrade to Pro'), findsWidgets);
    expect(find.textContaining('part of the Pro plan'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    // Still a plain PDF export.
    expect(find.text('Save PDF'), findsOneWidget);
    expect(textPdf.names, isEmpty);
  });

  for (final pro in [AppPlan.pro, AppPlan.gold]) {
    testWidgets('on ${pro.label} Text PDF reads the pages and saves a text PDF', (tester) async {
      plan = pro;
      await pumpSheet(tester);
      await tester.tap(find.text('Text PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Upgrade to Pro'), findsNothing);
      // The plain PDF options are not offered for a text PDF.
      expect(find.text('Small file'), findsNothing);

      await tester.enterText(find.byType(TextField), 'Lease');
      await tester.tap(find.text('Save text PDF'));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }

      expect(textPdf.names, ['Lease (text).pdf']);
      expect(exporter.calls, isEmpty);
      expect(find.text('Text PDF saved'), findsOneWidget);
      expect(find.textContaining('7 pages'), findsOneWidget);
    });
  }

  testWidgets('every quality shows an estimated size for this document', (tester) async {
    await pumpSheet(tester);
    for (final q in ExportQuality.values) {
      expect(find.text(q.label), findsOneWidget);
      expect(find.text('about ${formatFileSize(PdfExporter.estimateBytes(4, q))}'), findsOneWidget, reason: q.label);
    }
  });

  testWidgets('saves with the typed name and chosen quality, then shows success', (tester) async {
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), 'Lease: 2026/10');
    await tester.tap(find.text('Small file'));
    await tester.pump();
    await tapSave(tester);

    expect(exporter.calls, hasLength(1));
    expect(exporter.calls.single.fileName, 'Lease_ 2026_10.pdf');
    expect(exporter.calls.single.quality, ExportQuality.small);

    // Still writing: no success yet, and the button cannot be pressed again.
    expect(find.text('PDF saved'), findsNothing);
    expect(find.textContaining('Saving'), findsWidgets);
    expect(saveButton(tester).onPressed, isNull);
    await tester.tap(find.text('Saving…'), warnIfMissed: false);
    await tester.pump();
    expect(exporter.calls, hasLength(1));

    await tester.runAsync(() async {
      exporter.finish();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('PDF saved'), findsOneWidget);
    expect(find.textContaining('out.pdf'), findsOneWidget);
    expect(exporter.calls, hasLength(1));
  });

  testWidgets('a name that is already taken is saved with a number', (tester) async {
    final store = container.read(pageStoreProvider);
    await tester.runAsync(() => store.writeExportAtomically('Receipt.pdf', [1]));
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), 'Receipt');
    await tapSave(tester);
    expect(exporter.calls.single.fileName, 'Receipt (2).pdf');
  });

  testWidgets('the sheet cannot be dismissed while saving', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('Save PDF'));
    await tester.pump();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(ExportSheet), findsOneWidget);
  });

  testWidgets('an empty name disables saving', (tester) async {
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(find.text('Enter a name for the PDF'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Receipt');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('a failed save keeps the name and lets the user try again', (tester) async {
    await pumpSheet(tester);
    exporter.failNext = true;
    await tester.enterText(find.byType(TextField), 'Receipt');
    await tapSave(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Export failed'), findsOneWidget);
    expect(find.text('PDF saved'), findsNothing);
    expect(nameField(tester), 'Receipt');
    expect(saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('fits at 200% text size', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSheet(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Save PDF'));
    expect(find.text('Save PDF'), findsOneWidget);
  });

  group('helpers', () {
    test('default scan name pads the date and time', () {
      expect(PdfExporter.defaultScanName(DateTime(2026, 10, 3, 9, 5)), 'Scan 2026-10-03 09.05');
    });

    test('size estimates grow with quality and page count', () {
      final high = PdfExporter.estimateBytes(1, ExportQuality.high);
      final medium = PdfExporter.estimateBytes(1, ExportQuality.medium);
      final small = PdfExporter.estimateBytes(1, ExportQuality.small);
      expect(high, greaterThan(medium));
      expect(medium, greaterThan(small));
      expect(PdfExporter.estimateBytes(5, ExportQuality.medium), closeTo(medium * 5, 5));
    });

    test('file sizes read as KB below 1 MB and MB above', () {
      expect(formatFileSize(850 * 1024), '850 KB');
      expect(formatFileSize((1.4 * 1024 * 1024).round()), '1.4 MB');
    });

    test('a taken export name gets a number instead of being replaced', () async {
      final store = PageStore(rootDir: () async => tmp);
      expect(await store.freeExportName('Receipt.pdf'), 'Receipt.pdf');
      await store.writeExportAtomically('Receipt.pdf', [1]);
      expect(await store.freeExportName('Receipt.pdf'), 'Receipt (2).pdf');
      await store.writeExportAtomically('Receipt (2).pdf', [2]);
      expect(await store.freeExportName('Receipt.pdf'), 'Receipt (3).pdf');
    });
  });
}
