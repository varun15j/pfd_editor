import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_info.dart';
import '../../app/purchases.dart';
import '../../app/store_config.dart';
import '../../app/theme.dart';
import '../../domain/plan.dart';
import '../../domain/purchases.dart';
import '../../ui/state_views.dart';

/// Opens the plans screen, with [highlight] marked as the plan that unlocks
/// what the user tried to use.
Future<void> openPaywall(BuildContext context, {AppPlan? highlight}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PaywallScreen(highlight: highlight)));

/// Pro and Gold with their store prices: buy, upgrade from Pro to Gold,
/// restore and manage. Opened from Settings and from the upgrade pop-up.
class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key, this.highlight});

  final AppPlan? highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(purchasesProvider.select((s) => s.notice), (_, notice) {
      if (notice == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(notice.text)));
    });
    final state = ref.watch(purchasesProvider);
    final controller = ref.read(purchasesProvider.notifier);
    final store = controller.storeName;
    final text = Theme.of(context).textTheme;
    final c = LumaColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Plans')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xxl),
        children: [
          Row(
            children: [
              Expanded(child: Text('You are on ${state.plan.label}.', style: text.titleMedium)),
              if (state.plan != AppPlan.basic) PremiumBadge(label: state.plan.label),
            ],
          ),
          const SizedBox(height: Space.md),
          if (state.pending) ...[
            _Note(
              icon: Icons.hourglass_top_outlined,
              text: 'A payment is pending. Your plan unlocks as soon as $store confirms it.',
            ),
            const SizedBox(height: Space.md),
          ],
          if (!state.available)
            _Note(
              icon: Icons.storefront_outlined,
              text: 'Plans cannot be bought on this device. Install $appName from Google Play or the App Store to buy Pro or Gold.',
            )
          else if (state.offers.isEmpty && state.offersFailed)
            _Note(
              icon: Icons.cloud_off_outlined,
              text: 'Could not load the plans from $store.',
              action: TextButton(onPressed: controller.loadOffers, child: const Text('Try again')),
            )
          else if (state.offers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(Space.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
          for (final plan in [AppPlan.pro, AppPlan.gold])
            _PlanCard(
              plan: plan,
              current: state.plan,
              highlighted: plan == highlight,
              offers: [
                for (final o in state.offers)
                  if (o.plan == plan) o,
              ],
              enabled: state.available && !state.buying,
              onBuy: controller.buy,
            ),
          const SizedBox(height: Space.md),
          Text(
            'Subscriptions renew automatically until cancelled. Payment is charged to your $store account. '
            'Cancel anytime in $store subscriptions, at least 24 hours before the next renewal.',
            style: text.bodySmall?.copyWith(color: c.muted),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            children: [
              TextButton.icon(
                onPressed: state.available && !state.restoring ? controller.restore : null,
                icon: state.restoring
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.restore),
                label: const Text('Restore purchases'),
              ),
              if (state.available && state.plan != AppPlan.basic)
                TextButton(onPressed: controller.openManageSubscriptions, child: const Text('Manage subscription')),
              if (storeConfig.termsUrl.isNotEmpty)
                TextButton(onPressed: () => _open(storeConfig.termsUrl), child: const Text('Terms of use')),
              if (storeConfig.privacyUrl.isNotEmpty)
                TextButton(onPressed: () => _open(storeConfig.privacyUrl), child: const Text('Privacy policy')),
            ],
          ),
        ],
      ),
    );
  }

  static Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.current,
    required this.highlighted,
    required this.offers,
    required this.enabled,
    required this.onBuy,
  });

  final AppPlan plan;
  final AppPlan current;
  final bool highlighted;
  final List<PlanOffer> offers;
  final bool enabled;
  final ValueChanged<PlanOffer> onBuy;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = LumaColors.of(context);
    final owned = current.index >= plan.index;
    final features = [
      if (plan == AppPlan.gold) 'Everything in Pro',
      for (final f in PlanFeature.values)
        if (f.minimum == plan) _featureTitle(f),
    ];
    return Card(
      margin: const EdgeInsets.only(top: Space.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: highlighted ? c.premium : c.line, width: highlighted ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(plan.label, style: text.titleLarge)),
                if (current == plan)
                  const PremiumBadge(label: 'Your plan')
                else if (owned)
                  Text('Included in ${current.label}', style: text.labelMedium?.copyWith(color: c.muted)),
              ],
            ),
            const SizedBox(height: Space.sm),
            for (final f in features)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Row(
                  children: [
                    Icon(Icons.check, size: 18, color: c.success),
                    const SizedBox(width: Space.sm),
                    Expanded(child: Text(f)),
                  ],
                ),
              ),
            if (!owned)
              for (final offer in offers) ...[
                const SizedBox(height: Space.sm),
                SizedBox(
                  width: double.infinity,
                  child: (offer.period == PlanPeriod.yearly ? FilledButton.new : OutlinedButton.new)(
                    onPressed: enabled ? () => onBuy(offer) : null,
                    child: Text(
                      '${current == AppPlan.basic ? '' : 'Upgrade: '}${offer.period.label} · ${offer.price} / ${offer.period.unit}',
                    ),
                  ),
                ),
                if (offer.trial != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(offer.trial!, style: text.bodySmall?.copyWith(color: c.muted)),
                  ),
              ],
          ],
        ),
      ),
    );
  }

  static String _featureTitle(PlanFeature feature) => switch (feature) {
    PlanFeature.smartScan => 'Smart scanning: better page detection and auto crop',
    PlanFeature.textPdf => 'Text PDF: searchable text from scans',
    PlanFeature.word => 'PDF to Word',
    PlanFeature.autoMask => 'Auto mask: hide ID numbers on a page',
    PlanFeature.noWatermark => 'No "Scanned with" mark on exported PDFs',
    PlanFeature.pageNumbers => 'Page numbers on exported PDFs',
    PlanFeature.signatureLibrary => 'Saved signatures, initials and date stamps',
    PlanFeature.tableToExcel => 'Table to Excel: a photo of a table becomes a spreadsheet',
    PlanFeature.targetSize => 'Compress a PDF to fit under a size',
    PlanFeature.password => 'Password-protected PDFs',
    PlanFeature.splitPdf => 'Split a PDF and extract pages',
    PlanFeature.indianOcr => 'Text in Hindi, Marathi and other Indian languages',
    PlanFeature.smartName => 'Smart file names from the text on the page',
    PlanFeature.searchText => 'Search the text inside your documents',
    PlanFeature.bookFix => 'Book mode: flat pages, fingers removed',
  };
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.sm)),
      child: Row(
        children: [
          Icon(icon, color: c.ink),
          const SizedBox(width: Space.md),
          Expanded(child: Text(text)),
          ?action,
        ],
      ),
    );
  }
}
