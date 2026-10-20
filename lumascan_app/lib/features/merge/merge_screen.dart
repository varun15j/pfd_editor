import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../ui/file_size.dart';
import 'library_pick_screen.dart';
import 'merge_controller.dart';
import 'merge_sheet.dart';
import 'pdf_inspector.dart';
import 'pdf_picker.dart';

/// Merge PDFs: add files from the Library or the device, drag them into
/// order, and save the result as a new document. Files that are locked or
/// cannot be read are flagged and must be removed before merging.
class MergeScreen extends ConsumerWidget {
  const MergeScreen({super.key});

  Future<void> _addFromLibrary(BuildContext context, WidgetRef ref) async {
    final picked = await Navigator.of(context)
        .push<List<NewMergeSource>>(MaterialPageRoute(builder: (_) => const LibraryPickScreen()));
    if (picked != null) ref.read(mergeControllerProvider.notifier).add(picked);
  }

  Future<void> _addFromDevice(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await ref.read(pdfPickerProvider).pick();
      ref.read(mergeControllerProvider.notifier).add([
        for (final f in picked) NewMergeSource(name: f.name, path: f.path),
      ]);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not add those files ($e)')));
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('From Library'),
              subtitle: const Text('PDFs you saved in LumaScan'),
              onTap: () => Navigator.pop(sheet, true),
            ),
            ListTile(
              leading: const Icon(Icons.smartphone_outlined),
              title: const Text('From this device'),
              subtitle: const Text('Choose PDF files'),
              onTap: () => Navigator.pop(sheet, false),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice) {
      await _addFromLibrary(context, ref);
    } else {
      await _addFromDevice(context, ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mergeControllerProvider);
    final controller = ref.read(mergeControllerProvider.notifier);
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    final sources = state.sources;

    return Scaffold(
      appBar: AppBar(title: const Text('Merge PDFs')),
      body: sources.isEmpty
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(child: Icon(Icons.library_add_outlined, size: 56, color: c.accent)),
                    const SizedBox(height: Space.lg),
                    Text('Combine PDFs into one', style: text.titleLarge, textAlign: TextAlign.center),
                    const SizedBox(height: Space.sm),
                    Text(
                      'Add two or more PDFs, put them in order, and save the result as a new document. '
                      'Your originals are not changed.',
                      style: text.bodyMedium?.copyWith(color: c.muted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.sm),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Drag the handle to change the order.',
                      style: text.bodySmall?.copyWith(color: c.muted),
                    ),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.lg),
                    itemCount: sources.length,
                    onReorderItem: controller.reorder,
                    itemBuilder: (context, i) => _SourceTile(
                      key: ValueKey(sources[i].key),
                      index: i,
                      source: sources[i],
                      onRemove: () => controller.remove(sources[i].key),
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sources.isNotEmpty) ...[
                Text(
                  state.flagged.isNotEmpty
                      ? 'Remove the files marked above to continue.'
                      : sources.length < 2
                      ? 'Add at least one more PDF to merge.'
                      : '${sources.length} PDFs · ${state.totalPages} pages',
                  style: text.bodySmall?.copyWith(color: state.flagged.isNotEmpty ? c.danger : c.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.sm),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _add(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Add PDFs'),
                    ),
                  ),
                  if (sources.isNotEmpty) ...[
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: FilledButton(
                        onPressed: state.canMerge
                            ? () async {
                                final navigator = Navigator.of(context);
                                final messenger = ScaffoldMessenger.of(context);
                                if (await showMergeSheet(context)) {
                                  navigator.pop();
                                  messenger.showSnackBar(const SnackBar(content: Text('Merged PDF saved to Library')));
                                }
                              }
                            : null,
                        child: const Text('Merge'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({super.key, required this.index, required this.source, required this.onRemove});

  final int index;
  final MergeSource source;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final problem = source.problem;
    final pages = source.pages;
    final size = source.sizeBytes;
    final detail = switch (problem) {
      PdfProblem.locked => 'Password protected. Remove it, or save an unlocked copy first.',
      PdfProblem.unreadable => 'This file cannot be read as a PDF.',
      null => [
        if (pages != null) '$pages page${pages == 1 ? '' : 's'}' else 'Checking…',
        if (size != null) formatFileSize(size),
      ].join(' · '),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: Space.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: problem == null ? BorderSide.none : BorderSide(color: c.danger),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: Space.sm, right: Space.xs),
        leading: ReorderableDragStartListener(
          index: index,
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Icon(Icons.drag_handle, semanticLabel: 'Drag to reorder ${source.name}'),
          ),
        ),
        title: Text(source.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            if (problem != null) ...[
              Icon(problem == PdfProblem.locked ? Icons.lock_outline : Icons.error_outline, size: 16, color: c.danger),
              const SizedBox(width: Space.xs),
            ],
            Expanded(
              child: Text(detail, style: TextStyle(color: problem == null ? c.muted : c.danger)),
            ),
          ],
        ),
        trailing: IconButton(tooltip: 'Remove ${source.name}', icon: const Icon(Icons.close), onPressed: onRemove),
      ),
    );
  }
}
