import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/features/export/export_saver.dart';
import 'package:lumascan/features/share/pdf_sharer.dart';
import 'package:lumascan/features/share/text_pdf_next_sheet.dart';
import 'support/temp_dir.dart';

class _FakeSharer implements PdfSharer {
  final sent = <String>[];

  @override
  Future<SendOutcome> send(String path, {Rect? origin}) async {
    sent.add(path);
    return SendOutcome.sent;
  }
}

class _FakeSaver implements ExportSaver {
  final saved = <String>[];
  String? answer = 'Lease (text).pdf';

  @override
  bool get canSaveToFolder => true;

  @override
  Future<String?> saveFile(String path, {required String mimeType, String? name}) async {
    saved.add(path);
    return answer;
  }

  @override
  Future<String?> saveToFolder(List<String> paths, {required String mimeType}) async => 'Documents';
}

void main() {
  late Directory tmp;
  late File pdf;
  late _FakeSharer sharer;
  late _FakeSaver saver;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lumascan_next');
    pdf = File('${tmp.path}/Lease (text).pdf')..writeAsBytesSync([37, 80, 68, 70]);
    sharer = _FakeSharer();
    saver = _FakeSaver();
  });

  tearDown(() => deleteTemp(tmp));

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pdfSharerProvider.overrideWithValue(sharer), exportSaverProvider.overrideWithValue(saver)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showTextPdfNextSheet(context, pdfPath: pdf.path, pageCount: 3),
                  child: const Text('Open sheet'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
  }

  testWidgets('asks where it goes: save to device, share, or another app; no library copy', (tester) async {
    await openSheet(tester);

    expect(find.text('Text PDF ready'), findsOneWidget);
    expect(find.text('Lease (text).pdf · 3 pages'), findsOneWidget);
    final titles = ['Save to device', 'Share', 'Open in another PDF app'];
    final tops = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
    expect(tops, [...tops]..sort());
    expect(find.text('Save to library'), findsNothing);
  });

  testWidgets('Save to device opens the save screen and says where it went', (tester) async {
    await openSheet(tester);

    await tester.tap(find.text('Save to device'));
    await tester.pumpAndSettle();

    expect(saver.saved, [pdf.path]);
    expect(find.text('Saved as Lease (text).pdf'), findsOneWidget);
    expect(find.text('Save another copy'), findsOneWidget);
  });

  testWidgets('cancelling the save screen says nothing and keeps the sheet', (tester) async {
    saver.answer = null;
    await openSheet(tester);

    await tester.tap(find.text('Save to device'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Saved as'), findsNothing);
    expect(find.text('Text PDF ready'), findsOneWidget);
  });

  testWidgets('Share hands the PDF to the share sheet and closes', (tester) async {
    await openSheet(tester);

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(sharer.sent, [pdf.path]);
    expect(find.text('Text PDF ready'), findsNothing);
    expect(saver.saved, isEmpty);
  });
}
