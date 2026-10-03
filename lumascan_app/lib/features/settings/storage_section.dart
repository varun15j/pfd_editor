import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/page_store.dart';
import '../../ui/file_size.dart';

/// Space the app uses, read when Settings opens and again after clearing.
final storageUsageProvider = FutureProvider.autoDispose<StorageUsage>((ref) => ref.watch(pageStoreProvider).usage());

/// Storage: space used by what, and a Clear cache action that only removes
/// files the app can rebuild.
class StorageSection extends ConsumerWidget {
  const StorageSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(storageUsageProvider);
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;

    Widget row(String label, int bytes) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(formatFileSize(bytes), style: text.bodyMedium?.copyWith(color: c.muted)),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text('Storage', style: text.titleMedium)),
        const SizedBox(height: Space.sm),
        usage.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.md),
            child: Text('Checking…'),
          ),
          error: (e, _) => Text('Could not read storage use. ($e)'),
          data: (u) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row('Saved PDFs and previews', u.savedPdfs),
              row('Pages of the current document', u.pageOriginals),
              row('Cache', u.cache),
              const Divider(),
              row('Total', u.total),
              const SizedBox(height: Space.sm),
              Text(
                'Cache holds page previews and smaller copies made for sending. Clearing it keeps your saved PDFs and pages, and previews are made again when needed.',
                style: text.bodySmall?.copyWith(color: c.muted),
              ),
              const SizedBox(height: Space.sm),
              OutlinedButton.icon(
                onPressed: () => _clear(context, ref, u.cache),
                icon: const Icon(Icons.cleaning_services_outlined),
                label: const Text('Clear cache'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref, int cacheBytes) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear cache?'),
        content: Text(
          'This frees ${formatFileSize(cacheBytes)}. Your saved PDFs and the pages of your current document are kept.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear cache')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final freed = await ref.read(pageStoreProvider).clearCache();
      // Previews on screen were deleted with the cache; render them again.
      ref.read(renderServiceProvider).evictAll();
      ref.invalidate(storageUsageProvider);
      messenger.showSnackBar(SnackBar(content: Text('Cleared ${formatFileSize(freed)}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not clear the cache ($e)')));
    }
  }
}
