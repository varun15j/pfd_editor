import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/scanner_service.dart';
import '../../ui/state_views.dart';
import 'document_tile.dart';
import 'library_controller.dart';

/// Library tab: every saved document, newest first. Search, folders, sort
/// and grid view come with B1 in the UI/UX plan.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      // Riverpod keeps retrying a failed load in the background, so an error
      // can arrive while the state still reads as loading; show it anyway.
      body: switch (library) {
        AsyncValue(hasValue: false, hasError: true) => ErrorState(
          title: 'Library could not be opened',
          message: 'Your PDFs are still on this device.',
          onRetry: () => ref.invalidate(libraryProvider),
        ),
        AsyncValue(:final value?) when value.documents.isEmpty => EmptyState(
          icon: Icons.folder_open_outlined,
          title: 'No saved documents yet',
          message: 'PDFs you save will appear here, ready to find and share.',
          actionLabel: 'Scan a document',
          actionIcon: Icons.document_scanner_outlined,
          onAction: () => scanThenReview(context, ref, ScanSource.camera),
        ),
        AsyncValue(:final value?) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xxl * 3),
          itemCount: value.documents.length,
          separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
          itemBuilder: (_, i) => DocumentTile(document: value.documents[i]),
        ),
        _ => const LoadingList(label: 'Loading documents'),
      },
    );
  }
}
