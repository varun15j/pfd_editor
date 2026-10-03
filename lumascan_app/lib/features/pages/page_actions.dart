import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/models.dart';
import '../crop/crop_screen.dart';
import '../filters/filter_screen.dart';
import '../markup/markup_screen.dart';
import 'marks_notice.dart';
import 'scan_controller.dart';

/// Per-page actions shared by the list, gallery and single-page views.
enum PageAction {
  retake('Retake', Icons.camera_alt_outlined),
  crop('Crop', Icons.crop),
  rotate('Rotate', Icons.rotate_right),
  filters('Filters', Icons.tune),
  markup('Markup', Icons.draw_outlined),
  duplicate('Duplicate', Icons.copy_outlined),
  delete('Delete page', Icons.delete_outline);

  const PageAction(this.label, this.icon);

  final String label;
  final IconData icon;

  /// Shorter label for the toolbar under the page.
  String get shortLabel => this == PageAction.delete ? 'Delete' : label;
}

/// Runs [action] on [page], shown to the user as page [index] + 1.
Future<void> runPageAction(BuildContext context, WidgetRef ref, PageAction action, ScanPage page, int index) async {
  final controller = ref.read(scanControllerProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  switch (action) {
    case PageAction.retake:
      final outcome = await controller.retake(page.id);
      switch (outcome) {
        case ScanAdded():
          messenger.showSnackBar(
            SnackBar(
              content: Text('Page ${index + 1} retaken'),
              action: SnackBarAction(label: 'Undo', onPressed: controller.undo),
            ),
          );
        case ScanCancelled():
          break;
        case ScanFailed(:final message):
          messenger.showSnackBar(SnackBar(content: Text('Retake failed: $message')));
        case ScanPermissionBlocked():
          messenger.showSnackBar(
            SnackBar(
              content: const Text('Camera access is off for LumaScan.'),
              action: SnackBarAction(label: 'Open Settings', onPressed: openAppSettings),
            ),
          );
      }
    case PageAction.filters:
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FilterScreen(pageId: page.id)));
    case PageAction.markup:
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MarkupScreen(pageId: page.id)));
    case PageAction.crop:
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CropScreen(pageId: page.id)));
    case PageAction.rotate:
      rotatePage(context, ref, page);
    case PageAction.duplicate:
      controller.duplicate(page.id);
      messenger.showSnackBar(SnackBar(content: Text('Page ${index + 1} duplicated as page ${index + 2}')));
    case PageAction.delete:
      if (ref.read(scanControllerProvider).pages.length == 1) {
        await _confirmDiscardLastPage(context, ref);
        return;
      }
      controller.remove(page.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Page ${index + 1} deleted'),
          action: SnackBarAction(label: 'Undo', onPressed: controller.undo),
        ),
      );
  }
}

/// Rotates [page] a quarter turn clockwise. Marks do not rotate with the page,
/// so they are removed, and the snackbar says so and offers Undo.
void rotatePage(BuildContext context, WidgetRef ref, ScanPage page) {
  final controller = ref.read(scanControllerProvider.notifier);
  final turned = page.recipe.copyWith(quarterTurns: page.recipe.quarterTurns + 1);
  final dropsMarks = controller.dropsMarks(page.id, turned);
  controller.rotate(page.id);
  if (dropsMarks) showMarksRemovedNotice(context, controller);
}

/// Removing the only page would leave an empty document, so this asks
/// whether to discard the whole draft instead.
Future<void> _confirmDiscardLastPage(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Discard this document?'),
      content: const Text('This is the only page. Deleting it discards the document. Exported PDFs are kept.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final navigator = Navigator.of(context);
  await ref.read(scanControllerProvider.notifier).clear();
  if (navigator.canPop()) navigator.pop();
}

/// Bottom sheet listing the actions for one page.
Future<void> showPageActions(BuildContext context, WidgetRef ref, ScanPage page, int index) async {
  final action = await showModalBottomSheet<PageAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Page ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(page.recipe.filter.label),
            ),
            for (final a in PageAction.values)
              ListTile(leading: Icon(a.icon), title: Text(a.label), onTap: () => Navigator.pop(context, a)),
          ],
        ),
      ),
    ),
  );
  if (action != null && context.mounted) await runPageAction(context, ref, action, page, index);
}
