import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/library.dart';

enum DocumentMenuAction { rename, move, tags, share, delete }

/// First-page thumbnail on a white page, or a PDF icon when there is none.
class DocumentThumbnail extends StatelessWidget {
  const DocumentThumbnail({super.key, required this.document, this.iconSize = 24});

  final SavedDocument document;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final thumb = document.thumbnailPath;
    return ColoredBox(
      color: c.canvas,
      child: thumb != null && File(thumb).existsSync()
          ? Image.file(File(thumb), fit: BoxFit.cover, excludeFromSemantics: true)
          : Center(
              child: Icon(Icons.picture_as_pdf_outlined, color: c.accent, size: iconSize),
            ),
    );
  }
}

/// "On device" with an icon, so the state never relies on colour alone.
/// Cloud states join it once sync exists.
class DocumentStatus extends StatelessWidget {
  const DocumentStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.smartphone, size: 14, color: c.muted),
        const SizedBox(width: Space.xs),
        Flexible(
          child: Text('On device', style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// Folder and tags under a document's name, with an icon.
class DocumentLabels extends StatelessWidget {
  const DocumentLabels(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.label_outline, size: 14, color: c.muted),
        const SizedBox(width: Space.xs),
        Flexible(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// "Bills · tax, 2026": the folder name, then the tags.
String? documentLabels(SavedDocument doc, LibraryIndex index) {
  final parts = [?index.folderById(doc.folderId)?.name, if (doc.tags.isNotEmpty) doc.tags.join(', ')];
  return parts.isEmpty ? null : parts.join(' · ');
}

String pageCountLabel(int n) => '$n page${n == 1 ? '' : 's'}';

/// Shared behaviour for a document in a list or grid: tap opens it (or
/// toggles it while selecting), long press starts selecting, and the
/// overflow menu offers rename, move, tags, share and delete.
class _DocumentInteraction {
  const _DocumentInteraction({
    required this.document,
    required this.labels,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMenu,
  });

  final SavedDocument document;
  final String? labels;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<DocumentMenuAction> onMenu;

  String get semanticsLabel =>
      '${document.name}, ${formatModified(document.modifiedAt, DateTime.now())}, '
      '${pageCountLabel(document.pageCount)}, on device${labels == null ? '' : ', $labels'}';

  Widget trailing(BuildContext context) {
    if (selecting) {
      return ExcludeSemantics(
        child: Checkbox(value: selected, onChanged: (_) => onTap()),
      );
    }
    return PopupMenuButton<DocumentMenuAction>(
      tooltip: 'More for ${document.name}',
      onSelected: onMenu,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: DocumentMenuAction.rename,
          child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Rename')),
        ),
        PopupMenuItem(
          value: DocumentMenuAction.move,
          child: ListTile(leading: Icon(Icons.drive_file_move_outlined), title: Text('Move to folder')),
        ),
        PopupMenuItem(
          value: DocumentMenuAction.tags,
          child: ListTile(leading: Icon(Icons.label_outline), title: Text('Tags')),
        ),
        PopupMenuItem(
          value: DocumentMenuAction.share,
          child: ListTile(leading: Icon(Icons.ios_share), title: Text('Share')),
        ),
        PopupMenuItem(
          value: DocumentMenuAction.delete,
          child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')),
        ),
      ],
    );
  }

  Widget wrap(BuildContext context, {required Widget child}) {
    final c = LumaColors.of(context);
    return Semantics(
      selected: selecting ? selected : null,
      button: true,
      label: semanticsLabel,
      onLongPressHint: selecting ? null : 'Select',
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: selected ? c.accentSoft : null,
        shape: selected
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.md),
                side: BorderSide(color: c.accent, width: 2),
              )
            : null,
        child: InkWell(onTap: onTap, onLongPress: onLongPress, child: child),
      ),
    );
  }
}

/// One row in the Library list: thumbnail, name, modified time, pages and
/// status (US-02.1).
class DocumentRow extends StatelessWidget {
  const DocumentRow({
    super.key,
    required this.document,
    required this.onTap,
    required this.onLongPress,
    required this.onMenu,
    this.selecting = false,
    this.selected = false,
    this.labels,
  });

  final SavedDocument document;

  /// Folder and tags, such as "Bills · tax, 2026", or null for none.
  final String? labels;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<DocumentMenuAction> onMenu;

  @override
  Widget build(BuildContext context) {
    final i = _DocumentInteraction(
      document: document,
      labels: labels,
      selecting: selecting,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      onMenu: onMenu,
    );
    final text = Theme.of(context).textTheme;
    return i.wrap(
      context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.xs, Space.md),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.sm / 2),
              child: SizedBox(width: 48, height: 64, child: DocumentThumbnail(document: document)),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(document.name, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      '${formatModified(document.modifiedAt, DateTime.now())} · ${pageCountLabel(document.pageCount)}',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    const DocumentStatus(),
                    if (labels != null) ...[const SizedBox(height: 2), DocumentLabels(labels!)],
                  ],
                ),
              ),
            ),
            i.trailing(context),
          ],
        ),
      ),
    );
  }
}

/// One tile in the Library grid.
class DocumentGridCard extends StatelessWidget {
  const DocumentGridCard({
    super.key,
    required this.document,
    required this.onTap,
    required this.onLongPress,
    required this.onMenu,
    this.selecting = false,
    this.selected = false,
    this.labels,
  });

  final SavedDocument document;

  /// Folder and tags, such as "Bills · tax, 2026", or null for none.
  final String? labels;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<DocumentMenuAction> onMenu;

  /// Height of the text area under the thumbnail at 100% text size.
  static const textHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    final i = _DocumentInteraction(
      document: document,
      labels: labels,
      selecting: selecting,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      onMenu: onMenu,
    );
    final text = Theme.of(context).textTheme;
    return i.wrap(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: DocumentThumbnail(document: document, iconSize: 40)),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, 0, Space.sm),
            child: Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(document.name, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          formatModified(document.modifiedAt, DateTime.now()),
                          style: text.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const DocumentStatus(),
                      ],
                    ),
                  ),
                ),
                i.trailing(context),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact card for Home's Recent row.
class RecentDocumentCard extends StatelessWidget {
  const RecentDocumentCard({super.key, required this.document, required this.onTap});

  final SavedDocument document;
  final VoidCallback onTap;

  static const width = 132.0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '${document.name}, ${formatModified(document.modifiedAt, DateTime.now())}',
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: DocumentThumbnail(document: document, iconSize: 36)),
                Padding(
                  padding: const EdgeInsets.all(Space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(document.name, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        formatModified(document.modifiedAt, DateTime.now()),
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Just now", "5 min ago", "Today 14:05", "Yesterday", or "3 Oct 2026".
String formatModified(DateTime t, DateTime now) {
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  String two(int v) => v.toString().padLeft(2, '0');
  if (day == today) return 'Today ${two(t.hour)}:${two(t.minute)}';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${months[t.month - 1]} ${t.year}';
}
