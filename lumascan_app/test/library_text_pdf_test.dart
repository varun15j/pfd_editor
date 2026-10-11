import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/export/ocr_pdf_builder.dart';
import 'package:lumascan/export/text_pdf_service.dart';

import 'support/memory_stores.dart';
import 'support/pump_app.dart';

class _FakeTextPdf implements TextPdfService {
  _FakeTextPdf(this.output);
  final File output;
  final read = <(String, int, String)>[];

  @override
  Future<OcrPdfFile> fromPdf(
    String sourcePath, {
    required int pageCount,
    required String fileName,
    String languageCode = 'en',
    void Function(double fraction)? onProgress,
  }) async {
    read.add((sourcePath, pageCount, fileName));
    onProgress?.call(1);
    return OcrPdfFile(output, 5);
  }

  @override
  Future<OcrPdfFile> fromPages(
    List<ScanPage> pages, {
    required String fileName,
    String languageCode = 'en',
    void Function(double fraction)? onProgress,
  }) => throw UnimplementedError();
}

void main() {
  late Directory tmp;
  late SavedDocument lease;
  late _FakeTextPdf service;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lumascan_textpdf_lib');
    final source = File('${tmp.path}/Lease.pdf')..writeAsBytesSync([1, 2, 3]);
    service = _FakeTextPdf(File('${tmp.path}/Lease (text).pdf')..writeAsBytesSync([4, 5, 6]));
    lease = SavedDocument(
      id: 'a',
      name: 'Lease',
      pdfPath: source.path,
      pageCount: 3,
      type: ScanType.document,
      createdAt: DateTime(2026, 3, 9),
      modifiedAt: DateTime(2026, 3, 9),
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> openMenu(WidgetTester tester, AppPlan plan) async {
    await pumpApp(
      tester,
      library: MemoryLibraryStore(const LibraryIndex().copyWith(documents: [lease])),
      overrides: [
        textPdfServiceProvider.overrideWithValue(service),
        pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
        planProvider.overrideWith((ref) => plan),
      ],
    );
    await tester.tap(find.bySemanticsLabel('Library'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More for Lease'));
    await tester.pumpAndSettle();
  }

  testWidgets('on Basic Create text PDF is listed with Pro and opens the upgrade pop-up', (tester) async {
    await openMenu(tester, AppPlan.basic);
    expect(find.text('Create text PDF'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);

    await tester.tap(find.text('Create text PDF'));
    await tester.pumpAndSettle();

    expect(find.text('Upgrade to Pro'), findsWidgets);
    expect(service.read, isEmpty);
  });

  for (final plan in [AppPlan.pro, AppPlan.gold]) {
    testWidgets('on ${plan.label} Create text PDF reads the saved document and files the result', (tester) async {
      await openMenu(tester, plan);
      expect(find.text('Pro'), findsNothing);

      await tester.tap(find.text('Create text PDF'));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(service.read, hasLength(1));
      expect(service.read.single.$1, lease.pdfPath);
      expect(service.read.single.$2, 3);
      expect(service.read.single.$3, 'Lease (text).pdf');
      expect(find.text('Saved Lease (text).pdf'), findsOneWidget);
      // Filed in the Library next to the original.
      expect(find.text('Lease (text)'), findsWidgets);
    });
  }
}
