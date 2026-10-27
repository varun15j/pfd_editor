// Store settings for buying Pro and Gold. Edit this file to change product
// IDs, which plan each product unlocks, and the legal links on the paywall.
//
// Product IDs must match the products created in each store exactly, and
// cannot be changed in the store once created. Prices are not set here:
// each store sends them in the buyer's own currency.
//
// Google Play (Play Console > Monetize with Play > Subscriptions): one
// subscription per plan, each with a monthly and a yearly base plan.
//
// App Store (App Store Connect > Subscriptions): one subscription group
// holding one product per plan and period. Put Gold above Pro in the group's
// ranking, so moving from Pro to Gold is an upgrade that starts at once.
//
// Setup steps for both stores are in docs/in-app-purchases.md.
import '../domain/plan.dart';
import '../domain/purchases.dart';

/// Google Play products.
class GooglePlayStoreConfig {
  const GooglePlayStoreConfig({required this.subscriptions, required this.basePlans});

  /// Subscription product ID to the plan it unlocks.
  final Map<String, AppPlan> subscriptions;

  /// Base plan ID to how often it renews. Base plans not listed here are
  /// not shown on the paywall.
  final Map<String, PlanPeriod> basePlans;
}

/// App Store products.
class AppStoreConfig {
  const AppStoreConfig({required this.products});

  /// Product ID to the plan and period it sells.
  final Map<String, (AppPlan, PlanPeriod)> products;
}

class StoreConfig {
  const StoreConfig({
    required this.googlePlay,
    required this.appStore,
    required this.termsUrl,
    required this.privacyUrl,
  });

  final GooglePlayStoreConfig googlePlay;
  final AppStoreConfig appStore;

  /// Terms of use and privacy policy, linked under the buy buttons. Both
  /// stores require them on a subscription screen before release. An empty
  /// link is left out.
  final String termsUrl;
  final String privacyUrl;
}

// Edit the values here.
const storeConfig = StoreConfig(
  googlePlay: GooglePlayStoreConfig(
    subscriptions: {'lumascan_pro': AppPlan.pro, 'lumascan_gold': AppPlan.gold},
    basePlans: {
      'pro-monthly': PlanPeriod.monthly,
      'pro-yearly': PlanPeriod.yearly,
      'gold-monthly': PlanPeriod.monthly,
      'gold-yearly': PlanPeriod.yearly,
    },
  ),
  appStore: AppStoreConfig(
    products: {
      'lumascan.pro.monthly': (AppPlan.pro, PlanPeriod.monthly),
      'lumascan.pro.yearly': (AppPlan.pro, PlanPeriod.yearly),
      'lumascan.gold.monthly': (AppPlan.gold, PlanPeriod.monthly),
      'lumascan.gold.yearly': (AppPlan.gold, PlanPeriod.yearly),
    },
  ),
  termsUrl: '',
  privacyUrl: '',
);
