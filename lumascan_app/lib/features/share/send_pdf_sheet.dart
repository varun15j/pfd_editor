import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../export/pdf_shrinker.dart';
import '../../ui/file_size.dart';
import 'pdf_sharer.dart';

/// Offers to send a saved PDF as it is, or as a smaller copy. The saved file
/// is never changed: the smaller copy is a separate file made for sending.
Future<void> showSendPdfSheet(
  BuildContext context, {
  required String pdfPath,
  required String name,
  required int pageCount,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  // Back and the scrim are blocked by the sheet itself while the copy is made.
  enableDrag: false,
  builder: (_) => SendPdfSheet(pdfPath: pdfPath, name: name, pageCount: pageCount),
);

class SendPdfSheet extends ConsumerStatefulWidget {
  const SendPdfSheet({super.key, required this.pdfPath, required this.name, required this.pageCount});

  final String pdfPath;

  /// Display name, with or without .pdf.
  final String name;
  final int pageCount;

  @override
  ConsumerState<SendPdfSheet> createState() => _SendPdfSheetState();
}

class _SendPdfSheetState extends ConsumerState<SendPdfSheet> {
  double? _progress;
  String? _error;

  /// The smaller copy once it is made, so a second tap sends the same file.
  File? _copy;

  bool get _making => _progress != null;

  String get _fileName {
    final n = widget.name;
    return n.toLowerCase().endsWith('.pdf') ? n : '$n.pdf';
  }

  int? get _originalSize {
    final f = File(widget.pdfPath);
    return f.existsSync() ? f.lengthSync() : null;
  }

  Rect? _originOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  /// Opens the share sheet for [path]. A failure is shown here and leaves the
  /// saved file untouched.
  Future<void> _send(BuildContext tileContext, String path, {required String sent}) async {
    final origin = _originOf(tileContext);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final sharer = ref.read(pdfSharerProvider);
    setState(() => _error = null);
    try {
      final outcome = await sharer.send(path, origin: origin);
      if (outcome == SendOutcome.sent) {
        navigator.pop();
        messenger.showSnackBar(SnackBar(content: Text(sent)));
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not open the share sheet. Your saved PDF is unchanged. ($e)');
    }
  }

  Future<void> _sendOriginal(BuildContext tileContext) {
    if (!File(widget.pdfPath).existsSync()) {
      setState(() => _error = 'This PDF is no longer on this device.');
      return Future.value();
    }
    return _send(tileContext, widget.pdfPath, sent: 'PDF shared');
  }

  Future<void> _sendSmaller(BuildContext tileContext) async {
    if (_making) return;
    var copy = _copy;
    if (copy == null || !copy.existsSync()) {
      final shrinker = ref.read(pdfShrinkerProvider);
      setState(() {
        _progress = 0;
        _error = null;
      });
      try {
        copy = await shrinker.makeSmaller(
          sourcePath: widget.pdfPath,
          pageCount: widget.pageCount,
          name: widget.name,
          onProgress: (done, total) {
            if (mounted) setState(() => _progress = done / total);
          },
        );
      } on Object catch (e) {
        if (mounted) {
          setState(() {
            _progress = null;
            _error = 'Could not make a smaller copy. Your saved PDF is unchanged. ($e)';
          });
        }
        return;
      }
      if (!mounted) return;
      final original = _originalSize;
      final size = copy.lengthSync();
      if (original != null && size >= original) {
        // Nothing gained: say so instead of sending a copy that is not smaller.
        setState(() {
          _progress = null;
          _error =
              'A smaller copy would not be smaller (${formatFileSize(size)} against '
              '${formatFileSize(original)}). Send the PDF as it is.';
        });
        copy.deleteSync();
        return;
      }
      setState(() {
        _progress = null;
        _copy = copy;
      });
    }
    if (!tileContext.mounted) return;
    await _send(tileContext, copy.path, sent: 'Smaller copy shared');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final original = _originalSize;
    final copy = _copy;
    final estimate = PdfShrinker.estimateBytes(widget.pageCount);
    final copySubtitle = copy != null
        ? '${p.basename(copy.path)} · ${formatFileSize(copy.lengthSync())}'
        : '${PdfShrinker.copyName(widget.name)} · '
              '${original != null && estimate < original ? 'about ${formatFileSize(estimate)}' : 'size shown once it is made'}';

    return PopScope(
      canPop: !_making,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Send PDF', style: textTheme.headlineSmall),
              const SizedBox(height: 12),
              Builder(
                builder: (tileContext) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: !_making,
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: const Text('Send PDF'),
                  subtitle: Text('$_fileName · ${original == null ? 'size unknown' : formatFileSize(original)}'),
                  onTap: () => _sendOriginal(tileContext),
                ),
              ),
              Builder(
                builder: (tileContext) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: !_making,
                  leading: const Icon(Icons.compress),
                  title: const Text('Send smaller copy'),
                  subtitle: Text(copySubtitle),
                  onTap: () => _sendSmaller(tileContext),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A smaller copy has lower-resolution pages, and text in it cannot be selected. '
                'Your saved PDF is not changed.',
                style: textTheme.bodySmall,
              ),
              if (_making) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text('Making a smaller copy…', style: textTheme.bodySmall, textAlign: TextAlign.center),
              ],
              if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: scheme.error))],
            ],
          ),
        ),
      ),
    );
  }
}
