import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../domain/library.dart';
import '../library/library_controller.dart';
import '../share/docx_sharer.dart';
import '../share/send_pdf_sheet.dart';

/// Converts a saved PDF to a Word file in the exports folder, then offers to
/// share it. The saved PDF is not changed, and the Word file is not added to
/// the Library, which holds PDFs.
Future<void> convertToWord(BuildContext context, WidgetRef ref, SavedDocument doc) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!File(doc.pdfPath).existsSync()) {
    messenger.showSnackBar(SnackBar(content: Text('${doc.name} is no longer on this device.')));
    return;
  }
  final service = ref.read(wordServiceProvider);
  final sharer = ref.read(docxSharerProvider);
  final progress = ValueNotifier<double>(0);
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: _WordProgress(title: 'Converting to Word', name: doc.name, progress: progress),
      ),
    ),
  );
  try {
    final file = await service.pdfToWord(
      doc.pdfPath,
      pageCount: doc.pageCount,
      name: doc.name,
      onProgress: (f) => progress.value = f,
    );
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Saved ${p.basename(file.path)}'),
          action: context.mounted
              ? SnackBarAction(label: 'Share', onPressed: () => _shareWord(context, sharer, file.path))
              : null,
        ),
      );
  } on Object catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Could not convert ${doc.name} to Word. $e')));
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

Future<void> _shareWord(BuildContext context, DocxSharer sharer, String path) async {
  final box = context.findRenderObject() as RenderBox?;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await sharer.send(path, origin: box == null ? null : box.localToGlobal(Offset.zero) & box.size);
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('The share sheet could not be opened. ($e)')));
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
