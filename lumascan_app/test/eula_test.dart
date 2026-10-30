import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/app_info.dart';
import 'package:lumascan/domain/app_settings.dart';
import 'package:lumascan/domain/eula.dart';
import 'package:lumascan/features/onboarding/eula_screen.dart';
import 'package:lumascan/features/onboarding/onboarding_screen.dart';
import 'package:lumascan/features/settings/settings_screen.dart';

import 'support/memory_stores.dart';
import 'support/pump_app.dart';

void main() {
  late MemoryAppSettingsStore store;

  Future<void> start(WidgetTester tester, AppSettings saved) async {
    store = MemoryAppSettingsStore(saved);
    await pumpApp(tester, settings: store);
  }

  Future<void> agree(WidgetTester tester) async {
    await tester.tap(find.text('Agree and continue'));
    await tester.pumpAndSettle();
  }

  group('at start', () {
    testWidgets('a new install sees the agreement before the intro', (tester) async {
      await start(tester, const AppSettings());
      expect(find.byType(EulaScreen), findsOneWidget);
      expect(find.text('Before you start'), findsOneWidget);
      expect(find.text('End User Licence Agreement'), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);

      await agree(tester);
      expect(find.byType(EulaScreen), findsNothing);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(store.settings.eulaAcceptedVersion, eulaVersion);
    });

    testWidgets('is not shown again once the current version is accepted', (tester) async {
      await start(tester, const AppSettings(onboardingSeen: true, eulaAcceptedVersion: eulaVersion));
      expect(find.byType(EulaScreen), findsNothing);
      expect(find.text('Docs'), findsWidgets);
    });

    testWidgets('comes back, marked as updated, when the version is raised', (tester) async {
      await start(tester, const AppSettings(onboardingSeen: true, eulaAcceptedVersion: eulaVersion - 1));
      if (eulaVersion == 1) {
        // Version 0 means never accepted, so this is the first-run screen.
        expect(find.text('Before you start'), findsOneWidget);
      } else {
        expect(find.text('We have updated our terms'), findsOneWidget);
      }
      await agree(tester);
      expect(find.byType(EulaScreen), findsNothing);
      expect(find.byType(OnboardingScreen), findsNothing, reason: 'the intro was already seen');
      expect(find.text('Docs'), findsWidgets);
      expect(store.settings.eulaAcceptedVersion, eulaVersion);
    });

    testWidgets('the update wording shows for anyone who accepted an older version', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: EulaScreen.gate(updated: true)));
      expect(find.text('We have updated our terms'), findsOneWidget);
      expect(find.textContaining('new End User Licence Agreement'), findsOneWidget);
    });

    testWidgets('declining explains the agreement is needed and keeps it open', (tester) async {
      await start(tester, const AppSettings());
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      expect(find.text('Agreement needed'), findsOneWidget);
      await tester.tap(find.text('Read again'));
      await tester.pumpAndSettle();
      expect(find.byType(EulaScreen), findsOneWidget);
      expect(store.settings.eulaAcceptedVersion, 0);
    });
  });

  group('the text', () {
    testWidgets('every section is shown, numbered, with the version and date', (tester) async {
      await start(tester, const AppSettings());
      expect(find.text('Version $eulaVersion, effective $eulaEffectiveDate'), findsOneWidget);
      // A screen tall enough to lay out the whole agreement at once.
      tester.view.physicalSize = const Size(1080, 40000);
      await tester.pumpAndSettle();
      for (final (i, section) in eulaSections.indexed) {
        expect(find.text('${i + 1}. ${section.heading}'), findsOneWidget);
      }
    });

    test('names the app only through appName and covers the essentials', () {
      final all = [eulaIntro, for (final s in eulaSections) '${s.heading}\n${s.body}'].join('\n');
      expect(all, contains(appName));
      for (final topic in ['Licence', 'Plans, purchases and subscriptions', 'Privacy', 'Governing law']) {
        expect(eulaSections.map((s) => s.heading), contains(topic));
      }
      expect(all, contains('Apple'));
    });
  });

  group('settings', () {
    test('accepted version is saved and read back, and missing means never accepted', () {
      const s = AppSettings(eulaAcceptedVersion: 3);
      expect(AppSettings.fromJson(s.toJson()).eulaAcceptedVersion, 3);
      expect(AppSettings.fromJson(const {}).eulaAcceptedVersion, 0);
      expect(const AppSettings().eulaAccepted, isFalse);
      expect(const AppSettings(eulaAcceptedVersion: eulaVersion).eulaAccepted, isTrue);
      expect(const AppSettings(eulaAcceptedVersion: eulaVersion + 1).eulaAccepted, isTrue);
    });

    testWidgets('Settings opens the agreement to read, without asking again', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      tester.view.physicalSize = const Size(1080, 7000);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terms of use'));
      await tester.pumpAndSettle();
      expect(find.byType(EulaScreen), findsOneWidget);
      expect(find.text('Agree and continue'), findsNothing);
      expect(find.text('End User Licence Agreement'), findsOneWidget);
    });
  });
}
