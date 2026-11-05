// Lays out the whole Word feature test file in both views and checks that
// nothing throws (overflow, bad constraints, missing images...).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_docx/luma_docx.dart';

void main() {
  final doc = WordReader.read(File('test/fixtures/Word_Feature_Test.docx').readAsBytesSync());

  for (final layout in WordLayout.values) {
    testWidgets('renders every page in ${layout.name} view', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = WordViewController();
      WordLink? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WordDocumentView(
              document: doc,
              controller: controller,
              options: WordViewOptions(layout: layout, showComments: true),
              onLinkTap: (l) => tapped = l,
            ),
          ),
        ),
      );
      await tester.pump();
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
      final max = scroll.position.maxScrollExtent;
      expect(max, greaterThan(5000));
      for (var y = 0.0; y <= max; y += 700) {
        scroll.position.jumpTo(y);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'at $y');
      }
      // Jump to a heading and to a bookmark.
      controller.jumpToParagraph(doc.headings.last.paragraphIndex);
      await tester.pumpAndSettle();
      controller.jumpToBookmark(doc.bookmarks.keys.first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tapped, isNull);
    });
  }

  testWidgets('markup and hidden text options render', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WordDocumentView(
            document: doc,
            options: const WordViewOptions(layout: WordLayout.reflow, showMarkup: false, showHidden: true, textScale: 1.4),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('rejects a file that is not a Word document', () {
    expect(() => WordReader.read(File('test/fixtures/Word_Feature_Test.docx').readAsBytesSync().sublist(0, 200)), throwsFormatException);
  });
}
