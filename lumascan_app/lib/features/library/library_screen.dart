import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../domain/scanner_service.dart';
import '../../ui/state_views.dart';

/// Library tab. Saved documents are not stored yet (A2 and B1 in the UI/UX
/// plan), so it shows the empty state with the action that fills it.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: EmptyState(
        icon: Icons.folder_open_outlined,
        title: 'No saved documents yet',
        message: 'PDFs you save will appear here, ready to find and share.',
        actionLabel: 'Scan a document',
        actionIcon: Icons.document_scanner_outlined,
        onAction: () => scanThenReview(context, ref, ScanSource.camera),
      ),
    );
  }
}
