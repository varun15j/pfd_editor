import 'plan.dart';

/// How often a plan is paid for.
enum PlanPeriod {
  monthly('Monthly', 'month'),
  yearly('Yearly', 'year');

  const PlanPeriod(this.label, this.unit);

  final String label;

  /// "month" in "₹99 / month".
  final String unit;
}

/// One way to buy a plan, as the store offers it: Pro monthly, Gold yearly
/// with a free trial, and so on. Prices come from the store, already in the
/// buyer's currency, and are never written in the app.
class PlanOffer {
  const PlanOffer({required this.plan, required this.period, required this.price, this.trial, required this.storeData});

  final AppPlan plan;
  final PlanPeriod period;

  /// The store's price text, such as "₹99.00".
  final String price;

  /// A free trial the buyer can get, such as "7-day free trial", or null.
  final String? trial;

  /// The store's own product object, used by the store class to buy it.
  final Object storeData;
}

/// What a store reports while the app runs.
sealed class PurchaseUpdate {
  const PurchaseUpdate();
}

/// Every plan the store account owns right now, after asking the store at
/// start or for Restore purchases. Plans missing from it have ended.
class OwnedPlans extends PurchaseUpdate {
  const OwnedPlans(this.plans);

  final Set<AppPlan> plans;
}

/// A purchase went through (or one made earlier finished late) and is unlocked.
class PlanBought extends PurchaseUpdate {
  const PlanBought(this.plan);

  final AppPlan plan;
}

/// The payment has started but is not finished yet, as with some UPI and
/// cash payments. Nothing is unlocked until it completes.
class PurchasePending extends PurchaseUpdate {
  const PurchasePending(this.plan);

  final AppPlan? plan;
}

class PurchaseFailed extends PurchaseUpdate {
  const PurchaseFailed(this.message);

  final String message;
}

class PurchaseCancelled extends PurchaseUpdate {
  const PurchaseCancelled();
}

/// The best of [plans], or Basic when there are none.
AppPlan bestPlan(Iterable<AppPlan> plans) =>
    plans.fold(AppPlan.basic, (best, plan) => plan.index > best.index ? plan : best);

/// Buying and restoring plans through the phone's app store. Google Play and
/// the App Store each have their own class behind this, so the rest of the
/// app never knows which store it talks to.
abstract class PurchaseService {
  /// "Google Play" or "App Store", for messages such as where to cancel.
  String get storeName;

  /// Everything the store reports. Listen from app start, so purchases that
  /// finish while no screen is waiting for them are not missed.
  Stream<PurchaseUpdate> get updates;

  /// Whether the store can be used on this device now.
  Future<bool> isAvailable();

  /// The plans the store sells, with their prices.
  Future<List<PlanOffer>> loadOffers();

  /// Asks the store which plans this account owns and reports them as
  /// [OwnedPlans]. Throws when the store cannot answer, such as when offline.
  Future<void> refresh();

  /// Starts buying [offer]. The result arrives on [updates]. [owned] is the
  /// plan the store last reported, so an upgrade can replace it.
  Future<void> buy(PlanOffer offer, {required AppPlan owned});

  /// Opens the store's page for cancelling or changing a subscription.
  Future<void> openManageSubscriptions();

  void dispose();
}

/// For devices with no supported store (desktop, tests): nothing to buy.
class NoStorePurchaseService implements PurchaseService {
  @override
  String get storeName => 'the app store';

  @override
  Stream<PurchaseUpdate> get updates => const Stream.empty();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<PlanOffer>> loadOffers() async => const [];

  @override
  Future<void> refresh() async {}

  @override
  Future<void> buy(PlanOffer offer, {required AppPlan owned}) async {}

  @override
  Future<void> openManageSubscriptions() async {}

  @override
  void dispose() {}
}
