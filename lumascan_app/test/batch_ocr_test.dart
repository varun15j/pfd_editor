import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/ocr.dart';
import 'package:lumascan/features/batch_edit/batch_ocr_job.dart';
import 'package:lumascan/features/batch_edit/batch_ocr_screen.dart';
import 'package:lumascan/features/batch_edit/batch_review_screen.dart';

import 'support/screen_harness.dart';

/// Answers from [texts] by page ID; a missing entry throws. Pages listed in
/// [hold] wait until released, so a test can cancel mid-job.
class _FakeOcr implements OcrEngine {
  _FakeOcr({this.texts = const {}, this.readiness = OcrReadiness.ready});

  Map<String, String> texts;
  OcrReadiness readiness;
  final hold = <String, Completer<void>>{};
  final read = <String>[];

  @override
  Future<OcrCapability> capability(String languageCode) async => OcrCapability(
    readiness: readiness,
    language: 'English',
    reason: readiness == OcrReadiness.needsDownload ? 'Download English OCR to continue' : null,
  );

  @override
  Future<void> prepare(String languageCode) async => readiness = OcrReadiness.ready;

  @override
  Future<String> recognize(ScanPage page, {required String languageCode}) async {
    read.add(page.id);
    await hold[page.id]?.future;
    final text = texts[page.id];
    if (text == null) throw StateError('unreadable');
    return text;
  }
}

List<ScanPage> _pages(int n) => [for (var i = 0; i < n; i++) ScanPage(id: 'p$i', originalPath: '/p$i.jpg')];

void main() {
  group('BatchOcrJob', () {
    test('separates text, empty and failed pages and binds results to the page revision', () async {
      final engine = _FakeOcr(texts: {'p0': 'Invoice 42', 'p1': '  '});
      final job = BatchOcrJob(engine: engine, pages: _pages(3));

      await job.start();

      expect([for (final r in job.results) r.status], [OcrPageStatus.done, OcrPageStatus.empty, OcrPageStatus.failed]);
      expect(job.results.first.text, 'Invoice 42');
      expect(job.results.first.revision, const EditRecipe().cacheKey);
      expect(job.complete, isTrue);
    });

    test('cancel stops unstarted pages and keeps finished results', () async {
      final engine = _FakeOcr(texts: {'p0': 'a', 'p1': 'b', 'p2': 'c'});
      engine.hold['p1'] = Completer<void>();
      final job = BatchOcrJob(engine: engine, pages: _pages(3));

      final run = job.start();
      await Future<void>.delayed(Duration.zero);
      expect(job.currentNumber, 2);
      job.cancel();
      engine.hold['p1']!.complete();
      await run;

      expect(
        [for (final r in job.results) r.status],
        [OcrPageStatus.done, OcrPageStatus.done, OcrPageStatus.cancelled],
      );
      expect(engine.read, ['p0', 'p1']);
    });

    test('retry runs only failed and cancelled pages', () async {
      final engine = _FakeOcr(texts: {'p0': 'a'});
      final job = BatchOcrJob(engine: engine, pages: _pages(2));
      await job.start();
      expect(job.results.last.status, OcrPageStatus.failed);

      engine.texts = {'p0': 'a', 'p1': 'b'};
      engine.read.clear();
      await job.retry();

      expect(engine.read, ['p1']);
      expect([for (final r in job.results) r.status], [OcrPageStatus.done, OcrPageStatus.done]);
    });

    test('the default engine reports OCR as unavailable with a reason', () async {
      final c = await const UnavailableOcrEngine().capability('en');
      expect(c.readiness, OcrReadiness.unavailable);
      expect(c.reason, contains('not available'));
    });
  });

  group('Batch OCR screen', () {
    final harness = ScreenHarness();
    tearDown(harness.dispose);

    testWidgets('without an engine it explains why and leaves pages alone', (tester) async {
      await tester.runAsync(() => harness.setUp(pageCount: 2));
      await harness.pumpRoute(tester, (_) => const BatchReviewScreen());

      await tester.tap(find.text('OCR'));
      await harness.settle(tester);

      expect(find.text('2 selected pages'), findsOneWidget);
      expect(find.textContaining('not available in this version'), findsOneWidget);
      expect(find.textContaining('Recognize text on'), findsNothing);
    });

    testWidgets('download, run, then retry the failed page', (tester) async {
      final engine = _FakeOcr(readiness: OcrReadiness.needsDownload);
      await tester.runAsync(
        () => harness.setUp(pageCount: 3, overrides: [ocrEngineProvider.overrideWithValue(engine)]),
      );
      final ids = [for (final p in harness.pages) p.id];
      engine.texts = {ids[0]: 'Hello world', ids[1]: ''};
      await harness.pumpRoute(tester, (_) => BatchOcrScreen(pageIds: ids));

      expect(find.text('Download English OCR to continue'), findsOneWidget);
      await tester.tap(find.text('Download English OCR'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recognize text on 3 pages'));
      await tester.pumpAndSettle();
      expect(find.text('Finished: 1 with text, 1 without text, 1 not read'), findsOneWidget);
      expect(find.text('Page 1: Text found'), findsOneWidget);
      expect(find.text('Hello world'), findsOneWidget);
      expect(find.text('Page 2: No text found'), findsOneWidget);
      expect(find.text('Page 3: Failed'), findsOneWidget);

      engine.texts = {...engine.texts, ids[2]: 'Total'};
      await tester.tap(find.text('Retry 1 page'));
      await tester.pumpAndSettle();
      expect(find.text('Finished: 2 with text, 1 without text, 0 not read'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });
  });
}
