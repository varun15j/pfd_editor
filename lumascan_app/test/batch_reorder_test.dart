import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/features/batch_edit/batch_reorder_screen.dart';
import 'package:lumascan/features/batch_edit/batch_review_screen.dart';
import 'package:lumascan/features/pages/scan_controller.dart';

import 'support/screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.dispose);

  List<String> order() => [for (final p in harness.container.read(scanControllerProvider).pages) p.id];

  testWidgets('Move buttons change the order and Done commits it once', (tester) async {
    await tester.runAsync(() => harness.setUp(pageCount: 3));
    final ids = order();
    await harness.pumpRoute(tester, (_) => BatchReorderScreen(selectedIds: {ids[0]}));

    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_upward).first).onPressed, isNull);
    await tester.tap(find.byTooltip('Move page 1 down'));
    await tester.pump();
    await tester.tap(find.byTooltip('Move page 2 down'));
    await tester.pump();
    expect(order(), ids, reason: 'nothing changes until Done');
    expect(find.bySemanticsLabel('Page 3 of 3, selected'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(order(), [ids[1], ids[2], ids[0]]);
    expect(harness.container.read(scanControllerProvider).undoStack, hasLength(2));
  });

  testWidgets('Cancel restores the entry order', (tester) async {
    await tester.runAsync(() => harness.setUp(pageCount: 3));
    final ids = order();
    await harness.pumpRoute(tester, (_) => const BatchReorderScreen());

    await tester.tap(find.byTooltip('Move page 3 up'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(order(), ids);
  });

  testWidgets('selection follows its page after reordering from Batch Review', (tester) async {
    await tester.runAsync(() => harness.setUp(pageCount: 3));
    final ids = order();
    await harness.pumpRoute(tester, (_) => const BatchReviewScreen());
    await tester.tap(find.text('Clear'));
    await tester.pump();
    await tester.tap(find.text('Page 1'));
    await tester.pump();

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reorder'));
    await harness.settle(tester);
    await tester.tap(find.byTooltip('Move page 1 down'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await harness.settle(tester);

    expect(order(), [ids[1], ids[0], ids[2]]);
    final tiles = tester.widgetList<BatchPageTile>(find.byType(BatchPageTile)).toList();
    expect([for (final t in tiles) t.selected], [false, true, false]);
  });
}
