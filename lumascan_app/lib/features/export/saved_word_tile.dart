import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../domain/saved_export.dart';
import '../../ui/file_size.dart';
import '../../ui/luma_icons.dart';
import '../library/document_tile.dart';
import '../share/docx_sharer.dart';
import '../word_reader/open_word_document.dart' as reader;
import 'saved_exports.dart';

/// Opens a saved Word file in Word or another app that reads .docx.
Future<void> openWordFile(BuildContext context, SavedExport export) async {
  // A Word file made by OCR to Word (Pro and Gold) opens in the app's own
  // Word reader, like it did when it was made.
  if (export.format == ExportFormat.ocrWord) {
    return reader.openWordFile(context, export.path, name: p.basenameWithoutExtension(export.path));
  }
  final messenger = ScaffoldMessenger.of(context);
  final result = await OpenFilex.open(export.path, type: SharePlusDocxSharer.mimeType);
  if (result.type == ResultType.done) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(switch (result.type) {
        ResultType.noAppToOpen => 'No app on this device can open Word files. Try Share instead.',
        ResultType.fileNotFound => 'This Word file is no longer on this device.',
        _ => 'Could not open the Word file. ${result.message}',
      }),
    ),
  );
}

/// Hands a saved Word file to the system share sheet, pointing from
/// [context]'s box on iPad.
Future<void> shareWordFile(BuildContext context, WidgetRef ref, SavedExport export) async {
  final messenger = ScaffoldMessenger.of(context);
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  try {
    await ref.read(docxSharerProvider).send(export.path, origin: origin);
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open the share sheet. $e')));
  }
}

/// Asks, then deletes a saved Word file. The scan it came from is kept,
/// so it can be exported again.
Future<void> deleteWordFile(BuildContext context, WidgetRef ref, SavedExport export) async {
  final ok =
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete ${p.basename(export.path)}?'),
          content: const Text('The Word file is deleted from this phone. The scan is kept.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      ) ==
      true;
  if (ok) await ref.read(savedExportsProvider.notifier).delete(export);
}

enum _WordAction { open, share, delete }

/// Open in Word, Share and Delete for a saved Word file.
class SavedWordMenu extends ConsumerWidget {
  const SavedWordMenu({super.key, required this.export});

  final SavedExport export;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<_WordAction>(
    tooltip: 'More for ${export.name}',
    onSelected: (a) => switch (a) {
      _WordAction.open => openWordFile(context, export),
      _WordAction.share => shareWordFile(context, ref, export),
      _WordAction.delete => deleteWordFile(context, ref, export),
    },
    itemBuilder: (_) => const [
      PopupMenuItem(
        value: _WordAction.open,
        child: ListTile(leading: Icon(LumaIcons.openExternal), title: Text('Open in Word')),
      ),
      PopupMenuItem(
        value: _WordAction.share,
        child: ListTile(leading: Icon(LumaIcons.share), title: Text('Share')),
      ),
      PopupMenuItem(
        value: _WordAction.delete,
        child: ListTile(leading: Icon(LumaIcons.delete), title: Text('Delete')),
      ),
    ],
  );
}

/// One saved Word file in the Library: its name, when it was exported, its
/// pages and size. Tapping opens it.
class SavedWordTile extends StatelessWidget {
  const SavedWordTile({super.key, required this.export});

  final SavedExport export;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final details =
        '${formatModified(export.exportedAt, DateTime.now())} · ${pageCountLabel(export.pageCount)} · '
        '${formatFileSize(export.sizeBytes)} · Word';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: Space.md),
        leading: Icon(LumaIcons.article, size: 32, color: c.accent),
        title: Text(p.basename(export.path), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: () => openWordFile(context, export),
        trailing: SavedWordMenu(export: export),
      ),
    );
  }
}
