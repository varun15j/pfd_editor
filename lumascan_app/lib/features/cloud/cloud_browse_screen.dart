import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/cloud_storage.dart';
import '../../ui/file_size.dart';
import '../capture/pdf_import.dart';
import '../library/document_tile.dart' show formatModified;
import 'cloud_accounts.dart';
import 'cloud_import_flow.dart';
import '../../ui/luma_icons.dart';

/// Folders and files in a connected cloud account. Tapping a folder opens
/// it; tapping a PDF (or a Google Doc) opens its pages in Batch Review as a
/// new document; tapping a Word file imports it into a chosen Library folder.
/// Other files are listed but cannot be imported.
class CloudBrowseScreen extends ConsumerStatefulWidget {
  const CloudBrowseScreen({super.key, required this.provider, required this.account});

  final CloudStorageProvider provider;
  final CloudAccount account;

  @override
  ConsumerState<CloudBrowseScreen> createState() => _CloudBrowseScreenState();
}

class _CloudBrowseScreenState extends ConsumerState<CloudBrowseScreen> {
  /// Folders opened from the top, the last one being shown.
  final _path = <CloudEntry>[];
  late Future<List<CloudEntry>> _listing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _listing = widget.provider.list(_path.lastOrNull?.id);

  void _open(CloudEntry folder) => setState(() {
    _path.add(folder);
    _load();
  });

  void _up() => setState(() {
    _path.removeLast();
    _load();
  });

  Future<void> _refresh() async {
    setState(_load);
    await _listing.catchError((Object _) => <CloudEntry>[]);
  }

  @override
  Widget build(BuildContext context) {
    final title = _path.lastOrNull?.name ?? widget.provider.id.label;
    return PopScope(
      canPop: _path.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _path.isNotEmpty) _up();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, overflow: TextOverflow.ellipsis),
              Text(widget.account.label, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        body: FutureBuilder<List<CloudEntry>>(
          future: _listing,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final error = snapshot.error;
            if (error != null) return _ErrorView(error: error, onRetry: () => setState(_load), onSignedOut: _signedOut);
            final entries = snapshot.data ?? const <CloudEntry>[];
            return RefreshIndicator(
              onRefresh: _refresh,
              child: entries.isEmpty
                  ? ListView(
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(Space.xxl),
                          child: Center(child: Text('This folder is empty.')),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: Space.xxl),
                      itemCount: entries.length,
                      itemBuilder: (context, i) => _EntryTile(
                        entry: entries[i],
                        onTap: entries[i].isFolder ? () => _open(entries[i]) : () => _import(entries[i]),
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }

  void _signedOut() {
    ref.read(cloudAccountsProvider.notifier).signedOut(widget.provider.id);
    Navigator.of(context).pop();
  }

  Future<void> _import(CloudEntry entry) async {
    if (!entry.kind.importable) return;
    if (opensAsPages(entry.kind)) return _openAsPages(entry);
    final destination = await pickImportFolder(context, entry.name);
    if (destination == null || !mounted) return;
    final dir = await ref.read(cloudDownloadDirProvider)();
    if (!mounted) return;
    final signedIn = await runCloudImport(
      context,
      ref,
      name: entry.name,
      kind: entry.kind,
      destination: destination,
      fetch: () => widget.provider.download(entry, dir),
    );
    if (!signedIn && mounted) _signedOut();
  }

  /// Downloads a PDF (or a Google Doc as PDF) and opens its pages in Batch
  /// Review as a new document.
  Future<void> _openAsPages(CloudEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final dir = await ref.read(cloudDownloadDirProvider)();
    if (!mounted) return;
    try {
      await importPdfToBatchEdit(
        context,
        ref,
        name: entry.kind == CloudEntryKind.googleDoc ? '${entry.name}.pdf' : entry.name,
        fetch: (_) => widget.provider.download(entry, dir),
      );
    } on CloudSignInExpired {
      messenger.showSnackBar(const SnackBar(content: Text('The sign-in has expired. Connect the account again.')));
      if (mounted) _signedOut();
    }
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final CloudEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = entry.isFolder || entry.kind.importable;
    final details = <String>[
      if (entry.kind == CloudEntryKind.googleDoc) 'Google Docs, imported as PDF',
      if (entry.kind == CloudEntryKind.other) 'Only PDF and Word files can be imported',
      if (!entry.isFolder && entry.sizeBytes != null) formatFileSize(entry.sizeBytes!),
      if (!entry.isFolder && entry.modifiedAt != null) formatModified(entry.modifiedAt!.toLocal(), DateTime.now()),
    ];
    return ListTile(
      enabled: enabled,
      leading: Icon(switch (entry.kind) {
        CloudEntryKind.folder => LumaIcons.folder,
        CloudEntryKind.pdf => LumaIcons.pdf,
        CloudEntryKind.word => LumaIcons.document,
        CloudEntryKind.googleDoc => LumaIcons.article,
        CloudEntryKind.other => LumaIcons.file,
      }),
      title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      trailing: entry.isFolder
          ? const Icon(LumaIcons.next)
          : enabled
          ? const Icon(LumaIcons.download, semanticLabel: 'Import')
          : null,
      onTap: enabled ? onTap : null,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry, required this.onSignedOut});

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) {
    final expired = error is CloudSignInExpired;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expired ? 'The sign-in has expired. Connect the account again.' : 'Could not load this folder. $error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.lg),
            if (expired)
              FilledButton(onPressed: onSignedOut, child: const Text('Back to Accounts'))
            else
              FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
