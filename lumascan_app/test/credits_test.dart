import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:lumascan/app/credit_config.dart';
import 'package:lumascan/app/credits.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/purchases.dart';
import 'package:lumascan/data/credit_store.dart';
import 'package:lumascan/data/purchases/in_app_purchase_service.dart';
import 'package:lumascan/domain/credits.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/domain/purchases.dart';
import 'package:lumascan/features/credits/credits_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'purchases_test.dart' show FakePurchaseService;
import 'support/memory_stores.dart';

class FakeAppSharer implements AppSharer {
  bool shares = true;
  final sent = <String>[];

  @override
  Future<bool> share(String text, {Rect? origin}) async {
    sent.add(text);
    return shares;
  }
}

void main() {
  sqfliteFfiInit();

  late FakePurchaseService store;
  late MemoryCreditStore credits;

  ProviderContainer makeContainer({AppPlan plan = AppPlan.basic}) {
    final cache = MemoryPlanCacheStore()..plan = plan;
    store.owned = plan == AppPlan.basic ? {} : {plan};
    final container = ProviderContainer(
      overrides: [
        appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore()),
        purchaseServiceProvider.overrideWithValue(store),
        planCacheStoreProvider.overrideWithValue(cache),
        creditStoreProvider.overrideWithValue(credits),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<CreditsController> started(ProviderContainer container) async {
    await container.read(purchasesProvider.notifier).started;
    final controller = container.read(creditsProvider.notifier);
    await controller.started;
    return controller;
  }

  setUp(() {
    store = FakePurchaseService(owned: {});
    credits = MemoryCreditStore();
  });

  test('the rules are 100 to start, 5 per scan, import and export, 20 per share', () {
    expect(creditRules.welcomeCredits, 100);
    for (final action in CreditAction.values) {
      expect(creditRules.cost(action), 5);
    }
    expect(creditRules.shareReward, 20);
    expect(creditRules.packs.keys, unorderedEquals([AppPlan.basic, AppPlan.pro]));
  });

  test('a new install gets 100 welcome credits once', () async {
    final container = makeContainer();
    await started(container);
    expect(container.read(creditsProvider).balance, 100);
    expect(credits.entries.single.reason, CreditReason.welcome);

    // The next start reads the saved balance and gives nothing more.
    final again = makeContainer();
    await started(again);
    expect(again.read(creditsProvider).balance, 100);
    expect(credits.entries, hasLength(1));
  });

  test('20 photos use up the welcome credits, then scanning is blocked', () async {
    final container = makeContainer();
    final c = await started(container);
    for (var i = 0; i < 20; i++) {
      expect(c.trySpend(CreditAction.scan), isTrue);
    }
    expect(container.read(creditsProvider).balance, 0);
    expect(c.canAfford(CreditAction.scan), isFalse);
    expect(c.trySpend(CreditAction.scan), isFalse);
    await c.saved;
    expect(await credits.balance(), 0);
    expect(credits.entries, hasLength(21));
  });

  test('imports and exports cost 5 each, and the ledger keeps the balance after each', () async {
    final container = makeContainer();
    final c = await started(container);
    c.charge(CreditAction.importing, note: '3 pages');
    expect(c.trySpend(CreditAction.exporting, note: 'Lease'), isTrue);
    final history = container.read(creditsProvider).history;
    expect([for (final e in history) (e.reason, e.amount, e.balanceAfter)], [
      (CreditReason.exporting, -5, 90),
      (CreditReason.importing, -5, 95),
      (CreditReason.welcome, 100, 100),
    ]);
  });

  test('a charge for work already done stops at 0', () async {
    credits = MemoryCreditStore(balance: 7);
    final container = makeContainer();
    final c = await started(container);
    c.charge(CreditAction.scan, units: 3);
    expect(container.read(creditsProvider).balance, 0);
  });

  test('a failed export gives its credits back', () async {
    final container = makeContainer();
    final c = await started(container);
    expect(c.trySpend(CreditAction.exporting), isTrue);
    c.refund(CreditAction.exporting);
    expect(container.read(creditsProvider).balance, 100);
    expect(container.read(creditsProvider).history.first.reason, CreditReason.refund);
  });

  test('Gold uses no credits', () async {
    credits = MemoryCreditStore(balance: 0);
    final container = makeContainer(plan: AppPlan.gold);
    final c = await started(container);
    expect(c.unlimited, isTrue);
    expect(c.trySpend(CreditAction.scan), isTrue);
    c.charge(CreditAction.importing);
    expect(container.read(creditsProvider).balance, 0);
    expect(credits.entries, isEmpty);
  });

  test('sharing earns 20 credits once a day', () async {
    final container = makeContainer();
    final c = await started(container);
    expect(c.rewardShare(), 20);
    expect(container.read(creditsProvider).balance, 120);
    expect(c.rewardShare(), 0);
    expect(container.read(creditsProvider).balance, 120);
  });

  test('a bought pack adds its credits once, even when the store reports it twice', () async {
    final container = makeContainer();
    await started(container);
    store.send(const CreditsBought('credits_basic_100', 'GPA.1'));
    store.send(const CreditsBought('credits_basic_100', 'GPA.1'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(creditsProvider).balance, 200);
    expect(credits.entries.where((e) => e.reason == CreditReason.purchase), hasLength(1));
  });

  test('Basic and Pro see their own packs', () async {
    store.creditOffers = [
      for (final id in ['credits_basic_100', 'credits_pro_100', 'credits_pro_500'])
        CreditOffer(productId: id, credits: creditRules.packOf(id)!.credits, price: '₹$id', storeData: id),
    ];
    final container = makeContainer(plan: AppPlan.pro);
    final c = await started(container);
    await c.loadOffers();
    expect([for (final o in c.offersFor(AppPlan.basic)) o.productId], ['credits_basic_100']);
    expect([for (final o in c.offersFor(AppPlan.pro)) o.productId], ['credits_pro_100', 'credits_pro_500']);
  });

  test('store products become credit offers, smallest first, unknown ones left out', () {
    ProductDetails product(String id) =>
        ProductDetails(id: id, title: id, description: '', price: '₹1', rawPrice: 1, currencyCode: 'INR');
    final offers = InAppPurchaseService.creditOffersFrom([
      product('credits_pro_500'),
      product('lumascan_pro'),
      product('credits_pro_100'),
    ]);
    expect([for (final o in offers) o.credits], [100, 500]);
  });

  group('SQLite credits', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('lumascan_credits'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('keeps the balance and the ledger across restarts, and each purchase once', () async {
      final db = SqliteCreditStore(factory: databaseFactoryFfi, path: () async => '${tmp.path}/credits.db');
      expect(await db.balance(), isNull);
      final now = DateTime.now();
      await db.add(CreditEntry(reason: CreditReason.welcome, amount: 100, balanceAfter: 100, at: now));
      await db.add(CreditEntry(reason: CreditReason.scan, amount: -5, balanceAfter: 95, at: now, note: '1 photo'));
      final bought = CreditEntry(reason: CreditReason.purchase, amount: 100, balanceAfter: 195, at: now, purchaseId: 'p1');
      expect(await db.add(bought), isTrue);
      expect(await db.add(bought), isFalse);
      await db.close();

      final reopened = SqliteCreditStore(factory: databaseFactoryFfi, path: () async => '${tmp.path}/credits.db');
      expect(await reopened.balance(), 195);
      final history = await reopened.history();
      expect([for (final e in history) e.reason], [CreditReason.purchase, CreditReason.scan, CreditReason.welcome]);
      expect(history[1].note, '1 photo');
      await reopened.close();
    });

    test('falls back to memory when the database cannot be opened', () async {
      final broken = SqliteCreditStore(path: () async => throw StateError('no plugin'));
      await broken.add(CreditEntry(reason: CreditReason.welcome, amount: 100, balanceAfter: 100, at: DateTime.now()));
      expect(await broken.balance(), 100);
    });
  });

  testWidgets('Settings > Credits shows the balance and history, and sharing adds credits', (tester) async {
    final sharer = FakeAppSharer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore()),
          purchaseServiceProvider.overrideWithValue(store),
          planCacheStoreProvider.overrideWithValue(MemoryPlanCacheStore()),
          creditStoreProvider.overrideWithValue(credits),
          appSharerProvider.overrideWithValue(sharer),
        ],
        child: const MaterialApp(home: CreditsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('100'), findsOneWidget);
    expect(find.text('Welcome credits'), findsOneWidget);

    await tester.tap(find.textContaining('Share '));
    await tester.pumpAndSettle();
    expect(sharer.sent.single, contains(shareAppLink));
    expect(find.text('120'), findsOneWidget);
    expect(find.text('Shared the app'), findsOneWidget);
  });
}
