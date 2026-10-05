import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/undo_toast.dart';
import '../pages/page_actions.dart';
import '../pages/scan_controller.dart';
import 'batch_actions.dart';
import 'batch_crop_queue.dart';
import 'batch_enhance_screen.dart';
import 'batch_reorder_screen.dart';
import 'batch_selection.dart';

/// Runs [action] on the selected pages. Every change that touches several
/// pages is one undo step, offered right away in an undo toast.
Future<void> runBatchAction(BuildContext context, WidgetRef ref, BatchAction action, BatchSelection selection) async {
  final controller = ref.read(scanControllerProvider.notifier);
  final pages = ref.read(scanControllerProvider).pages;
  final selected = selection.pagesIn(pages);
  if (selected.isEmpty && action.needsSelection) return;
  final messenger = ScaffoldMessenger.of(context);
  final count = selected.length;
  final noun = 'page${count == 1 ? '' : 's'}';

  switch (action) {
    case BatchAction.enhance:
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => BatchEnhanceScreen(pageIds: [for (final p in selected) p.id])));
    case BatchAction.crop:
      final summary = await runCropQueue(Navigator.of(context), [for (final p in selected) p.id]);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(summary.message)));
    case BatchAction.rotate:
      final dropsMarks = controller.rotationDropsMarks(selection.ids);
      controller.rotatePages(selection.ids);
      showUndoToast(
        messenger,
        message: dropsMarks ? 'Rotated $count $noun. Markup on them was removed' : 'Rotated $count $noun',
        onUndo: controller.undo,
      );
    case BatchAction.delete:
      if (count == pages.length) {
        await _confirmDiscardDocument(context, ref);
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete $count $noun?'),
          content: const Text('You can undo this right after.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok != true) return;
      controller.removePages(selection.ids);
      showUndoToast(messenger, message: 'Deleted $count $noun', onUndo: controller.undo);
    case BatchAction.reorder:
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => BatchReorderScreen(selectedIds: selection.ids)));
    case BatchAction.retake:
    case BatchAction.markup:
    case BatchAction.duplicate:
      final page = selected.single;
      await runPageAction(context, ref, _pageActions[action]!, page, pages.indexOf(page));
  }
}

const _pageActions = {
  BatchAction.retake: PageAction.retake,
  BatchAction.markup: PageAction.markup,
  BatchAction.duplicate: PageAction.duplicate,
};

/// Deleting every page leaves no document, so this asks to discard it and
/// leaves Batch Review when the user agrees (US-03.5 AC 7).
Future<void> _confirmDiscardDocument(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Discard this document?'),
      content: const Text(
        'All pages are selected. Deleting them discards the whole document, and this cannot be undone. '
        'Exported PDFs are kept.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard document')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final navigator = Navigator.of(context);
  if (navigator.canPop()) navigator.pop();
  await ref.read(scanControllerProvider.notifier).clear();
}
