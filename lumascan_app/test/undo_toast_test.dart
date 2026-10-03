import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/theme.dart';
import 'package:lumascan/ui/undo_toast.dart';

void main() {
  late int undone;

  Future<void> pumpToast(
    WidgetTester tester, {
    double textScale = 1,
    String message = 'Changes applied to 7 pages',
  }) async {
    undone = 0;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLumaTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showUndoToast(ScaffoldMessenger.of(context), message: message, onUndo: () => undone++),
              child: const Text('apply'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('shows the message with Undo and Keep', (tester) async {
    await pumpToast(tester);
    expect(find.text('Changes applied to 7 pages'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Keep'), findsOneWidget);
  });

  testWidgets('goes away by itself after ten seconds, and not before', (tester) async {
    await pumpToast(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Changes applied to 7 pages'), findsOneWidget, reason: 'still there after the old 4 seconds');
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Changes applied to 7 pages'), findsOneWidget, reason: 'about 9.4 seconds in');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Changes applied to 7 pages'), findsNothing);
    expect(undone, 0, reason: 'timing out keeps the changes');
  });

  testWidgets('Undo runs the undo and closes the message', (tester) async {
    await pumpToast(tester);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('Changes applied to 7 pages'), findsNothing);
  });

  testWidgets('Keep closes the message and changes nothing', (tester) async {
    await pumpToast(tester);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(undone, 0);
    expect(find.text('Changes applied to 7 pages'), findsNothing);
  });

  testWidgets('a new message replaces the one on screen', (tester) async {
    await pumpToast(tester);
    await tester.tap(find.text('apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Changes applied to 7 pages'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('fits at 200% text size with a long message', (tester) async {
    await pumpToast(
      tester,
      textScale: 2,
      message: 'Changes applied to 12 pages. Markup removed from this page because it was rotated',
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Keep'), findsOneWidget);
  });
}
