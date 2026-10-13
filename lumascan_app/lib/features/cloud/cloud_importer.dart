import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../domain/cloud_storage.dart';
import '../../domain/library.dart';
import '../../pdf_edit/pdf_saver.dart';
import '../library/library_controller.dart';
import '../merge/pdf_inspector.dart';

final cloudImporterProvider = Provider<CloudImporter>(CloudImporter.new);

/// Saves a file brought in from cloud storage to the Library, the same way
/// files from the phone are: a PDF is copied into the exports folder and a
/// Word file goes through the Word import (WordService.wordToPdf). Either way
/// the result is a Library document, placed in the chosen folder.
class CloudImporter {
  CloudImporter(this._ref);

  final Ref _ref;

  /// Imports the downloaded [file] named [name] in the cloud. [kind] is what
  /// the file is (a Google Doc arrives as a PDF). [folderId] null means the
  /// Library's top level. Throws [FormatException] with a message for the
  /// user when the file cannot be read.
  Future<SavedDocument> import(
    File file, {
    required String name,
    required CloudEntryKind kind,
    String? folderId,
  }) async {
    final library = _ref.read(libraryProvider.notifier);
    final stem = _stem(name);
    final SavedDocument saved;
    switch (kind) {
      case CloudEntryKind.word:
        final made = await _ref.read(wordServiceProvider).wordToPdf(file.path, name: stem);
        saved = await library.addPdf(made.file, pageCount: made.pageCount);
      case CloudEntryKind.pdf || CloudEntryKind.googleDoc:
        final info = await _ref.read(pdfInspectorProvider).inspect(file.path);
        final pages = info.pageCount;
        if (pages == null) {
          throw FormatException(
            info.problem == PdfProblem.locked
                ? '$name is locked with a password, so it cannot be added to the Library.'
                : '$name could not be read as a PDF.',
          );
        }
        saved = await library.addPdf(await _copyToExports(file, stem), pageCount: pages);
      case CloudEntryKind.folder || CloudEntryKind.other:
        throw FormatException('Only PDF and Word files can be imported, not $name.');
    }
    if (folderId == null) return saved;
    await library.moveToFolder(saved.id, folderId);
    return saved.copyWith(folderId: () => folderId);
  }

  /// Copies through a temp file and a rename, so the Library never lists a
  /// half-written PDF.
  Future<File> _copyToExports(File file, String stem) async {
    final store = _ref.read(pageStoreProvider);
    final fileName = await store.freeExportName(PdfEditSaver.safeFileName(stem));
    final target = p.join((await store.exportsDir).path, fileName);
    final part = await file.copy('$target.part');
    return part.rename(target);
  }

  /// "Lease" for "Lease.pdf" or "Lease.docx"; a Google Doc's name has no
  /// extension and is kept whole.
  static String _stem(String name) {
    final ext = p.extension(name).toLowerCase();
    return ext == '.pdf' || ext == '.docx' ? p.basenameWithoutExtension(name) : name;
  }
}
