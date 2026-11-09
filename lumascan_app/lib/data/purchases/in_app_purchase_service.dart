import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../app/credit_config.dart';
import '../../domain/credits.dart';
import '../../domain/plan.dart';
import '../../domain/purchases.dart';

/// What Google Play and the App Store share through the in_app_purchase
/// plugin: listening to the purchase stream from app start, turning each
/// purchase into a [PurchaseUpdate], and finishing purchases so the store
/// does not refund them. Each store's own rules live in its subclass.
abstract class InAppPurchaseService implements PurchaseService {
  InAppPurchaseService({InAppPurchase? iap, this.creditProducts = const {}}) : iap = iap ?? InAppPurchase.instance {
    _subscription = this.iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => report(PurchaseFailed('$storeName could not finish the purchase.')),
    );
  }

  @protected
  final InAppPurchase iap;

  /// Product IDs of the consumable credit packs (`credit_config.dart`).
  final Set<String> creditProducts;

  // Synchronous, so an update is handled before refresh() returns.
  final _updates = StreamController<PurchaseUpdate>.broadcast(sync: true);
  late final StreamSubscription<List<PurchaseDetails>> _subscription;

  @override
  Stream<PurchaseUpdate> get updates => _updates.stream;

  /// The plan [purchase] unlocks, or null when it is not one of our products.
  @protected
  AppPlan? planOf(PurchaseDetails purchase);

  /// Whether [purchase] may unlock its plan. Store classes add their checks.
  @protected
  bool isValid(PurchaseDetails purchase) => planOf(purchase) != null && isPaid(purchase);

  /// Whether the store says [purchase] is paid for, not only started.
  @protected
  bool isPaid(PurchaseDetails purchase) => true;

  /// Called for each valid purchase the store reports, bought now or
  /// restored, so a store class can keep it (for example to upgrade it later).
  @protected
  void onOwned(PurchaseDetails purchase, AppPlan plan) {}

  /// Called for a restored purchase. Reports it as bought by default.
  @protected
  void onRestored(PurchaseDetails purchase, AppPlan plan) => report(PlanBought(plan));

  @protected
  void report(PurchaseUpdate update) {
    if (!_updates.isClosed) _updates.add(update);
  }

  /// The id that tells one purchase from another, for counting credits once.
  static String purchaseIdOf(PurchaseDetails purchase) =>
      purchase.purchaseID ?? purchase.verificationData.serverVerificationData;

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final plan = planOf(purchase);
      final credits = creditProducts.contains(purchase.productID);
      switch (purchase.status) {
        case PurchaseStatus.purchased || PurchaseStatus.restored when credits:
          if (isPaid(purchase)) report(CreditsBought(purchase.productID, purchaseIdOf(purchase)));
        case PurchaseStatus.pending:
          report(PurchasePending(plan));
        case PurchaseStatus.purchased:
          if (plan != null && isValid(purchase)) {
            onOwned(purchase, plan);
            report(PlanBought(plan));
          }
        case PurchaseStatus.restored:
          if (plan != null && isValid(purchase)) {
            onOwned(purchase, plan);
            onRestored(purchase, plan);
          }
        case PurchaseStatus.error:
          report(PurchaseFailed(_failure(purchase.error)));
        case PurchaseStatus.canceled:
          report(const PurchaseCancelled());
      }
      // Finishing acknowledges the purchase. Google refunds a purchase that
      // is not acknowledged within three days, and the App Store keeps
      // delivering an unfinished one.
      if (purchase.pendingCompletePurchase) {
        try {
          await iap.completePurchase(purchase);
        } catch (_) {
          // Tried again the next time the store reports it.
        }
      }
    }
  }

  String _failure(IAPError? error) {
    final detail = error?.message ?? '';
    return detail.isEmpty ? 'The purchase did not go through.' : 'The purchase did not go through ($detail).';
  }

  @override
  Future<List<CreditOffer>> loadCreditOffers() async {
    if (creditProducts.isEmpty) return const [];
    final response = await iap.queryProductDetails(creditProducts);
    if (response.error != null && response.productDetails.isEmpty) {
      throw StateError('$storeName did not return the credit packs: ${response.error!.message}');
    }
    return creditOffersFrom(response.productDetails);
  }

  /// One offer per product that is a known credit pack, smallest first.
  @visibleForTesting
  static List<CreditOffer> creditOffersFrom(List<ProductDetails> details) {
    final offers = [
      for (final product in details)
        if (creditRules.packOf(product.id) case final pack?)
          CreditOffer(productId: product.id, credits: pack.credits, price: product.price, storeData: product),
    ];
    offers.sort((a, b) => a.credits - b.credits);
    return offers;
  }

  @override
  Future<void> buyCredits(CreditOffer offer) async {
    // Consumed once bought (Android) or finished (iOS), so a pack can be
    // bought again.
    await iap.buyConsumable(purchaseParam: PurchaseParam(productDetails: offer.storeData as ProductDetails));
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return await iap.isAvailable();
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    _updates.close();
  }
}
