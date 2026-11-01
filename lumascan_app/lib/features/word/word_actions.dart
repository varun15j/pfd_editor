import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../domain/library.dart';
import '../../domain/models.dart';
import '../../domain/plan.dart';
import '../../ui/upgrade_dialog.dart';
import '../../export/word/word_service.dart';
import '../library/library_controller.dart';
import '../merge/pdf_inspector.dart';
import '../merge/pdf_picker.dart';
import '../share/send_pdf_sheet.dart';
import 'word_saved_sheet.dart';
import '../../ui/luma_icons.dart';

/// Converts a saved PDF to a Word file in the exports folder, then asks what
/// to do with it. Pages with text become editable text, picture pages stay
/// pictures. The saved PDF is not changed, and the Word file is not added to
/// the Library, which holds PDFs.
Future<void> convertToWord(BuildContext context, WidgetRef ref, SavedDocument doc) async {
  if (!await _ensureWordPlan(context, ref)) return;
  if (!context.mounted) return;
  if (!File(doc.pdfPath).existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${doc.name} is no longer on this device.')));
    return;
  }
  final editable = await askWordKind(context);
  if (editable == null || !context.mounted) return;
  final service = ref.read(wordServiceProvider);
  await _convert(
    context,
    title: 'Converting to Word',
    name: doc.name,
    run: (onProgress) => service.pdfToWord(
      doc.pdfPath,
      pageCount: doc.pageCount,
      name: doc.name,
      editableText: editable,
      onProgress: onProgress,
    ),
  );
}

/// Asks how a PDF becomes Word: as editable text where the PDF has text
/// (true), or with every page as a picture so it looks exactly the same
/// (false). Null when the sheet is closed.
Future<bool?> askWordKind(BuildContext context) => showModalBottomSheet<bool>(
  context: context,
  showDragHandle: true,
  builder: (sheetContext) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Text('Convert to Word', style: Theme.of(sheetContext).textTheme.headlineSmall),
          ),
          ListTile(
            leading: const Icon(LumaIcons.textTool),
            title: const Text('Editable text'),
            subtitle: const Text(
              'Text PDFs and text PDFs made with OCR become text you can edit. Pages that are only a picture stay pictures',
            ),
            onTap: () => Navigator.pop(sheetContext, true),
          ),
          ListTile(
            leading: const Icon(LumaIcons.image),
            title: const Text('Exact look'),
            subtitle: const Text('Every page is one full-page picture, so it looks the same as the PDF'),
            onTap: () => Navigator.pop(sheetContext, false),
          ),
        ],
      ),
    ),
  ),
);

/// Tools > PDF to Word: lets the user pick any PDF on the device and
/// converts it the same way as [convertToWord].
Future<void> pickPdfToWord(BuildContext context, WidgetRef ref) async {
  if (!await _ensureWordPlan(context, ref) || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final List<PickedPdf> picked;
  try {
    picked = await ref.read(pdfPickerProvider).pick();
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open the file picker ($e)')));
    return;
  }
  if (picked.isEmpty || !context.mounted) return;
  final pdf = picked.first;
  try {
    final info = await ref.read(pdfInspectorProvider).inspect(pdf.path);
    final pageCount = info.pageCount;
    if (pageCount == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            info.problem == PdfProblem.locked
                ? '${pdf.name} is locked with a password. Unlock it first, then convert it.'
                : '${pdf.name} could not be read as a PDF.',
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    final editable = await askWordKind(context);
    if (editable == null || !context.mounted) return;
    final name = p.basenameWithoutExtension(pdf.name);
    final service = ref.read(wordServiceProvider);
    await _convert(
      context,
      title: 'Converting to Word',
      name: pdf.name,
      run: (onProgress) =>
          service.pdfToWord(pdf.path, pageCount: pageCount, name: name, editableText: editable, onProgress: onProgress),
    );
  } finally {
    _deleteQuietly(pdf.path);
  }
}

/// Export > Word from the pages screen: the scan's pages become a Word
/// file. A page already read with OCR becomes its text; the others are
/// pictures. Nothing is read again here.
Future<void> exportScanAsWord(BuildContext context, WidgetRef ref, List<ScanPage> pages, {required String name}) async {
  if (!await _ensureWordPlan(context, ref) || !context.mounted || pages.isEmpty) return;
  final service = ref.read(wordServiceProvider);
  await _convert(
    context,
    title: 'Saving as Word',
    name: name,
    run: (onProgress) => service.pagesToWord(pages, name: name, onProgress: onProgress),
  );
}

/// PDF to Word is part of Pro and Gold. On Basic this shows the upgrade
/// pop-up and returns false.
Future<bool> _ensureWordPlan(BuildContext context, WidgetRef ref) =>
    ensurePlan(context, ref, PlanFeature.word, what: 'Convert to Word');

/// Shows progress while [run] makes the Word file, then the saved sheet.
Future<void> _convert(
  BuildContext context, {
  required String title,
  required String name,
  required Future<WordFile> Function(void Function(double) onProgress) run,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final progress = ValueNotifier<double>(0);
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: _WordProgress(title: title, name: name, progress: progress),
      ),
    ),
  );
  try {
    final word = await run((f) => progress.value = f);
    navigator.pop();
    if (context.mounted) {
      await showWordSavedSheet(context, word);
    } else {
      messenger.showSnackBar(SnackBar(content: Text('Saved ${p.basename(word.file.path)}')));
    }
  } on Object catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Could not convert $name to Word. $e')));
  } finally {
    progress.dispose();
  }
}

/// Lets the user pick a Word (.docx) file from the device, turns it into a
/// PDF and saves that to the Library.
Future<void> importWordFile(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final PlatformFile? picked;
  try {
    picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['docx']);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open the file picker ($e)')));
    return;
  }
  if (picked == null || !context.mounted) return;
  final chosen = picked;

  final service = ref.read(wordServiceProvider);
  final library = ref.read(libraryProvider.notifier);
  final name = p.basenameWithoutExtension(chosen.name);

  // The picked file is copied into app storage so it stays readable while converting.
  final String copy;
  try {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'word_sources'));
    await dir.create(recursive: true);
    copy = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}.docx');
    await chosen.xFile.saveTo(copy);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not read ${chosen.name} ($e)')));
    return;
  }
  if (!context.mounted) return;

  final progress = ValueNotifier<double>(0);
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: _WordProgress(title: 'Opening Word file', name: chosen.name, progress: progress),
      ),
    ),
  );
  try {
    final made = await service.wordToPdf(copy, name: name);
    navigator.pop();
    final saved = await library.addPdf(made.file, pageCount: made.pageCount);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Saved ${saved.name}.pdf'),
          action: context.mounted
              ? SnackBarAction(
                  label: 'Send',
                  onPressed: () =>
                      showSendPdfSheet(context, pdfPath: saved.pdfPath, name: saved.name, pageCount: saved.pageCount),
                )
              : null,
        ),
      );
  } on FormatException catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } on Object catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Could not open ${chosen.name} as a Word file. $e')));
  } finally {
    progress.dispose();
    _deleteQuietly(copy);
  }
}

void _deleteQuietly(String path) {
  try {
    File(path).deleteSync();
  } on FileSystemException {
    // The copy is in app storage; it is replaced or removed with the app.
  }
}

class _WordProgress extends StatelessWidget {
  const _WordProgress({required this.title, required this.name, required this.progress});

  final String title;
  final String name;
  final ValueNotifier<double> progress;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (_, value, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: value),
          const SizedBox(height: 8),
          Text('${(value * 100).round()}%', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}
