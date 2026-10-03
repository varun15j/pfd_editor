import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../domain/scanner_service.dart';
import '../capture/add_pages_sheet.dart';
import '../crop/crop_screen.dart';
import '../export/export_sheet.dart';
import '../filters/filter_screen.dart';
import '../pdf_editor/open_pdf.dart';
import 'page_actions.dart';
import 'page_gallery.dart';
import 'page_image.dart';
import 'page_single_view.dart';
import 'scan_actions.dart';
import 'scan_controller.dart';

/// Draft review screen (S08 Pages): every captured page, in order, with
/// crop, rotate, filter and delete actions, plus add-more and export.
/// Pages show as a list, a gallery grid or one page at a time; a menu in the
/// app bar switches between them.
class PagesScreen extends ConsumerStatefulWidget {
  const PagesScreen({super.key});

  @override
  ConsumerState<PagesScreen> createState() => _PagesScreenState();
}

class _PagesScreenState extends ConsumerState<PagesScreen> {
  PagesLayout _layout = PagesLayout.page;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanControllerProvider);
    final controller = ref.read(scanControllerProvider.notifier);
    final pages = state.pages;

    return PopScope(
      canPop: !state.unsaved || pages.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave(context, ref);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(pages.isEmpty ? 'LumaScan' : '${pages.length} page${pages.length == 1 ? '' : 's'}'),
          actions: [
            if (pages.isNotEmpty)
              PopupMenuButton<PagesLayout>(
                tooltip: 'Change view',
                icon: Icon(_layout.icon),
                initialValue: _layout,
                onSelected: (layout) => setState(() => _layout = layout),
                itemBuilder: (context) => [
                  for (final l in PagesLayout.values)
                    CheckedPopupMenuItem(value: l, checked: l == _layout, child: Text(l.label)),
                ],
              ),
            if (pages.isNotEmpty) ...[
              IconButton(
                tooltip: 'Undo',
                icon: const Icon(Icons.undo),
                onPressed: state.canUndo ? controller.undo : null,
              ),
              IconButton(
                tooltip: 'Redo',
                icon: const Icon(Icons.redo),
                onPressed: state.canRedo ? controller.redo : null,
              ),
            ],
            if (pages.isNotEmpty)
              IconButton(
                tooltip: 'Discard draft',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () => _confirmDiscard(context, ref),
              ),
          ],
        ),
        body: pages.isEmpty
            ? _EmptyState(busy: state.busy, onScan: (s) => _scan(context, ref, s))
            : switch (_layout) {
                PagesLayout.gallery => PageGallery(pages: pages),
                PagesLayout.page => PageSingleView(pages: pages),
                PagesLayout.list => ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  itemCount: pages.length,
                  buildDefaultDragHandles: false,
                  onReorderItem: controller.move,
                  itemBuilder: (context, i) => _PageCard(key: ValueKey(pages[i].id), index: i, page: pages[i]),
                ),
              },
        bottomNavigationBar: pages.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                          onPressed: state.busy ? null : () => showAddPagesSheet(context, ref),
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: const Text('Add pages'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: state.busy ? null : () => showExportSheet(context),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Export PDF'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  /// Asks before leaving a draft that hasn't been exported since it changed.
  /// The pages are autosaved, so keeping the draft loses nothing.
  Future<void> _confirmLeave(BuildContext context, WidgetRef ref) async {
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave without exporting?'),
        content: const Text(
          "These pages haven't been saved as a PDF yet. Keep them as a draft to finish later, or discard them.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, _LeaveChoice.discard), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(context, _LeaveChoice.keep), child: const Text('Keep draft')),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    final navigator = Navigator.of(context);
    final draft = ref.read(scanControllerProvider.notifier);
    // Popping with pages left would ask again, so mark them as handled first.
    if (choice == _LeaveChoice.keep) draft.markSaved();
    navigator.pop();
    // Delete the files after the screen is gone so no page shows a missing image.
    if (choice == _LeaveChoice.discard) await draft.clear();
  }

  Future<void> _scan(BuildContext context, WidgetRef ref, ScanSource source) => runScan(context, ref, source);

  Future<void> _confirmDiscard(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard all pages?'),
        content: const Text('The scanned pages in this draft will be deleted. Exported PDFs are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    if (ok == true) await ref.read(scanControllerProvider.notifier).clear();
  }
}

enum _LeaveChoice { keep, discard }

/// How the Pages screen lays out the draft's pages.
enum PagesLayout {
  list('List view', Icons.view_list_outlined),
  gallery('Gallery view', Icons.grid_view_outlined),
  page('Page view', Icons.crop_portrait_outlined);

  const PagesLayout(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.busy, required this.onScan});

  final bool busy;
  final void Function(ScanSource) onScan;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 24),
        Text('Scan a document', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Edges are found automatically. Capture as many pages as you need, then crop, '
          'apply filters and export one PDF.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Material(
          color: LumaColors.of(context).accent,
          borderRadius: BorderRadius.circular(21),
          child: InkWell(
            borderRadius: BorderRadius.circular(21),
            onTap: busy ? null : () => onScan(ScanSource.camera),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scan with camera',
                          style: TextStyle(
                            color: LumaColors.of(context).onAccent,
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Auto edge detection and multi-page capture',
                          style: TextStyle(color: LumaColors.of(context).onAccent, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.document_scanner_outlined, color: LumaColors.of(context).onAccent, size: 40),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: busy ? null : () => onScan(ScanSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Import from photos'),
        ),
        const SizedBox(height: 12),
        Consumer(
          builder: (context, ref, _) => OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: busy ? null : () => pickAndEditPdf(context, ref),
            icon: const Icon(Icons.edit_document),
            label: const Text('Edit a PDF'),
          ),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class _PageCard extends ConsumerWidget {
  const _PageCard({super.key, required this.index, required this.page});

  final int index;
  final ScanPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(scanControllerProvider.notifier);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FilterScreen(pageId: page.id))),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(width: 64, height: 84, child: PageImage(page: page)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Page ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(page.recipe.filter.label, style: Theme.of(context).textTheme.bodySmall),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Crop',
                          icon: const Icon(Icons.crop),
                          onPressed: () =>
                              Navigator.of(context)
                                  .push(MaterialPageRoute<void>(builder: (_) => CropScreen(pageId: page.id))),
                        ),
                        IconButton(
                          tooltip: 'Rotate',
                          icon: const Icon(Icons.rotate_right),
                          onPressed: () => controller.rotate(page.id),
                        ),
                        IconButton(
                          tooltip: 'Delete page',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => runPageAction(context, ref, PageAction.delete, page, index),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
