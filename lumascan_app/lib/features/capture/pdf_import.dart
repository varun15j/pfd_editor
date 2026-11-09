import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/shell.dart';
import '../../domain/cloud_storage.dart';
import '../../domain/credits.dart';
import '../../domain/photo_import.dart';
import '../../pdf_edit/pdf_saver.dart';
import '../batch_edit/batch_review_screen.dart';
import '../credits/credits_screen.dart';
import '../open/open_progress.dart';
import '../open/pdf_file_check.dart';
import '../pages/scan_controller.dart';
import '../pdf_editor/open_pdf.dart';

/// Long edge, in pixels, of each page image made from an imported PDF:
/// about 300 dpi on an A4 page, the same detail as a camera scan.
const importedPageLongEdge = 3508;

/// JPEG quality of those page images.
const importedPageJpegQuality = 90;

/// Imports a PDF as a new document of editable pages and opens it in Batch
/// Review, where its pages can be cropped, filtered, reordered, OCR'd and
/// exported like a scan.
///
/// [fetch] gives the file to read (a download or the copy the picker made)
/// and runs under the progress dialog, so a slow download shows too. That
/// file is deleted afterwards. Each page becomes an image; the document on
/// screen before, if any, stays on Home. Returns true when the document
/// opened.
///
/// A [CloudSignInExpired] thrown by [fetch] is passed on, so the caller can
/// offer to connect again. Every other failure is shown here.
Future<bool> importPdfToBatchEdit(
  BuildContext context,
  WidgetRef ref, {
  required String name,
  required Future<File> Function(OpenProgress progress) fetch,
}) async {
  if (!await ensureCredits(context, ref, CreditAction.importing) || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final maker = ref.read(pdfPagesMakerProvider);
  File? fetched;
  Directory? pagesDir;
  Future<void> cleanUp() async {
    await _deleteQuietly(fetched);
    await _deleteDirQuietly(pagesDir);
  }

  final List<PickedPhoto>? pages;
  try {
    pages = await runOpenWithProgress<List<PickedPhoto>>(
      context,
      name: name,
      discard: (_) => cleanUp(),
      task: (progress) async {
        progress.report('Getting the file');
        final file = fetched = await fetch(progress);
        progress.throwIfCancelled();
        if (!context.mounted) throw const OpenCancelled();
        final dir = pagesDir = await ref.read(pdfImportDirProvider)();
        if (!context.mounted) throw const OpenCancelled();
        return maker.makePages(context, file.path, name, dir, progress);
      },
    );
  } on CloudSignInExpired {
    await cleanUp();
    rethrow;
  } on PdfPasswordException {
    await cleanUp();
    messenger.showSnackBar(const SnackBar(content: Text('The PDF stays locked without its password.')));
    return false;
  } on DocumentOpenException catch (e) {
    await cleanUp();
    if (context.mounted) await showOpenError(context, title: e.title, message: e.message);
    return false;
  } on FileSystemException catch (e) {
    await cleanUp();
    // ENOSPC is 28 on Android, Linux and iOS.
    final failure = DocumentOpenException(e.osError?.errorCode == 28 ? OpenFailure.noSpace : OpenFailure.unreadable);
    if (context.mounted) await showOpenError(context, title: failure.title, message: failure.message);
    return false;
  } catch (e) {
    await cleanUp();
    final fallback = DocumentOpenException(OpenFailure.corrupted, detail: '$e');
    if (context.mounted) await showOpenError(context, title: fallback.title, message: fallback.message);
    return false;
  }
  if (pages == null || !context.mounted) {
    // Cancelled. Files made so far are deleted here or by [discard].
    await cleanUp();
    return false;
  }

  final scans = ref.read(scanControllerProvider.notifier);
  try {
    await scans.startNewDocument();
    // The pages are already pages: no page search, no crop.
    final result = await scans.importPhotos(pages, autoCrop: false);
    if (result.added == 0) {
      messenger.showSnackBar(SnackBar(content: Text('Could not read the pages of $name.')));
      return false;
    }
    scans.rename(documentNameFor(name));
  } finally {
    // The draft keeps its own copies of the page images.
    await cleanUp();
  }
  if (!navigator.mounted) return false;
  openDraft(navigator.context);
  await navigator.push(MaterialPageRoute<void>(builder: (_) => const BatchReviewScreen()));
  return true;
}

/// "Lease" for "Lease.pdf"; other names are kept as they are.
String documentNameFor(String fileName) =>
    p.extension(fileName).toLowerCase() == '.pdf' ? p.basenameWithoutExtension(fileName) : fileName;

/// Turns a PDF into page images. Behind an interface so the import can be
/// tested without the native PDFium engine.
abstract interface class PdfPagesMaker {
  /// Writes one JPEG per page of the PDF at [path] into [dir], in page
  /// order, reporting to [progress] and stopping when it is cancelled.
  Future<List<PickedPhoto>> makePages(
    BuildContext context,
    String path,
    String name,
    Directory dir,
    OpenProgress progress,
  );
}

final pdfPagesMakerProvider = Provider<PdfPagesMaker>((_) => const PdfrxPagesMaker());

/// [PdfPagesMaker] on pdfrx: the file is checked and opened as the PDF
/// editor opens it (password, damaged files, page limit), then every page is
/// rendered one at a time, so only one page image is ever in memory.
class PdfrxPagesMaker implements PdfPagesMaker {
  const PdfrxPagesMaker();

  @override
  Future<List<PickedPhoto>> makePages(
    BuildContext context,
    String path,
    String name,
    Directory dir,
    OpenProgress progress,
  ) async {
    final (document, _) = await openCheckedPdf(context, path, progress, maxPages: maxEditablePdfPages);
    try {
      return await _renderPages(document, dir, name, progress);
    } finally {
      await document.dispose();
    }
  }
}

Future<List<PickedPhoto>> _renderPages(PdfDocument document, Directory dir, String name, OpenProgress progress) async {
  final total = document.pages.length;
  final stem = documentNameFor(name);
  final photos = <PickedPhoto>[];
  progress.report('Making editable pages', done: 0, total: total);
  for (final page in document.pages) {
    progress.throwIfCancelled();
    final raster = await PdfrxRasterizer.renderPage(page, importedPageLongEdge, importedPageJpegQuality);
    final path = p.join(dir.path, 'page_${page.pageNumber.toString().padLeft(4, '0')}.jpg');
    await File(path).writeAsBytes(raster.jpeg, flush: true);
    photos.add(PickedPhoto(path: path, name: '$stem page ${page.pageNumber}'));
    progress.report('Making editable pages', done: photos.length, total: total);
  }
  progress.throwIfCancelled();
  return photos;
}

/// Makes a new, empty folder for one import's page images.
final pdfImportDirProvider = Provider<Future<Directory> Function()>((_) => _newPagesDir);

Future<Directory> _newPagesDir() async {
  final root = Directory(p.join((await getTemporaryDirectory()).path, 'pdf_import'));
  // Left behind by a crash or a force stop.
  await _deleteDirQuietly(root);
  return Directory(p.join(root.path, '${DateTime.now().microsecondsSinceEpoch}')).create(recursive: true);
}

Future<void> _deleteQuietly(File? file) async {
  try {
    await file?.delete();
  } on FileSystemException {
    // Already gone.
  }
}

Future<void> _deleteDirQuietly(Directory? dir) async {
  try {
    await dir?.delete(recursive: true);
  } on FileSystemException {
    // Already gone.
  }
}
