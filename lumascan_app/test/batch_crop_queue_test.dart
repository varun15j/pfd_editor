import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/photo_import.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/features/batch_edit/batch_crop_queue.dart';
import 'package:lumascan/features/batch_edit/batch_review_screen.dart';
import 'package:lumascan/features/pages/scan_controller.dart';

import 'support/screen_harness.dart';

/// Finds a different page outline in every original, by file path.
class _PerPageAnalyzer implements PhotoAnalyzer {
  final quads = <String, CropQuad>{};
  final analyzed = <String>[];

  @override
  Future<CropQuad?> analyze(String path) async {
    analyzed.add(path);
    return quads[path];
  }
}

CropQuad _inset(double d) =>
    CropQuad(NormPoint(d, d), NormPoint(1 - d, d), NormPoint(1 - d, 1 - d), NormPoint(d, 1 - d));

void main() {
  test('summary names applied and remaining pages', () {
    expect(const CropQueueSummary(applied: 3, remaining: 0).message, 'Cropped 3 pages');
    expect(const CropQueueSummary(applied: 1, remaining: 2).message, 'Cropped 1 page. 2 pages left to crop');
    expect(const CropQueueSummary(applied: 0, remaining: 1).message, 'No pages cropped. 1 page left to crop');
  });

  group('crop queue', () {
    final harness = ScreenHarness();
    late _PerPageAnalyzer analyzer;
    tearDown(harness.dispose);

    ScanState state() => harness.container.read(scanControllerProvider);

    Future<void> open(WidgetTester tester) async {
      analyzer = _PerPageAnalyzer();
      await tester.runAsync(
        () => harness.setUp(
          pageCount: 3,
          overrides: [photoAnalyzerProvider.overrideWithValue(analyzer), planProvider.overrideWithValue(AppPlan.pro)],
        ),
      );
      for (final (i, p) in harness.pages.indexed) {
        analyzer.quads[p.originalPath] = _inset(const [0.05, 0.1, 0.15][i]);
      }
      await harness.pumpRoute(tester, (_) => const BatchReviewScreen());
      await tester.tap(find.text('Crop'));
      await harness.settle(tester);
      await tester.tap(find.text('Adjust each page'));
      await harness.settle(tester);
    }

    Future<void> tapAndSettle(WidgetTester tester, String text) async {
      await tester.tap(find.text(text));
      await harness.settle(tester);
    }

    testWidgets('each page is detected and cropped on its own', (tester) async {
      await open(tester);

      for (var i = 0; i < 3; i++) {
        expect(find.text('Crop page ${i + 1} of 3'), findsOneWidget);
        await tapAndSettle(tester, 'Reset to detected');
        await tapAndSettle(tester, i == 2 ? 'Apply and finish' : 'Apply and next');
      }

      expect([for (final p in state().pages) p.recipe.crop], [_inset(0.05), _inset(0.1), _inset(0.15)]);
      expect(analyzer.analyzed.toSet(), {for (final p in state().pages) p.originalPath});
      expect(find.text('Cropped 3 pages'), findsOneWidget);
      expect(find.text('Batch review'), findsOneWidget);
    });

    testWidgets('Skip, Back and Finish keep crops already applied', (tester) async {
      await open(tester);

      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Back')).onPressed, isNull);
      await tapAndSettle(tester, 'Reset to detected');
      await tapAndSettle(tester, 'Apply and next');
      await tapAndSettle(tester, 'Skip');
      expect(find.text('Crop page 3 of 3'), findsOneWidget);
      await tapAndSettle(tester, 'Back');
      expect(find.text('Crop page 2 of 3'), findsOneWidget);

      await tapAndSettle(tester, 'Finish');

      expect([for (final p in state().pages) p.recipe.crop], [_inset(0.05), CropQuad.full, CropQuad.full]);
      expect(find.text('Cropped 1 page. 2 pages left to crop'), findsOneWidget);
    });

    testWidgets('Reset brings back the crop the page had', (tester) async {
      await open(tester);

      await tapAndSettle(tester, 'Reset to detected');
      await tapAndSettle(tester, 'Reset');
      await tapAndSettle(tester, 'Apply and next');
      await tapAndSettle(tester, 'Finish');
      expect(state().pages.first.recipe.crop, CropQuad.full);
    });
  });

  group('crop all selected pages at once', () {
    final harness = ScreenHarness();
    late _PerPageAnalyzer analyzer;
    tearDown(harness.dispose);

    ScanState state() => harness.container.read(scanControllerProvider);

    Future<void> choose(WidgetTester tester, String choice) async {
      analyzer = _PerPageAnalyzer();
      await tester.runAsync(
        () => harness.setUp(
          pageCount: 3,
          overrides: [photoAnalyzerProvider.overrideWithValue(analyzer), planProvider.overrideWithValue(AppPlan.pro)],
        ),
      );
      // No page is found in the third photo.
      for (final (i, p) in harness.pages.take(2).indexed) {
        analyzer.quads[p.originalPath] = _inset(const [0.05, 0.1][i]);
      }
      await harness.pumpRoute(tester, (_) => const BatchReviewScreen());
      await tester.tap(find.text('Crop'));
      await harness.settle(tester);
      expect(find.text('Crop 3 selected pages'), findsOneWidget);
      await tester.tap(find.text(choice));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await harness.settle(tester);
    }

    testWidgets('Auto crop crops every page to the page found, as one undo step', (tester) async {
      await choose(tester, 'Auto crop');

      expect([for (final p in state().pages) p.recipe.crop], [_inset(0.05), _inset(0.1), CropQuad.full]);
      expect(find.text('Auto cropped 2 pages, no page found on 1'), findsOneWidget);
      harness.container.read(scanControllerProvider.notifier).undo();
      expect([for (final p in state().pages) p.recipe.crop], everyElement(CropQuad.full));
    });

    testWidgets('Full photo removes the crop from every page', (tester) async {
      analyzer = _PerPageAnalyzer();
      await tester.runAsync(
        () => harness.setUp(
          pageCount: 2,
          overrides: [photoAnalyzerProvider.overrideWithValue(analyzer), planProvider.overrideWithValue(AppPlan.pro)],
        ),
      );
      final controller = harness.container.read(scanControllerProvider.notifier);
      controller.setCrops({for (final p in harness.pages) p.id: _inset(0.1)});
      await harness.pumpRoute(tester, (_) => const BatchReviewScreen());
      await tester.tap(find.text('Crop'));
      await harness.settle(tester);
      await tester.tap(find.text('Full photo'));
      await harness.settle(tester);

      expect([for (final p in state().pages) p.recipe.crop], everyElement(CropQuad.full));
      expect(find.text('Full photo on 2 pages'), findsOneWidget);
    });
  });
}
