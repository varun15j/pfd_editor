import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/purchases.dart';
import 'package:lumascan/app/store_config.dart';
import 'package:lumascan/data/purchases/app_store_purchase_service.dart';
import 'package:lumascan/data/purchases/google_play_purchase_service.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/domain/purchases.dart';
import 'package:lumascan/features/plans/paywall_screen.dart';
import 'package:lumascan/ui/upgrade_dialog.dart';

import 'support/memory_stores.dart';

/// A store that answers with whatever the test sets.
class FakePurchaseService implements PurchaseService {
  FakePurchaseService({this.available = true, this.owned = const {}, List<PlanOffer>? offers})
    : offers = offers ?? _offers;

  bool available;
  Set<AppPlan> owned;
  List<PlanOffer> offers;
  bool refreshFails = false;
  final bought = <(PlanOffer, AppPlan)>[];
  final _updates = StreamController<PurchaseUpdate>.broadcast(sync: true);

  static final _offers = [
    for (final plan in [AppPlan.pro, AppPlan.gold])
      for (final period in PlanPeriod.values)
        PlanOffer(
          plan: plan,
          period: period,
          price: '₹${plan == AppPlan.pro ? 99 : 199}${period == PlanPeriod.yearly ? '0' : ''}',
          trial: plan == AppPlan.pro && period == PlanPeriod.yearly ? '7-day free trial' : null,
          storeData: '${plan.name}-${period.name}',
        ),
  ];

  void send(PurchaseUpdate update) => _updates.add(update);

  @override
  String get storeName => 'Google Play';

  @override
  Stream<PurchaseUpdate> get updates => _updates.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<PlanOffer>> loadOffers() async => offers;

  @override
  Future<void> refresh() async {
    if (refreshFails) throw StateError('offline');
    send(OwnedPlans(owned));
  }

  @override
  Future<void> buy(PlanOffer offer, {required AppPlan owned}) async => bought.add((offer, owned));

  @override
  Future<void> openManageSubscriptions() async {}

  @override
  void dispose() => _updates.close();
}

void main() {
  late FakePurchaseService store;
  late MemoryPlanCacheStore cache;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore()),
        purchaseServiceProvider.overrideWithValue(store),
        planCacheStoreProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    store = FakePurchaseService();
    cache = MemoryPlanCacheStore();
  });

  test('the best plan wins, and no plan means Basic', () {
    expect(bestPlan(const []), AppPlan.basic);
    expect(bestPlan(const [AppPlan.pro, AppPlan.gold]), AppPlan.gold);
  });

  test('at start the plan comes from the store and is saved', () async {
    store.owned = {AppPlan.pro};
    final container = makeContainer();
    await container.read(purchasesProvider.notifier).started;
    expect(container.read(purchasedPlanProvider), AppPlan.pro);
    expect(container.read(planProvider), AppPlan.pro);
    expect(cache.plan, AppPlan.pro);
    expect(container.read(purchasesProvider).offers, hasLength(4));
  });

  test('offline at start keeps the saved plan', () async {
    cache.plan = AppPlan.gold;
    store.refreshFails = true;
    final container = makeContainer();
    await container.read(purchasesProvider.notifier).started;
    expect(container.read(purchasedPlanProvider), AppPlan.gold);
  });

  test('a plan that ended in the store drops back at the next start', () async {
    cache.plan = AppPlan.gold;
    store.owned = {AppPlan.pro};
    final container = makeContainer();
    await container.read(purchasesProvider.notifier).started;
    expect(container.read(purchasedPlanProvider), AppPlan.pro);
    expect(cache.plan, AppPlan.pro);
  });

  test('no store on the device: Basic, nothing to buy', () async {
    store.available = false;
    final container = makeContainer();
    await container.read(purchasesProvider.notifier).started;
    expect(container.read(purchasesProvider).available, isFalse);
    expect(container.read(purchasedPlanProvider), AppPlan.basic);
  });

  test('buying passes the owned plan, and the bought plan unlocks', () async {
    store.owned = {AppPlan.pro};
    final container = makeContainer();
    await container.read(purchasesProvider.notifier).started;
    final gold = store.offers.firstWhere((o) => o.plan == AppPlan.gold);
    await container.read(purchasesProvider.notifier).buy(gold);
    expect(store.bought.single, (gold, AppPlan.pro), reason: 'Play replaces the Pro subscription');

    store.send(const PurchasePending(AppPlan.gold));
    expect(container.read(purchasesProvider).pending, isTrue);
    expect(container.read(purchasedPlanProvider), AppPlan.pro, reason: 'nothing unlocks while pending');

    store.send(const PlanBought(AppPlan.gold));
    expect(container.read(purchasedPlanProvider), AppPlan.gold);
    expect(container.read(purchasesProvider).pending, isFalse);
    expect(cache.plan, AppPlan.gold);
  });

  test('restore reports what it found', () async {
    final container = makeContainer();
    await container.read(purchasesProvider.notifier).started;
    await container.read(purchasesProvider.notifier).restore();
    expect(container.read(purchasesProvider).notice?.text, contains('No Pro or Gold plan'));

    store.owned = {AppPlan.gold};
    await container.read(purchasesProvider.notifier).restore();
    expect(container.read(purchasedPlanProvider), AppPlan.gold);
    expect(container.read(purchasesProvider).notice?.text, 'Restored: you are on Gold.');

    store.refreshFails = true;
    await container.read(purchasesProvider.notifier).restore();
    expect(container.read(purchasedPlanProvider), AppPlan.gold);
    expect(container.read(purchasesProvider).notice?.text, contains('Could not reach Google Play'));
  });

  test('the debug plan still wins over the store plan in debug builds', () async {
    store.owned = {AppPlan.gold};
    final container = makeContainer();
    await container.read(purchasesProvider.notifier).started;
    container.read(appSettingsProvider.notifier).setDebugPlan(AppPlan.basic);
    expect(container.read(planProvider), AppPlan.basic);
    expect(container.read(purchasedPlanProvider), AppPlan.gold);
  });

  group('paywall', () {
    Future<ProviderContainer> pumpPaywall(WidgetTester tester, {AppPlan? highlight}) async {
      // A tall screen, so every plan card and the buttons under the feature
      // lists are built without scrolling.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = makeContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: PaywallScreen(highlight: highlight)),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('lists the store prices and buys the tapped one', (tester) async {
      await pumpPaywall(tester);
      expect(find.text('You are on Basic.'), findsOneWidget);
      expect(find.text('Monthly · ₹99 / month'), findsOneWidget);
      expect(find.text('Yearly · ₹1990 / year'), findsOneWidget);
      expect(find.text('7-day free trial'), findsOneWidget);

      await tester.tap(find.text('Monthly · ₹99 / month'));
      await tester.pump();
      expect(store.bought.single.$1.plan, AppPlan.pro);
    });

    testWidgets('on Pro only Gold can be bought, as an upgrade', (tester) async {
      store.owned = {AppPlan.pro};
      await pumpPaywall(tester);
      expect(find.text('Your plan'), findsOneWidget);
      expect(find.textContaining('₹99'), findsNothing);
      expect(find.text('Upgrade: Yearly · ₹1990 / year'), findsOneWidget);
      expect(find.text('Manage subscription'), findsOneWidget);
    });

    testWidgets('says when plans cannot be bought on this device', (tester) async {
      store.available = false;
      await pumpPaywall(tester);
      expect(find.textContaining('Plans cannot be bought on this device'), findsOneWidget);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Restore purchases')).onPressed, isNull);
    });

    testWidgets('shows store messages', (tester) async {
      await pumpPaywall(tester);
      store.send(const PurchaseFailed('The purchase did not go through.'));
      await tester.pump();
      expect(find.text('The purchase did not go through.'), findsOneWidget);
    });
  });

  testWidgets('the upgrade pop-up opens the plans screen', (tester) async {
    final container = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => ensurePlan(context, ref, PlanFeature.textPdf, what: 'Text PDF'),
              child: const Text('Go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Upgrade to Pro'));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsOneWidget);
  });

  group('Google Play', () {
    const config = GooglePlayStoreConfig(
      subscriptions: {'lumascan_pro': AppPlan.pro, 'lumascan_gold': AppPlan.gold},
      basePlans: {'pro-monthly': PlanPeriod.monthly, 'pro-yearly': PlanPeriod.yearly, 'gold-yearly': PlanPeriod.yearly},
    );

    PricingPhaseWrapper phase(String price, int micros, String period) => PricingPhaseWrapper(
      billingCycleCount: 0,
      billingPeriod: period,
      formattedPrice: price,
      priceAmountMicros: micros,
      priceCurrencyCode: 'INR',
      recurrenceMode: RecurrenceMode.infiniteRecurring,
    );

    SubscriptionOfferDetailsWrapper offer(String basePlan, List<PricingPhaseWrapper> phases, {String? offerId}) =>
        SubscriptionOfferDetailsWrapper(
          basePlanId: basePlan,
          offerId: offerId,
          offerTags: const [],
          offerIdToken: '$basePlan/${offerId ?? 'base'}',
          pricingPhases: phases,
        );

    List<GooglePlayProductDetails> product(String id, List<SubscriptionOfferDetailsWrapper> offers) =>
        GooglePlayProductDetails.fromProductDetails(
          ProductDetailsWrapper(
            description: '',
            name: id,
            productId: id,
            productType: ProductType.subs,
            title: id,
            subscriptionOfferDetails: offers,
          ),
        );

    test('one offer per base plan, priced at the renewing price, using a free trial when there is one', () {
      final details = [
        ...product('lumascan_gold', [
          offer('gold-yearly', [phase('₹1,499.00', 1499000000, 'P1Y')]),
          offer('gold-monthly', [phase('₹199.00', 199000000, 'P1M')]),
        ]),
        ...product('lumascan_pro', [
          offer('pro-monthly', [phase('₹99.00', 99000000, 'P1M')]),
          offer('pro-yearly', [phase('₹799.00', 799000000, 'P1Y')]),
          offer('pro-yearly', [phase('Free', 0, 'P7D'), phase('₹799.00', 799000000, 'P1Y')], offerId: 'trial'),
        ]),
        ...product('other_product', [
          offer('pro-monthly', [phase('₹1.00', 1000000, 'P1M')]),
        ]),
      ];
      final offers = GooglePlayPurchaseService.offersFrom(details, config);
      expect(
        [for (final o in offers) (o.plan, o.period, o.price, o.trial)],
        [
          (AppPlan.pro, PlanPeriod.monthly, '₹99.00', null),
          (AppPlan.pro, PlanPeriod.yearly, '₹799.00', '7-day free trial'),
          (AppPlan.gold, PlanPeriod.yearly, '₹1,499.00', null),
        ],
        reason: 'gold-monthly is not in this config, other_product is not ours',
      );
      expect((offers[1].storeData as GooglePlayProductDetails).offerToken, 'pro-yearly/trial');
    });

    test('owned plans leave out pending purchases and unknown products', () {
      GooglePlayPurchaseDetails purchase(String product, PurchaseStateWrapper state) =>
          GooglePlayPurchaseDetails.fromPurchase(
            PurchaseWrapper(
              orderId: 'o-$product',
              packageName: 'com.mobi.scanner',
              purchaseTime: 0,
              purchaseToken: 't-$product',
              signature: '',
              products: [product],
              isAutoRenewing: true,
              originalJson: '{}',
              isAcknowledged: true,
              purchaseState: state,
            ),
          ).single;
      final owned = GooglePlayPurchaseService.ownedFrom([
        purchase('lumascan_pro', PurchaseStateWrapper.purchased),
        purchase('lumascan_gold', PurchaseStateWrapper.pending),
        purchase('something_else', PurchaseStateWrapper.purchased),
      ], config);
      expect(owned.keys, [AppPlan.pro]);
    });
  });

  test('App Store: one offer per configured product, in plan and period order', () {
    ProductDetails details(String id, String price) =>
        ProductDetails(id: id, title: id, description: '', price: price, rawPrice: 0, currencyCode: 'INR');
    final offers = AppStorePurchaseService.offersFrom([
      details('lumascan.gold.monthly', '₹199'),
      details('lumascan.pro.yearly', '₹799'),
      details('lumascan.pro.monthly', '₹99'),
      details('unknown', '₹1'),
    ], storeConfig.appStore);
    expect(
      [for (final o in offers) (o.plan, o.period, o.price)],
      [
        (AppPlan.pro, PlanPeriod.monthly, '₹99'),
        (AppPlan.pro, PlanPeriod.yearly, '₹799'),
        (AppPlan.gold, PlanPeriod.monthly, '₹199'),
      ],
    );
  });
}
