import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../domain/models.dart';
import '../../pdf_edit/pdf_edit_controller.dart';
import '../../pdf_edit/pdf_saver.dart';

Future<void> showSavePdfSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const SavePdfSheet(),
);

/// Saves the edited document as a new PDF, then offers the share sheet.
/// The opened file is never overwritten.
class SavePdfSheet extends ConsumerStatefulWidget {
  const SavePdfSheet({super.key});

  @override
  ConsumerState<SavePdfSheet> createState() => _SavePdfSheetState();
}

class _SavePdfSheetState extends ConsumerState<SavePdfSheet> {
  late final TextEditingController _name;
  ExportQuality _quality = ExportQuality.high;
  double? _progress;
  File? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: PdfEditSaver.defaultFileName(ref.read(pdfEditControllerProvider).sourceName));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = ref.read(pdfEditControllerProvider);
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final file = await ref
          .read(pdfEditSaverProvider)
          .save(
            sourcePath: state.sourcePath!,
            pages: state.pages,
            quality: _quality,
            fileName: _name.text,
            password: state.password,
            onProgress: (done, total) {
              if (mounted) setState(() => _progress = done / total);
            },
          );
      ref.read(pdfEditControllerProvider.notifier).markSaved();
      if (mounted) setState(() => _result = file);
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = 'Saving failed. Your edits are still here. ($e)';
        });
      }
    }
  }

  Future<void> _share(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(_result!.path, mimeType: 'application/pdf')],
        // Required on iPad, where the share sheet is a popover.
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = ref.watch(pdfEditControllerProvider.select((s) => s.pages.length));
    final textTheme = Theme.of(context).textTheme;
    final result = _result;
    final busy = _progress != null && result == null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 0, 22, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (result != null) ...[
              Text('Saved', style: textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '${p.basename(result.path)} · $pageCount page${pageCount == 1 ? '' : 's'} · '
                '${(result.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB',
              ),
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
              Text('Save as new PDF', style: textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('$pageCount page${pageCount == 1 ? '' : 's'}', style: textTheme.bodySmall),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                enabled: !busy,
                decoration: const InputDecoration(labelText: 'File name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Text('Quality', style: textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<ExportQuality>(
                segments: [for (final q in ExportQuality.values) ButtonSegment(value: q, label: Text(q.label))],
                selected: {_quality},
                onSelectionChanged: busy ? null : (v) => setState(() => _quality = v.first),
              ),
              const SizedBox(height: 12),
              Text(
                'Pages are saved as images with your marks on top, so text from the original '
                'will not be selectable or searchable in the new file. The original PDF is not changed.',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (busy) ...[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text('Saving pages…', style: textTheme.bodySmall, textAlign: TextAlign.center),
              ] else
                FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_alt), label: const Text('Save PDF')),
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
