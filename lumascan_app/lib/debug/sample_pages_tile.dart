import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/pages/pages_screen.dart';
import '../features/pages/scan_controller.dart';
import 'debug_panel.dart';
import 'sample_pages.dart';

/// Adds the bundled math revision photos to the draft through the normal
/// photo import, with auto-crop, and opens the draft: pages to try batch
/// edit and page detection on. Shown in the debug panel and in Settings >
/// Developer (debug builds only).
class SamplePagesTile extends ConsumerStatefulWidget {
  const SamplePagesTile({super.key, this.onStart, this.contentPadding});

  /// Called once the pages are added, before the draft opens (the debug
  /// panel closes itself).
  final VoidCallback? onStart;

  final EdgeInsetsGeometry? contentPadding;

  @override
  ConsumerState<SamplePagesTile> createState() => _SamplePagesTileState();
}

class _SamplePagesTileState extends ConsumerState<SamplePagesTile> {
  bool _adding = false;

  Future<void> _add() async {
    setState(() => _adding = true);
    final messenger = ScaffoldMessenger.maybeOf(debugNavigatorKey.currentContext ?? context);
    try {
      final photos = await loadSamplePages();
      final result = await ref.read(scanControllerProvider.notifier).importPhotos(photos, autoCrop: true);
      if (!mounted) return;
      widget.onStart?.call();
      messenger?.showSnackBar(SnackBar(content: Text('Added ${result.added} sample pages')));
      if (result.added > 0) {
        (debugNavigatorKey.currentState ?? Navigator.of(context)).push(
          MaterialPageRoute<void>(builder: (_) => const PagesScreen()),
        );
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Sample pages not added ($e)')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: widget.contentPadding,
    leading: _adding
        ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.collections_outlined),
    title: const Text('Add sample pages'),
    subtitle: Text('The ${samplePageAssets.length} math revision photos, auto-cropped, for testing batch edit'),
    onTap: _adding ? null : _add,
  );
}
