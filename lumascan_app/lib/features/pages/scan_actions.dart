import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/scanner_service.dart';
import '../capture/photo_import_screen.dart';
import 'scan_controller.dart';

/// Runs the scanner (or photo import) into the current draft and reports the
/// outcome: a snackbar for added pages and failures, a dialog when the camera
/// is blocked. Returns true when pages were added. Shared by Home, the Scan
/// button and the draft screen so they all react the same way.
Future<bool> runScan(BuildContext context, WidgetRef ref, ScanSource source) async {
  // Photos go through LumaScan's own import, which keeps the chosen order and
  // can auto-crop (C2).
  if (source == ScanSource.gallery) return importPhotosFlow(context, ref);
  final outcome = await ref.read(scanControllerProvider.notifier).scan(source);
  if (!context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  switch (outcome) {
    case ScanAdded(:final count):
      messenger.showSnackBar(SnackBar(content: Text('Added $count page${count == 1 ? '' : 's'}')));
      return true;
    case ScanCancelled():
      return false;
    case ScanFailed(:final message):
      messenger.showSnackBar(SnackBar(content: Text('Scan failed: $message')));
      return false;
    case ScanPermissionBlocked(:final permanently):
      final choice = await showCameraPermissionGuide(context, permanently: permanently);
      if (!context.mounted) return false;
      return switch (choice) {
        CameraGuideChoice.retry => runScan(context, ref, source),
        CameraGuideChoice.importPhotos => runScan(context, ref, ScanSource.gallery),
        CameraGuideChoice.settings => openAppSettings().then((_) => false),
        null => false,
      };
  }
}

enum CameraGuideChoice { retry, settings, importPhotos }

/// Explains why the camera is needed, how to allow it, and offers photo
/// import so the user is never stuck (C1).
Future<CameraGuideChoice?> showCameraPermissionGuide(BuildContext context, {required bool permanently}) =>
    showDialog<CameraGuideChoice>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.no_photography_outlined),
        title: const Text('Camera access needed'),
        content: Text(
          permanently
              ? 'LumaScan uses the camera only to scan pages, and the pages stay on this device. '
                    'Camera access is turned off, so turn it on in Settings, or import photos of the pages instead.'
              : 'LumaScan uses the camera only to scan pages, and the pages stay on this device. '
                    'Allow camera access when asked, or import photos of the pages instead.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not now')),
          TextButton(
            onPressed: () => Navigator.pop(context, CameraGuideChoice.importPhotos),
            child: const Text('Import photos'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, permanently ? CameraGuideChoice.settings : CameraGuideChoice.retry),
            child: Text(permanently ? 'Open Settings' : 'Try again'),
          ),
        ],
      ),
    );
