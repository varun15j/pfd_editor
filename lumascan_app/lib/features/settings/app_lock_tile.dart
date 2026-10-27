import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_lock.dart';
import '../../app/device_auth.dart';
import '../../app/preferences.dart';
import '../../domain/plan.dart';
import '../../ui/state_views.dart';
import '../../ui/upgrade_dialog.dart';

/// Settings switch for the app lock (Pro). Turning it on or off asks for
/// fingerprint, face or PIN first, so only the phone's owner can change it.
class AppLockTile extends ConsumerWidget {
  const AppLockTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(appSettingsProvider.select((s) => s.appLock));
    final included = ref.watch(planIncludesProvider(PlanFeature.appLock));
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          const Flexible(child: Text('Lock with fingerprint or face')),
          if (!included) ...[const SizedBox(width: 8), PremiumBadge(label: PlanFeature.appLock.minimum.label)],
        ],
      ),
      subtitle: const Text(
        'Asks for your fingerprint, face or phone PIN each time the app opens. '
        'Saved PDFs and pages are not changed.',
      ),
      value: on,
      onChanged: (value) => value ? _turnOn(context, ref) : _turnOff(context, ref),
    );
  }

  Future<void> _turnOn(BuildContext context, WidgetRef ref) async {
    if (!await ensurePlan(context, ref, PlanFeature.appLock, what: 'App lock')) return;
    if (!await ref.read(deviceAuthProvider).isAvailable()) {
      if (context.mounted) {
        _say(context, 'Set a screen lock (PIN, pattern or password) in your phone settings first.');
      }
      return;
    }
    final result = await ref.read(appLockProvider.notifier).confirm('Confirm to turn on the app lock');
    if (result == DeviceAuthResult.success) {
      ref.read(appSettingsProvider.notifier).setAppLock(true);
    } else if (result == DeviceAuthResult.failed && context.mounted) {
      _say(context, "Couldn't check it's you, so the app lock is still off.");
    }
  }

  Future<void> _turnOff(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(appLockProvider.notifier).confirm('Confirm to turn off the app lock');
    // With no screen lock left there is nothing to confirm against.
    if (result == DeviceAuthResult.success || result == DeviceAuthResult.unavailable) {
      ref.read(appSettingsProvider.notifier).setAppLock(false);
    }
  }

  void _say(BuildContext context, String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
