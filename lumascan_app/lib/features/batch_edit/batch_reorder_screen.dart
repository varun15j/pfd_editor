import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/models.dart';
import '../pages/page_image.dart';
import '../pages/scan_controller.dart';

/// Reorder (BE-06): the document's pages in order, with a drag handle and
/// Move up / Move down buttons on each, so the order can be changed without
/// dragging. Done saves the new order as one undo step; Cancel or Back
/// leaves the document as it was. Pages selected in Batch Review keep their
/// check mark, because selection follows the page, not the position.
class BatchReorderScreen extends ConsumerStatefulWidget {
  const BatchReorderScreen({super.key, this.selectedIds = const {}});

  final Set<String> selectedIds;

  @override
  ConsumerState<BatchReorderScreen> createState() => _BatchReorderScreenState();
}

class _BatchReorderScreenState extends ConsumerState<BatchReorderScreen> {
  late final List<String> _entryOrder = [for (final p in ref.read(scanControllerProvider).pages) p.id];
  late final List<String> _order = [..._entryOrder];

  bool get _changed => _order.join('/') != _entryOrder.join('/');

  void _move(int from, int to) => setState(() => _order.insert(to, _order.removeAt(from)));

  void _done() {
    if (_changed) {
      final controller = ref.read(scanControllerProvider.notifier);
      controller.reorderPages(_order);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: const Text('Page order changed'),
            action: SnackBarAction(label: 'Undo', onPressed: controller.undo),
          ),
        );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final pages = ref.watch(scanControllerProvider).pages;
    final byId = {for (final p in pages) p.id: p};
    final order = [
      for (final id in _order)
        if (byId.containsKey(id)) id,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reorder pages'),
        actions: [TextButton(onPressed: _done, child: const Text('Done'))],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        buildDefaultDragHandles: false,
        itemCount: order.length,
        onReorderItem: _move,
        itemBuilder: (context, i) => _ReorderTile(
          key: ValueKey(order[i]),
          page: byId[order[i]]!,
          index: i,
          count: order.length,
          selected: widget.selectedIds.contains(order[i]),
          onMoveUp: i == 0 ? null : () => _move(i, i - 1),
          onMoveDown: i == order.length - 1 ? null : () => _move(i, i + 1),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _done,
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReorderTile extends StatelessWidget {
  const _ReorderTile({
    super.key,
    required this.page,
    required this.index,
    required this.count,
    required this.selected,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final ScanPage page;
  final int index;
  final int count;
  final bool selected;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            SizedBox(width: 52, height: 68, child: PageImage(page: page)),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                label: 'Page ${index + 1} of $count${selected ? ', selected' : ''}',
                excludeSemantics: true,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Page ${index + 1}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.check_circle, size: 18, color: colors.accent),
                    ],
                  ],
                ),
              ),
            ),
            IconButton(tooltip: 'Move page ${index + 1} up', icon: const Icon(Icons.arrow_upward), onPressed: onMoveUp),
            IconButton(
              tooltip: 'Move page ${index + 1} down',
              icon: const Icon(Icons.arrow_downward),
              onPressed: onMoveDown,
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.drag_handle)),
            ),
          ],
        ),
      ),
    );
  }
}
