import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/preferences.dart';
import '../../app/theme.dart';
import '../../domain/library.dart';
import '../../domain/plan.dart';
import '../../ui/state_views.dart';
import '../../ui/luma_icons.dart';

enum DocumentMenuAction { rename, move, tags, share, password, textPdf, word, split, delete }

/// First-page thumbnail on a white page, or a PDF icon when there is none.
/// Low animation profile: always the icon; the pages show once the document
/// is opened.
class DocumentThumbnail extends StatelessWidget {
  const DocumentThumbnail({super.key, required this.document, this.iconSize = 24});

  final SavedDocument document;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final thumb = Motion.of(context).pageThumbnails ? document.thumbnailPath : null;
    return ColoredBox(
      color: c.canvas,
      child: thumb != null && File(thumb).existsSync()
          ? Image.file(File(thumb), fit: BoxFit.cover, excludeFromSemantics: true)
          : Center(
              child: Icon(LumaIcons.pdf, color: c.accent, size: iconSize),
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
        Icon(LumaIcons.device, size: 14, color: c.muted),
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
        Icon(LumaIcons.tag, size: 14, color: c.muted),
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

/// The heart on a document: outline when not a favorite, filled when it
/// is. Tapping it toggles. While selecting it only shows the state.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({
    super.key,
    required this.name,
    required this.favorite,
    required this.onPressed,
    this.size = 22,
  });

  /// The document's name, for the tooltip.
  final String name;
  final bool favorite;

  /// Null shows the state without a button, for favorites while selecting.
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final on = favorite;
    final icon = AnimatedSwitcher(
      duration: Motion.of(context).duration(const Duration(milliseconds: 200)),
      transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
      child: Icon(
        on ? LumaIcons.favoriteFilled : LumaIcons.favorite,
        key: ValueKey(on),
        size: size,
        color: on ? c.danger : c.muted,
      ),
    );
    if (onPressed == null) {
      return Padding(
        padding: const EdgeInsets.all(Space.xs),
        child: ExcludeSemantics(child: icon),
      );
    }
    return IconButton(
      tooltip: on ? 'Remove $name from favorites' : 'Add $name to favorites',
      isSelected: on,
      onPressed: onPressed,
      icon: icon,
    );
  }
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
    required this.onFavorite,
  });

  final SavedDocument document;
  final String? labels;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<DocumentMenuAction> onMenu;
  final VoidCallback onFavorite;

  String get semanticsLabel =>
      '${document.name}${document.favorite ? ', favorite' : ''}, '
      '${formatModified(document.modifiedAt, DateTime.now())}, '
      '${pageCountLabel(document.pageCount)}, on device${labels == null ? '' : ', $labels'}';

  /// The heart (unless [heart] is false, for the grid where it sits on the
  /// thumbnail) and the overflow menu; a checkbox while selecting.
  Widget trailing(BuildContext context, {bool heart = true}) {
    if (selecting) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (heart && document.favorite)
            FavoriteButton(name: document.name, favorite: true, onPressed: null, size: 18),
          ExcludeSemantics(
            child: Checkbox(value: selected, onChanged: (_) => onTap()),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (heart) FavoriteButton(name: document.name, favorite: document.favorite, onPressed: onFavorite),
        _menu(context),
      ],
    );
  }

  Widget _menu(BuildContext context) {
    return PopupMenuButton<DocumentMenuAction>(
      tooltip: 'More for ${document.name}',
      onSelected: onMenu,
      itemBuilder: (menuContext) => [
        PopupMenuItem(
          value: DocumentMenuAction.rename,
          child: ListTile(leading: Icon(LumaIcons.rename), title: Text('Rename')),
        ),
        PopupMenuItem(
          value: DocumentMenuAction.move,
          child: ListTile(leading: Icon(LumaIcons.moveToFolder), title: Text('Move to folder')),
        ),
        PopupMenuItem(
          value: DocumentMenuAction.tags,
          child: ListTile(leading: Icon(LumaIcons.tag), title: Text('Tags')),
        ),
        PopupMenuItem(
          value: DocumentMenuAction.share,
          child: ListTile(leading: Icon(LumaIcons.share), title: Text('Share')),
        ),
        PopupMenuItem(
          value: DocumentMenuAction.password,
          child: ListTile(
            leading: const Icon(LumaIcons.password),
            title: const Text('Add password'),
            // Shown to everyone; on Basic it opens the upgrade pop-up.
            trailing: ProviderScope.containerOf(menuContext).read(planIncludesProvider(PlanFeature.password))
                ? null
                : const PremiumBadge(label: 'Pro'),
          ),
        ),
        PopupMenuItem(
          value: DocumentMenuAction.textPdf,
          child: ListTile(
            leading: const Icon(LumaIcons.textResult),
            title: const Text('Create text PDF'),
            // Shown to everyone; on Basic it opens the upgrade pop-up.
            trailing: ProviderScope.containerOf(menuContext).read(planIncludesProvider(PlanFeature.textPdf))
                ? null
                : const PremiumBadge(label: 'Pro'),
          ),
        ),
        PopupMenuItem(
          value: DocumentMenuAction.word,
          child: ListTile(
            leading: const Icon(LumaIcons.document),
            title: const Text('Convert to Word'),
            // Shown to everyone; on Basic it opens the upgrade pop-up.
            trailing: ProviderScope.containerOf(menuContext).read(planIncludesProvider(PlanFeature.word))
                ? null
                : const PremiumBadge(label: 'Pro'),
          ),
        ),
        PopupMenuItem(
          value: DocumentMenuAction.split,
          child: ListTile(
            leading: const Icon(LumaIcons.split),
            title: const Text('Split or extract pages'),
            // Shown to everyone; on Basic it opens the upgrade pop-up.
            trailing: ProviderScope.containerOf(menuContext).read(planIncludesProvider(PlanFeature.splitPdf))
                ? null
                : const PremiumBadge(label: 'Pro'),
          ),
        ),
        // A favorite can't be deleted; the item stays, disabled, and says why.
        PopupMenuItem(
          value: DocumentMenuAction.delete,
          enabled: !document.favorite,
          child: ListTile(
            enabled: !document.favorite,
            leading: const Icon(LumaIcons.delete),
            title: const Text('Delete'),
            subtitle: document.favorite ? const Text('Remove from favorites to delete') : null,
          ),
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
      onTap: onTap,
      onLongPress: onLongPress,
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
        // The Semantics above carries the label and actions, so the ink does not
        // add a second, unlabelled tap target for a screen reader.
        child: InkWell(onTap: onTap, onLongPress: onLongPress, excludeFromSemantics: true, child: child),
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
    required this.onFavorite,
    this.selecting = false,
    this.selected = false,
    this.labels,
    this.snippet,
  });

  final SavedDocument document;

  /// Folder and tags, such as "Bills · tax, 2026", or null for none.
  final String? labels;

  /// Where a search matched the text inside the document, such as
  /// "…rent of ₹12,000 for March…", or null.
  final String? snippet;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<DocumentMenuAction> onMenu;

  /// The heart was tapped.
  final VoidCallback onFavorite;

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
      onFavorite: onFavorite,
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
                    if (snippet != null) ...[
                      const SizedBox(height: 2),
                      Text(snippet!, style: text.bodySmall?.copyWith(fontStyle: FontStyle.italic), maxLines: 2),
                    ],
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
    required this.onFavorite,
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

  /// The heart was tapped.
  final VoidCallback onFavorite;

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
      onFavorite: onFavorite,
    );
    final text = Theme.of(context).textTheme;
    return i.wrap(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                DocumentThumbnail(document: document, iconSize: 40),
                Positioned(
                  top: Space.xs,
                  right: Space.xs,
                  child: FavoriteBadge(
                    child: FavoriteButton(
                      name: document.name,
                      favorite: document.favorite,
                      onPressed: selecting ? null : onFavorite,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                i.trailing(context, heart: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A round backing for a heart drawn over a page preview, so it stays
/// visible on a white or a dark page.
class FavoriteBadge extends StatelessWidget {
  const FavoriteBadge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: LumaColors.of(context).surface.withValues(alpha: 0.85), shape: BoxShape.circle),
    child: child,
  );
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
