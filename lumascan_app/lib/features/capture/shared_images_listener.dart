import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/shell.dart';
import '../../domain/share_inbox.dart';
import '../pages/scan_controller.dart';
import 'photo_import_screen.dart';

/// Picks up images shared into the app from the gallery's share sheet
/// (Android "Share", iOS share extension) and runs them through photo
/// import as a new document: the user sets the order and auto-crop, then
/// the document opens with the pages arriving.
///
/// The inbox is checked when the app starts and each time it comes back to
/// the foreground, which is what a share does. A share that arrives while
/// pages are being added waits for the next check.
class SharedImagesListener extends ConsumerStatefulWidget {
  const SharedImagesListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SharedImagesListener> createState() => _SharedImagesListenerState();
}

class _SharedImagesListenerState extends ConsumerState<SharedImagesListener> with WidgetsBindingObserver {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final inbox = ref.read(shareInboxProvider);
      final List<SharedBatch> batches;
      try {
        batches = await inbox.pending();
      } catch (_) {
        return;
      }
      if (batches.isEmpty || !mounted) return;
      final photos = [for (final b in batches) ...b.photos];
      if (photos.isEmpty) {
        for (final b in batches) {
          await inbox.discard(b);
        }
        return;
      }
      if (ref.read(scanControllerProvider).busy) return;
      try {
        await addShowingDraft(
          context,
          (onAdding) => importPhotosFlow(context, ref, photos: photos, newDocument: true, onAdding: onAdding),
        );
      } finally {
        // Imported pages are copied into the app's own storage, and a share
        // the user turned down is not offered again.
        for (final b in batches) {
          await inbox.discard(b);
        }
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
