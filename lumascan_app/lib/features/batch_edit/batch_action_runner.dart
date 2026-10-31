import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../app/providers.dart';
import '../../domain/id_masking.dart';
import '../../domain/models.dart';
import '../../domain/plan.dart';
import '../../pdf_edit/annotations.dart';
import '../../ui/undo_toast.dart';
import '../../ui/upgrade_dialog.dart';
import '../markup/auto_mask.dart';
import '../pages/page_actions.dart';
import '../pages/scan_controller.dart';
import 'batch_actions.dart';
import 'batch_auto_crop.dart';
import 'batch_crop_queue.dart';
import 'batch_enhance_screen.dart';
import 'batch_ocr_screen.dart';
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
  // The last action's undo toast would otherwise sit over the next screen,
  // such as the markup tools.
  messenger.hideCurrentSnackBar();
  final count = selected.length;
  final noun = 'page${count == 1 ? '' : 's'}';

  switch (action) {
    case BatchAction.enhance:
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => BatchEnhanceScreen(pageIds: [for (final p in selected) p.id])));
    case BatchAction.crop:
      // Auto crop and Full photo for all pages are Pro; Basic adjusts each page.
      final smart = ref.read(planIncludesProvider(PlanFeature.smartScan));
      final choice = smart
          ? await showModalBottomSheet<CropChoice>(
              context: context,
              showDragHandle: true,
              builder: (_) => CropChoiceSheet(count: count),
            )
          : CropChoice.adjust;
      if (choice == null || !context.mounted) return;
      switch (choice) {
        case CropChoice.adjust:
          final summary = await runCropQueue(Navigator.of(context), [for (final p in selected) p.id]);
          messenger
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text(summary.message)));
        case CropChoice.auto:
          final found = await autoCropPages(context, ref.read(photoAnalyzerProvider), selected);
          if (found == null) return;
          controller.setCrops(found);
          final missed = count - found.length;
          showUndoToast(
            messenger,
            message: [
              'Auto cropped ${found.length} page${found.length == 1 ? '' : 's'}',
              if (missed > 0) 'no page found on $missed',
            ].join(', '),
            onUndo: controller.undo,
          );
        case CropChoice.full:
          controller.setCrops({for (final p in selected) p.id: CropQuad.full});
          showUndoToast(messenger, message: 'Full photo on $count $noun', onUndo: controller.undo);
      }
    case BatchAction.ocr:
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              BatchOcrScreen(pageIds: [for (final p in selected) p.id], languageCode: ref.read(ocrLanguageProvider)),
        ),
      );
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
    case BatchAction.maskIds:
      await _maskIds(context, ref, selected);
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

/// Auto mask on every selected page (Pro and Gold), one undo step for all.
Future<void> _maskIds(BuildContext context, WidgetRef ref, List<ScanPage> pages) async {
  if (!await ensurePlan(context, ref, PlanFeature.autoMask, what: 'Auto mask')) return;
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  final (engine, reason) = await autoMaskEngine(ref.read(ocrEngineProvider));
  if (engine == null) {
    say(reason!);
    return;
  }
  if (!context.mounted) return;
  final done = ValueNotifier(0);
  final navigator = Navigator.of(context);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Looking for ID numbers'),
          content: ValueListenableBuilder<int>(
            valueListenable: done,
            builder: (_, n, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: pages.isEmpty ? null : n / pages.length),
                const SizedBox(height: 12),
                Text('Page ${n < pages.length ? n + 1 : n} of ${pages.length}, read on this phone'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  final store = ref.read(pageStoreProvider);
  final added = <String, List<Annotation>>{};
  final found = <IdMatch>[];
  var failed = 0;
  try {
    for (final page in pages) {
      try {
        final hits = await findIdsOnPage(engine, page);
        found.addAll(hits);
        added[page.id] = masksFor(hits, store.newId);
      } catch (_) {
        failed++;
      }
      done.value++;
    }
  } finally {
    navigator.pop();
    done.dispose();
  }
  final marked = added.values.where((m) => m.isNotEmpty).length;
  if (found.isEmpty) {
    say(failed > 0 ? 'Could not read $failed of the pages. Mask them by hand in Markup.' : 'No ID numbers found.');
    return;
  }
  final controller = ref.read(scanControllerProvider.notifier);
  controller.addAnnotations(added);
  showUndoToast(
    messenger,
    message: [
      autoMaskSummary(found, pages: marked),
      if (failed > 0) 'Could not read $failed ${failed == 1 ? 'page' : 'pages'}.',
    ].join(' '),
    onUndo: controller.undo,
  );
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
