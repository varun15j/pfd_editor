import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/app_info.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/app/theme.dart';
import 'package:lumascan/data/export_state_store.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/data/smart_namer.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/domain/scanner_service.dart';
import 'package:lumascan/export/ocr_pdf_builder.dart';
import 'package:lumascan/export/pdf_exporter.dart';
import 'package:lumascan/export/text_pdf_service.dart';
import 'package:lumascan/features/export/export_sheet.dart';
import 'package:lumascan/features/library/library_controller.dart';
import 'package:lumascan/features/pages/scan_controller.dart';

import 'support/memory_stores.dart';
import 'support/temp_dir.dart';

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
    bool keepLayout = false,
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
    bool keepLayout = false,
    void Function(double fraction)? onProgress,
  }) => throw UnimplementedError();
}

/// Suggests [name] for any pages, noting each call.
class _FakeNamer implements SmartNamer {
  _FakeNamer(this.name);
  String? name;
  int calls = 0;

  @override
  Duration get timeout => Duration.zero;

  @override
  Future<String?> suggest(List<ScanPage> pages, {String languageCode = 'en'}) async {
    calls++;
    return name;
  }
}

void main() {
  var plan = AppPlan.basic;
  late _FakeNamer namer;
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
    namer = _FakeNamer('Invoice INV-7 2026-10-26');
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
        smartNamerProvider.overrideWithValue(namer),
        exportStateStoreProvider.overrideWithValue(MemoryExportStateStore()),
      ],
    );
    await container.read(scanControllerProvider.notifier).scan(ScanSource.camera);
  });

  tearDown(() {
    container.dispose();
    deleteTemp(tmp);
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    // The scan in setUp already read the plan (for its credits), so the plan
    // a test sets afterwards needs a fresh read.
    container.invalidate(planProvider);
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

  testWidgets('offers the scan\'s name, like "11-Oct-2026_16-47_SCAN"', (tester) async {
    await pumpSheet(tester);
    expect(nameField(tester), matches(RegExp(r'^\d\d-[A-Z][a-z]{2}-\d{4}_\d\d-\d\d_SCAN$')));
    expect(find.text('.pdf'), findsOneWidget);
  });

  group('smart file names', () {
    testWidgets('on Basic the name is not read from the page, and the button offers Pro', (tester) async {
      await pumpSheet(tester);
      expect(namer.calls, 0);
      expect(nameField(tester), contains('_SCAN'));

      await tester.tap(find.byTooltip('Name from page text · Pro'));
      await tester.pumpAndSettle();
      expect(find.text('Upgrade to Pro'), findsWidgets);
      expect(namer.calls, 0);
    });

    for (final pro in [AppPlan.pro, AppPlan.gold]) {
      testWidgets('on ${pro.label} the sheet opens with a name from the page text', (tester) async {
        plan = pro;
        await pumpSheet(tester);
        expect(namer.calls, 1);
        expect(nameField(tester), 'Invoice INV-7 2026-10-26');
      });
    }

    testWidgets('a page with nothing to name keeps the date name, and says so only when asked', (tester) async {
      plan = AppPlan.pro;
      namer.name = null;
      await pumpSheet(tester);
      expect(nameField(tester), contains('_SCAN'));
      expect(find.textContaining('No title'), findsNothing);

      await tester.tap(find.byTooltip('Name from page text'));
      await tester.pumpAndSettle();
      expect(namer.calls, 2);
      expect(find.text('No title, number or date found on the first page.'), findsOneWidget);
    });

    testWidgets('the button replaces a typed name, because the user asked', (tester) async {
      plan = AppPlan.pro;
      await pumpSheet(tester);
      await tester.enterText(find.byType(TextField), 'Mine');
      namer.name = 'Receipt 4471';
      await tester.tap(find.byTooltip('Name from page text'));
      await tester.pumpAndSettle();
      expect(nameField(tester), 'Receipt 4471');
    });
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

      expect(textPdf.names, ['Saved/Lease (text).pdf']);
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
    expect(exporter.calls.single.fileName, 'Saved/Lease_ 2026_10.pdf');
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

  testWidgets('on Basic the PDF carries the watermark and page numbers offer the upgrade', (tester) async {
    await pumpSheet(tester);
    expect(find.textContaining(exportWatermark), findsOneWidget);
    expect(find.text('Page numbers · Pro'), findsOneWidget);

    await tester.ensureVisible(find.text('Page numbers · Pro'));
    await tester.tap(find.text('Page numbers · Pro'));
    await tester.pumpAndSettle();
    expect(find.textContaining('part of the Pro plan'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);

    await tester.ensureVisible(find.text('Save PDF'));
    await tapSave(tester);
    expect(exporter.calls.single.watermark, exportWatermark);
    expect(exporter.calls.single.pageNumbers, isFalse);
  });

  for (final pro in [AppPlan.pro, AppPlan.gold]) {
    testWidgets('on ${pro.label} the PDF has no watermark and can number its pages', (tester) async {
      plan = pro;
      await pumpSheet(tester);
      expect(find.textContaining(exportWatermark), findsNothing);

      await tester.ensureVisible(find.text('Page numbers'));
      await tester.tap(find.text('Page numbers'));
      await tester.pumpAndSettle();
      expect(find.text('Upgrade to Pro'), findsNothing);

      await tester.ensureVisible(find.text('Save PDF'));
      await tapSave(tester);
      expect(exporter.calls.single.watermark, isNull);
      expect(exporter.calls.single.pageNumbers, isTrue);
    });
  }

  group('Saved folder', () {
    /// Opens the sheet (pumping the app the first time), saves as "Lease"
    /// and waits for the result.
    Future<void> exportOnce(WidgetTester tester, {bool first = false}) async {
      if (first) {
        await pumpSheet(tester);
      } else {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), 'Lease');
      await tapSave(tester);
      // Planning, writing and filing each wait on the file system.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> done(WidgetTester tester) async {
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    }

    testWidgets('an unchanged scan reuses its saved PDF; a changed one is made again', (tester) async {
      exporter.finish();
      await exportOnce(tester, first: true);
      expect(exporter.calls, hasLength(1));
      expect(exporter.calls.single.fileName, 'Saved/Lease.pdf');
      expect(find.text('PDF saved'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      await done(tester);

      await exportOnce(tester);
      expect(exporter.calls, hasLength(1), reason: 'nothing changed, so nothing is made again');
      expect(find.text('No changes since your last export'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      await done(tester);

      final pages = container.read(scanControllerProvider).pages;
      container.read(scanControllerProvider.notifier).rotate(pages.first.id);
      await exportOnce(tester);
      expect(exporter.calls, hasLength(2));
      expect(exporter.calls.last.fileName, 'Saved/Lease.pdf', reason: 'the new file replaces the old one');
      final docs = (await tester.runAsync(() => container.read(libraryProvider.future)))!.documents;
      expect(docs, hasLength(1), reason: 'exporting again does not add a second entry');
      expect(docs.single.isScanExport, isTrue);
    });
  });

  testWidgets('a name that is already taken is saved with a number', (tester) async {
    final store = container.read(pageStoreProvider);
    await tester.runAsync(() async {
      await store.savedDir;
      await store.writeExportAtomically('Saved/Receipt.pdf', [1]);
    });
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), 'Receipt');
    await tapSave(tester);
    expect(exporter.calls.single.fileName, 'Saved/Receipt (2).pdf');
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
