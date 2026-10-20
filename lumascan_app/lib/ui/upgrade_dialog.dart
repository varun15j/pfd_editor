import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/preferences.dart';
import '../domain/plan.dart';
import 'state_views.dart';

/// Whether the current plan includes [feature]. When it does not, shows the
/// upgrade pop-up and returns false, so a locked button can be shown and
/// tapped but does nothing else.
Future<bool> ensurePlan(BuildContext context, WidgetRef ref, PlanFeature feature, {required String what}) async {
  if (ref.read(planIncludesProvider(feature))) return true;
  await showUpgradeDialog(context, feature, what: what);
  return false;
}

/// "Upgrade to Pro" pop-up for a feature the plan does not include. There
/// is no purchase flow yet, so Upgrade says so; billing will plug in here.
Future<void> showUpgradeDialog(BuildContext context, PlanFeature feature, {required String what}) {
  final plan = feature.minimum.label;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.workspace_premium_outlined),
      title: Text('Upgrade to $plan'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PremiumBadge(label: '$plan plan'),
          const SizedBox(height: 12),
          Text('$what is part of the $plan plan, and Gold includes it too.'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Not now')),
        FilledButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Plans cannot be bought in this version yet.')));
          },
          child: Text('Upgrade to $plan'),
        ),
      ],
    ),
  );
}
