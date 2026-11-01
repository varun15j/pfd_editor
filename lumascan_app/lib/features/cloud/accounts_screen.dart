import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../app/theme.dart';
import '../../domain/cloud_storage.dart';
import 'cloud_accounts.dart';
import 'cloud_browse_screen.dart';
import 'cloud_import_flow.dart';
import '../../ui/luma_icons.dart';

/// Settings > Accounts: cloud storage accounts to import documents from.
/// Connecting is optional and read-only; nothing is uploaded or synced.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(cloudProvidersProvider);
    final accounts = ref.watch(cloudAccountsProvider);
    final text = Theme.of(context).textTheme;
    final c = LumaColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xxl),
        children: [
          Text(
            'Connect cloud storage to import its PDF and Word files into your Library. '
            '$appName only reads your files. It never uploads, changes or deletes anything in your accounts.',
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
          const SizedBox(height: Space.lg),
          if (accounts.isLoading && !accounts.hasValue)
            const Padding(
              padding: EdgeInsets.all(Space.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final provider in providers) ...[
              _ProviderCard(provider: provider, account: accounts.value?[provider.id]),
              const SizedBox(height: Space.md),
            ],
        ],
      ),
    );
  }
}

IconData cloudProviderIcon(CloudProviderId id) => switch (id) {
  CloudProviderId.googleDrive => LumaIcons.googleDrive,
  CloudProviderId.oneDrive => LumaIcons.cloud,
  CloudProviderId.iCloudDrive => LumaIcons.cloud,
};

class _ProviderCard extends ConsumerStatefulWidget {
  const _ProviderCard({required this.provider, required this.account});

  final CloudStorageProvider provider;
  final CloudAccount? account;

  @override
  ConsumerState<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends ConsumerState<_ProviderCard> {
  bool _busy = false;

  CloudStorageProvider get provider => widget.provider;

  String get _status {
    final account = widget.account;
    return switch (provider.availability) {
      CloudAvailability.unsupportedPlatform =>
        provider.id == CloudProviderId.iCloudDrive ? 'Only on iPhone and iPad' : 'Not available on this device',
      CloudAvailability.notConfigured => 'Not set up in this build yet',
      CloudAvailability.ready when provider.usesSystemPicker => 'Uses the Apple account on this iPhone',
      CloudAvailability.ready => account == null ? 'Not connected' : 'Connected as ${account.label}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final ready = provider.availability == CloudAvailability.ready;
    final connected = widget.account != null;
    final label = provider.id.label;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(cloudProviderIcon(provider.id)),
              title: Text(label),
              subtitle: Text(_status),
              onTap: ready && connected && !_busy ? _browse : null,
            ),
            if (ready)
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: Space.sm,
                children: [
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(Space.sm),
                      child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (provider.usesSystemPicker)
                    FilledButton.tonal(onPressed: _pick, child: const Text('Choose a file'))
                  else if (connected) ...[
                    TextButton(onPressed: _disconnect, child: const Text('Disconnect')),
                    FilledButton.tonal(onPressed: _browse, child: const Text('Browse files')),
                  ] else
                    FilledButton(onPressed: _connect, child: Text('Connect $label')),
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
      final account = await ref.read(cloudAccountsProvider.notifier).connect(provider);
      if (account != null) messenger.showSnackBar(SnackBar(content: Text('Connected ${account.label}')));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not connect ${provider.id.label}. $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final label = provider.id.label;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Disconnect $label?'),
            content: const Text(
              '$appName forgets this account on this phone. Documents you already imported stay in your Library.',
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
      await ref.read(cloudAccountsProvider.notifier).disconnect(provider);
      messenger.showSnackBar(SnackBar(content: Text('Disconnected $label')));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not disconnect $label. $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _browse() {
    final account = widget.account;
    if (account == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloudBrowseScreen(provider: provider, account: account),
      ),
    );
  }

  Future<void> _pick() async {
    final messenger = ScaffoldMessenger.of(context);
    final PickedCloudFile? picked;
    try {
      picked = await provider.pickFile();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open the file picker ($e)')));
      return;
    }
    if (picked == null || !mounted) return;
    final file = picked;
    final destination = await pickImportFolder(context, file.name);
    if (destination == null || !mounted) {
      _deleteQuietly(file);
      return;
    }
    await runCloudImport(
      context,
      ref,
      name: file.name,
      kind: CloudEntry.kindForName(file.name),
      destination: destination,
      fetch: () async => file.file,
    );
  }

  static void _deleteQuietly(PickedCloudFile file) {
    try {
      file.file.deleteSync();
    } on Object {
      // A temp copy; the system clears these.
    }
  }
}
