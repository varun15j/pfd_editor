import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../data/library_store.dart';
import '../../domain/library.dart';
import '../../domain/models.dart';
import '../library/document_tile.dart';
import '../library/library_actions.dart';
import '../pages/page_image.dart';
import '../pages/scan_controller.dart';

/// One document on Home: a scan kept as page images (the one on screen or an
/// earlier one), or a saved PDF.
sealed class HomeDoc {
  const HomeDoc();

  String get name;
  DateTime get time;
  int get pageCount;
  String get key;
}

/// A scan, saved as page images from its first page. [parkedId] is null for
/// the document last on screen.
class ScanHomeDoc extends HomeDoc {
  const ScanHomeDoc({
    required this.name,
    required this.time,
    required this.pageCount,
    required this.cover,
    required this.exported,
    this.parkedId,
  });

  factory ScanHomeDoc.parked(ParkedDraft d) => ScanHomeDoc(
    name: d.name,
    time: d.savedAt,
    pageCount: d.pageCount,
    cover: d.cover,
    exported: d.exported,
    parkedId: d.id,
  );

  @override
  final String name;
  @override
  final DateTime time;
  @override
  final int pageCount;
  final ScanPage cover;

  /// Also exported as a PDF and not changed since.
  final bool exported;
  final String? parkedId;

  @override
  String get key => 'scan-${parkedId ?? 'current'}';
}

class PdfHomeDoc extends HomeDoc {
  const PdfHomeDoc(this.document);

  final SavedDocument document;

  @override
  String get name => document.name;
  @override
  DateTime get time => document.modifiedAt;
  @override
  int get pageCount => document.pageCount;
  @override
  String get key => 'pdf-${document.id}';
}

/// Home's documents, newest first: the scan last on screen, earlier scans
/// and recent PDFs.
List<HomeDoc> homeDocuments(ScanState scan, List<SavedDocument> pdfs) {
  final current = scan.pages.isEmpty
      ? null
      : ScanHomeDoc(
          name: scan.info?.name ?? 'Scan',
          time: scan.info?.createdAt ?? DateTime.now(),
          pageCount: scan.pages.length,
          cover: scan.pages.first,
          exported: scan.exported,
        );
  final rest = <HomeDoc>[for (final d in scan.parked) ScanHomeDoc.parked(d), for (final d in pdfs) PdfHomeDoc(d)]
    ..sort((a, b) => b.time.compareTo(a.time));
  // The one last worked on stays first, whatever its date.
  return [?current, ...rest];
}

/// The documents as a gallery of page previews or as a list. Sized to its
/// content, to sit inside Home's scrolling column.
class HomeDocumentsView extends ConsumerWidget {
  const HomeDocumentsView({super.key, required this.docs, required this.grid});

  final List<HomeDoc> docs;
  final bool grid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(scanControllerProvider.select((s) => s.busy));
    VoidCallback? open(HomeDoc d) => busy && d is ScanHomeDoc ? null : () => _open(context, ref, d);
    if (!grid) {
      return Column(
        children: [
          for (final d in docs) ...[
            _HomeDocRow(key: ValueKey(d.key), doc: d, onTap: open(d)),
            const SizedBox(height: Space.sm),
          ],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = math.max(2, (width / 170).floor());
        final tileWidth = (width - Space.md * (columns - 1)) / columns;
        return Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [
            for (final d in docs)
              SizedBox(
                width: tileWidth,
                child: _HomeDocCard(key: ValueKey(d.key), doc: d, onTap: open(d)),
              ),
          ],
        );
      },
    );
  }

  static Future<void> _open(BuildContext context, WidgetRef ref, HomeDoc doc) async {
    switch (doc) {
      case PdfHomeDoc(:final document):
        await openDocument(context, ref, document);
      case ScanHomeDoc(:final parkedId):
        if (parkedId != null) await ref.read(scanControllerProvider.notifier).openParked(parkedId);
        if (context.mounted) openDraft(context);
    }
  }
}

String _details(HomeDoc d) {
  final kind = switch (d) {
    ScanHomeDoc(:final exported) => exported ? 'Images, PDF made' : 'Images',
    PdfHomeDoc() => 'PDF',
  };
  return '${formatModified(d.time, DateTime.now())} · ${pageCountLabel(d.pageCount)} · $kind';
}

/// First page of the document, filling its box.
class _Preview extends StatelessWidget {
  const _Preview({required this.doc});

  final HomeDoc doc;

  @override
  Widget build(BuildContext context) => switch (doc) {
    ScanHomeDoc(:final cover) => ColoredBox(
      color: LumaColors.of(context).canvas,
      child: PageImage(page: cover, fit: BoxFit.cover),
    ),
    PdfHomeDoc(:final document) => DocumentThumbnail(document: document, iconSize: 36),
  };
}

class _HomeDocCard extends StatelessWidget {
  const _HomeDocCard({super.key, required this.doc, required this.onTap});

  final HomeDoc doc;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final d = doc;
    return Semantics(
      button: true,
      label: '${d.name}, ${_details(d)}',
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: AspectRatio(
                  aspectRatio: 1 / 1.15,
                  child: _Preview(doc: d),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, 0, Space.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.name, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(_details(d), style: text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                    if (d is ScanHomeDoc) _ScanMenu(doc: d) else const SizedBox(width: Space.sm),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeDocRow extends StatelessWidget {
  const _HomeDocRow({super.key, required this.doc, required this.onTap});

  final HomeDoc doc;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final d = doc;
    return Semantics(
      button: true,
      label: '${d.name}, ${_details(d)}',
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.xs, Space.md),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.sm / 2),
                    child: SizedBox(width: 48, height: 64, child: _Preview(doc: d)),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(_details(d), style: text.bodySmall),
                      ],
                    ),
                  ),
                ),
                if (d is ScanHomeDoc) _ScanMenu(doc: d) else const SizedBox(width: Space.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ScanAction { rename, delete }

/// Rename or delete a scan from Home. Saved PDFs have their menu in Library.
class _ScanMenu extends ConsumerWidget {
  const _ScanMenu({required this.doc});

  final ScanHomeDoc doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_ScanAction>(
      tooltip: 'More for ${doc.name}',
      onSelected: (a) => switch (a) {
        _ScanAction.rename => _rename(context, ref),
        _ScanAction.delete => _delete(context, ref),
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _ScanAction.rename,
          child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Rename')),
        ),
        PopupMenuItem(
          value: _ScanAction.delete,
          child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')),
        ),
      ],
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await showScanRenameDialog(context, doc.name);
    if (name == null) return;
    final controller = ref.read(scanControllerProvider.notifier);
    final id = doc.parkedId;
    if (id == null) {
      controller.rename(name);
    } else {
      await controller.renameParked(id, name);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    if (!await confirmScanDelete(context, doc.name)) return;
    final controller = ref.read(scanControllerProvider.notifier);
    final id = doc.parkedId;
    if (id == null) {
      await controller.clear();
    } else {
      await controller.deleteParked(id);
    }
  }
}

/// Asks for a new name for a scan. Returns null when cancelled.
Future<String?> showScanRenameDialog(BuildContext context, String current) => showDialog<String>(
  context: context,
  builder: (_) => _RenameDialog(current: current),
);

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _text = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? get _error => validateLabelName(_text.text, const [], maxLength: 80);

  void _save() {
    if (_error == null) Navigator.pop(context, _text.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename scan'),
    content: TextField(
      controller: _text,
      autofocus: true,
      decoration: InputDecoration(labelText: 'Name', errorText: _text.text == widget.current ? null : _error),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _error == null ? _save : null, child: const Text('Rename')),
    ],
  );
}

/// Asks before deleting a scan's page images. Exported files are kept.
Future<bool> confirmScanDelete(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $name?'),
        content: const Text('Its page images are deleted from this phone. PDFs and JPGs you exported are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    ) ==
    true;
