import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/features/batch_edit/batch_review_screen.dart';
import 'package:lumascan/features/crop/crop_screen.dart';
import 'package:lumascan/features/export/export_sheet.dart';
import 'package:lumascan/features/filters/filter_screen.dart';
import 'package:lumascan/features/markup/markup_screen.dart';
import 'package:lumascan/features/markup/markup_style.dart';
import 'package:lumascan/features/merge/merge_screen.dart';
import 'package:lumascan/features/pdf_editor/pdf_editor_screen.dart';
import 'package:lumascan/pdf_edit/pdf_edit_controller.dart';
import 'package:lumascan/features/pages/pages_screen.dart';

import 'support/screen_harness.dart';

void main() {
  final harness = ScreenHarness();

  final screens = <String, Future<void> Function(WidgetTester, Brightness, double)>{
    'Review': (t, b, s) => harness.pump(t, const PagesScreen(), brightness: b, textScale: s),
    'Review list': (t, b, s) async {
      await harness.pump(t, const PagesScreen(), brightness: b, textScale: s);
      await t.tap(find.byTooltip('Change view'));
      await t.pumpAndSettle();
      await t.tap(find.text('List view'), warnIfMissed: false);
      await harness.settle(t);
    },
    'Review gallery': (t, b, s) async {
      await harness.pump(t, const PagesScreen(), brightness: b, textScale: s);
      await t.tap(find.byTooltip('Change view'));
      await t.pumpAndSettle();
      await t.tap(find.text('Gallery view'), warnIfMissed: false);
      await harness.settle(t);
    },
    'Markup': (t, b, s) => harness.pumpRoute(
      t,
      (_) => MarkupScreen(pageId: harness.pages.first.id),
      brightness: b,
      textScale: s,
    ),
    'PDF editor': (t, b, s) {
      harness.container
          .read(pdfEditControllerProvider.notifier)
          .open(path: '/tmp/source.pdf', name: 'Lease.pdf', pageSizes: const [(612, 792), (612, 792)]);
      return harness.pump(
        t,
        PdfEditorScreen(pageImage: (page, {thumbnail = false}) => const ColoredBox(color: Colors.white)),
        brightness: b,
        textScale: s,
      );
    },
    'Batch review': (t, b, s) => harness.pumpRoute(t, (_) => const BatchReviewScreen(), brightness: b, textScale: s),
    'Merge': (t, b, s) => harness.pumpRoute(t, (_) => const MergeScreen(), brightness: b, textScale: s),
    'Crop': (t, b, s) => harness.pumpRoute(
      t,
      (_) => CropScreen(pageId: harness.pages.first.id),
      brightness: b,
      textScale: s,
    ),
    'Enhance': (t, b, s) => harness.pumpRoute(
      t,
      (_) => FilterScreen(pageId: harness.pages.first.id),
      brightness: b,
      textScale: s,
    ),
    'Save': (t, b, s) async {
      await harness.pump(
        t,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showExportSheet(context), child: const Text('open')),
          ),
        ),
        brightness: b,
        textScale: s,
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    },
  };

  for (final brightness in Brightness.values) {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} in ${brightness.name}: guidelines', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.runAsync(harness.setUp);
        addTearDown(harness.dispose);
        await entry.value(tester, brightness, 1);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  }

  for (final entry in screens.entries) {
    testWidgets('${entry.key} fits at 200% text size', (tester) async {
      await tester.runAsync(harness.setUp);
      addTearDown(harness.dispose);
      await entry.value(tester, Brightness.light, 2);
      expect(tester.takeException(), isNull);
    });
  }

  group('screen reader', () {
    testWidgets('Enhance can compare with the original without press and hold', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.runAsync(harness.setUp);
      addTearDown(harness.dispose);
      await harness.pumpRoute(tester, (_) => FilterScreen(pageId: harness.pages.first.id));
      expect(find.bySemanticsLabel('Page preview'), findsOneWidget);
      expect(find.text('Press and hold the page to see the original'), findsOneWidget);

      Future<void> toggle() async {
        final node = tester.getSemantics(find.bySemanticsLabel(RegExp('Page preview')));
        final actions = node.getSemanticsData().customSemanticsActionIds!;
        expect(actions, hasLength(1));
        tester.semantics.performAction(
          find.semantics.byLabel(RegExp('Page preview')),
          SemanticsAction.customAction,
          args: actions.first,
        );
        await tester.pump();
      }

      await toggle();
      expect(find.text('Showing original'), findsOneWidget);
      expect(find.bySemanticsLabel('Page preview, original'), findsOneWidget);
      await toggle();
      expect(find.text('Press and hold the page to see the original'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('colour swatches have names and the chosen one is selected', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.runAsync(harness.setUp);
      addTearDown(harness.dispose);
      await harness.pumpRoute(tester, (_) => MarkupScreen(pageId: harness.pages.first.id));
      await tester.tap(find.text('Pen'));
      await harness.settle(tester);
      for (final name in MarkupStyle.paletteNames) {
        expect(find.bySemanticsLabel('$name ink'), findsOneWidget);
      }
      expect(tester.getSemantics(find.bySemanticsLabel('Black ink')).flagsCollection.isSelected, Tristate.isTrue);
      expect(tester.getSemantics(find.bySemanticsLabel('Blue ink')).flagsCollection.isSelected, Tristate.isFalse);
      handle.dispose();
    });
  });
}
