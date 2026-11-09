import 'plan.dart';

/// Why credits went up or down. Stored by [name] in the ledger, so a value
/// is never renamed once released.
enum CreditReason {
  /// The credits every new install starts with.
  welcome('Welcome credits'),

  /// One photo taken with the camera or the system scanner.
  scan('Photo scanned'),

  /// Photos, a PDF or a cloud file brought into the app.
  importing('Import'),

  /// A PDF, JPG or Word file made from a scan.
  exporting('Export'),

  /// The app was shared with someone from Settings > Credits.
  share('Shared the app'),

  /// Credits bought from the app store.
  purchase('Credits bought'),

  /// Credits given back, such as when an export failed after it was charged.
  refund('Refund');

  const CreditReason(this.label);

  final String label;
}

/// Something that costs credits.
enum CreditAction {
  scan(CreditReason.scan),
  importing(CreditReason.importing),
  exporting(CreditReason.exporting);

  const CreditAction(this.reason);

  final CreditReason reason;
}

/// One line of the credits ledger: what happened, how many credits it added
/// (positive) or took (negative), and the balance after it.
class CreditEntry {
  const CreditEntry({
    required this.reason,
    required this.amount,
    required this.balanceAfter,
    required this.at,
    this.note,
    this.purchaseId,
  });

  final CreditReason reason;
  final int amount;
  final int balanceAfter;
  final DateTime at;

  /// A short detail, such as "3 pages" or the file name.
  final String? note;

  /// The store's id of the purchase that added these credits, so a purchase
  /// the store reports twice is only counted once.
  final String? purchaseId;
}

/// A pack of credits on sale for one plan, as set in `credit_config.dart`.
/// The price is not here: the store sends it in the buyer's currency.
class CreditPack {
  const CreditPack({required this.credits, required this.googlePlayId, required this.appStoreId});

  final int credits;

  /// Product ID of a consumable in-app product in Play Console.
  final String googlePlayId;

  /// Product ID of a consumable in App Store Connect.
  final String appStoreId;
}

/// A credit pack as the store sells it, with its price.
class CreditOffer {
  const CreditOffer({required this.productId, required this.credits, required this.price, required this.storeData});

  final String productId;
  final int credits;

  /// The store's price text, such as "₹49.00".
  final String price;

  /// The store's own product object, used by the store class to buy it.
  final Object storeData;
}

/// The credit rules. Edit the values in `lib/app/credit_config.dart`.
class CreditRules {
  const CreditRules({
    required this.welcomeCredits,
    required this.costs,
    required this.shareReward,
    required this.shareRewardsPerDay,
    required this.packs,
  });

  /// Given once, the first time the app opens after install.
  final int welcomeCredits;

  /// What each action costs, per photo for [CreditAction.scan] and per
  /// action for imports and exports.
  final Map<CreditAction, int> costs;

  /// Given each time the app is shared.
  final int shareReward;

  /// How many shares a day earn [shareReward]. More shares are welcome but
  /// earn nothing, so the share button cannot be tapped for free credits.
  final int shareRewardsPerDay;

  /// The packs each plan can buy. A plan with no packs here (Gold) has
  /// unlimited credits through [PlanFeature.unlimitedCredits].
  final Map<AppPlan, List<CreditPack>> packs;

  int cost(CreditAction action) => costs[action] ?? 0;

  /// Every product ID of every pack, for one store.
  Set<String> googlePlayIds() => {for (final list in packs.values) for (final p in list) p.googlePlayId};
  Set<String> appStoreIds() => {for (final list in packs.values) for (final p in list) p.appStoreId};

  /// The pack with store product [productId], on any plan.
  CreditPack? packOf(String productId) {
    for (final list in packs.values) {
      for (final pack in list) {
        if (pack.googlePlayId == productId || pack.appStoreId == productId) return pack;
      }
    }
    return null;
  }
}
