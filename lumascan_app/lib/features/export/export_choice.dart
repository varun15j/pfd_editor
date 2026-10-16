import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../pages/scan_controller.dart';
import '../share/image_sharer.dart';
import '../word/word_actions.dart';
import 'export_sheet.dart';

/// Export: the scan is already saved as page images, so this only makes a
/// copy, as one PDF, as one Word file, or as one JPG per page.
Future<void> showExportChoice(BuildContext context, WidgetRef ref) async {
  final choice = await showModalBottomSheet<_ExportKind>(context: context, builder: (_) => const _ExportChoiceSheet());
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _ExportKind.pdf:
      await showExportSheet(context);
    case _ExportKind.word:
      final scan = ref.read(scanControllerProvider);
      await exportScanAsWord(context, ref, scan.pages, name: scan.info?.name ?? 'Scan');
    case _ExportKind.jpg:
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        enableDrag: false,
        builder: (_) => const JpgExportSheet(),
      );
  }
}

enum _ExportKind { pdf, word, jpg }

class _ExportChoiceSheet extends StatelessWidget {
  const _ExportChoiceSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
            child: Text('Export', style: Theme.of(context).textTheme.headlineSmall),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Export as PDF'),
            subtitle: const Text('All pages in one file, saved to your Library'),
            onTap: () => Navigator.pop(context, _ExportKind.pdf),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Export as Word'),
            subtitle: const Text('A .docx file. Pages read with OCR become text you can edit'),
            onTap: () => Navigator.pop(context, _ExportKind.word),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('JPG images'),
            subtitle: const Text('One photo per page, to save to the gallery or send'),
            onTap: () => Navigator.pop(context, _ExportKind.jpg),
          ),
        ],
      ),
    ),
  );
}

/// Saves every page as a JPG, then offers the share sheet.
class JpgExportSheet extends ConsumerStatefulWidget {
  const JpgExportSheet({super.key});

  @override
  ConsumerState<JpgExportSheet> createState() => _JpgExportSheetState();
}

class _JpgExportSheetState extends ConsumerState<JpgExportSheet> {
  double _progress = 0;
  List<File>? _files;
  String? _error;
  bool _hasMarks = false;

  @override
  void initState() {
    super.initState();
    _export();
  }

  Future<void> _export() async {
    final scan = ref.read(scanControllerProvider);
    final pages = scan.pages;
    final exporter = ref.read(jpgExporterProvider);
    _hasMarks = pages.any((p) => p.annotations.isNotEmpty);
    try {
      final files = await exporter.export(
        pages,
        scan.info?.name ?? 'Scan',
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = done / total);
        },
      );
      if (mounted) setState(() => _files = files);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'The JPGs could not be saved. Your pages are unchanged. ($e)');
    }
  }

  Future<void> _send() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      await ref.read(imageSharerProvider).send([for (final f in _files!) f.path], origin: origin);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'The share sheet could not be opened. ($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final files = _files;
    final error = _error;
    final done = files != null || error != null;
    return PopScope(
      canPop: done,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(files == null ? 'Saving JPGs' : 'JPGs saved', style: text.headlineSmall),
              const SizedBox(height: 8),
              if (files == null && error == null) ...[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text('Saving… ${(_progress * 100).round()}%', style: text.bodySmall, textAlign: TextAlign.center),
              ],
              if (files != null) ...[
                Text('${files.length} JPG${files.length == 1 ? '' : 's'}, one per page'),
                if (_hasMarks) ...[
                  const SizedBox(height: 4),
                  Text('Markup is kept only in PDFs.', style: text.bodySmall),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: _send, icon: const Icon(Icons.ios_share), label: const Text('Send')),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              if (done) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
