import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/app_info.dart';
import 'package:lumascan/app/app_lock.dart';
import 'package:lumascan/app/device_auth.dart';
import 'package:lumascan/domain/app_settings.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/features/cloud/accounts_screen.dart';

import 'support/memory_stores.dart';
import 'support/pump_app.dart';

class _FakeAuth implements DeviceAuth {
  bool available = true;
  final answers = <DeviceAuthResult>[];
  final reasons = <String>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<DeviceAuthResult> authenticate(String reason) async {
    reasons.add(reason);
    return answers.isEmpty ? DeviceAuthResult.success : answers.removeAt(0);
  }
}

void main() {
  late _FakeAuth auth;
  late DateTime now;

  setUp(() {
    auth = _FakeAuth();
    now = DateTime(2026, 10, 27, 9);
  });

  Future<MemoryAppSettingsStore> pump(WidgetTester tester, AppSettings settings) async {
    final store = MemoryAppSettingsStore(settings);
    await pumpApp(
      tester,
      settings: store,
      overrides: [deviceAuthProvider.overrideWithValue(auth), appLockClockProvider.overrideWithValue(() => now)],
    );
    return store;
  }

  Future<void> leaveFor(WidgetTester tester, Duration away) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(away);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  test('app lock is a Pro feature and its settings survive a JSON round trip', () {
    expect(AppPlan.basic.includes(PlanFeature.appLock), isFalse);
    expect(AppPlan.pro.includes(PlanFeature.appLock), isTrue);
    expect(AppPlan.gold.includes(PlanFeature.appLock), isTrue);

    const s = AppSettings(appLock: true, appLockDelay: AppLockDelay.fiveMinutes);
    expect(AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>), s);
    final old = AppSettings.fromJson(const {'version': 3});
    expect(old.appLock, isFalse, reason: 'settings saved before the app lock leave it off');
    expect(old.appLockDelay, AppLockDelay.oneMinute);
  });

  testWidgets('without the lock the app opens straight away and never asks', (tester) async {
    await pump(tester, const AppSettings(onboardingSeen: true));
    expect(find.byType(LockScreen), findsNothing);
    await leaveFor(tester, const Duration(hours: 1));
    expect(find.byType(LockScreen), findsNothing);
    expect(auth.reasons, isEmpty);
  });

  testWidgets('a locked app asks on opening and shows the app once it is the owner', (tester) async {
    auth.answers.add(DeviceAuthResult.cancelled);
    await pump(tester, const AppSettings(onboardingSeen: true, appLock: true));
    expect(find.text('$appName is locked'), findsOneWidget);
    expect(auth.reasons, hasLength(1), reason: 'the prompt opens by itself');

    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('a failed check says so and stays locked', (tester) async {
    auth.answers.add(DeviceAuthResult.failed);
    await pump(tester, const AppSettings(onboardingSeen: true, appLock: true));
    expect(find.textContaining("Couldn't check it's you"), findsOneWidget);
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('locks again only after the chosen time in the background', (tester) async {
    await pump(tester, const AppSettings(onboardingSeen: true, appLock: true));
    expect(find.byType(LockScreen), findsNothing, reason: 'unlocked on opening');

    await leaveFor(tester, const Duration(seconds: 30));
    expect(find.byType(LockScreen), findsNothing, reason: 'under a minute away');

    auth.answers.add(DeviceAuthResult.cancelled);
    await leaveFor(tester, const Duration(minutes: 2));
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('Immediately locks after any time away', (tester) async {
    await pump(tester, const AppSettings(onboardingSeen: true, appLock: true, appLockDelay: AppLockDelay.immediately));
    auth.answers.add(DeviceAuthResult.cancelled);
    await leaveFor(tester, Duration.zero);
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('the back button does not close pages behind the lock screen', (tester) async {
    await pump(tester, const AppSettings(onboardingSeen: true, appLock: true));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountsScreen), findsOneWidget);
    auth.answers.add(DeviceAuthResult.cancelled);
    await leaveFor(tester, const Duration(minutes: 5));
    expect(find.byType(LockScreen), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);

    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountsScreen), findsOneWidget, reason: 'Accounts is still open after unlocking');
  });

  testWidgets('a phone with no screen lock left turns the app lock off', (tester) async {
    auth.answers.add(DeviceAuthResult.unavailable);
    final store = await pump(tester, const AppSettings(onboardingSeen: true, appLock: true));
    expect(find.byType(LockScreen), findsNothing);
    expect(store.settings.appLock, isFalse);
  });

  group('Settings switch', () {
    Future<MemoryAppSettingsStore> openSettings(WidgetTester tester, AppSettings settings) async {
      final store = await pump(tester, settings);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Lock with fingerprint or face'), 300);
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('on Basic it offers the upgrade instead of turning on', (tester) async {
      final store = await openSettings(tester, const AppSettings(onboardingSeen: true, debugPlan: AppPlan.basic));
      await tester.tap(find.text('Lock with fingerprint or face'));
      await tester.pumpAndSettle();
      expect(find.text('Upgrade to Pro'), findsWidgets);
      expect(store.settings.appLock, isFalse);
      expect(auth.reasons, isEmpty);
    });

    testWidgets('on Pro it asks first, then turns on and offers the delay', (tester) async {
      final store = await openSettings(tester, const AppSettings(onboardingSeen: true, debugPlan: AppPlan.pro));
      await tester.tap(find.text('Lock with fingerprint or face'));
      await tester.pumpAndSettle();
      expect(auth.reasons, ['Confirm to turn on the app lock']);
      expect(store.settings.appLock, isTrue);
      expect(find.byType(LockScreen), findsNothing, reason: 'confirming counts as unlocking');
      expect(find.text('Lock again'), findsOneWidget);

      await tester.tap(find.text('Lock again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('After 5 minutes'));
      await tester.pumpAndSettle();
      expect(store.settings.appLockDelay, AppLockDelay.fiveMinutes);
    });

    testWidgets('a phone with no screen lock is told to set one', (tester) async {
      auth.available = false;
      final store = await openSettings(tester, const AppSettings(onboardingSeen: true, debugPlan: AppPlan.pro));
      await tester.tap(find.text('Lock with fingerprint or face'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Set a screen lock'), findsOneWidget);
      expect(store.settings.appLock, isFalse);
    });

    testWidgets('turning off asks first, and stays on when cancelled', (tester) async {
      final store = await openSettings(tester, const AppSettings(onboardingSeen: true, appLock: true));
      auth.answers.add(DeviceAuthResult.cancelled);
      await tester.tap(find.text('Lock with fingerprint or face'));
      await tester.pumpAndSettle();
      expect(store.settings.appLock, isTrue);

      await tester.tap(find.text('Lock with fingerprint or face'));
      await tester.pumpAndSettle();
      expect(store.settings.appLock, isFalse);
      expect(auth.reasons.last, 'Confirm to turn off the app lock');
    });
  });

  test('the channel falls back safely when the platform side is missing', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const auth = ChannelDeviceAuth();
    expect(await auth.isAvailable(), isFalse);
    expect(await auth.authenticate('x'), DeviceAuthResult.unavailable);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('lumascan/device_auth'),
      (call) async => call.method == 'isAvailable' ? true : 'cancelled',
    );
    expect(await auth.isAvailable(), isTrue);
    expect(await auth.authenticate('x'), DeviceAuthResult.cancelled);
  });
}
