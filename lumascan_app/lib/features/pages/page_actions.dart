import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../crop/crop_screen.dart';
import '../filters/filter_screen.dart';
import 'scan_controller.dart';

/// Per-page actions shared by the gallery and single-page views.
enum PageAction {
  filters('Filters', Icons.tune),
  crop('Crop', Icons.crop),
  rotate('Rotate', Icons.rotate_right),
  delete('Delete page', Icons.delete_outline);

  const PageAction(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Runs [action] on [page], shown to the user as page [index] + 1.
Future<void> runPageAction(BuildContext context, WidgetRef ref, PageAction action, ScanPage page, int index) async {
  final controller = ref.read(scanControllerProvider.notifier);
  switch (action) {
    case PageAction.filters:
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FilterScreen(pageId: page.id)));
    case PageAction.crop:
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CropScreen(pageId: page.id)));
    case PageAction.rotate:
      controller.rotate(page.id);
    case PageAction.delete:
      controller.remove(page.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Page ${index + 1} deleted'),
          action: SnackBarAction(label: 'Undo', onPressed: controller.undo),
        ),
      );
  }
}

/// Bottom sheet listing the actions for one page.
Future<void> showPageActions(BuildContext context, WidgetRef ref, ScanPage page, int index) async {
  final action = await showModalBottomSheet<PageAction>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
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
  );
  if (action != null && context.mounted) await runPageAction(context, ref, action, page, index);
}
