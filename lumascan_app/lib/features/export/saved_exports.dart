import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../data/page_store.dart';
import '../../domain/saved_export.dart';
import '../library/library_actions.dart';

/// What to do for an export: reuse the saved file because nothing changed,
/// or write a new one under [ExportNew.fileName].
sealed class ExportPlan {
  const ExportPlan();
}

/// The scan and the options are unchanged since [saved] was made, and its
/// file is still there.
class ExportReuse extends ExportPlan {
  const ExportReuse(this.saved);

  final SavedExport saved;
}

/// Write the file as [fileName] (relative to the exports folder, inside the
/// Saved folder). [previous] is the earlier export it replaces, if any.
class ExportNew extends ExportPlan {
  const ExportNew(this.fileName, {this.previous});

  final String fileName;
  final SavedExport? previous;
}

/// Exports in the Saved folder whose files are still on the device, newest
/// first. Read from the export state database. Since exports are no longer
/// kept (each one is saved where the user picks, or shared), this lists only
/// files exported before that; [plan] and [record] are no longer used for
/// new exports, and the database is kept so these files stay listed.
final savedExportsProvider = AsyncNotifierProvider<SavedExportsController, List<SavedExport>>(
  SavedExportsController.new,
);

/// Word files in the Saved folder (Word exports and OCR to Word files). Saved PDFs are in the Library, so the
/// lists show them from there.
final savedWordFilesProvider = Provider<List<SavedExport>>(
  (ref) => [
    for (final e in ref.watch(savedExportsProvider).value ?? const <SavedExport>[])
      if (e.format == ExportFormat.word || e.format == ExportFormat.ocrWord) e,
  ],
);

/// Whether any file exported before exports stopped being kept is still on
/// the phone: PDFs in the Library made from scans, or Word files. Only then
/// do Home and Library show the Saved and All chips, so these files can still
/// be opened, saved elsewhere or deleted. New exports are never kept.
final hasOldExportsProvider = Provider<bool>(
  (ref) =>
      ref.watch(visibleDocumentsProvider).any((d) => d.isScanExport) || ref.watch(savedWordFilesProvider).isNotEmpty,
);

class SavedExportsController extends AsyncNotifier<List<SavedExport>> {
  @override
  Future<List<SavedExport>> build() async => [
    for (final e in await ref.read(exportStateStoreProvider).all())
      if (File(e.path).existsSync()) e,
  ];

  /// Decides whether scan [docKey] needs exporting as [format]: when its
  /// last export has the same [fingerprint] and the file is still there, it
  /// is reused. Otherwise the new file replaces the last one: it gets the
  /// same name, or [fileName] when the scan was renamed. A file of another
  /// scan with that name is never replaced; the new one gets a number.
  Future<ExportPlan> plan({
    required String docKey,
    required ExportFormat format,
    required String fingerprint,
    required String fileName,
  }) async {
    final previous = await ref.read(exportStateStoreProvider).find(docKey, format);
    if (previous != null && previous.fingerprint == fingerprint && File(previous.path).existsSync()) {
      return ExportReuse(previous);
    }
    final files = ref.read(pageStoreProvider);
    final saved = (await files.savedDir).path;
    final stem = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    var candidate = fileName;
    bool taken(String name) {
      final full = p.join(saved, name);
      return !(previous != null && p.equals(full, previous.path)) && File(full).existsSync();
    }

    for (var n = 2; taken(candidate); n++) {
      candidate = '$stem ($n)$ext';
    }
    // Always "Saved/<name>", also where the platform separator is "\".
    return ExportNew(p.posix.join(PageStore.savedFolder, candidate), previous: previous);
  }

  /// Notes that [export] was written. The file of the export it replaces
  /// is deleted when it had another name.
  Future<void> record(SavedExport export, {SavedExport? previous}) async {
    if (previous != null && !p.equals(previous.path, export.path)) {
      final old = File(previous.path);
      if (old.existsSync()) await old.delete();
    }
    await ref.read(exportStateStoreProvider).put(export);
    ref.invalidateSelf();
    await future;
  }

  /// Deletes a saved file (a Word file; saved PDFs are deleted from the
  /// Library) and forgets it, so the next export makes it again.
  Future<void> delete(SavedExport export) async {
    final file = File(export.path);
    if (file.existsSync()) await file.delete();
    await ref.read(exportStateStoreProvider).removePath(export.path);
    ref.invalidateSelf();
    await future;
  }
}
