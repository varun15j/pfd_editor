import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../app/preferences.dart';
import '../../app/theme.dart';
import '../../domain/cloud_storage.dart';
import '../../ui/luma_icons.dart';
import '../cloud/drive_sync.dart';

/// Settings > Sync: back up every export to the user's Google Drive, with a
/// switch for sync itself and one for using mobile data.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final sync = ref.watch(driveSyncProvider);
    final available = ref.watch(driveBackupProvider).availability;
    final text = Theme.of(context).textTheme;
    final c = LumaColors.of(context);
    final state = sync.value;
    final account = state?.account;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xxl),
        children: [
          Text(
            'Every PDF you export is also saved to your Google Drive, in a folder named $appName. '
            '$appName can only see the files it puts there, not the rest of your Drive.',
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
          const SizedBox(height: Space.lg),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sync'),
            subtitle: Text(
              settings.syncEnabled
                  ? 'Exports upload to Google Drive.'
                  : 'Off. Exports stay on this phone and wait until sync is on again.',
            ),
            value: settings.syncEnabled,
            onChanged: controller.setSyncEnabled,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sync using cellular data'),
            subtitle: Text(
              settings.syncOnCellular
                  ? 'Uploads use Wi-Fi or mobile data.'
                  : 'Uploads wait for Wi-Fi, so they do not use your mobile data.',
            ),
            value: settings.syncOnCellular,
            onChanged: settings.syncEnabled ? controller.setSyncOnCellular : null,
          ),
          const SizedBox(height: Space.lg),
          _AccountCard(available: available, account: account, loading: sync.isLoading && !sync.hasValue),
          if (account != null && state != null) ...[const SizedBox(height: Space.md), _Status(state: state)],
        ],
      ),
    );
  }
}

class _AccountCard extends ConsumerStatefulWidget {
  const _AccountCard({required this.available, required this.account, required this.loading});

  final CloudAvailability available;
  final CloudAccount? account;
  final bool loading;

  @override
  ConsumerState<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends ConsumerState<_AccountCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final ready = widget.available == CloudAvailability.ready;
    final status = switch (widget.available) {
      CloudAvailability.unsupportedPlatform => 'Not available on this device',
      CloudAvailability.notConfigured => 'Not set up in this build yet',
      CloudAvailability.ready => account == null ? 'Not connected' : 'Syncing to ${account.label}',
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LumaIcons.googleDrive),
              title: const Text('Google Drive'),
              subtitle: Text(status),
            ),
            if (ready && !widget.loading)
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: Space.sm,
                children: [
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(Space.sm),
                      child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (account != null)
                    TextButton(onPressed: _disconnect, child: const Text('Disconnect'))
                  else
                    FilledButton(onPressed: _connect, child: const Text('Connect Google Drive')),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _connect() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final account = await ref.read(driveSyncProvider.notifier).connect();
      if (account != null) messenger.showSnackBar(SnackBar(content: Text('Syncing to ${account.label}')));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not connect Google Drive. $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Stop syncing to Google Drive?'),
            content: const Text(
              'New exports stay on this phone only. Files already in your Google Drive are not deleted.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Disconnect')),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(driveSyncProvider.notifier).disconnect();
      messenger.showSnackBar(const SnackBar(content: Text('Google Drive disconnected')));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not disconnect Google Drive. $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// What sync is doing: up to date, uploading, or why it waits.
class _Status extends ConsumerWidget {
  const _Status({required this.state});

  final DriveSyncState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final waiting = state.pending == 1 ? '1 export' : '${state.pending} exports';
    final line = switch (state) {
      DriveSyncState(uploading: true) => 'Uploading $waiting…',
      DriveSyncState(pending: 0) => 'Up to date.',
      DriveSyncState(hold: SyncHold.off) => '$waiting waiting. Sync is off.',
      DriveSyncState(hold: SyncHold.offline) => '$waiting waiting for a connection.',
      DriveSyncState(hold: SyncHold.waitingForWifi) => '$waiting waiting for Wi-Fi.',
      _ => '$waiting waiting.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(line, style: text.bodyMedium),
        if (state.error != null) ...[
          const SizedBox(height: Space.xs),
          Text(state.error!, style: text.bodySmall?.copyWith(color: scheme.error)),
        ],
        if (state.pending > 0 && !state.uploading)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => ref.read(driveSyncProvider.notifier).flush(),
              child: const Text('Sync now'),
            ),
          ),
      ],
    );
  }
}
