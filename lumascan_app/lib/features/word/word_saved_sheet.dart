import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../export/word/word_service.dart';
import '../share/docx_sharer.dart';
import '../share/pdf_sharer.dart';
import '../../ui/luma_icons.dart';

/// Asks what to do with a Word file once it is made: open it in Word or
/// another app, share it, or save it to the Documents folder. The Word file
/// stays in the app's exports folder either way; the Library holds PDFs.
Future<void> showWordSavedSheet(BuildContext context, WordFile word) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => WordSavedSheet(word: word),
);

class WordSavedSheet extends ConsumerWidget {
  const WordSavedSheet({super.key, required this.word});

  final WordFile word;

  /// "2 pages of editable text, 1 picture page".
  static String summary(WordFile word) {
    String count(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    return [
      if (word.textPages > 0) count(word.textPages, 'page of editable text', 'pages of editable text'),
      if (word.picturePages > 0) count(word.picturePages, 'picture page', 'picture pages'),
    ].join(', ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final path = word.file.path;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Word file saved', style: textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(p.basename(path), style: textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text(summary(word), style: textTheme.bodySmall),
            if (word.textPages == 0) ...[
              const SizedBox(height: 4),
              Text(
                'These pages had no text to take, so each one is a picture. '
                'Make a text PDF first to get text you can edit.',
                style: textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            _Option(icon: LumaIcons.openExternal, title: 'Open in Word', onTap: () => _open(context)),
            Builder(
              builder: (tileContext) =>
                  _Option(icon: LumaIcons.share, title: 'Share', onTap: () => _share(context, ref, tileContext)),
            ),
            _Option(
              icon: LumaIcons.folder,
              title: 'Save to Documents folder',
              subtitle: 'Choose Documents in the save dialog',
              onTap: () => _saveToDocuments(context),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await OpenFilex.open(word.file.path, type: SharePlusDocxSharer.mimeType);
    if (result.type == ResultType.done) {
      navigator.pop();
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (result.type) {
          ResultType.noAppToOpen => 'No app on this device can open Word files. Try Share instead.',
          ResultType.fileNotFound => 'This Word file is no longer on this device.',
          _ => 'Could not open the Word file. ${result.message}',
        }),
      ),
    );
  }

  /// Shares from the tile that was tapped, so the iPad share sheet has
  /// somewhere to point.
  Future<void> _share(BuildContext context, WidgetRef ref, BuildContext tileContext) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final box = tileContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      final outcome = await ref.read(docxSharerProvider).send(word.file.path, origin: origin);
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
        dialogTitle: 'Save Word file to Documents',
        fileName: p.basename(word.file.path),
        bytes: await File(word.file.path).readAsBytes(),
        mimeType: SharePlusDocxSharer.mimeType,
        type: FileType.custom,
        allowedExtensions: const ['docx'],
      );
      // Cancelling the dialog keeps the sheet open, so another option can be picked.
      if (saved == null) return;
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Saved to Documents')));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save the Word file. $e')));
    }
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.title, required this.onTap, this.subtitle});

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
