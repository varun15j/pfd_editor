import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../pdf_edit/pdf_edit_controller.dart';
import 'pdf_editor_screen.dart';

/// Lets the user pick a PDF, copies it into app storage (so it stays
/// readable after the picker's cache is cleared), opens it with pdfrx and
/// shows the editor. Password-protected files ask for the password.
Future<void> pickAndEditPdf(BuildContext context, WidgetRef ref, {PdfEditorEntry entry = PdfEditorEntry.edit}) async {
  final messenger = ScaffoldMessenger.of(context);

  final PlatformFile? picked;
  try {
    picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf']);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open the file picker ($e)')));
    return;
  }
  if (picked == null || !context.mounted) return;

  final String path;
  try {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'pdf_sources'));
    await dir.create(recursive: true);
    path = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}.pdf');
    await picked.xFile.saveTo(path);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not read ${picked.name} ($e)')));
    return;
  }
  if (!context.mounted) return;
  await openPdfInEditor(context, ref, path: path, name: picked.name, entry: entry);
}

/// Opens a PDF that is already in app storage, such as a saved library
/// document, and shows the editor. Edits are always saved as a new file.
Future<void> openPdfInEditor(
  BuildContext context,
  WidgetRef ref, {
  required String path,
  required String name,
  PdfEditorEntry entry = PdfEditorEntry.edit,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  String? password;
  var attempts = 0;
  final PdfDocument document;
  try {
    await pdfrxFlutterInitialize();
    document = await PdfDocument.openFile(
      path,
      passwordProvider: () async {
        if (!context.mounted) return null;
        password = await _askPassword(context, retry: attempts++ > 0);
        return password;
      },
    );
  } on PdfPasswordException {
    messenger.showSnackBar(const SnackBar(content: Text('The PDF stays locked without its password.')));
    return;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('This file could not be opened as a PDF ($e)')));
    return;
  }

  if (document.pages.isEmpty || !context.mounted) {
    await document.dispose();
    if (context.mounted) messenger.showSnackBar(const SnackBar(content: Text('This PDF has no pages.')));
    return;
  }

  ref
      .read(pdfEditControllerProvider.notifier)
      .open(
        path: path,
        name: name,
        password: password,
        pageSizes: [for (final page in document.pages) (page.width, page.height)],
      );
  await navigator.push(MaterialPageRoute(builder: (_) => PdfEditorScreen.forDocument(document, entry: entry)));
}

Future<String?> _askPassword(BuildContext context, {required bool retry}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _PasswordDialog(retry: retry),
);

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.retry});
  final bool retry;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Password needed'),
      content: TextField(
        controller: _text,
        autofocus: true,
        obscureText: true,
        decoration: InputDecoration(
          hintText: 'PDF password',
          errorText: widget.retry ? 'That password did not work. Try again.' : null,
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _text.text), child: const Text('Open')),
      ],
    );
  }
}
