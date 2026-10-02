import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/app.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/app/theme.dart';
import 'package:lumascan/domain/scanner_service.dart';
import 'package:lumascan/ui/state_views.dart';

class _BlockedScanner implements ScannerService {
  @override
  Future<List<String>> scan({required ScanSource source, int maxPages = 100}) async =>
      throw const ScannerPermissionDenied(permanently: true);

  @override
  Future<void> cleanUp() async {}
}

Future<void> pumpApp(WidgetTester tester, {List overrides = const [], double textScale = 1}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.6;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(ProviderScope(overrides: [...overrides], child: const LumaScanApp()));
  await tester.pumpAndSettle();
}

/// WCAG relative-luminance contrast ratio.
double contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final la = lum(a), lb = lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('app shell', () {
    testWidgets('home offers scan, import and PDF editing', (tester) async {
      await pumpApp(tester);
      expect(find.text('LumaScan'), findsOneWidget);
      for (final label in ['Scan', 'Import', 'Edit PDF']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(find.text('Your scans will show up here.'), findsOneWidget);
      expect(find.byTooltip('Scan a document'), findsOneWidget);
    });

    testWidgets('bottom bar switches between the four tabs', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.bySemanticsLabel('Library'));
      await tester.pumpAndSettle();
      expect(find.text('No saved documents yet'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Tools'));
      await tester.pumpAndSettle();
      expect(find.text('Edit and sign a PDF'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Scan something new'), findsOneWidget);
    });

    testWidgets('selected tab is announced as selected', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      expect(tester.getSemantics(find.bySemanticsLabel('Home')), isSemantics(isSelected: true, isButton: true));
      expect(tester.getSemantics(find.bySemanticsLabel('Library')), isSemantics(isSelected: false, isButton: true));
      handle.dispose();
    });

    testWidgets('blocked camera explains and links to Settings', (tester) async {
      await pumpApp(tester, overrides: [scannerServiceProvider.overrideWithValue(_BlockedScanner())]);
      await tester.tap(find.bySemanticsLabel('Scan'));
      await tester.pumpAndSettle();
      expect(find.text('Camera access needed'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('the centre Scan button uses the same camera flow', (tester) async {
      await pumpApp(tester, overrides: [scannerServiceProvider.overrideWithValue(_BlockedScanner())]);
      await tester.tap(find.byTooltip('Scan a document'));
      await tester.pumpAndSettle();
      expect(find.text('Camera access needed'), findsOneWidget);
    });

    testWidgets('appearance setting switches to the dark theme', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      final context = tester.element(find.text('Appearance'));
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(LumaColors.of(context).background, LumaColors.dark.background);
    });

    testWidgets('home and tabs fit at 200% text size', (tester) async {
      await pumpApp(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      for (final tab in ['Library', 'Tools', 'Settings']) {
        await tester.tap(find.bySemanticsLabel(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
    });

    testWidgets('bottom bar items and quick actions are at least 48 dp tall', (tester) async {
      await pumpApp(tester);
      for (final label in ['Home', 'Library', 'Tools', 'Settings', 'Scan', 'Import', 'Edit PDF']) {
        expect(tester.getSize(find.bySemanticsLabel(label)).height, greaterThanOrEqualTo(minTapTarget), reason: label);
      }
    });
  });

  group('design tokens', () {
    for (final (name, c) in [('light', LumaColors.light), ('dark', LumaColors.dark)]) {
      test('$name text and actions meet WCAG AA contrast', () {
        final pairs = {
          'ink on surface': (c.ink, c.surface),
          'ink on background': (c.ink, c.background),
          'muted on surface': (c.muted, c.surface),
          'muted on background': (c.muted, c.background),
          'muted on raised': (c.muted, c.surfaceRaised),
          'on-accent on accent': (c.onAccent, c.accent),
          'accent on surface': (c.accent, c.surface),
          'on-premium on premium': (c.onPremium, c.premium),
          'danger on surface': (c.danger, c.surface),
        };
        pairs.forEach((label, p) {
          expect(contrast(p.$1, p.$2), greaterThanOrEqualTo(4.5), reason: '$name $label');
        });
      });
    }
  });

  group('shared state widgets', () {
    Future<void> pumpIn(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: buildLumaTheme(Brightness.light),
        home: Scaffold(body: child),
      ),
    );

    testWidgets('empty state runs its action', (tester) async {
      var tapped = 0;
      await pumpIn(
        tester,
        EmptyState(
          icon: Icons.inbox,
          title: 'Nothing here',
          message: 'Add one',
          actionLabel: 'Add',
          onAction: () => tapped++,
        ),
      );
      await tester.tap(find.text('Add'));
      expect(tapped, 1);
    });

    testWidgets('error state offers retry', (tester) async {
      var retried = 0;
      await pumpIn(tester, ErrorState(message: 'Could not load', onRetry: () => retried++));
      await tester.tap(find.text('Try again'));
      expect(retried, 1);
    });

    testWidgets('loading list is announced once', (tester) async {
      await pumpIn(tester, const LoadingList(label: 'Loading documents'));
      expect(find.bySemanticsLabel('Loading documents'), findsOneWidget);
    });

    testWidgets('premium badge says Premium, not colour alone', (tester) async {
      await pumpIn(tester, const Center(child: PremiumBadge()));
      expect(find.text('Premium'), findsOneWidget);
      expect(find.byIcon(Icons.workspace_premium_outlined), findsOneWidget);
    });
  });
}
