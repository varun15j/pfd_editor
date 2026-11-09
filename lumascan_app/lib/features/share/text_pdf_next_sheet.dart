import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../export/export_delivery.dart';
import 'pdf_sharer.dart';
import '../../ui/luma_icons.dart';

/// Asks where a text PDF goes once it is built: saved where the user picks
/// (Documents, an SD card, Drive) or shared. It can also be opened in
/// another PDF app. The app keeps no copy of exports, so the PDF waits in
/// the Outbox only until then.
Future<void> showTextPdfNextSheet(BuildContext context, {required String pdfPath, required int pageCount}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TextPdfNextSheet(pdfPath: pdfPath, pageCount: pageCount),
    );

class TextPdfNextSheet extends ConsumerWidget {
  const TextPdfNextSheet({super.key, required this.pdfPath, required this.pageCount});

  final String pdfPath;
  final int pageCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Text PDF ready', style: textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '${p.basename(pdfPath)} · $pageCount page${pageCount == 1 ? '' : 's'}',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(exportNotKeptNote, style: textTheme.bodySmall),
            const SizedBox(height: 16),
            ExportDeliveryButtons(paths: [pdfPath], onShare: (button) => _share(context, ref, button)),
            _NextOption(
              icon: LumaIcons.openExternal,
              title: 'Open in another PDF app',
              onTap: () => _open(context),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await OpenFilex.open(pdfPath, type: 'application/pdf');
    if (result.type == ResultType.done) {
      navigator.pop();
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(_openMessage(result))));
  }

  static String _openMessage(OpenResult result) => switch (result.type) {
    ResultType.noAppToOpen => 'No app on this device can open PDFs.',
    ResultType.fileNotFound => 'This PDF is no longer on this device.',
    _ => 'Could not open the PDF. ${result.message}',
  };

  /// Shares the file from the tile that was tapped, so the iPad share sheet
  /// has somewhere to point. The file is not changed.
  Future<void> _share(BuildContext context, WidgetRef ref, BuildContext tileContext) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final box = tileContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      final outcome = await ref.read(pdfSharerProvider).send(pdfPath, origin: origin);
      if (outcome == SendOutcome.sent && navigator.mounted) navigator.pop();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open the share sheet. $e')));
    }
  }
}

class _NextOption extends StatelessWidget {
  const _NextOption({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    onTap: onTap,
  );
}
