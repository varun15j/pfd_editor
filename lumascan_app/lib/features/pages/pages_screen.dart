import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/app.dart';
import '../../domain/models.dart';
import '../../domain/scanner_service.dart';
import '../crop/crop_screen.dart';
import '../export/export_sheet.dart';
import '../filters/filter_screen.dart';
import '../pdf_editor/open_pdf.dart';
import 'page_image.dart';
import 'scan_controller.dart';

/// Draft review screen (S08 Pages): every captured page, in order, with
/// crop, rotate, filter and delete actions, plus add-more and export.
class PagesScreen extends ConsumerWidget {
  const PagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanControllerProvider);
    final controller = ref.read(scanControllerProvider.notifier);
    final pages = state.pages;

    return Scaffold(
      appBar: AppBar(
        title: Text(pages.isEmpty ? 'LumaScan' : '${pages.length} page${pages.length == 1 ? '' : 's'}'),
        actions: [
          if (state.canUndo)
            IconButton(tooltip: 'Undo', icon: const Icon(Icons.undo), onPressed: controller.undo),
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
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              itemCount: pages.length,
              buildDefaultDragHandles: false,
              onReorderItem: controller.move,
              itemBuilder: (context, i) => _PageCard(
                key: ValueKey(pages[i].id),
                index: i,
                page: pages[i],
              ),
            ),
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
                        onPressed: state.busy ? null : () => _scan(context, ref, ScanSource.camera),
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
    );
  }

  Future<void> _scan(BuildContext context, WidgetRef ref, ScanSource source) async {
    final outcome = await ref.read(scanControllerProvider.notifier).scan(source);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (outcome) {
      case ScanAdded(:final count):
        messenger.showSnackBar(SnackBar(content: Text('Added $count page${count == 1 ? '' : 's'}')));
      case ScanCancelled():
        break;
      case ScanFailed(:final message):
        messenger.showSnackBar(SnackBar(content: Text('Scan failed: $message')));
      case ScanPermissionBlocked(:final permanently):
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Camera access needed'),
            content: Text(permanently
                ? 'Camera access is turned off for LumaScan. Turn it on in Settings to scan documents. '
                    'You can still import pages from your photos.'
                : 'LumaScan needs the camera to scan documents. Pages stay on this device.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not now')),
              if (permanently)
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    openAppSettings();
                  },
                  child: const Text('Open Settings'),
                )
              else
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _scan(context, ref, source);
                  },
                  child: const Text('Try again'),
                ),
            ],
          ),
        );
    }
  }

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
          color: LumaScanApp.teal,
          borderRadius: BorderRadius.circular(21),
          child: InkWell(
            borderRadius: BorderRadius.circular(21),
            onTap: busy ? null : () => onScan(ScanSource.camera),
            child: const Padding(
              padding: EdgeInsets.all(22),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Scan with camera',
                            style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w600)),
                        SizedBox(height: 6),
                        Text('Auto edge detection and multi-page capture',
                            style: TextStyle(color: Color(0xFFCEE5DC), fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(Icons.document_scanner_outlined, color: Colors.white, size: 40),
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
        if (busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
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
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFDFE6E0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => FilterScreen(pageId: page.id)),
        ),
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
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => CropScreen(pageId: page.id)),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Rotate',
                          icon: const Icon(Icons.rotate_right),
                          onPressed: () => controller.rotate(page.id),
                        ),
                        IconButton(
                          tooltip: 'Delete page',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            controller.remove(page.id);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Page ${index + 1} deleted'),
                              action: SnackBarAction(label: 'Undo', onPressed: controller.undo),
                            ));
                          },
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
