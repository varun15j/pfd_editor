import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/features/share/pdf_sharer.dart';
import 'package:lumascan/features/share/text_pdf_next_sheet.dart';

class _FakeSharer implements PdfSharer {
  final sent = <String>[];

  @override
  Future<SendOutcome> send(String path, {Rect? origin}) async {
    sent.add(path);
    return SendOutcome.sent;
  }
}

void main() {
  late Directory tmp;
  late File pdf;
  late _FakeSharer sharer;
  var saved = 0;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lumascan_next');
    pdf = File('${tmp.path}/Lease (text).pdf')..writeAsBytesSync([37, 80, 68, 70]);
    sharer = _FakeSharer();
    saved = 0;
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pdfSharerProvider.overrideWithValue(sharer)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showTextPdfNextSheet(
                    context,
                    pdfPath: pdf.path,
                    pageCount: 3,
                    saveToLibrary: () async => saved++,
                  ),
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

  testWidgets('offers library, another app, share and Documents, in that order', (tester) async {
    await openSheet(tester);

    expect(find.text('Text PDF saved'), findsOneWidget);
    expect(find.text('Lease (text).pdf · 3 pages'), findsOneWidget);
    final titles = ['Save to library', 'Open in another PDF app', 'Share', 'Save to Documents folder'];
    final tops = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
    expect(tops, [...tops]..sort());
    expect(tops.toSet(), hasLength(4), reason: 'each option is on its own row');
  });

  testWidgets('Save to library files the PDF and closes the sheet', (tester) async {
    await openSheet(tester);

    await tester.tap(find.text('Save to library'));
    await tester.pumpAndSettle();

    expect(saved, 1);
    expect(find.text('Text PDF saved'), findsNothing);
    expect(find.text('Saved to your Library'), findsOneWidget);
  });

  testWidgets('Share hands the PDF to the share sheet and closes', (tester) async {
    await openSheet(tester);

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(sharer.sent, [pdf.path]);
    expect(find.text('Text PDF saved'), findsNothing);
    expect(saved, 0, reason: 'sharing does not file the PDF in the library');
  });
}
