import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/motion.dart';
import '../app/preferences.dart';

/// Debug panel: pick the animation profile, to try what a 2 GB phone gets on
/// a fast one and the other way round. "Auto" follows the phone's memory and
/// cores ([autoMotionProfileProvider]). Debug builds only.
class MotionProfileTile extends ConsumerWidget {
  const MotionProfileTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picked = ref.watch(appSettingsProvider.select((s) => s.debugMotion));
    final auto = ref.watch(autoMotionProfileProvider);
    final spec = ref.watch(deviceSpecProvider).value;
    final phone = spec == null
        ? 'phone not read'
        : '${spec.totalMb ?? '?'} MB, ${spec.cores ?? '?'} cores${spec.lowRamDevice ? ', low RAM' : ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Animation profile', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            picked == null
                ? 'Auto: ${auto.label} ($phone).'
                : 'Using ${picked.label} (Auto would pick ${auto.label}, $phone).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<MotionProfile?>(
            showSelectedIcon: false,
            emptySelectionAllowed: false,
            segments: const [
              ButtonSegment(value: null, label: Text('Auto')),
              ButtonSegment(value: MotionProfile.high, label: Text('High')),
              ButtonSegment(value: MotionProfile.low, label: Text('Low')),
            ],
            selected: {picked},
            onSelectionChanged: (s) => ref.read(appSettingsProvider.notifier).setDebugMotion(s.first),
          ),
        ],
      ),
    );
  }
}
