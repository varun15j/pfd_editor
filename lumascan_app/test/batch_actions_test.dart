import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/features/batch_edit/batch_actions.dart';
import 'package:lumascan/features/batch_edit/batch_review_screen.dart';
import 'package:lumascan/features/batch_edit/batch_selection.dart';
import 'package:lumascan/features/pages/scan_controller.dart';

import 'support/screen_harness.dart';

void main() {
  group('availability', () {
    test('nothing selected explains what to select', () {
      expect(availabilityOf(BatchAction.rotate, const BatchSelection()).reason, 'Select pages to rotate');
      expect(availabilityOf(BatchAction.retake, const BatchSelection()).reason, 'Select one page to retake');
    });

    test('single-page actions need exactly one page', () {
      const two = BatchSelection({'a', 'b'});
      expect(availabilityOf(BatchAction.rotate, two).enabled, isTrue);
      expect(availabilityOf(BatchAction.delete, two).enabled, isTrue);
      expect(availabilityOf(BatchAction.retake, two).reason, 'Select one page to retake');
      expect(availabilityOf(BatchAction.markup, two).reason, 'Select one page to mark up');
      expect(availabilityOf(BatchAction.duplicate, two).reason, 'Select one page to duplicate');
      expect(availabilityOf(BatchAction.duplicate, const BatchSelection({'a'})).enabled, isTrue);
    });

    test('scope label names the count', () {
      expect(scopeLabel(BatchAction.rotate, 4), 'Rotate 4 selected pages');
      expect(scopeLabel(BatchAction.delete, 1), 'Delete 1 selected page');
    });
  });

  group('action bar', () {
    final harness = ScreenHarness();
    tearDown(harness.dispose);

    ScanState state() => harness.container.read(scanControllerProvider);

    Future<void> open(WidgetTester tester, {int pages = 3}) async {
      await tester.runAsync(() => harness.setUp(pageCount: pages));
      await harness.pumpRoute(tester, (_) => const BatchReviewScreen());
    }

    testWidgets('Rotate turns every selected page and one Undo restores them', (tester) async {
      await open(tester);
      await tester.tap(find.text('Page 3'));
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Rotate 2 selected pages'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect([for (final p in state().pages) p.recipe.quarterTurns], [1, 1, 0]);
      expect(find.text('Rotated 2 pages'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect([for (final p in state().pages) p.recipe.quarterTurns], [0, 0, 0]);
    });

    testWidgets('a disabled action says how to enable it', (tester) async {
      await open(tester);
      await tester.tap(find.text('Clear'));
      await tester.pump();

      await tester.tap(find.text('Rotate'));
      await tester.pump();
      expect(find.text('Select pages to rotate'), findsOneWidget);
      expect(state().pages.every((p) => p.recipe.quarterTurns == 0), isTrue);
    });

    testWidgets('Delete confirms the count and can be undone', (tester) async {
      await open(tester);
      final ids = [for (final p in state().pages) p.id];
      await tester.tap(find.text('Page 2'));
      await tester.pump();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 pages?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect([for (final p in state().pages) p.id], [ids[1]]);
      expect(find.text('0 selected'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect([for (final p in state().pages) p.id], ids);
    });

    testWidgets('deleting every page asks to discard the document', (tester) async {
      await open(tester, pages: 2);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Discard this document?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state().pages, hasLength(2));

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard document'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(state().pages, isEmpty);
      expect(find.text('Batch review'), findsNothing);
    });

    testWidgets('More keeps single-page actions visible with a reason', (tester) async {
      await open(tester);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Select one page to retake'), findsOneWidget);
      expect(find.text('Select one page to duplicate'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear'));
      await tester.pump();
      await tester.tap(find.text('Page 1'));
      await tester.pump();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();
      expect(state().pages, hasLength(4));
      expect(state().pages[1].originalPath, state().pages[0].originalPath);
    });
  });
}
