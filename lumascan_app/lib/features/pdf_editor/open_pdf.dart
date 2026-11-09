import 'dart:async';
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

/// Lets the user pick a PDF, moves it into app storage (so it stays
/// readable after the picker's cache is cleared), opens it with pdfrx and
/// shows the editor. Password-protected files ask for the password.
///
/// On Android the picker copies the chosen file into its cache before it
/// returns, which takes seconds for a big file. The progress dialog starts
/// as soon as the picker says it is copying, so the screen never sits there
/// without feedback. The app's copy is deleted when the editor closes, when
/// opening fails and when it is cancelled.
Future<void> pickAndEditPdf(BuildContext context, WidgetRef ref, {PdfEditorEntry entry = PdfEditorEntry.edit}) async {
  final messenger = ScaffoldMessenger.of(context);
  final pick = Completer<PlatformFile?>();
  Future<void>? opening;

  void startOpening() {
    if (!context.mounted) return;
    opening ??= _openWithProgress(
      context,
      ref,
      name: 'Selected file',
      entry: entry,
      ownsFile: true,
      resolvePath: (progress) async {
        progress.report('Copying the file');
        final picked = await pick.future;
        if (picked == null) throw const OpenCancelled();
        if (progress.cancelled) {
          await _deletePickerCopy(picked);
          throw const OpenCancelled();
        }
        progress.rename(picked.name);
        return (await _takeIntoAppStorage(picked, progress), picked.name);
      },
    );
  }

  try {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      onFileLoading: (status) {
        if (status == FilePickerStatus.picking) startOpening();
      },
    );
    pick.complete(picked);
    if (picked == null && opening == null) return;
  } catch (e) {
    if (!pick.isCompleted) pick.complete(null);
    if (opening == null) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open the file picker ($e)')));
      return;
    }
  }
  startOpening();
  await opening;
}

/// Opens a PDF that is already in app storage, such as a saved library
/// document, and shows the editor. Edits are always saved as a new file.
Future<void> openPdfInEditor(
  BuildContext context,
  WidgetRef ref, {
  required String path,
  required String name,
  PdfEditorEntry entry = PdfEditorEntry.edit,
}) => _openWithProgress(context, ref, name: name, entry: entry, resolvePath: (_) async => (path, name));

/// A PDF opened and measured, ready for the editor.
class _OpenedPdf {
  const _OpenedPdf(this.path, this.name, this.document, this.password);
  final String path;
  final String name;
  final PdfDocument document;
  final String? password;
}

/// Runs the open under the progress dialog. [resolvePath] gives the file to
/// open and its display name. With [ownsFile] that file is the app's own
/// copy and is deleted once it is no longer needed.
Future<void> _openWithProgress(
  BuildContext context,
  WidgetRef ref, {
  required String name,
  required PdfEditorEntry entry,
  required Future<(String, String)> Function(OpenProgress progress) resolvePath,
  bool ownsFile = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  String? ownedPath;
  Future<void> dropOwnedFile() async {
    final path = ownedPath;
    if (ownsFile && path != null) await _deleteQuietly(path);
  }

  final _OpenedPdf? opened;
  try {
    opened = await runOpenWithProgress<_OpenedPdf>(
      context,
      name: name,
      discard: (o) async {
        await o.document.dispose();
        await dropOwnedFile();
      },
      task: (progress) async {
        final (path, shownName) = await resolvePath(progress);
        ownedPath = path;
        progress.throwIfCancelled();
        if (!context.mounted) throw const OpenCancelled();
        final document = await openCheckedPdf(context, path, progress);
        return _OpenedPdf(path, shownName, document.$1, document.$2);
      },
    );
  } on PdfPasswordException {
    await dropOwnedFile();
    messenger.showSnackBar(const SnackBar(content: Text('The PDF stays locked without its password.')));
    return;
  } on DocumentOpenException catch (e) {
    await dropOwnedFile();
    if (context.mounted) await showOpenError(context, title: e.title, message: e.message);
    return;
  } catch (e) {
    await dropOwnedFile();
    final fallback = DocumentOpenException(OpenFailure.corrupted, detail: '$e');
    if (context.mounted) await showOpenError(context, title: fallback.title, message: fallback.message);
    return;
  }
  if (opened == null) {
    // Cancelled. A copy still being made is deleted by the task or [discard].
    await dropOwnedFile();
    return;
  }
  if (!context.mounted) {
    await opened.document.dispose();
    await dropOwnedFile();
    return;
  }

  final document = opened.document;
  ref
      .read(pdfEditControllerProvider.notifier)
      .open(
        path: opened.path,
        name: opened.name,
        password: opened.password,
        pageSizes: [for (final page in document.pages) (page.width, page.height)],
      );
  await navigator.push(MaterialPageRoute(builder: (_) => PdfEditorScreen.forDocument(document, entry: entry)));
  // Edits are saved as new files, so the opened copy is no longer needed.
  await dropOwnedFile();
}

/// Checks the file, opens it with PDFium on pdfrx's background worker and
/// measures every page a slice at a time, reporting progress and stopping as
/// soon as the user cancels. PDFium reads the file from disk as it needs it,
/// so even a very large file is never loaded into memory in one piece.
///
/// With [maxPages], a longer document fails with [OpenFailure.tooManyPages]
/// before any page is read.
Future<(PdfDocument, String?)> openCheckedPdf(
  BuildContext context,
  String path,
  OpenProgress progress, {
  int? maxPages,
}) async {
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
    if (maxPages != null && total > maxPages) {
      throw DocumentOpenException(OpenFailure.tooManyPages, detail: '$total');
    }
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
    return (document, password);
  } catch (_) {
    await document.dispose();
    rethrow;
  }
}

/// Puts a picked file into app storage. The picker's own cached copy is
/// moved (instant, no second copy on disk) when it can be; otherwise the
/// file is streamed over a chunk at a time with byte progress, so a big
/// file is never read into memory whole.
Future<String> _takeIntoAppStorage(PlatformFile picked, OpenProgress progress) async {
  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'pdf_sources'));
  await dir.create(recursive: true);
  await _clearOldSources(dir);
  final path = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}.pdf');

  final cached = picked.path;
  if (cached != null && _isPickerCache(cached)) {
    try {
      await File(cached).rename(path);
      return path;
    } on FileSystemException {
      // Another file system: copy it below.
    }
  }

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
  await _deletePickerCopy(picked);
  if (progress.cancelled) {
    await _deleteQuietly(path);
    throw const OpenCancelled();
  }
  return path;
}

/// The Android picker caches picked files under `cache/file_picker/`.
bool _isPickerCache(String path) => p.split(path).contains('file_picker');

Future<void> _deletePickerCopy(PlatformFile picked) async {
  final cached = picked.path;
  if (cached != null && _isPickerCache(cached)) await _deleteQuietly(cached);
}

/// Copies left behind by a crash or a force stop: anything older than a day.
Future<void> _clearOldSources(Directory dir) async {
  final cutoff = DateTime.now().subtract(const Duration(days: 1));
  try {
    await for (final entry in dir.list()) {
      if (entry is File && (await entry.lastModified()).isBefore(cutoff)) await _deleteQuietly(entry.path);
    }
  } on FileSystemException {
    // Nothing to clear.
  }
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
