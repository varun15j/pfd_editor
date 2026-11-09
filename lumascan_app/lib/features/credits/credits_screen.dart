import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_info.dart';
import '../../app/credit_config.dart';
import '../../app/credits.dart';
import '../../app/motion.dart';
import '../../app/purchases.dart';
import '../../app/theme.dart';
import '../../domain/credits.dart';
import '../../domain/plan.dart';
import '../../ui/luma_icons.dart';
import '../plans/paywall_screen.dart';

/// Shares a link to the app. Behind an interface so tests need no plugin.
abstract class AppSharer {
  /// Returns true when the share sheet was not dismissed.
  Future<bool> share(String text, {Rect? origin});
}

class SharePlusAppSharer implements AppSharer {
  @override
  Future<bool> share(String text, {Rect? origin}) async {
    final result = await SharePlus.instance.share(ShareParams(text: text, sharePositionOrigin: origin));
    return result.status != ShareResultStatus.dismissed;
  }
}

final appSharerProvider = Provider<AppSharer>((ref) => SharePlusAppSharer());

/// The message sent when the app is shared.
String get shareAppText => 'I scan my documents with $appName. Get it here: $shareAppLink';

/// Whether there are credits for [units] of [action]. When there are not,
/// shows how to get more and returns false. Gold never runs out.
Future<bool> ensureCredits(BuildContext context, WidgetRef ref, CreditAction action, {int units = 1}) async {
  final credits = ref.read(creditsProvider.notifier);
  if (credits.canAfford(action, units)) return true;
  await showOutOfCreditsSheet(context, action);
  return false;
}

/// Like [ensureCredits], and takes the credits when there are enough.
Future<bool> spendCredits(BuildContext context, WidgetRef ref, CreditAction action, {String? note}) async {
  if (ref.read(creditsProvider.notifier).trySpend(action, note: note)) return true;
  if (context.mounted) await showOutOfCreditsSheet(context, action);
  return false;
}

String _actionText(CreditAction action) => switch (action) {
  CreditAction.scan => 'Scanning a photo',
  CreditAction.importing => 'Importing',
  CreditAction.exporting => 'Exporting',
};

/// "You are out of credits": buy a pack, share the app, or see Gold.
Future<void> showOutOfCreditsSheet(BuildContext context, CreditAction action) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _OutOfCreditsSheet(action: action),
);

class _OutOfCreditsSheet extends ConsumerWidget {
  const _OutOfCreditsSheet({required this.action});

  final CreditAction action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credits = ref.read(creditsProvider.notifier);
    final balance = ref.watch(creditsProvider.select((s) => s.balance));
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Not enough credits', style: text.headlineSmall),
            const SizedBox(height: Space.xs),
            Text(
              '${_actionText(action)} uses ${credits.costOf(action)} credits, and you have $balance. '
              'Buy credits or share $appName to get more.',
            ),
            const SizedBox(height: Space.md),
            const BuyCreditsSection(),
            const ShareAppTile(contentPadding: EdgeInsets.zero),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LumaIcons.pro),
              title: const Text('Unlimited with Gold'),
              subtitle: const Text('Scan, import and export without credits.'),
              trailing: const Icon(LumaIcons.next),
              onTap: () => openPaywall(context, highlight: AppPlan.gold),
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings row: the balance, opening [CreditsScreen].
class CreditsTile extends ConsumerWidget {
  const CreditsTile({super.key, this.contentPadding});

  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlimited = ref.watch(unlimitedCreditsProvider);
    final balance = ref.watch(creditsProvider.select((s) => s.balance));
    return ListTile(
      contentPadding: contentPadding,
      leading: const Icon(LumaIcons.credits),
      title: const Text('Credits'),
      subtitle: Text(
        unlimited ? 'Unlimited on Gold.' : '$balance credits left. Scans, imports and exports use credits.',
      ),
      trailing: const Icon(LumaIcons.next),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CreditsScreen())),
    );
  }
}

/// Settings > Credits: the balance, what things cost, buying more, sharing
/// the app for free credits, and every change so far.
class CreditsScreen extends ConsumerWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(creditsProvider);
    final controller = ref.read(creditsProvider.notifier);
    final unlimited = ref.watch(unlimitedCreditsProvider);
    final rules = controller.rules;
    final text = Theme.of(context).textTheme;
    final c = LumaColors.of(context);
    final motion = Motion.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Credits')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xxl),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Balance', style: text.labelLarge?.copyWith(color: c.muted)),
                  const SizedBox(height: Space.xs),
                  AnimatedSwitcher(
                    duration: motion.duration(const Duration(milliseconds: 250)),
                    child: Text(
                      unlimited ? 'Unlimited' : '${state.balance}',
                      key: ValueKey(unlimited ? -1 : state.balance),
                      style: text.displaySmall,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    unlimited
                        ? 'Gold scans, imports and exports without credits.'
                        : 'Each photo scanned uses ${rules.cost(CreditAction.scan)} credits, each import '
                              '${rules.cost(CreditAction.importing)} and each export ${rules.cost(CreditAction.exporting)}. '
                              'New installs start with ${rules.welcomeCredits}.',
                    style: text.bodySmall?.copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
          ),
          if (!unlimited) ...[
            const SizedBox(height: Space.xl),
            const _Header('Get more credits'),
            const BuyCreditsSection(),
            const ShareAppTile(contentPadding: EdgeInsets.zero),
          ],
          const SizedBox(height: Space.xl),
          const _Header('History'),
          if (state.history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.md),
              child: Text('Nothing yet.', style: text.bodyMedium?.copyWith(color: c.muted)),
            )
          else
            for (final e in state.history) _HistoryRow(e),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.entry);

  final CreditEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final when = MaterialLocalizations.of(context);
    final date = '${when.formatShortDate(entry.at)}, ${when.formatTimeOfDay(TimeOfDay.fromDateTime(entry.at))}';
    final plus = entry.amount > 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(entry.reason.label),
      subtitle: Text(entry.note == null ? date : '${entry.note} · $date'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${plus ? '+' : ''}${entry.amount}',
            style: TextStyle(fontWeight: FontWeight.w600, color: plus ? c.success : c.ink),
          ),
          Text('${entry.balanceAfter} left', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.muted)),
        ],
      ),
    );
  }
}

/// The credit packs the current plan can buy, with the store's prices.
/// Basic and Pro buy different packs, so each has its own rate.
class BuyCreditsSection extends ConsumerStatefulWidget {
  const BuyCreditsSection({super.key});

  @override
  ConsumerState<BuyCreditsSection> createState() => _BuyCreditsSectionState();
}

class _BuyCreditsSectionState extends ConsumerState<BuyCreditsSection> {
  @override
  void initState() {
    super.initState();
    final state = ref.read(creditsProvider);
    if (state.offers.isEmpty) ref.read(creditsProvider.notifier).loadOffers();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(creditsProvider);
    final controller = ref.read(creditsProvider.notifier);
    final plan = ref.watch(purchasedPlanProvider);
    final offers = controller.offersFor(plan);
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    if (offers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          children: [
            Expanded(
              child: Text(
                state.offersFailed
                    ? 'Credit packs could not be loaded.'
                    : 'Credit packs are not on sale on this device yet.',
                style: text.bodySmall?.copyWith(color: c.muted),
              ),
            ),
            if (state.offersFailed) TextButton(onPressed: controller.loadOffers, child: const Text('Retry')),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final offer in offers)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LumaIcons.storefront),
            title: Text('${offer.credits} credits'),
            subtitle: Text('${plan.label} price'),
            trailing: FilledButton(
              onPressed: state.buying ? null : () => _buy(offer),
              child: Text(offer.price),
            ),
          ),
      ],
    );
  }

  Future<void> _buy(CreditOffer offer) async {
    final messenger = ScaffoldMessenger.of(context);
    final store = ref.read(purchasesProvider.notifier).storeName;
    if (!await ref.read(creditsProvider.notifier).buy(offer)) {
      messenger.showSnackBar(SnackBar(content: Text('$store could not start the purchase. Try again.')));
    }
  }
}

/// Share the app; the first share each day earns credits.
class ShareAppTile extends ConsumerWidget {
  const ShareAppTile({super.key, this.contentPadding});

  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(creditsProvider.select((s) => s.history.length));
    final controller = ref.read(creditsProvider.notifier);
    final reward = controller.rules.shareReward;
    final left = controller.shareRewardsLeftToday;
    return ListTile(
      contentPadding: contentPadding,
      leading: const Icon(LumaIcons.share),
      title: Text('Share $appName'),
      subtitle: Text(left > 0 ? 'Get $reward free credits.' : 'Thanks for sharing! Share again tomorrow for more credits.'),
      trailing: const Icon(LumaIcons.next),
      onTap: () => _share(context, ref),
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final bool shared;
    try {
      shared = await ref.read(appSharerProvider).share(shareAppText, origin: origin);
    } on Object {
      messenger.showSnackBar(const SnackBar(content: Text('The share sheet could not be opened.')));
      return;
    }
    if (!shared) return;
    final got = ref.read(creditsProvider.notifier).rewardShare();
    if (got > 0) messenger.showSnackBar(SnackBar(content: Text('Thanks for sharing! $got credits added.')));
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) =>
      Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium));
}
