import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/cloud_storage.dart';
import '../library/library_controller.dart';
import '../library/library_organize.dart';
import '../share/send_pdf_sheet.dart';
import 'cloud_importer.dart';
import '../../ui/luma_icons.dart';

/// Where an imported document goes: a Library folder, or the top level when
/// [folderId] is null.
class ImportDestination {
  const ImportDestination(this.folderId);

  final String? folderId;
}

/// Asks which Library folder [fileName] goes into. Null when dismissed.
Future<ImportDestination?> pickImportFolder(BuildContext context, String fileName) async {
  const top = '';
  final picked = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final folders = ref.watch(libraryProvider).value?.folders ?? const [];
        return SafeArea(
          child: SingleChildScrollView(
            child: RadioGroup<String>(
              onChanged: (v) => Navigator.pop(sheetContext, v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xs),
                    child: Semantics(
                      header: true,
                      child: Text('Import to', style: Theme.of(context).textTheme.titleLarge),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
                    child: Text(
                      '$fileName is saved as a PDF in your Library. The file in your cloud account is not changed.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const RadioListTile<String>(value: top, title: Text('Library (no folder)')),
                  for (final f in folders) RadioListTile<String>(value: f.id, title: Text(f.name)),
                  ListTile(
                    leading: const Icon(LumaIcons.createNewFolder),
                    title: const Text('New folder'),
                    onTap: () async {
                      final folder = await createFolderFlow(context, ref);
                      if (folder != null && sheetContext.mounted) Navigator.pop(sheetContext, folder.id);
                    },
                  ),
                  const SizedBox(height: Space.sm),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  if (picked == null) return null;
  return ImportDestination(picked == top ? null : picked);
}

/// Fetches a file with [fetch] (a download, or the copy the system picker
/// made), imports it into [destination] and reports the outcome in a snack
/// bar. The fetched copy is deleted afterwards.
///
/// Returns false when the service refused the sign-in, so the caller can
/// offer to connect again.
Future<bool> runCloudImport(
  BuildContext context,
  WidgetRef ref, {
  required String name,
  required CloudEntryKind kind,
  required ImportDestination destination,
  required Future<File> Function() fetch,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final importer = ref.read(cloudImporterProvider);
  final stage = ValueNotifier<String>('Downloading');
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: _ImportProgress(name: name, stage: stage),
      ),
    ),
  );
  File? file;
  try {
    file = await fetch();
    stage.value = 'Saving to your Library';
    final saved = await importer.import(file, name: name, kind: kind, folderId: destination.folderId);
    navigator.pop();
    final folder = ref.read(libraryProvider).value?.folderById(destination.folderId)?.name;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Saved ${saved.name}.pdf to ${folder ?? 'your Library'}'),
          action: context.mounted
              ? SnackBarAction(
                  label: 'Send',
                  onPressed: () =>
                      showSendPdfSheet(context, pdfPath: saved.pdfPath, name: saved.name, pageCount: saved.pageCount),
                )
              : null,
        ),
      );
    return true;
  } on CloudSignInExpired {
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('The sign-in has expired. Connect the account again.')));
    return false;
  } on FormatException catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return true;
  } on Object catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Could not import $name. $e')));
    return true;
  } finally {
    stage.dispose();
    _deleteQuietly(file);
  }
}

void _deleteQuietly(File? file) {
  try {
    file?.deleteSync();
  } on FileSystemException {
    // A temp file; the system clears these.
  }
}

class _ImportProgress extends StatelessWidget {
  const _ImportProgress({required this.name, required this.stage});

  final String name;
  final ValueNotifier<String> stage;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Importing'),
    content: ValueListenableBuilder<String>(
      valueListenable: stage,
      builder: (_, value, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}
