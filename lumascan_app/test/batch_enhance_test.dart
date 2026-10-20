import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/features/batch_edit/batch_enhance_screen.dart';
import 'package:lumascan/features/batch_edit/batch_review_screen.dart';
import 'package:lumascan/features/pages/scan_controller.dart';

import 'support/screen_harness.dart';

void main() {
  final harness = ScreenHarness();
  tearDown(harness.dispose);

  ScanState state() => harness.container.read(scanControllerProvider);

  testWidgets('Enhance from Batch Review applies one look to the selected pages only', (tester) async {
    await tester.runAsync(() => harness.setUp(pageCount: 3));
    final ids = [for (final p in harness.pages) p.id];
    const crop = CropQuad(NormPoint(0.1, 0.1), NormPoint(0.9, 0.1), NormPoint(0.9, 0.9), NormPoint(0.1, 0.9));
    final controller = harness.container.read(scanControllerProvider.notifier);
    controller.updateRecipe(ids[0], const EditRecipe(crop: crop, quarterTurns: 1));
    await harness.pumpRoute(tester, (_) => const BatchReviewScreen());

    await tester.tap(find.text('Page 3'));
    await tester.pump();
    await tester.tap(find.text('Enhance'));
    await harness.settle(tester);

    expect(find.text('Enhance 2 pages'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('B&W'));
    await tester.pump();
    await tester.tap(find.text('Apply to 2 pages'));
    await harness.settle(tester);

    final pages = state().pages;
    expect(
      [for (final p in pages) p.recipe.filter],
      [DocumentFilter.blackWhite, DocumentFilter.blackWhite, DocumentFilter.original],
    );
    expect(pages[0].recipe.crop, crop);
    expect(pages[0].recipe.quarterTurns, 1);
    expect(find.text('Batch review'), findsOneWidget);
    expect(find.text('Enhanced 2 pages'), findsOneWidget);
  });

  testWidgets('Reset, compare and paging between selected pages', (tester) async {
    await tester.runAsync(() => harness.setUp(pageCount: 2));
    final ids = [for (final p in harness.pages) p.id];
    harness.container.read(scanControllerProvider.notifier).applyEnhancementToPages({
      ids[0],
    }, const EditRecipe(filter: DocumentFilter.grayscale, contrast: 0.5));
    await harness.pumpRoute(tester, (_) => BatchEnhanceScreen(pageIds: ids));

    expect(find.text('Page 1 of 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Next selected page'));
    await tester.pump();
    expect(find.text('Page 2 of 2'), findsOneWidget);

    await tester.tap(find.text('Compare with original'));
    await tester.pump();
    expect(find.bySemanticsLabel('Page 2 of 2 selected, original'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pump();
    await tester.tap(find.text('Apply to 2 pages'));
    await harness.settle(tester);
    expect(state().pages.every((p) => p.recipe.filter == DocumentFilter.original && p.recipe.contrast == 0), isTrue);
  });

  testWidgets('Cancel leaves the pages unchanged', (tester) async {
    await tester.runAsync(() => harness.setUp(pageCount: 2));
    final ids = [for (final p in harness.pages) p.id];
    await harness.pumpRoute(tester, (_) => BatchEnhanceScreen(pageIds: ids));

    await tester.tap(find.bySemanticsLabel('Grayscale'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await harness.settle(tester);
    expect(state().pages.every((p) => p.recipe.filter == DocumentFilter.original), isTrue);
    expect(state().undoStack, hasLength(1), reason: 'only the scan itself');
  });
}
