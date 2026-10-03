import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/scanner_service.dart';
import '../pages/scan_actions.dart';

/// "Add pages" on a document being reviewed: camera or photos. New pages go
/// to the end, where they can be dragged into place.
Future<void> showAddPagesSheet(BuildContext context, WidgetRef ref) async {
  final source = await showModalBottomSheet<ScanSource>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xs),
            child: Semantics(header: true, child: Text('Add pages', style: Theme.of(sheet).textTheme.titleLarge)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
            child: Text(
              'New pages are added at the end. Drag them to move them.',
              style: Theme.of(sheet).textTheme.bodyMedium?.copyWith(color: LumaColors.of(sheet).muted),
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
            leading: const Icon(Icons.document_scanner_outlined),
            title: const Text('Scan with camera'),
            onTap: () => Navigator.pop(sheet, ScanSource.camera),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Import photos'),
            onTap: () => Navigator.pop(sheet, ScanSource.gallery),
          ),
          const SizedBox(height: Space.md),
        ],
      ),
    ),
  );
  if (source != null && context.mounted) await runScan(context, ref, source);
}
