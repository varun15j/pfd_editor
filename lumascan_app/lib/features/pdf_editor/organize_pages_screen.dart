import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pdf_edit/annotations.dart';
import '../../pdf_edit/pdf_edit_controller.dart';

/// Reorder and delete pages. Drag the handle to reorder; Move up and Move
/// down give the same result without dragging (PDF-02 accessibility).
/// Tapping a page returns its index so the editor can jump to it.
class OrganizePagesScreen extends ConsumerWidget {
  const OrganizePagesScreen({super.key, required this.thumbnail});

  final Widget Function(EditorPage page) thumbnail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pdfEditControllerProvider);
    final controller = ref.read(pdfEditControllerProvider.notifier);
    final pages = state.pages;

    return Scaffold(
      appBar: AppBar(
        title: Text('${pages.length} page${pages.length == 1 ? '' : 's'}'),
        actions: [
          if (state.canUndo) IconButton(tooltip: 'Undo', icon: const Icon(Icons.undo), onPressed: controller.undo),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        buildDefaultDragHandles: false,
        itemCount: pages.length,
        onReorderItem: controller.movePage,
        itemBuilder: (context, i) {
          final page = pages[i];
          return Card(
            key: ValueKey(page.id),
            margin: const EdgeInsets.only(bottom: 10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.pop(context, i),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      height: 84,
                      child: Center(
                        child: AspectRatio(aspectRatio: page.aspect, child: thumbnail(page)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Page ${i + 1}', style: Theme.of(context).textTheme.titleMedium),
                          if (page.annotations.isNotEmpty)
                            Text(
                              '${page.annotations.length} mark${page.annotations.length == 1 ? '' : 's'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Page actions',
                      onSelected: (action) {
                        switch (action) {
                          case 'up':
                            controller.movePage(i, i - 1);
                          case 'down':
                            controller.movePage(i, i + 1);
                          case 'delete':
                            _delete(context, ref, page.id, i);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'up', enabled: i > 0, child: const Text('Move up')),
                        PopupMenuItem(value: 'down', enabled: i < pages.length - 1, child: const Text('Move down')),
                        PopupMenuItem(value: 'delete', enabled: pages.length > 1, child: const Text('Delete page')),
                      ],
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle, semanticLabel: 'Drag to reorder'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _delete(BuildContext context, WidgetRef ref, String pageId, int index) {
    final controller = ref.read(pdfEditControllerProvider.notifier);
    if (!controller.deletePage(pageId)) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted page ${index + 1}'),
          action: SnackBarAction(label: 'Undo', onPressed: controller.undo),
        ),
      );
  }
}
