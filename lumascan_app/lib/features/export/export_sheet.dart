import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../domain/models.dart';
import '../../export/pdf_exporter.dart';
import '../../pdf_edit/pdf_saver.dart';
import '../../ui/file_size.dart';
import '../library/library_controller.dart';
import '../pages/scan_controller.dart';
import '../share/send_pdf_sheet.dart';

export '../../ui/file_size.dart';

Future<void> showExportSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  // Dragging down would close the sheet mid-save; back and the scrim are
  // blocked by the sheet itself while saving.
  enableDrag: false,
  builder: (_) => const ExportSheet(),
);

/// Save (S09): name, page size and quality with estimated sizes, progress,
/// then share. Success is shown only once the file is on disk.
class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({super.key});

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  late final TextEditingController _name;
  PdfPageSize _size = PdfPageSize.a4;
  ExportQuality _quality = ExportQuality.medium;
  double? _progress;
  File? _result;
  String? _error;
  bool _inLibrary = false;

  bool get _saving => _progress != null && _result == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: PdfExporter.defaultScanName(DateTime.now()))..addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  bool get _nameValid => _name.text.trim().isNotEmpty;

  Future<void> _export() async {
    // A second tap before the sheet rebuilds must not start a second save.
    if (_saving || !_nameValid) return;
    final pages = ref.read(scanControllerProvider).pages;
    // Read up front: the export finishes and is filed even if the sheet is
    // closed meanwhile.
    final library = ref.read(libraryProvider.notifier);
    final store = ref.read(pageStoreProvider);
    final exporter = ref.read(pdfExporterProvider);
    final fileName = PdfEditSaver.safeFileName(_name.text);
    final draft = ref.read(scanControllerProvider.notifier);
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final file = await exporter.export(
        pages,
        // A name that is already taken gets a number, never replaces a file.
        ExportOptions(pageSize: _size, quality: _quality, fileName: await store.freeExportName(fileName)),
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

  Future<void> _send() {
    final file = _result!;
    return showSendPdfSheet(
      context,
      pdfPath: file.path,
      name: p.basename(file.path),
      pageCount: ref.read(scanControllerProvider).pages.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = ref.watch(scanControllerProvider.select((s) => s.pages.length));
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final result = _result;
    final saving = _saving;

    return PopScope(
      canPop: !saving,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(22, 20, 22, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (result != null) ...[
                Text('PDF saved', style: textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  '${p.basename(result.path)} · $pageCount page${pageCount == 1 ? '' : 's'} · '
                  '${formatFileSize(result.lengthSync())}',
                ),
                if (_inLibrary) ...[
                  const SizedBox(height: 4),
                  Text('Saved to your Library', style: textTheme.bodySmall),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: _send, icon: const Icon(Icons.ios_share), label: const Text('Send')),
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
              ] else ...[
                Text('Save as PDF', style: textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('$pageCount page${pageCount == 1 ? '' : 's'}', style: textTheme.bodySmall),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  enabled: !saving,
                  maxLength: 80,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'File name',
                    suffixText: '.pdf',
                    border: const OutlineInputBorder(),
                    counterText: '',
                    errorText: _nameValid ? null : 'Enter a name for the PDF',
                  ),
                ),
                const SizedBox(height: 16),
                Text('Page size', style: textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<PdfPageSize>(
                  segments: [for (final s in PdfPageSize.values) ButtonSegment(value: s, label: Text(s.label))],
                  selected: {_size},
                  onSelectionChanged: saving ? null : (v) => setState(() => _size = v.first),
                ),
                const SizedBox(height: 16),
                Text('Quality', style: textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final q in ExportQuality.values)
                  _QualityTile(
                    quality: q,
                    pageCount: pageCount,
                    selected: q == _quality,
                    onTap: saving ? null : () => setState(() => _quality = q),
                  ),
                const SizedBox(height: 16),
                if (saving) ...[
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 8),
                  Text(
                    'Saving… ${((_progress ?? 0) * 100).round()}%',
                    style: textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed: pageCount == 0 || saving || !_nameValid ? null : _export,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(saving ? 'Saving…' : 'Save PDF'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One quality choice with its estimated size for this document.
class _QualityTile extends StatelessWidget {
  const _QualityTile({required this.quality, required this.pageCount, required this.selected, required this.onTap});

  final ExportQuality quality;
  final int pageCount;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final size = formatFileSize(PdfExporter.estimateBytes(pageCount, quality));
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        enabled: onTap != null,
        onTap: onTap,
        leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
        title: Text(quality.label),
        subtitle: Text(quality.hint),
        trailing: Text('about $size'),
      ),
    );
  }
}
