import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/photo_import.dart';
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
        () => harness.setUp(pageCount: 3, overrides: [photoAnalyzerProvider.overrideWithValue(analyzer)]),
      );
      for (final (i, p) in harness.pages.indexed) {
        analyzer.quads[p.originalPath] = _inset(const [0.05, 0.1, 0.15][i]);
      }
      await harness.pumpRoute(tester, (_) => const BatchReviewScreen());
      await tester.tap(find.text('Crop'));
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
}
