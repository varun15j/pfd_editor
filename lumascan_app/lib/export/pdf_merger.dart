import 'dart:isolate';
import 'dart:io';

import '../data/page_store.dart';
import '../domain/models.dart';
import '../pdf_edit/pdf_flattener.dart';
import '../pdf_edit/pdf_saver.dart';

/// One PDF to merge and how many pages it has.
class MergeInput {
  const MergeInput({required this.path, required this.pageCount});

  final String path;
  final int pageCount;
}

/// Joins PDFs, in the order given, into a new PDF. The sources are only read.
///
/// No write engine for existing PDFs has been chosen yet (ADR-014), so each
/// page is rendered to an image and rebuilt at its own size, as the PDF
/// editor does when it saves. Text in the merged file cannot be selected, and
/// the merge screen says so.
class PdfMerger {
  PdfMerger(this._store, this._rasterizer);

  final PageStore _store;
  final PdfRasterizer _rasterizer;

  /// Width given to a page whose size is not known, in points (A4).
  static const _fallbackWidth = 595.0;

  /// Writes the merged PDF to the exports folder under [fileName], or under
  /// "name (2).pdf" and so on when that name is taken, so no existing file is
  /// ever replaced.
  Future<File> merge(
    List<MergeInput> inputs, {
    required String fileName,
    ExportQuality quality = ExportQuality.high,
    void Function(int done, int total)? onProgress,
  }) async {
    if (inputs.isEmpty) throw ArgumentError('Nothing to merge');
    final total = inputs.fold<int>(0, (sum, i) => sum + i.pageCount) + 1;
    final pages = <FlattenPage>[];
    for (final input in inputs) {
      final rasters = _rasterizer.renderPages(
        input.path,
        [for (var n = 1; n <= input.pageCount; n++) n],
        longEdge: quality.maxDimension,
        jpegQuality: quality.jpegQuality,
      );
      await for (final raster in rasters) {
        final w = raster.widthPt ?? _fallbackWidth;
        final h = raster.heightPt ?? _fallbackWidth * raster.height / raster.width;
        pages.add(FlattenPage(jpeg: raster.jpeg, widthPt: w, heightPt: h, annotations: const []));
        onProgress?.call(pages.length, total);
      }
    }
    if (pages.isEmpty) throw StateError('No pages could be read');
    final name = await _store.freeExportName(PdfEditSaver.safeFileName(fileName));
    final title = name.substring(0, name.length - 4);
    final bytes = await Isolate.run(() => buildEditedPdf(pages, title: title));
    onProgress?.call(total, total);
    return _store.writeExportAtomically(name, bytes);
  }
}
