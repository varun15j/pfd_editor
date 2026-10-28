import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import 'pdf_sharer.dart';
import '../../ui/luma_icons.dart';

/// Asks what to do with a text PDF once it is built: keep it in the app's
/// library, open it in another PDF app, share it, or save it to the Documents
/// folder. The sheet shows every time, so the user decides where it goes.
Future<void> showTextPdfNextSheet(
  BuildContext context, {
  required String pdfPath,
  required int pageCount,
  required Future<void> Function() saveToLibrary,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => TextPdfNextSheet(pdfPath: pdfPath, pageCount: pageCount, saveToLibrary: saveToLibrary),
);

class TextPdfNextSheet extends ConsumerWidget {
  const TextPdfNextSheet({super.key, required this.pdfPath, required this.pageCount, required this.saveToLibrary});

  final String pdfPath;
  final int pageCount;

  /// Files the PDF in the app's library. The sheet closes once it is done.
  final Future<void> Function() saveToLibrary;

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
            Text('Text PDF saved', style: textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '${p.basename(pdfPath)} · $pageCount page${pageCount == 1 ? '' : 's'}',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _NextOption(
              icon: LumaIcons.library,
              title: 'Save to library',
              subtitle: 'Keep it with your documents',
              onTap: () => _saveToLibrary(context),
            ),
            _NextOption(
              icon: LumaIcons.openExternal,
              title: 'Open in another PDF app',
              onTap: () => _open(context),
            ),
            Builder(
              builder: (tileContext) => _NextOption(
                icon: LumaIcons.share,
                title: 'Share',
                onTap: () => _share(context, ref, tileContext),
              ),
            ),
            _NextOption(
              icon: LumaIcons.folder,
              title: 'Save to Documents folder',
              subtitle: 'Choose Documents in the save dialog',
              onTap: () => _saveToDocuments(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveToLibrary(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await saveToLibrary();
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Saved to your Library')));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save to your Library. $e')));
    }
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
      if (outcome == SendOutcome.sent) navigator.pop();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open the share sheet. $e')));
    }
  }

  Future<void> _saveToDocuments(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save PDF to Documents',
        fileName: p.basename(pdfPath),
        bytes: await File(pdfPath).readAsBytes(),
        mimeType: 'application/pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      // Cancelling the dialog keeps the sheet open, so the user can pick another option.
      if (saved == null) return;
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Saved to Documents')));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save the PDF. $e')));
    }
  }
}

class _NextOption extends StatelessWidget {
  const _NextOption({required this.icon, required this.title, required this.onTap, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    onTap: onTap,
  );
}
