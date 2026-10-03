import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/app.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/domain/app_settings.dart';
import 'package:lumascan/features/onboarding/onboarding_screen.dart';
import 'package:lumascan/features/settings/settings_screen.dart';

import 'support/memory_stores.dart';
import 'support/pump_app.dart';

void main() {
  late MemoryAppSettingsStore store;

  Future<void> firstRun(WidgetTester tester, {double textScale = 1, AppSettings? saved}) async {
    store = MemoryAppSettingsStore(saved ?? const AppSettings());
    await pumpApp(tester, settings: store, textScale: textScale);
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }

  group('first run', () {
    testWidgets('shows the intro before the app, one page at a time with dots', (tester) async {
      await firstRun(tester);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Scan anything'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 1 of 3'), findsOneWidget);

      await next(tester);
      expect(find.text('Edit and sign'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 2 of 3'), findsOneWidget);

      await next(tester);
      expect(find.text('Save and send'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 3 of 3'), findsOneWidget);
    });

    testWidgets('the last page leads to the usage-data question', (tester) async {
      await firstRun(tester);
      await next(tester);
      await next(tester);
      await next(tester);
      expect(find.text('Help improve LumaScan?'), findsOneWidget);
      expect(find.text('Share usage data'), findsOneWidget);
      expect(find.text('No thanks'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Next'), findsNothing);
    });

    testWidgets('Skip goes straight to the question instead of past it', (tester) async {
      await firstRun(tester);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('Help improve LumaScan?'), findsOneWidget);
      expect(store.settings.onboardingSeen, isFalse, reason: 'not seen until the question is answered');
    });

    testWidgets('declining continues to the app and records the answer', (tester) async {
      await firstRun(tester);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No thanks'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.text('Home'), findsWidgets);
      expect(store.settings.onboardingSeen, isTrue);
      expect(store.settings.analytics, isFalse);
    });

    testWidgets('agreeing records the answer', (tester) async {
      await firstRun(tester);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share usage data'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(store.settings.analytics, isTrue);
    });

    testWidgets('Back steps to the previous page', (tester) async {
      await firstRun(tester);
      await next(tester);
      await next(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Edit and sign'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Scan anything'), findsOneWidget);
    });

    testWidgets('is not shown again once seen', (tester) async {
      await firstRun(tester, saved: const AppSettings(onboardingSeen: true));
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.text('Home'), findsWidgets);
    });

    testWidgets('waits for the saved choice instead of flashing the intro', (tester) async {
      store = MemoryAppSettingsStore(const AppSettings(onboardingSeen: true));
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(overrides: [appSettingsStoreProvider.overrideWithValue(store)], child: const LumaScanApp()),
      );
      // First frame: nothing from either screen yet.
      expect(find.byType(OnboardingScreen), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('fits at 200% text size on every page', (tester) async {
      await firstRun(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      await next(tester);
      await next(tester);
      await next(tester);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('No thanks'));
      await tester.pumpAndSettle();
      expect(find.text('No thanks'), findsOneWidget);
    });
  });

  group('from Settings', () {
    Future<void> openSettings(WidgetTester tester, {AppSettings? saved}) async {
      store = MemoryAppSettingsStore(saved ?? const AppSettings(onboardingSeen: true));
      await pumpApp(tester, settings: store);
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1080, 7000);
      await tester.pumpAndSettle();
    }

    testWidgets('the usage-data choice can be changed, and starts off', (tester) async {
      await openSettings(tester);
      Switch field() => tester.widget<Switch>(
        find.descendant(
          of: find.widgetWithText(SwitchListTile, 'Share anonymous usage data'),
          matching: find.byType(Switch),
        ),
      );
      expect(field().value, isFalse);
      await tester.ensureVisible(find.text('Share anonymous usage data'));
      await tester.tap(find.text('Share anonymous usage data'));
      await tester.pumpAndSettle();
      expect(field().value, isTrue);
      expect(store.settings.analytics, isTrue);

      await tester.tap(find.text('Share anonymous usage data'));
      await tester.pumpAndSettle();
      expect(store.settings.analytics, isFalse);
    });

    testWidgets('Replay intro shows the intro again and returns to Settings', (tester) async {
      await openSettings(tester, saved: const AppSettings(onboardingSeen: true, analytics: true));
      await tester.ensureVisible(find.text('Replay intro'));
      await tester.tap(find.text('Replay intro'));
      await tester.pumpAndSettle();
      expect(find.text('Scan anything'), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No thanks'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(store.settings.analytics, isFalse, reason: 'the new answer replaces the old one');
    });

    testWidgets('leaving a replay with Back changes nothing', (tester) async {
      await openSettings(tester, saved: const AppSettings(onboardingSeen: true, analytics: true));
      await tester.ensureVisible(find.text('Replay intro'));
      await tester.tap(find.text('Replay intro'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(store.settings.analytics, isTrue);
    });
  });

  group('values', () {
    test('survive a JSON round trip, and no answer stays no answer', () {
      const answered = AppSettings(onboardingSeen: true, analytics: false);
      expect(AppSettings.fromJson(answered.toJson()), answered);
      expect(const AppSettings().toJson().containsKey('analytics'), isFalse);
      expect(AppSettings.fromJson(const {}).analytics, isNull);
      expect(AppSettings.fromJson(const {}).onboardingSeen, isFalse);
    });

    test('copyWith can keep, set or leave the answer', () {
      const s = AppSettings(analytics: true);
      expect(s.copyWith(onboardingSeen: true).analytics, isTrue);
      expect(s.copyWith(analytics: false).analytics, isFalse);
      expect(s.copyWith(analytics: null).analytics, isNull);
    });

    test('completing keeps an earlier answer when none is given', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore(const AppSettings(analytics: true))),
        ],
      );
      addTearDown(container.dispose);
      await container.read(appSettingsProvider.notifier).loaded;
      container.read(appSettingsProvider.notifier).completeOnboarding();
      final s = container.read(appSettingsProvider);
      expect((s.onboardingSeen, s.analytics), (true, true));
    });
  });
}
