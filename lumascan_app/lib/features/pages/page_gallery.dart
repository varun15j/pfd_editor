import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/models.dart';
import '../crop/crop_screen.dart';
import '../filters/filter_screen.dart';
import 'page_image.dart';
import 'scan_controller.dart';

/// Gallery layout for the Pages screen: a grid of page thumbnails with the
/// page number under each. Tap a page for its actions; long-press and drag
/// it onto another page to move it there.
class PageGallery extends ConsumerWidget {
  const PageGallery({super.key, required this.pages});

  final List<ScanPage> pages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      // About three columns on a phone, more on wider screens.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: pages.length,
      itemBuilder: (context, i) => _GalleryTile(key: ValueKey(pages[i].id), index: i, page: pages[i]),
    );
  }
}

class _GalleryTile extends ConsumerWidget {
  const _GalleryTile({super.key, required this.index, required this.page});

  final int index;
  final ScanPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = LumaColors.of(context);
    final label = 'Page ${index + 1}';

    Widget thumbnail({bool highlighted = false}) => DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlighted ? colors.accent : Theme.of(context).dividerColor,
              width: highlighted ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: PageImage(page: page),
          ),
        );

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => ref.read(scanControllerProvider.notifier).move(details.data, index),
      builder: (context, candidates, _) => LongPressDraggable<int>(
        data: index,
        feedback: SizedBox(
          width: 96,
          height: 128,
          child: Material(elevation: 6, borderRadius: BorderRadius.circular(10), child: thumbnail()),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: _layout(context, thumbnail(), label)),
        child: Semantics(
          button: true,
          label: label,
          hint: 'Opens page actions',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _showActions(context, ref),
            child: _layout(context, thumbnail(highlighted: candidates.isNotEmpty), label),
          ),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, Widget thumbnail, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: thumbnail),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      );

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(scanControllerProvider.notifier);
    final action = await showModalBottomSheet<_PageAction>(
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
            for (final a in _PageAction.values)
              ListTile(leading: Icon(a.icon), title: Text(a.label), onTap: () => Navigator.pop(context, a)),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _PageAction.filters:
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FilterScreen(pageId: page.id)));
      case _PageAction.crop:
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CropScreen(pageId: page.id)));
      case _PageAction.rotate:
        controller.rotate(page.id);
      case _PageAction.delete:
        controller.remove(page.id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Page ${index + 1} deleted'),
          action: SnackBarAction(label: 'Undo', onPressed: controller.undo),
        ));
    }
  }
}

enum _PageAction {
  filters('Filters', Icons.tune),
  crop('Crop', Icons.crop),
  rotate('Rotate', Icons.rotate_right),
  delete('Delete page', Icons.delete_outline);

  const _PageAction(this.label, this.icon);

  final String label;
  final IconData icon;
}
