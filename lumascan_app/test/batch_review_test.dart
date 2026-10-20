import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/features/batch_edit/batch_review_screen.dart';
import 'package:lumascan/features/batch_edit/batch_selection.dart';
import 'package:lumascan/features/pages/pages_screen.dart';
import 'package:lumascan/features/pages/scan_controller.dart';

import 'support/screen_harness.dart';

List<ScanPage> _pages(List<String> ids) => [for (final id in ids) ScanPage(id: id, originalPath: '/$id.jpg')];

void main() {
  group('BatchSelection', () {
    test('starts with every page and toggles by ID', () {
      final pages = _pages(['a', 'b', 'c']);
      var s = BatchSelection.all(pages);
      expect(s.count, 3);
      expect(s.coversAll(pages), isTrue);

      s = s.toggle('b');
      expect(s.ids, {'a', 'c'});
      expect(s.coversAll(pages), isFalse);
      expect(s.toggle('b').coversAll(pages), isTrue);
    });

    test('follows pages through a reorder and drops deleted ones', () {
      final s = const BatchSelection({'a', 'c'});
      final reordered = _pages(['c', 'b', 'a']);
      expect([for (final p in s.pagesIn(reordered)) p.id], ['c', 'a']);

      final afterDelete = _pages(['b', 'a']);
      expect(s.retain(afterDelete).ids, {'a'});
      expect(identical(s.retain(reordered), s), isTrue);
    });

    test('isSingle only for exactly one page', () {
      expect(const BatchSelection().isSingle, isFalse);
      expect(const BatchSelection({'a'}).isSingle, isTrue);
      expect(const BatchSelection({'a', 'b'}).isSingle, isFalse);
    });
  });

  group('Batch Review screen', () {
    final harness = ScreenHarness();
    tearDown(harness.dispose);

    testWidgets('opens from the Pages screen with every page selected', (tester) async {
      await tester.runAsync(() => harness.setUp(pageCount: 3));
      await harness.pump(tester, const PagesScreen());

      await tester.tap(find.byTooltip('Batch edit'));
      await harness.settle(tester);

      expect(find.text('Batch review'), findsOneWidget);
      expect(find.text('3 selected'), findsOneWidget);
      expect(find.byType(BatchPageTile), findsNWidgets(3));
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('tap toggles one page; Clear and Select all change every page', (tester) async {
      await tester.runAsync(() => harness.setUp(pageCount: 3));
      await harness.pumpRoute(tester, (_) => const BatchReviewScreen());

      await tester.tap(find.text('Page 2'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);

      await tester.tap(find.text('Select all'));
      await tester.pump();
      expect(find.text('3 selected'), findsOneWidget);

      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(find.text('0 selected'), findsOneWidget);
    });

    testWidgets('selection stays with its page when the draft is reordered or trimmed', (tester) async {
      await tester.runAsync(() => harness.setUp(pageCount: 3));
      await harness.pumpRoute(tester, (_) => const BatchReviewScreen());
      final ids = [for (final p in harness.pages) p.id];

      await tester.tap(find.text('Page 1'));
      await tester.pump();
      final controller = harness.container.read(scanControllerProvider.notifier);
      controller.move(0, 2);
      await tester.pump();

      final tiles = tester.widgetList<BatchPageTile>(find.byType(BatchPageTile)).toList();
      expect([for (final t in tiles) t.page.id], [ids[1], ids[2], ids[0]]);
      expect([for (final t in tiles) t.selected], [true, true, false]);

      controller.remove(ids[1]);
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('Back returns to the Pages screen', (tester) async {
      await tester.runAsync(() => harness.setUp(pageCount: 2));
      await harness.pumpRoute(tester, (_) => const BatchReviewScreen());

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Batch review'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });
}
