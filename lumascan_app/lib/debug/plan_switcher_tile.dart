import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/preferences.dart';
import '../domain/plan.dart';

/// Debug panel: pick the plan the app behaves as, to try Basic, Pro and Gold
/// without buying. "Real plan" follows [purchasedPlan]. Debug builds only.
class PlanSwitcherTile extends ConsumerWidget {
  const PlanSwitcherTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picked = ref.watch(appSettingsProvider.select((s) => s.debugPlan));
    final plan = ref.watch(planProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Plan', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            picked == null
                ? 'Behaving as the real plan: ${plan.label}.'
                : 'Behaving as ${plan.label} (the real plan is ${purchasedPlan.label}).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<AppPlan?>(
            showSelectedIcon: false,
            emptySelectionAllowed: false,
            segments: [
              const ButtonSegment(value: null, label: Text('Real')),
              for (final p in AppPlan.values) ButtonSegment(value: p, label: Text(p.label)),
            ],
            selected: {picked},
            onSelectionChanged: (s) => ref.read(appSettingsProvider.notifier).setDebugPlan(s.first),
          ),
        ],
      ),
    );
  }
}
