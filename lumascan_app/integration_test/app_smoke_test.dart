// Runs the real app on an iOS simulator or a phone, with the real plugins and
// storage, so it catches what the widget tests in test/ cannot: a plugin that
// fails to load on iOS, a missing Info.plist key, or a crash at start-up.
//
//   flutter test integration_test -d <device id>
//
// The camera and the system pickers are not opened: the simulator has no
// document camera, and system sheets are outside Flutter's reach.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lumascan/app/app.dart';
import 'package:lumascan/app/shell.dart';
import 'package:lumascan/features/onboarding/onboarding_screen.dart';

/// Pumps until [finder] shows up, for screens that wait on disk reads.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $finder');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app starts, gets past the intro and opens every tab', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LumaScanApp()));
    await pumpUntilFound(tester, find.byWidgetPredicate((w) => w is OnboardingScreen || w is AppShell));

    // A fresh install shows the intro; a reused simulator may have seen it.
    if (find.byType(OnboardingScreen).evaluate().isNotEmpty) {
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No thanks'));
      await tester.pumpAndSettle();
    }

    await pumpUntilFound(tester, find.byType(AppShell));
    for (final label in ['Scan', 'Import', 'Edit PDF']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.bySemanticsLabel('Library'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel('Tools'));
    await tester.pumpAndSettle();
    expect(find.text('Merge PDFs'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('Appearance'))).brightness, Brightness.dark);
    // Put it back so a run on a real phone leaves its setting alone.
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Home'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Scan'), findsOneWidget);
  });
}
