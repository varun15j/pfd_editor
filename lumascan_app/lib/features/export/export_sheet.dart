import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../domain/models.dart';
import '../../export/pdf_exporter.dart';
import '../library/library_controller.dart';
import '../pages/scan_controller.dart';

Future<void> showExportSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const ExportSheet(),
);

/// Export (S09): page size and quality, progress, then share.
class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({super.key});

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  PdfPageSize _size = PdfPageSize.a4;
  ExportQuality _quality = ExportQuality.medium;
  double? _progress;
  File? _result;
  String? _error;
  bool _inLibrary = false;

  Future<void> _export() async {
    final pages = ref.read(scanControllerProvider).pages;
    // Read up front: the export finishes and is filed even if the sheet is
    // closed meanwhile.
    final library = ref.read(libraryProvider.notifier);
    final draft = ref.read(scanControllerProvider.notifier);
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final file = await ref
          .read(pdfExporterProvider)
          .export(
            pages,
            ExportOptions(pageSize: _size, quality: _quality),
            onProgress: (done, total) {
              if (mounted) setState(() => _progress = done / total);
            },
          );
      if (mounted) setState(() => _result = file);
      draft.markSaved();
      // The PDF is already safe on disk; a failed index write only means it
      // is missing from the Library list, so it is reported, not thrown.
      await library.addScan(file, pages);
      if (mounted) setState(() => _inLibrary = true);
    } on Object catch (e) {
      if (!mounted) return;
      if (_result != null) {
        setState(() => _error = 'The PDF was created but could not be added to your Library. ($e)');
      } else {
        setState(() {
          _progress = null;
          _error = 'Export failed. Your pages are unchanged. ($e)';
        });
      }
    }
  }

  Future<void> _share(BuildContext context) async {
    final file = _result!;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        // Required on iPad, where the share sheet is a popover.
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = ref.watch(scanControllerProvider.select((s) => s.pages.length));
    final textTheme = Theme.of(context).textTheme;
    final result = _result;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (result != null) ...[
              Text('PDF ready', style: textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '${p.basename(result.path)} · $pageCount page${pageCount == 1 ? '' : 's'} · '
                '${(result.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB',
              ),
              if (_inLibrary) ...[const SizedBox(height: 4), Text('Saved to your Library', style: textTheme.bodySmall)],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              Builder(
                builder: (buttonContext) => FilledButton.icon(
                  onPressed: () => _share(buttonContext),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share or save'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
            ] else ...[
              Text('Export PDF', style: textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('$pageCount page${pageCount == 1 ? '' : 's'}', style: textTheme.bodySmall),
              const SizedBox(height: 16),
              Text('Page size', style: textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<PdfPageSize>(
                segments: [for (final s in PdfPageSize.values) ButtonSegment(value: s, label: Text(s.label))],
                selected: {_size},
                onSelectionChanged: _progress != null ? null : (v) => setState(() => _size = v.first),
              ),
              const SizedBox(height: 16),
              Text('Quality', style: textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<ExportQuality>(
                segments: [for (final q in ExportQuality.values) ButtonSegment(value: q, label: Text(q.label))],
                selected: {_quality},
                onSelectionChanged: _progress != null ? null : (v) => setState(() => _quality = v.first),
              ),
              const SizedBox(height: 20),
              if (_progress != null) ...[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text('Rendering pages…', style: textTheme.bodySmall, textAlign: TextAlign.center),
              ] else
                FilledButton.icon(
                  onPressed: pageCount == 0 ? null : _export,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Create PDF'),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
