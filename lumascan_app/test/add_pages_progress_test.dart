import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/photo_import.dart';
import 'package:lumascan/domain/ui_prefs.dart';
import 'package:lumascan/features/capture/scan_tips.dart';
import 'package:lumascan/features/pages/adding_progress.dart';
import 'package:lumascan/features/pages/pages_screen.dart';
import 'package:lumascan/features/pages/scan_controller.dart';

import 'support/fake_photos.dart';
import 'support/memory_stores.dart';
import 'support/pump_app.dart';

/// Analyses a photo only when the test lets it, so the state in the middle of
/// an import can be looked at. A name listed in [unreadable] fails.
class _GatedAnalyzer implements PhotoAnalyzer {
  _GatedAnalyzer({this.unreadable = const {}});

  final Set<String> unreadable;
  final _gates = <Completer<void>>[];
  var _next = 0;

  /// Lets the next waiting photo through.
  void release() => _gates[_next++].complete();

  int get waiting => _gates.length - _next;

  @override
  Future<CropQuad?> analyze(String path) async {
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    if (unreadable.any(path.endsWith)) throw const FormatException('corrupt');
    return null;
  }
}

PickedPhoto photo(String name) => PickedPhoto(path: '/nowhere/$name', name: name);

/// The draft screen keeps animating while page images load, so wait a fixed
/// time instead of for it to settle.
Future<void> pumpFor(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('controller', () {
    late ProviderContainer container;
    late _GatedAnalyzer analyzer;

    setUp(() {
      analyzer = _GatedAnalyzer();
      container = ProviderContainer(
        overrides: [
          photoAnalyzerProvider.overrideWithValue(analyzer),
          pageStoreProvider.overrideWithValue(NoCopyPageStore()),
          draftStoreProvider.overrideWithValue(MemoryDraftStore()),
        ],
      );
      addTearDown(container.dispose);
      container.listen(scanControllerProvider, (_, _) {});
    });

    ScanState state() => container.read(scanControllerProvider);
    Future<void> turn() => Future<void>.delayed(Duration.zero);

    test('an import reports how many pages are coming and how many are ready', () async {
      var announced = 0;
      final done = container
          .read(scanControllerProvider.notifier)
          .importPhotos([photo('a'), photo('b'), photo('c')], autoCrop: true, onAdding: () => announced++);
      await turn();
      expect(announced, 1, reason: 'told once, as soon as the count is known');
      expect(state().adding, const AddProgress(total: 3));
      expect(state().pages, isEmpty, reason: 'pages are committed together, as one undo step');

      analyzer.release();
      await turn();
      await turn();
      expect(state().adding, const AddProgress(total: 3, done: 1));
      analyzer.release();
      await turn();
      await turn();
      expect(state().adding, const AddProgress(total: 3, done: 2));
      analyzer.release();
      await done;

      expect(state().adding, isNull);
      expect(state().pages, hasLength(3));
      expect(state().canUndo, isTrue);
      expect(state().busy, isFalse);
    });

    test('an unreadable photo still counts as handled, and the progress is cleared at the end', () async {
      analyzer = _GatedAnalyzer(unreadable: {'b'});
      container.dispose();
      container = ProviderContainer(
        overrides: [
          photoAnalyzerProvider.overrideWithValue(analyzer),
          pageStoreProvider.overrideWithValue(NoCopyPageStore()),
          draftStoreProvider.overrideWithValue(MemoryDraftStore()),
        ],
      );
      addTearDown(container.dispose);
      container.listen(scanControllerProvider, (_, _) {});
      final done = container.read(scanControllerProvider.notifier).importPhotos([
        photo('a'),
        photo('b'),
      ], autoCrop: true);
      await turn();
      analyzer.release();
      await turn();
      await turn();
      analyzer.release();
      final result = await done;
      expect(result.added, 1);
      expect(state().adding, isNull);
    });

    test('nothing is announced when no photos were picked', () async {
      var announced = 0;
      await container
          .read(scanControllerProvider.notifier)
          .importPhotos(const [], autoCrop: true, onAdding: () => announced++);
      expect(announced, 0);
      expect(state().adding, isNull);
    });
  });

  group('screens', () {
    late FakePhotoPicker picker;
    late _GatedAnalyzer analyzer;

    Future<void> openImport(WidgetTester tester, {Set<String> unreadable = const {}, double textScale = 1}) async {
      analyzer = _GatedAnalyzer(unreadable: unreadable);
      await pumpApp(
        tester,
        textScale: textScale,
        prefs: MemoryUiPrefsStore(const UiPrefs(dismissedCards: {scanTipsId})),
        overrides: [
          photoPickerProvider.overrideWithValue(picker),
          photoAnalyzerProvider.overrideWithValue(analyzer),
          pageStoreProvider.overrideWithValue(NoCopyPageStore()),
        ],
      );
      await tester.tap(find.bySemanticsLabel('Import'));
      await tester.pumpAndSettle();
    }

    Future<void> step(WidgetTester tester) async {
      analyzer.release();
      await tester.pump();
      await tester.pump();
    }

    setUp(
      () => picker = FakePhotoPicker([
        for (final n in ['a', 'b', 'c', 'd']) photo('$n.jpg'),
      ]),
    );

    testWidgets('a new document opens at once with a placeholder for every page and a progress bar', (tester) async {
      await openImport(tester);
      await tester.tap(find.text('Add 4 pages'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(PagesScreen), findsOneWidget, reason: 'opened before the import is done');
      expect(find.byType(PagePlaceholder), findsNWidgets(4));
      expect(find.text('Adding 1 of 4 pages'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.descendant(of: find.byType(AddingBanner), matching: find.byType(LinearProgressIndicator)),
            )
            .value,
        0,
      );
      expect(find.text('Adding pages'), findsOneWidget);
      expect(find.text('Scan a document'), findsNothing, reason: 'not the empty state');

      await step(tester);
      await step(tester);
      expect(find.text('Adding 3 of 4 pages'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.descendant(of: find.byType(AddingBanner), matching: find.byType(LinearProgressIndicator)),
            )
            .value,
        0.5,
      );
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
      expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'the page being worked on');

      await step(tester);
      await step(tester);
      await pumpFor(tester);
      expect(find.byType(PagePlaceholder), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('4 pages'), findsOneWidget);
      expect(find.text('Added 4 pages'), findsOneWidget);
    });

    testWidgets('on an existing document the placeholders come after the pages already there', (tester) async {
      picker.photos = [photo('a.jpg')];
      await openImport(tester);
      await tester.tap(find.text('Add 1 page'));
      await tester.pump();
      await tester.pump();
      await step(tester);
      await pumpFor(tester);
      expect(find.text('1 page'), findsOneWidget);

      picker.photos = [photo('b.jpg'), photo('c.jpg'), photo('d.jpg')];
      await tester.tap(find.text('Add pages'));
      await pumpFor(tester);
      await tester.tap(find.text('Import photos'));
      await pumpFor(tester);
      await tester.tap(find.text('Add 3 pages'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(PagePlaceholder), findsNWidgets(3));
      expect(find.bySemanticsLabel('Page 2, being added'), findsOneWidget);
      expect(find.bySemanticsLabel('Page 4, being added'), findsOneWidget);
      expect(find.text('Adding 1 of 3 pages'), findsOneWidget);
      expect(find.text('1 page'), findsOneWidget, reason: 'the page already there is still shown');

      for (var i = 0; i < 3; i++) {
        await step(tester);
      }
      await pumpFor(tester);
      expect(find.byType(PagePlaceholder), findsNothing);
      expect(find.text('4 pages'), findsOneWidget);
    });

    testWidgets('the list view shows placeholders too', (tester) async {
      await openImport(tester);
      await tester.tap(find.text('Add 4 pages'));
      await tester.pump();
      await tester.pump();
      await step(tester);
      await step(tester);
      await step(tester);
      await step(tester);
      await pumpFor(tester);
      picker.photos = [photo('e.jpg'), photo('f.jpg')];
      await tester.tap(find.byTooltip('Change view'));
      await tester.pump();
      await pumpFor(tester);
      await tester.tap(find.text('List view'), warnIfMissed: false);
      await pumpFor(tester);
      await tester.tap(find.text('Add pages'));
      await pumpFor(tester);
      await tester.tap(find.text('Import photos'));
      await pumpFor(tester);
      await tester.tap(find.text('Add 2 pages'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(PagePlaceholder), findsNWidgets(2));
      expect(find.text('Page 5'), findsOneWidget);
      expect(find.text('Page 6'), findsOneWidget);
    });

    testWidgets('page view shows them in the thumbnail strip', (tester) async {
      await openImport(tester);
      await tester.tap(find.text('Add 4 pages'));
      await tester.pump();
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await step(tester);
      }
      await pumpFor(tester);
      // Page view is the default layout for a document with pages.
      picker.photos = [photo('e.jpg'), photo('f.jpg')];
      await tester.tap(find.text('Add pages'));
      await pumpFor(tester);
      await tester.tap(find.text('Import photos'));
      await pumpFor(tester);
      await tester.tap(find.text('Add 2 pages'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(PagePlaceholder), findsNWidgets(2));
      expect(find.text('Adding 1 of 2 pages'), findsOneWidget);
    });

    testWidgets('when no photo can be read the empty draft is not left open', (tester) async {
      picker.photos = [photo('a.jpg'), photo('b.jpg')];
      await openImport(tester, unreadable: {'a.jpg', 'b.jpg'});
      await tester.tap(find.text('Add 2 pages'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(PagesScreen), findsOneWidget);
      await step(tester);
      await step(tester);
      await pumpFor(tester);
      expect(find.byType(PagesScreen), findsNothing);
      expect(find.textContaining("couldn't be read"), findsOneWidget);
    });

    testWidgets('fits at 200% text size while pages are being added', (tester) async {
      await openImport(tester, textScale: 2);
      await tester.tap(find.text('Add 4 pages'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(PagePlaceholder), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  });
}
