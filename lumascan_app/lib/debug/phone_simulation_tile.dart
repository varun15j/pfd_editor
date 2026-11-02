import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/motion.dart';
import '../app/preferences.dart';
import 'phone_simulation.dart';

/// Debug panel: act as a cheaper phone, and show the performance overlay.
/// See docs/phone-simulation.md. Debug builds only.
class PhoneSimulationTile extends ConsumerWidget {
  const PhoneSimulationTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final phone = settings.debugPhone;
    final motion = ref.watch(motionProfileProvider);
    final small = Theme.of(context).textTheme.bodySmall;
    final cores = Platform.numberOfProcessors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Simulate phone', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            phone == null
                ? 'This phone as it is.'
                : 'Acting as ${phone.totalMb} MB, ${phone.cores} cores: ${phone.renderSlots} '
                      '${phone.renderSlots == 1 ? 'render' : 'renders'} at once, ${phone.imageCacheMb} MB picture '
                      'cache, ${motion.label}. Real memory and cores are not taken away.',
            style: small,
          ),
          const SizedBox(height: 8),
          SegmentedButton<SimulatedPhone?>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: null, label: Text('Real')),
              ButtonSegment(value: SimulatedPhone.mid4gb, label: Text('4 GB')),
              ButtonSegment(value: SimulatedPhone.entry2gb, label: Text('2 GB')),
            ],
            selected: {phone},
            onSelectionChanged: (s) => ref.read(appSettingsProvider.notifier).setDebugPhone(s.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Slow the CPU'),
            subtitle: Text(
              phone == null
                  ? 'Pick a phone above first.'
                  : 'Keeps ${phone.busyCoresOn(cores)} of $cores cores busy, so the app gets about '
                        "that phone's CPU. The phone gets warm.",
            ),
            value: settings.debugBusyCores,
            onChanged: phone == null ? null : (v) => ref.read(appSettingsProvider.notifier).setDebugBusyCores(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Performance overlay'),
            subtitle: const Text('Frame times, slow frames (over 16.7 ms) and app memory at the top right.'),
            value: settings.debugPerfOverlay,
            onChanged: (v) => ref.read(appSettingsProvider.notifier).setDebugPerfOverlay(v),
          ),
        ],
      ),
    );
  }
}
