import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../library/library_controller.dart';
import '../share/send_pdf_sheet.dart';
import 'merge_controller.dart';
import '../../export/pdf_merger.dart';
import '../../ui/file_size.dart';

/// Names and saves the merged PDF. Resolves to true once it is saved and the
/// user taps Done, so the merge screen can close.
Future<bool> showMergeSheet(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // Back and the scrim are blocked by the sheet itself while it works.
      enableDrag: false,
      builder: (_) => const MergeSheet(),
    ) ??
    false;

/// Merges the listed PDFs into a new document in the Library. The originals
/// are only read.
class MergeSheet extends ConsumerStatefulWidget {
  const MergeSheet({super.key});

  @override
  ConsumerState<MergeSheet> createState() => _MergeSheetState();
}

class _MergeSheetState extends ConsumerState<MergeSheet> {
  late final TextEditingController _name;
  double? _progress;
  File? _result;
  int _pages = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    _name = TextEditingController(
      text: 'Merged ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}.${two(t.minute)}',
    );
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _busy => _progress != null && _result == null;

  Future<void> _merge() async {
    final sources = ref.read(mergeControllerProvider).sources;
    final library = ref.read(libraryProvider.notifier);
    final merger = ref.read(pdfMergerProvider);
    setState(() {
      _progress = 0;
      _error = null;
    });
    final File file;
    try {
      file = await merger.merge(
        [for (final s in sources) MergeInput(path: s.path, pageCount: s.pages!)],
        fileName: _name.text,
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = done / total);
        },
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = 'Merging failed. Your PDFs are unchanged. ($e)';
        });
      }
      return;
    }
    final pages = sources.fold<int>(0, (sum, s) => sum + s.pages!);
    if (mounted) {
      setState(() {
        _result = file;
        _pages = pages;
      });
    }
    try {
      await library.addPdf(file, pageCount: pages);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Saved, but it could not be added to your Library. ($e)');
    }
  }

  Future<void> _send() =>
      showSendPdfSheet(context, pdfPath: _result!.path, name: p.basename(_result!.path), pageCount: _pages);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mergeControllerProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final result = _result;
    final count = state.sources.length;

    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(22, 0, 22, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (result != null) ...[
                Text('Merged', style: text.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  '${p.basename(result.path)} · $_pages page${_pages == 1 ? '' : 's'} · '
                  '${formatFileSize(result.lengthSync())}',
                ),
                const SizedBox(height: 4),
                Text('Saved to your Library. Your original PDFs are unchanged.', style: text.bodySmall),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: _send, icon: const Icon(Icons.ios_share), label: const Text('Send')),
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Done')),
              ] else ...[
                Text('Merge $count PDFs', style: text.headlineSmall),
                const SizedBox(height: 4),
                Text('${state.totalPages} pages, in the order shown', style: text.bodySmall),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'File name',
                    suffixText: '.pdf',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Pages are combined as images, so text in the new PDF cannot be selected. '
                  'Your original PDFs are not changed.',
                  style: text.bodySmall,
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 8),
                  Text('Merging…', style: text.bodySmall, textAlign: TextAlign.center),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || _name.text.trim().isEmpty ? null : _merge,
                  child: Text(_busy ? 'Merging…' : 'Merge'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
