import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/plan_cache_store.dart';
import '../data/purchases/app_store_purchase_service.dart';
import '../data/purchases/google_play_purchase_service.dart';
import '../domain/plan.dart';
import '../domain/purchases.dart';
import 'providers.dart';
import 'store_config.dart';

/// The phone's app store: Google Play on Android, the App Store on iOS, and
/// none elsewhere. Overridden in tests.
final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  final PurchaseService service;
  if (kIsWeb) {
    service = NoStorePurchaseService();
  } else if (Platform.isAndroid) {
    service = GooglePlayPurchaseService(storeConfig.googlePlay);
  } else if (Platform.isIOS) {
    service = AppStorePurchaseService(storeConfig.appStore);
  } else {
    service = NoStorePurchaseService();
  }
  ref.onDispose(service.dispose);
  return service;
});

final planCacheStoreProvider = Provider<PlanCacheStore>((ref) => PlanCacheStore(ref.watch(pageStoreProvider)));

/// The plan the store says this user paid for. Starts on the last plan the
/// store reported (Basic the first time), then follows the store.
final purchasedPlanProvider = Provider<AppPlan>((ref) => ref.watch(purchasesProvider.select((s) => s.plan)));

/// A message for the paywall to show once, such as "Payment pending".
class PurchaseNotice {
  PurchaseNotice(this.text);

  final String text;
}

class PurchasesState {
  const PurchasesState({
    this.plan = AppPlan.basic,
    this.available = false,
    this.offers = const [],
    this.offersFailed = false,
    this.buying = false,
    this.restoring = false,
    this.pending = false,
    this.notice,
  });

  /// The plan paid for, as last reported by the store.
  final AppPlan plan;

  /// Whether the store can be used on this device.
  final bool available;

  /// What the store sells, with prices. Empty until loaded.
  final List<PlanOffer> offers;

  /// Whether loading [offers] failed, so the paywall can offer to retry.
  final bool offersFailed;

  /// Whether the store's buy sheet is being opened.
  final bool buying;

  /// Whether Restore purchases is running.
  final bool restoring;

  /// Whether a payment has started but not finished.
  final bool pending;

  final PurchaseNotice? notice;

  PurchasesState copyWith({
    AppPlan? plan,
    bool? available,
    List<PlanOffer>? offers,
    bool? offersFailed,
    bool? buying,
    bool? restoring,
    bool? pending,
    PurchaseNotice? notice,
  }) => PurchasesState(
    plan: plan ?? this.plan,
    available: available ?? this.available,
    offers: offers ?? this.offers,
    offersFailed: offersFailed ?? this.offersFailed,
    buying: buying ?? this.buying,
    restoring: restoring ?? this.restoring,
    pending: pending ?? this.pending,
    notice: notice ?? this.notice,
  );
}

/// Buying, restoring and the plan paid for. Created at app start, which
/// listens to the store and asks it for the current plan (a silent restore),
/// so a purchase made on another phone or before a reinstall comes back.
final purchasesProvider = NotifierProvider<PurchasesController, PurchasesState>(PurchasesController.new);

class PurchasesController extends Notifier<PurchasesState> {
  late PurchaseService _service;
  bool _storeAnswered = false;
  Future<void> _started = Future.value();

  /// Completes once the saved plan is read and the store has been asked.
  Future<void> get started => _started;

  String get storeName => _service.storeName;

  @override
  PurchasesState build() {
    _service = ref.watch(purchaseServiceProvider);
    final subscription = _service.updates.listen(_onUpdate);
    ref.onDispose(subscription.cancel);
    _started = _start();
    return const PurchasesState();
  }

  Future<void> _start() async {
    final cached = await ref.read(planCacheStoreProvider).load();
    if (!ref.mounted) return;
    if (cached != null && !_storeAnswered) state = state.copyWith(plan: cached);
    if (!await _service.isAvailable() || !ref.mounted) return;
    state = state.copyWith(available: true);
    await Future.wait([_refreshQuietly(), loadOffers()]);
  }

  Future<void> _refreshQuietly() async {
    try {
      await _service.refresh();
    } catch (_) {
      // Offline or the store is busy: stay on the saved plan.
    }
  }

  /// Loads what the store sells. Called at start and by the paywall's retry.
  Future<void> loadOffers() async {
    try {
      final offers = await _service.loadOffers();
      if (ref.mounted) state = state.copyWith(offers: offers, offersFailed: false);
    } catch (_) {
      if (ref.mounted) state = state.copyWith(offersFailed: true);
    }
  }

  /// Opens the store's buy sheet for [offer]. The result arrives later from
  /// the store; an upgrade from Pro replaces the Pro subscription.
  Future<void> buy(PlanOffer offer) async {
    if (state.buying) return;
    state = state.copyWith(buying: true);
    try {
      await _service.buy(offer, owned: state.plan);
    } catch (_) {
      _notify('${_service.storeName} could not start the purchase. Try again.');
    } finally {
      if (ref.mounted) state = state.copyWith(buying: false);
    }
  }

  /// Asks the store again for the plans this account owns.
  Future<void> restore() async {
    if (state.restoring) return;
    state = state.copyWith(restoring: true);
    try {
      await _service.refresh();
      if (!ref.mounted) return;
      _notify(
        state.plan == AppPlan.basic
            ? 'No Pro or Gold plan was found for this ${_service.storeName} account.'
            : 'Restored: you are on ${state.plan.label}.',
      );
    } catch (_) {
      _notify('Could not reach ${_service.storeName}. Check the connection and try again.');
    } finally {
      if (ref.mounted) state = state.copyWith(restoring: false);
    }
  }

  Future<void> openManageSubscriptions() async {
    try {
      await _service.openManageSubscriptions();
    } catch (_) {
      _notify('Could not open ${_service.storeName}.');
    }
  }

  void _onUpdate(PurchaseUpdate update) {
    if (!ref.mounted) return;
    switch (update) {
      case OwnedPlans(:final plans):
        _setPlan(bestPlan(plans));
      case PlanBought(:final plan):
        final raised = plan.index > state.plan.index;
        state = state.copyWith(pending: false);
        if (raised) {
          _setPlan(plan);
          _notify('You are on ${plan.label} now. Thank you!');
        }
      case PurchasePending(:final plan):
        state = state.copyWith(pending: true);
        _notify('Payment pending. ${plan?.label ?? 'Your plan'} unlocks as soon as the payment completes.');
      case PurchaseFailed(:final message):
        _notify(message);
      case PurchaseCancelled():
        break;
    }
  }

  void _setPlan(AppPlan plan) {
    _storeAnswered = true;
    if (plan != state.plan) state = state.copyWith(plan: plan);
    unawaited(ref.read(planCacheStoreProvider).save(plan).catchError((Object _) {}));
  }

  void _notify(String text) {
    if (ref.mounted) state = state.copyWith(notice: PurchaseNotice(text));
  }
}
