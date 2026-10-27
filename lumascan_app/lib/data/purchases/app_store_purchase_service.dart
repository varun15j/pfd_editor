import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/store_config.dart';
import '../../domain/plan.dart';
import '../../domain/purchases.dart';
import 'in_app_purchase_service.dart';

/// Buying Pro and Gold through the App Store (iOS), with StoreKit 2.
///
/// Each plan and period is its own product, all in one subscription group
/// ([AppStoreConfig]), so the App Store itself swaps Pro for Gold on upgrade.
/// The App Store has no "list active subscriptions" call in the plugin:
/// [refresh] restores purchases, which with StoreKit 2 returns only the
/// current entitlements, and collects what arrives.
class AppStorePurchaseService extends InAppPurchaseService {
  AppStorePurchaseService(this.config, {super.iap, this.restoreSettle = const Duration(seconds: 1)});

  final AppStoreConfig config;

  /// How long to wait after a restore for its purchases to arrive.
  final Duration restoreSettle;

  /// Plans restored during [refresh], or null when no refresh is running.
  Set<AppPlan>? _restoring;

  @override
  String get storeName => 'App Store';

  @override
  AppPlan? planOf(PurchaseDetails purchase) => config.products[purchase.productID]?.$1;

  @override
  void onRestored(PurchaseDetails purchase, AppPlan plan) {
    final restoring = _restoring;
    restoring == null ? report(PlanBought(plan)) : restoring.add(plan);
  }

  @override
  Future<List<PlanOffer>> loadOffers() async {
    final response = await iap.queryProductDetails(config.products.keys.toSet());
    if (response.error != null && response.productDetails.isEmpty) {
      throw StateError('The App Store did not return the plans: ${response.error!.message}');
    }
    return offersFrom(response.productDetails, config);
  }

  /// One offer per product in [config], in Pro then Gold, monthly then
  /// yearly order.
  @visibleForTesting
  static List<PlanOffer> offersFrom(List<ProductDetails> details, AppStoreConfig config) {
    final offers = [
      for (final product in details)
        if (config.products[product.id] case (final plan, final period))
          PlanOffer(plan: plan, period: period, price: product.price, storeData: product),
    ];
    offers.sort((a, b) => a.plan.index != b.plan.index ? a.plan.index - b.plan.index : a.period.index - b.period.index);
    return offers;
  }

  @override
  Future<void> refresh() async {
    final restoring = _restoring = <AppPlan>{};
    try {
      await iap.restorePurchases();
      await Future<void>.delayed(restoreSettle);
      report(OwnedPlans({...restoring}));
    } finally {
      if (identical(_restoring, restoring)) _restoring = null;
    }
  }

  @override
  Future<void> buy(PlanOffer offer, {required AppPlan owned}) async {
    // The subscription group handles the upgrade; nothing to pass for it.
    await iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: offer.storeData as ProductDetails));
  }

  @override
  Future<void> openManageSubscriptions() async {
    try {
      await iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>().showManageSubscriptions();
    } catch (_) {
      await launchUrl(Uri.parse('https://apps.apple.com/account/subscriptions'), mode: LaunchMode.externalApplication);
    }
  }
}
