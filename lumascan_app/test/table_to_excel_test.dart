import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/app/theme.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/ocr.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/domain/scanner_service.dart';
import 'package:lumascan/domain/table_extractor.dart';
import 'package:lumascan/export/xlsx_writer.dart';
import 'package:lumascan/features/table/table_to_excel.dart';
import 'package:lumascan/features/tools/tools_screen.dart';

import 'support/memory_stores.dart';

/// A word box in fractions of the page.
OcrBox _w(String text, double left, double top, {double width = 0.08, double height = 0.02}) =>
    OcrBox(text: text, left: left, top: top, right: left + width, bottom: top + height);

/// One block per word, the way ML Kit often splits a table.
OcrLayout _layout(List<OcrBox> words) => OcrLayout([
  for (final w in words)
    OcrBlock(
      text: w.text,
      left: w.left,
      top: w.top,
      right: w.right,
      bottom: w.bottom,
      lines: [
        OcrLine(text: w.text, left: w.left, top: w.top, right: w.right, bottom: w.bottom, words: [w]),
      ],
    ),
]);

/// The word boxes tesseract found on sample_scan_img/tables/grocery_bill_printed.jpg.
OcrLayout _fixture() {
  OcrBox box(Map<String, Object?> j) => OcrBox(
    text: j['text']! as String,
    left: (j['left']! as num).toDouble(),
    top: (j['top']! as num).toDouble(),
    right: (j['right']! as num).toDouble(),
    bottom: (j['bottom']! as num).toDouble(),
  );
  final blocks = jsonDecode(File('test/fixtures/table_ocr_grocery_bill.json').readAsStringSync()) as List<Object?>;
  return OcrLayout([
    for (final b in blocks.cast<Map<String, Object?>>())
      OcrBlock(
        text: b['text']! as String,
        left: (b['left']! as num).toDouble(),
        top: (b['top']! as num).toDouble(),
        right: (b['right']! as num).toDouble(),
        bottom: (b['bottom']! as num).toDouble(),
        lines: [
          for (final l in (b['lines']! as List<Object?>).cast<Map<String, Object?>>())
            OcrLine(
              text: l['text']! as String,
              left: (l['left']! as num).toDouble(),
              top: (l['top']! as num).toDouble(),
              right: (l['right']! as num).toDouble(),
              bottom: (l['bottom']! as num).toDouble(),
              words: [for (final w in (l['words']! as List<Object?>).cast<Map<String, Object?>>()) box(w)],
            ),
        ],
      ),
  ]);
}

void main() {
  group('reading a table', () {
    test('a printed bill becomes rows and columns, with the title on its own row', () {
      final table = const TableExtractor().extract(_fixture());
      expect(table.columnCount, 4);
      expect(table.rows.first, ['Monthly grocery bill', '', '', '']);
      expect(table.rows[1], ['Item', 'Qty', 'Rate', 'Amount']);
      expect(table.rows[2], ['Basmati rice', '10', '95.50', '955.00']);
      // Tesseract missed the single-digit quantities, so those cells are empty.
      expect(table.rows[5], ['Sunflower oil', '', '1,250.00', '3,750.00']);
      expect(table.rows[7], ['Green tea bags', '', '299', '299']);
      expect(table.rows.last, ['Total', '', '', '5,714.00']);
    });

    test('words close together share a cell, a wide gap starts the next one', () {
      final table = const TableExtractor().extract(
        _layout([
          _w('Item', 0.1, 0.1),
          _w('Total', 0.6, 0.1),
          _w('cost', 0.69, 0.1, width: 0.06),
          _w('Green', 0.1, 0.2),
          _w('tea', 0.19, 0.2, width: 0.05),
          _w('299', 0.62, 0.2),
        ]),
      );
      expect(table.rows, [
        ['Item', 'Total cost'],
        ['Green tea', '299'],
      ]);
    });

    test('a slightly tilted row stays one row, and a missing cell stays empty', () {
      final table = const TableExtractor().extract(
        _layout([
          _w('Rice', 0.1, 0.100),
          _w('12 kg', 0.4, 0.104),
          _w('60', 0.7, 0.108),
          _w('Flour', 0.1, 0.2),
          _w('40', 0.7, 0.2),
        ]),
      );
      expect(table.rows, [
        ['Rice', '12 kg', '60'],
        ['Flour', '', '40'],
      ]);
    });

    test('a photo with no text gives an empty table', () {
      expect(const TableExtractor().extract(const OcrLayout([])).isEmpty, isTrue);
    });

    test('fixing a cell changes only that cell', () {
      const table = ExtractedTable([
        ['a', 'b'],
        ['c', 'd'],
      ]);
      expect(table.withCell(1, 0, 'x').rows, [
        ['a', 'b'],
        ['x', 'd'],
      ]);
    });
  });

  group('the Excel file', () {
    test('plain numbers become numbers; codes, dates and phone numbers stay text', () {
      expect(XlsxWriter.numberIn('1,250.00'), 1250);
      expect(XlsxWriter.numberIn('1,23,456'), 123456);
      expect(XlsxWriter.numberIn('₹ 60'), 60);
      expect(XlsxWriter.numberIn('-3.5'), -3.5);
      expect(XlsxWriter.numberIn('0.75'), 0.75);
      expect(XlsxWriter.numberIn('007'), isNull);
      expect(XlsxWriter.numberIn('12/10/2026'), isNull);
      expect(XlsxWriter.numberIn('98765 43210'), isNull);
      expect(XlsxWriter.numberIn('12 kg'), isNull);
      expect(XlsxWriter.numberIn('1234567890123456'), isNull, reason: 'too long for Excel to keep exactly');
    });

    test('column names run A to Z, then AA', () {
      expect([0, 25, 26, 27, 701].map(XlsxWriter.columnName), ['A', 'Z', 'AA', 'AB', 'ZZ']);
    });

    test('the sheet has a bold first row, numbers as numbers and text escaped', () {
      final bytes = XlsxWriter.write([
        ['Item', 'Amount'],
        ['Oil & ghee <1L>', '3,750.00'],
        ['', '5'],
      ]);
      final zip = ZipDecoder().decodeBytes(bytes);
      String part(String name) => utf8.decode(zip.findFile(name)!.content as List<int>);
      expect(zip.files.map((f) => f.name), containsAll(['[Content_Types].xml', 'xl/workbook.xml', 'xl/styles.xml']));
      final sheet = part('xl/worksheets/sheet1.xml');
      expect(sheet, contains('<c r="A1" s="1" t="inlineStr"><is><t xml:space="preserve">Item</t></is></c>'));
      expect(sheet, contains('<t xml:space="preserve">Oil &amp; ghee &lt;1L&gt;</t>'));
      expect(sheet, contains('<c r="B2"><v>3750.0</v></c>'));
      expect(sheet, isNot(contains('r="A3"')), reason: 'empty cells are left out');
      expect(sheet, contains('<c r="B3"><v>5</v></c>'));
      expect(sheet, contains('state="frozen"'));
    });

    test('a save never replaces an earlier file', () async {
      final tmp = await Directory.systemTemp.createTemp('lumascan_xlsx');
      addTearDown(() => tmp.delete(recursive: true));
      final store = PageStore(rootDir: () async => tmp);
      const table = ExtractedTable([
        ['a'],
      ]);
      final first = await saveTableAsExcel(store, table, name: 'Table.xlsx');
      final second = await saveTableAsExcel(store, table, name: 'Table.xlsx');
      expect(first.path.endsWith('Table.xlsx'), isTrue);
      expect(second.path.endsWith('Table (2).xlsx'), isTrue);
    });

    test('file names carry the date and time', () {
      expect(tableFileName(DateTime(2026, 10, 7, 9, 5)), 'Table 2026-10-07 0905.xlsx');
    });
  });

  test('Table to Excel is Gold only', () {
    expect(PlanFeature.tableToExcel.minimum, AppPlan.gold);
    expect(AppPlan.pro.includes(PlanFeature.tableToExcel), isFalse);
    expect(AppPlan.gold.includes(PlanFeature.tableToExcel), isTrue);
  });

  group('Table to Excel in the app', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lumascan_table');
    });
    tearDown(() => tmp.delete(recursive: true));

    Future<void> pumpTools(WidgetTester tester, AppPlan plan, {OcrEngine? ocr, ScannerService? scanner}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryStoreProvider.overrideWithValue(MemoryLibraryStore()),
            planProvider.overrideWithValue(plan),
            pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
            if (ocr != null) ocrEngineProvider.overrideWithValue(ocr),
            if (scanner != null) scannerServiceProvider.overrideWithValue(scanner),
          ],
          child: MaterialApp(theme: buildLumaTheme(Brightness.light), home: const ToolsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('on Pro the tile has a Gold badge and asks to upgrade', (tester) async {
      await pumpTools(tester, AppPlan.pro);
      await tester.scrollUntilVisible(find.text('Table to Excel'), 100);
      await tester.ensureVisible(find.text('Table to Excel'));
      await tester.pumpAndSettle();
      expect(find.text('Gold'), findsOneWidget);
      await tester.tap(find.text('Table to Excel'));
      await tester.pumpAndSettle();
      expect(find.text('Upgrade to Gold'), findsWidgets);
      expect(find.text('Table to Excel is part of the Gold plan.'), findsOneWidget);
    });

    testWidgets('on Gold one photo becomes a table to check, fix and save', (tester) async {
      final photo = File('${tmp.path}/photo.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
      final scanner = _FakeScanner(photo.path);
      await pumpTools(
        tester,
        AppPlan.gold,
        ocr: _FakeOcr(_layout([_w('Item', 0.1, 0.1), _w('Cost', 0.6, 0.1), _w('Rice', 0.1, 0.2), _w('6O', 0.6, 0.2)])),
        scanner: scanner,
      );
      await tester.scrollUntilVisible(find.text('Table to Excel'), 100);
      await tester.ensureVisible(find.text('Table to Excel'));
      await tester.pumpAndSettle();
      expect(find.text('Gold'), findsNothing);
      await tester.tap(find.text('Table to Excel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      expect(scanner.asked, [(ScanSource.camera, 1)]);
      expect(find.text('Check the table'), findsOneWidget);
      expect(find.textContaining('2 rows, 2 columns'), findsOneWidget);

      // OCR read a letter O for a zero; the cell is fixed by hand.
      await tester.tap(find.text('6O'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '60');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('60'), findsOneWidget);

      await tester.tap(find.text('Save as Excel'));
      // The file is written with real IO, a step at a time.
      for (var i = 0; i < 30 && find.text('Excel file saved').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('Excel file saved'), findsOneWidget);

      final saved = Directory('${tmp.path}/exports').listSync().whereType<File>().single;
      expect(saved.path, endsWith('.xlsx'));
      final sheet = utf8.decode(
        ZipDecoder().decodeBytes(saved.readAsBytesSync()).findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
      );
      expect(sheet, contains('<c r="B2"><v>60</v></c>'));
    });

    testWidgets('a photo with no text says so and opens nothing', (tester) async {
      final photo = File('${tmp.path}/photo.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
      await pumpTools(tester, AppPlan.gold, ocr: _FakeOcr(const OcrLayout([])), scanner: _FakeScanner(photo.path));
      await tester.scrollUntilVisible(find.text('Table to Excel'), 100);
      await tester.ensureVisible(find.text('Table to Excel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Table to Excel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose a photo'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(find.text('Check the table'), findsNothing);
      expect(find.textContaining('No text found'), findsOneWidget);
    });
  });
}

class _FakeScanner implements ScannerService {
  _FakeScanner(this.path);

  final String path;
  final asked = <(ScanSource, int)>[];

  @override
  Future<List<String>> scan({required ScanSource source, int maxPages = 100}) async {
    asked.add((source, maxPages));
    return [path];
  }

  @override
  Future<void> cleanUp() async {}
}

class _FakeOcr implements OcrEngine, OcrFileLayoutEngine {
  _FakeOcr(this.layout);

  final OcrLayout layout;

  @override
  Future<OcrCapability> capability(String languageCode) async =>
      const OcrCapability(readiness: OcrReadiness.ready, language: 'English');

  @override
  Future<void> prepare(String languageCode) async {}

  @override
  Future<String> recognize(ScanPage page, {required String languageCode}) async => layout.text;

  @override
  Future<String> recognizeFile(String path) async => layout.text;

  @override
  Future<OcrLayout> recognizeLayoutFile(String path) async => layout;
}
