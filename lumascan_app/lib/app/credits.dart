import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/credit_store.dart';
import '../domain/credits.dart';
import '../domain/plan.dart';
import '../domain/purchases.dart';
import 'credit_config.dart';
import 'preferences.dart';
import 'purchases.dart';

final creditStoreProvider = Provider<CreditStore>((ref) => SqliteCreditStore());

/// The credit rules in use. Overridden in tests.
final creditRulesProvider = Provider<CreditRules>((ref) => creditRules);

/// Whether this plan uses no credits at all (Gold).
final unlimitedCreditsProvider = Provider<bool>((ref) => ref.watch(planIncludesProvider(PlanFeature.unlimitedCredits)));

class CreditsState {
  const CreditsState({
    required this.balance,
    this.history = const [],
    this.loaded = false,
    this.offers = const [],
    this.offersFailed = false,
    this.buying = false,
  });

  final int balance;

  /// Newest first.
  final List<CreditEntry> history;

  /// Whether the saved balance has been read. Until then nothing is blocked.
  final bool loaded;

  /// The credit packs the store sells, with prices. Empty until loaded.
  final List<CreditOffer> offers;
  final bool offersFailed;
  final bool buying;

  CreditsState copyWith({
    int? balance,
    List<CreditEntry>? history,
    bool? loaded,
    List<CreditOffer>? offers,
    bool? offersFailed,
    bool? buying,
  }) => CreditsState(
    balance: balance ?? this.balance,
    history: history ?? this.history,
    loaded: loaded ?? this.loaded,
    offers: offers ?? this.offers,
    offersFailed: offersFailed ?? this.offersFailed,
    buying: buying ?? this.buying,
  );
}

/// Credits: the balance, the ledger, spending, share rewards and buying
/// packs. Created at app start, so credit purchases that finish while no
/// screen is open are still counted.
///
/// Spending is decided at once from the balance in memory, so a scan or an
/// export never waits on the database; each change is then written to the
/// [CreditStore] in order.
final creditsProvider = NotifierProvider<CreditsController, CreditsState>(CreditsController.new);

class CreditsController extends Notifier<CreditsState> {
  late CreditStore _store;
  late CreditRules _rules;
  late PurchaseService _service;
  Future<void> _writes = Future.value();

  /// Changes made before the saved balance was read, applied on top of it.
  final _early = <CreditEntry>[];
  Future<void> _started = Future.value();

  /// Completes once the saved credits are read.
  Future<void> get started => _started;

  /// Completes once every change so far is written.
  Future<void> get saved => _writes;

  @override
  CreditsState build() {
    _store = ref.watch(creditStoreProvider);
    _rules = ref.watch(creditRulesProvider);
    _service = ref.watch(purchaseServiceProvider);
    final subscription = _service.updates.listen(_onUpdate);
    ref.onDispose(subscription.cancel);
    _started = _load();
    return CreditsState(balance: _rules.welcomeCredits);
  }

  CreditRules get rules => _rules;

  bool get unlimited => ref.read(unlimitedCreditsProvider);

  Future<void> _load() async {
    try {
      var balance = await _store.balance();
      if (balance == null) {
        // A new install: the welcome credits are the first ledger entry.
        final welcome = CreditEntry(
          reason: CreditReason.welcome,
          amount: _rules.welcomeCredits,
          balanceAfter: _rules.welcomeCredits,
          at: DateTime.now(),
        );
        await _store.add(welcome);
        balance = welcome.balanceAfter;
      }
      // Changes made while loading, replayed on the saved balance.
      for (final e in _early) {
        balance = (balance! + e.amount).clamp(0, 1 << 31);
        await _store.add(_withBalance(e, balance));
      }
      _early.clear();
      final history = await _store.history();
      if (ref.mounted) state = state.copyWith(balance: balance, history: history, loaded: true);
    } on Object catch (e) {
      debugPrint('Could not read credits: $e');
      if (ref.mounted) state = state.copyWith(loaded: true);
    }
  }

  static CreditEntry _withBalance(CreditEntry e, int balance) => CreditEntry(
    reason: e.reason,
    amount: e.amount,
    balanceAfter: balance,
    at: e.at,
    note: e.note,
    purchaseId: e.purchaseId,
  );

  /// What [units] of [action] cost: 0 on an unlimited plan.
  int costOf(CreditAction action, [int units = 1]) => unlimited ? 0 : _rules.cost(action) * units;

  /// Whether the balance covers [units] of [action]. Always true on Gold and
  /// before the saved balance is read.
  bool canAfford(CreditAction action, [int units = 1]) => !state.loaded || state.balance >= costOf(action, units);

  /// Takes the credits for [units] of [action] when the balance covers them
  /// and returns true; otherwise changes nothing and returns false.
  bool trySpend(CreditAction action, {int units = 1, String? note}) {
    if (!canAfford(action, units)) return false;
    _record(action.reason, -costOf(action, units), note: note);
    return true;
  }

  /// Takes the credits for [units] of [action] that are already done, such
  /// as pages the system scanner returned. The balance stops at 0, so a scan
  /// started with credits left is never undone.
  void charge(CreditAction action, {int units = 1, String? note}) {
    final cost = costOf(action, units);
    if (cost == 0) return;
    _record(action.reason, -cost, note: note);
  }

  /// Gives back the credits of an action that did not finish.
  void refund(CreditAction action, {int units = 1, String? note}) {
    final cost = costOf(action, units);
    if (cost > 0) _record(CreditReason.refund, cost, note: note ?? action.reason.label);
  }

  /// How many share rewards are left today.
  int get shareRewardsLeftToday {
    final now = DateTime.now();
    final today = state.history.where(
      (e) => e.reason == CreditReason.share && e.at.year == now.year && e.at.month == now.month && e.at.day == now.day,
    );
    return (_rules.shareRewardsPerDay - today.length - _early.where((e) => e.reason == CreditReason.share).length)
        .clamp(0, _rules.shareRewardsPerDay);
  }

  /// The app was shared. Returns the credits given: [CreditRules.shareReward],
  /// or 0 once today's share rewards are used up.
  int rewardShare() {
    if (shareRewardsLeftToday == 0) return 0;
    _record(CreditReason.share, _rules.shareReward);
    return _rules.shareReward;
  }

  void _record(CreditReason reason, int amount, {String? note, String? purchaseId}) {
    final entry = CreditEntry(
      reason: reason,
      amount: amount,
      // At least 0: a charge for work already done may be more than is left.
      balanceAfter: (state.balance + amount).clamp(0, 1 << 31),
      at: DateTime.now(),
      note: note,
      purchaseId: purchaseId,
    );
    if (!state.loaded) {
      _early.add(entry);
      state = state.copyWith(balance: entry.balanceAfter);
      return;
    }
    state = state.copyWith(balance: entry.balanceAfter, history: [entry, ...state.history]);
    _writes = _writes.then((_) => _store.add(entry)).then((_) {}, onError: (Object e) {
      debugPrint('Could not save credits: $e');
    });
  }

  // ---- Buying ------------------------------------------------------------

  /// The packs the current plan can buy, from the store's offers.
  List<CreditOffer> offersFor(AppPlan plan) {
    final ids = {for (final p in _rules.packs[plan] ?? const <CreditPack>[]) ...[p.googlePlayId, p.appStoreId]};
    return [
      for (final o in state.offers)
        if (ids.contains(o.productId)) o,
    ];
  }

  Future<void> loadOffers() async {
    try {
      final offers = await _service.loadCreditOffers();
      if (ref.mounted) state = state.copyWith(offers: offers, offersFailed: false);
    } catch (_) {
      if (ref.mounted) state = state.copyWith(offersFailed: true);
    }
  }

  Future<bool> buy(CreditOffer offer) async {
    if (state.buying) return false;
    state = state.copyWith(buying: true);
    try {
      await _service.buyCredits(offer);
      return true;
    } catch (_) {
      return false;
    } finally {
      if (ref.mounted) state = state.copyWith(buying: false);
    }
  }

  Future<void> _onUpdate(PurchaseUpdate update) async {
    if (update is! CreditsBought) return;
    final pack = _rules.packOf(update.productId);
    if (pack == null || !ref.mounted) return;
    await _started;
    if (!ref.mounted) return;
    // The ledger refuses a purchase id it already has.
    if (state.history.any((e) => e.purchaseId == update.purchaseId)) return;
    _record(CreditReason.purchase, pack.credits, note: '${pack.credits} credits', purchaseId: update.purchaseId);
  }
}
