import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/store_config.dart';
import '../../domain/plan.dart';
import '../../domain/purchases.dart';
import 'in_app_purchase_service.dart';

/// Buying Pro and Gold through Google Play Billing (Android).
///
/// Each plan is a subscription with monthly and yearly base plans
/// ([GooglePlayStoreConfig]). Play answers "which subscriptions are active"
/// directly, so [refresh] knows when a plan has ended. Moving from Pro to
/// Gold replaces the Pro subscription, and Play credits its unused time.
class GooglePlayPurchaseService extends InAppPurchaseService {
  GooglePlayPurchaseService(this.config, {super.iap});

  final GooglePlayStoreConfig config;

  /// The active purchase of each plan, needed to replace it on upgrade.
  final _owned = <AppPlan, GooglePlayPurchaseDetails>{};

  @override
  String get storeName => 'Google Play';

  @override
  AppPlan? planOf(PurchaseDetails purchase) => config.subscriptions[purchase.productID];

  @override
  bool isValid(PurchaseDetails purchase) =>
      super.isValid(purchase) &&
      (purchase is! GooglePlayPurchaseDetails ||
          purchase.billingClientPurchase.purchaseState == PurchaseStateWrapper.purchased);

  @override
  void onOwned(PurchaseDetails purchase, AppPlan plan) {
    if (purchase is GooglePlayPurchaseDetails) _owned[plan] = purchase;
  }

  @override
  Future<List<PlanOffer>> loadOffers() async {
    final response = await iap.queryProductDetails(config.subscriptions.keys.toSet());
    if (response.error != null && response.productDetails.isEmpty) {
      throw StateError('Google Play did not return the plans: ${response.error!.message}');
    }
    return offersFrom(response.productDetails, config);
  }

  /// One offer per base plan in [config], in Pro then Gold, monthly then
  /// yearly order. When Play also returns a free-trial offer for a base plan
  /// (it only does for buyers who can get it), buying uses the trial.
  @visibleForTesting
  static List<PlanOffer> offersFrom(List<ProductDetails> details, GooglePlayStoreConfig config) {
    final offers = <PlanOffer>[];
    final seen = <String>{};
    for (final product in details.whereType<GooglePlayProductDetails>()) {
      final plan = config.subscriptions[product.id];
      final index = product.subscriptionIndex;
      final all = product.productDetails.subscriptionOfferDetails;
      if (plan == null || index == null || all == null) continue;
      final basePlanId = all[index].basePlanId;
      final period = config.basePlans[basePlanId];
      if (period == null || !seen.add('${product.id}/$basePlanId')) continue;
      // Every entry of this base plan: the plain one and any offers on it.
      final entries = details
          .whereType<GooglePlayProductDetails>()
          .where(
            (d) =>
                d.id == product.id && d.subscriptionIndex != null && all[d.subscriptionIndex!].basePlanId == basePlanId,
          )
          .toList();
      final withTrial = entries.where((d) => _freePhase(all[d.subscriptionIndex!]) != null).firstOrNull;
      final chosen =
          withTrial ?? entries.firstWhere((d) => all[d.subscriptionIndex!].offerId == null, orElse: () => product);
      final phases = all[chosen.subscriptionIndex!].pricingPhases;
      final free = withTrial == null ? null : _freePhase(all[withTrial.subscriptionIndex!]);
      offers.add(
        PlanOffer(
          plan: plan,
          period: period,
          // The last phase is the price that renews, after any trial.
          price: phases.last.formattedPrice,
          trial: free == null ? null : '${_periodText(free.billingPeriod)} free trial',
          storeData: chosen,
        ),
      );
    }
    offers.sort((a, b) => a.plan.index != b.plan.index ? a.plan.index - b.plan.index : a.period.index - b.period.index);
    return offers;
  }

  static PricingPhaseWrapper? _freePhase(SubscriptionOfferDetailsWrapper offer) =>
      offer.pricingPhases.where((p) => p.priceAmountMicros == 0).firstOrNull;

  /// "P7D" to "7-day", "P1M" to "1-month".
  static String _periodText(String iso) {
    final match = RegExp(r'^P(\d+)([DWMY])$').firstMatch(iso);
    if (match == null) return 'Free';
    const units = {'D': 'day', 'W': 'week', 'M': 'month', 'Y': 'year'};
    return '${match.group(1)}-${units[match.group(2)]}';
  }

  @override
  Future<void> refresh() async {
    final addition = iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await addition.queryPastPurchases();
    if (response.error != null) {
      throw StateError('Google Play could not list purchases: ${response.error!.message}');
    }
    final owned = ownedFrom(response.pastPurchases, config);
    _owned
      ..clear()
      ..addAll(owned);
    for (final purchase in owned.values) {
      if (purchase.pendingCompletePurchase) {
        try {
          await iap.completePurchase(purchase);
        } catch (_) {}
      }
    }
    report(OwnedPlans(owned.keys.toSet()));
  }

  /// The paid-for purchase of each plan among [purchases]. Pending ones and
  /// products not in [config] are left out.
  @visibleForTesting
  static Map<AppPlan, GooglePlayPurchaseDetails> ownedFrom(
    List<GooglePlayPurchaseDetails> purchases,
    GooglePlayStoreConfig config,
  ) => {
    for (final purchase in purchases)
      if (config.subscriptions[purchase.productID] case final plan?)
        if (purchase.billingClientPurchase.purchaseState == PurchaseStateWrapper.purchased) plan: purchase,
  };

  @override
  Future<void> buy(PlanOffer offer, {required AppPlan owned}) async {
    final details = offer.storeData as GooglePlayProductDetails;
    final current = _owned[owned];
    await iap.buyNonConsumable(
      purchaseParam: GooglePlayPurchaseParam(
        productDetails: details,
        offerToken: details.offerToken,
        changeSubscriptionParam: current == null
            ? null
            : ChangeSubscriptionParam(
                oldPurchaseDetails: current,
                // Gold starts at once; the unused Pro time lowers the first charge.
                replacementMode: ReplacementMode.chargeProratedPrice,
              ),
      ),
    );
  }

  @override
  Future<void> openManageSubscriptions() async {
    await launchUrl(
      Uri.parse('https://play.google.com/store/account/subscriptions'),
      mode: LaunchMode.externalApplication,
    );
  }
}
