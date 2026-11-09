import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/app_info.dart';
import '../../ui/luma_icons.dart';
import '../share/send_pdf_sheet.dart';
import 'export_saver.dart';

/// Said under every export: the app keeps no copy, so it is saved or shared now.
const exportNotKeptNote =
    '$appName does not keep a copy. Save it to your phone or SD card, or share it. '
    'Your pages stay in $appName, so you can export again at any time.';

/// "Save to device" and "Share" for a finished export, the two places an
/// export can go. [paths] is one file, or several (JPGs) that are saved into
/// one folder the user picks. [onShare] opens the share sheet from the
/// button that was tapped. [onSaved] runs once the files are saved.
class ExportDeliveryButtons extends ConsumerStatefulWidget {
  const ExportDeliveryButtons({
    super.key,
    required this.paths,
    required this.onShare,
    this.name,
    this.onSaved,
    this.shareLabel = 'Share',
  });

  final List<String> paths;

  /// The name offered in the save screen for a single file; its own name
  /// when null.
  final String? name;
  final Future<void> Function(BuildContext button) onShare;
  final VoidCallback? onSaved;
  final String shareLabel;

  @override
  ConsumerState<ExportDeliveryButtons> createState() => _ExportDeliveryButtonsState();
}

class _ExportDeliveryButtonsState extends ConsumerState<ExportDeliveryButtons> {
  bool _saving = false;
  String? _savedAs;
  String? _error;

  bool get _single => widget.paths.length == 1;

  Future<void> _save() async {
    if (_saving) return;
    final saver = ref.read(exportSaverProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final path = widget.paths.first;
      final saved = _single
          ? await saver.saveFile(path, mimeType: ExportMime.of(path), name: widget.name)
          : await saver.saveToFolder(widget.paths, mimeType: ExportMime.of(path));
      if (!mounted) return;
      // Cancelled: nothing is said, and either button can be tapped again.
      if (saved == null) return;
      setState(() => _savedAs = _single ? 'Saved as $saved' : 'Saved ${widget.paths.length} files in $saved');
      widget.onSaved?.call();
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not save it there. Try another place or share it. ($e)');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final canSave = _single || ref.watch(exportSaverProvider).canSaveToFolder;
    final savedAs = _savedAs;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (savedAs != null) ...[
          Row(
            children: [
              Icon(LumaIcons.checkCircle, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(savedAs, style: text.bodyMedium)),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (canSave)
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(LumaIcons.save),
            label: Text(
              savedAs != null
                  ? 'Save another copy'
                  : _single
                  ? 'Save to device'
                  : 'Save to a folder',
            ),
          ),
        if (canSave) ...[
          const SizedBox(height: 4),
          Text(
            _single ? 'Pick Documents, Downloads, an SD card or Drive' : 'Pick a folder on your phone or SD card',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ],
        Builder(
          builder: (button) => canSave
              ? OutlinedButton.icon(
                  onPressed: _saving ? null : () => widget.onShare(button),
                  icon: const Icon(LumaIcons.share),
                  label: Text(widget.shareLabel),
                )
              : FilledButton.icon(
                  onPressed: () => widget.onShare(button),
                  icon: const Icon(LumaIcons.share),
                  label: Text(widget.shareLabel),
                ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }
}

/// Where the share sheet on an iPad points: the widget in [context].
Rect? shareOriginOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  return box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
}

/// "PDF ready" with Save to device and Share, for a PDF just exported to
/// the Outbox, such as an ID copy. Share opens the send sheet, which can
/// also make a smaller copy.
Future<void> showPdfReadySheet(BuildContext context, {required String pdfPath, required int pageCount}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) {
        final text = Theme.of(sheet).textTheme;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('PDF ready', style: text.headlineSmall),
                const SizedBox(height: 4),
                Text('${p.basename(pdfPath)} · $pageCount page${pageCount == 1 ? '' : 's'}'),
                const SizedBox(height: 4),
                Text(exportNotKeptNote, style: text.bodySmall),
                const SizedBox(height: 16),
                ExportDeliveryButtons(
                  paths: [pdfPath],
                  onShare: (_) =>
                      showSendPdfSheet(sheet, pdfPath: pdfPath, name: p.basename(pdfPath), pageCount: pageCount),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.pop(sheet), child: const Text('Done')),
              ],
            ),
          ),
        );
      },
    );
