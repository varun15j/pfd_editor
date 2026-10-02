import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/scanner_service.dart';
import 'scan_controller.dart';

/// Runs the scanner (or photo import) into the current draft and reports the
/// outcome: a snackbar for added pages and failures, a dialog when the camera
/// is blocked. Returns true when pages were added. Shared by Home, the Scan
/// button and the draft screen so they all react the same way.
Future<bool> runScan(BuildContext context, WidgetRef ref, ScanSource source) async {
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
      final retry = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Camera access needed'),
          content: Text(
            permanently
                ? 'Camera access is turned off for LumaScan. Turn it on in Settings to scan documents. '
                      'You can still import pages from your photos.'
                : 'LumaScan needs the camera to scan documents. Pages stay on this device.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
            if (permanently)
              FilledButton(
                onPressed: () {
                  Navigator.pop(context, false);
                  openAppSettings();
                },
                child: const Text('Open Settings'),
              )
            else
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Try again')),
          ],
        ),
      );
      if (retry == true && context.mounted) return runScan(context, ref, source);
      return false;
  }
}
