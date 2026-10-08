import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/debug/plan_switcher_tile.dart';
import 'package:lumascan/domain/app_settings.dart';
import 'package:lumascan/domain/plan.dart';

import 'support/memory_stores.dart';

void main() {
  test('Pro and Gold include smart scanning; Basic does not', () {
    expect(AppPlan.basic.includes(PlanFeature.smartScan), isFalse);
    expect(AppPlan.pro.includes(PlanFeature.smartScan), isTrue);
    expect(AppPlan.gold.includes(PlanFeature.smartScan), isTrue, reason: 'Gold has everything Pro has');
  });

  test('until purchases exist, everyone is on Basic', () {
    expect(purchasedPlan, AppPlan.basic);
  });

  test('the debug plan is saved with the settings, and an unknown one is ignored', () {
    const s = AppSettings(debugPlan: AppPlan.gold);
    expect(AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>), s);
    expect(const AppSettings().toJson().containsKey('debugPlan'), isFalse);
    expect(AppSettings.fromJson(const {'debugPlan': 'platinum'}).debugPlan, isNull);
    expect(const AppSettings(debugPlan: AppPlan.pro).copyWith(debugPlan: null).debugPlan, isNull);
  });

  group('plan provider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(overrides: [appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore())]);
      addTearDown(container.dispose);
    });

    test('follows the real plan until a debug plan is picked', () {
      expect(container.read(planProvider), purchasedPlan);
      expect(container.read(planIncludesProvider(PlanFeature.smartScan)), isFalse);

      container.read(appSettingsProvider.notifier).setDebugPlan(AppPlan.pro);
      expect(container.read(planProvider), AppPlan.pro);
      expect(container.read(planIncludesProvider(PlanFeature.smartScan)), isTrue);

      container.read(appSettingsProvider.notifier).setDebugPlan(null);
      expect(container.read(planProvider), purchasedPlan);
    });
  });

  testWidgets('the debug panel switches the plan', (tester) async {
    final container = ProviderContainer(
      overrides: [appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: PlanSwitcherTile())),
      ),
    );
    expect(find.text('Behaving as the real plan: Basic.'), findsOneWidget);

    await tester.tap(find.text('Pro'));
    await tester.pump();
    expect(container.read(planProvider), AppPlan.pro);
    expect(find.text('Behaving as Pro (the real plan is Basic).'), findsOneWidget);

    await tester.tap(find.text('Gold'));
    await tester.pump();
    expect(container.read(planProvider), AppPlan.gold);

    await tester.tap(find.text('Real'));
    await tester.pump();
    expect(container.read(planProvider), AppPlan.basic);
    expect(container.read(appSettingsProvider).debugPlan, isNull);
  });
}
