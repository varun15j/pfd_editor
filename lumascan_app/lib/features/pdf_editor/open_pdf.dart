import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../pdf_edit/pdf_edit_controller.dart';
import '../open/open_progress.dart';
import '../open/pdf_file_check.dart';
import 'pdf_editor_screen.dart';

/// Lets the user pick a PDF, copies it into app storage (so it stays
/// readable after the picker's cache is cleared), opens it with pdfrx and
/// shows the editor. Password-protected files ask for the password. The copy
/// and the open run under one progress dialog the user can cancel.
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

  await _openWithProgress(
    context,
    ref,
    name: picked.name,
    entry: entry,
    resolvePath: (progress) => _copyIntoAppStorage(picked!, progress),
  );
}

/// Opens a PDF that is already in app storage, such as a saved library
/// document, and shows the editor. Edits are always saved as a new file.
Future<void> openPdfInEditor(
  BuildContext context,
  WidgetRef ref, {
  required String path,
  required String name,
  PdfEditorEntry entry = PdfEditorEntry.edit,
}) => _openWithProgress(context, ref, name: name, entry: entry, resolvePath: (_) async => path);

/// A PDF opened and measured, ready for the editor.
class _OpenedPdf {
  const _OpenedPdf(this.path, this.document, this.password);
  final String path;
  final PdfDocument document;
  final String? password;
}

Future<void> _openWithProgress(
  BuildContext context,
  WidgetRef ref, {
  required String name,
  required PdfEditorEntry entry,
  required Future<String> Function(OpenProgress progress) resolvePath,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final _OpenedPdf? opened;
  try {
    opened = await runOpenWithProgress<_OpenedPdf>(
      context,
      name: name,
      discard: (o) => o.document.dispose(),
      task: (progress) async {
        final path = await resolvePath(progress);
        progress.throwIfCancelled();
        if (!context.mounted) throw const OpenCancelled();
        return _openPdf(context, path, progress);
      },
    );
  } on PdfPasswordException {
    messenger.showSnackBar(const SnackBar(content: Text('The PDF stays locked without its password.')));
    return;
  } on DocumentOpenException catch (e) {
    if (context.mounted) await showOpenError(context, title: e.title, message: e.message);
    return;
  } catch (e) {
    final fallback = DocumentOpenException(OpenFailure.corrupted, detail: '$e');
    if (context.mounted) await showOpenError(context, title: fallback.title, message: fallback.message);
    return;
  }
  if (opened == null) return; // Cancelled.
  if (!context.mounted) {
    await opened.document.dispose();
    return;
  }

  final document = opened.document;
  ref
      .read(pdfEditControllerProvider.notifier)
      .open(
        path: opened.path,
        name: name,
        password: opened.password,
        pageSizes: [for (final page in document.pages) (page.width, page.height)],
      );
  await navigator.push(MaterialPageRoute(builder: (_) => PdfEditorScreen.forDocument(document, entry: entry)));
}

/// Checks the file, opens it with PDFium on pdfrx's background worker and
/// measures every page a slice at a time, reporting progress and stopping as
/// soon as the user cancels. PDFium reads the file from disk as it needs it,
/// so even a very large file is never loaded into memory in one piece.
Future<_OpenedPdf> _openPdf(BuildContext context, String path, OpenProgress progress) async {
  progress.report('Checking the file');
  final facts = await checkPdfFile(path);
  progress.throwIfCancelled();

  progress.report('Opening the document');
  await pdfrxFlutterInitialize();
  String? password;
  var attempts = 0;
  final PdfDocument document;
  try {
    document = await PdfDocument.openFile(
      path,
      useProgressiveLoading: true,
      passwordProvider: () async {
        if (progress.cancelled || !context.mounted) return null;
        password = await progress.waitForUser(() => _askPassword(context, retry: attempts++ > 0));
        return password;
      },
    );
  } on PdfPasswordException {
    if (progress.cancelled) throw const OpenCancelled();
    rethrow;
  } on PdfException catch (e) {
    throw pdfiumFailure(e.errorCode, facts: facts);
  }

  try {
    progress.throwIfCancelled();
    final total = document.pages.length;
    if (total == 0) throw const DocumentOpenException(OpenFailure.noPages);
    progress.report('Reading pages', done: 0, total: total);
    await document.loadPagesProgressively(
      onPageLoadProgress: (loaded, total, _) {
        progress.report('Reading pages', done: loaded, total: total);
        return !progress.cancelled;
      },
    );
    progress.throwIfCancelled();
    for (final page in document.pages) {
      if (!isUsablePageSize(page.width, page.height)) throw const DocumentOpenException(OpenFailure.damagedPage);
    }
    progress.report('Reading pages', done: total, total: total);
    return _OpenedPdf(path, document, password);
  } catch (_) {
    await document.dispose();
    rethrow;
  }
}

/// Copies a picked file into app storage a chunk at a time, reporting the
/// bytes copied. Files from cloud providers can take a while to arrive.
Future<String> _copyIntoAppStorage(PlatformFile picked, OpenProgress progress) async {
  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'pdf_sources'));
  await dir.create(recursive: true);
  final path = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}.pdf');
  final total = await picked.xFile.length().catchError((Object _) => 0);
  progress.report('Copying the file', done: 0, total: total, unit: OpenUnit.bytes);
  final sink = File(path).openWrite();
  var copied = 0;
  try {
    await for (final chunk in picked.xFile.openRead()) {
      if (progress.cancelled) break;
      sink.add(chunk);
      copied += chunk.length;
      progress.report('Copying the file', done: copied, total: total, unit: OpenUnit.bytes);
    }
    await sink.flush();
    await sink.close();
  } on FileSystemException catch (e) {
    await sink.close().catchError((_) {});
    await _deleteQuietly(path);
    // ENOSPC is 28 on Android, Linux and iOS.
    throw DocumentOpenException(e.osError?.errorCode == 28 ? OpenFailure.noSpace : OpenFailure.unreadable);
  } catch (_) {
    await sink.close().catchError((_) {});
    await _deleteQuietly(path);
    throw const DocumentOpenException(OpenFailure.unreadable);
  }
  if (progress.cancelled) {
    await _deleteQuietly(path);
    throw const OpenCancelled();
  }
  return path;
}

Future<void> _deleteQuietly(String path) async {
  try {
    await File(path).delete();
  } on FileSystemException {
    // Already gone.
  }
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
