import 'dart:io';
import 'dart:isolate';

import '../data/page_store.dart';
import '../domain/models.dart';
import '../pdf_edit/pdf_flattener.dart';
import '../pdf_edit/pdf_saver.dart';

/// One new PDF to make from a source PDF: its pages (1-based, in order) and
/// its file name without .pdf.
class SplitPart {
  const SplitPart({required this.pages, required this.name});

  final List<int> pages;
  final String name;
}

/// Why a typed list of page ranges cannot be used.
class PageRangeException implements Exception {
  const PageRangeException(this.message);

  /// Shown to the user under the field.
  final String message;

  @override
  String toString() => message;
}

/// Reads ranges such as "1-3, 5, 8-10" into one list of pages per range, for
/// a PDF of [pageCount] pages. "7-" runs to the last page. Spaces are
/// ignored and en dashes count as hyphens. Throws [PageRangeException] for
/// an empty list, a page outside the PDF or a range that runs backwards.
List<List<int>> parsePageRanges(String text, int pageCount) {
  final groups = <List<int>>[];
  for (final raw in text.replaceAll('–', '-').split(',')) {
    final part = raw.replaceAll(' ', '');
    if (part.isEmpty) continue;
    final match = RegExp(r'^(\d+)(?:-(\d*))?$').firstMatch(part);
    if (match == null) throw PageRangeException('"${raw.trim()}" is not a page or a range like 2-5.');
    final from = int.parse(match[1]!);
    final to = match[2] == null ? from : (match[2]!.isEmpty ? pageCount : int.parse(match[2]!));
    for (final n in [from, to]) {
      if (n < 1 || n > pageCount) {
        throw PageRangeException('Page $n is not in this PDF. It has $pageCount page${pageCount == 1 ? '' : 's'}.');
      }
    }
    if (to < from) throw PageRangeException('$from-$to runs backwards. Write it as $to-$from.');
    groups.add([for (var n = from; n <= to; n++) n]);
  }
  if (groups.isEmpty) throw const PageRangeException('Type the pages, such as 1-3, 4-6.');
  return groups;
}

/// Pages 1 to [pageCount] in runs of [size]; the last run may be shorter.
List<List<int>> pagesInChunks(int pageCount, int size) {
  if (size < 1) throw ArgumentError.value(size, 'size');
  return [
    for (var start = 1; start <= pageCount; start += size)
      [for (var n = start; n < start + size && n <= pageCount; n++) n],
  ];
}

/// "1-3, 5, 8-10" for pages [1, 2, 3, 5, 8, 9, 10]: sorted runs, as a label
/// or a file name.
String describePages(Iterable<int> pages) {
  final sorted = pages.toSet().toList()..sort();
  final runs = <String>[];
  for (var i = 0; i < sorted.length; i++) {
    final start = sorted[i];
    while (i + 1 < sorted.length && sorted[i + 1] == sorted[i] + 1) {
      i++;
    }
    runs.add(start == sorted[i] ? '$start' : '$start-${sorted[i]}');
  }
  return runs.join(', ');
}

/// Makes new PDFs from some of the pages of a PDF: several files when
/// splitting, one when extracting. The source is only read.
///
/// Like merging, each page is rendered to an image and rebuilt at its own
/// size (no write engine for existing PDFs yet, ADR-014), so text in the new
/// files cannot be selected. Anything drawn or masked on a saved page is part
/// of that image, so it stays covered in every part.
class PdfSplitter {
  PdfSplitter(this._store, this._rasterizer);

  final PageStore _store;
  final PdfRasterizer _rasterizer;

  /// Width given to a page whose size is not known, in points (A4).
  static const _fallbackWidth = 595.0;

  /// Writes one PDF per part to the exports folder, in order. A taken name
  /// gets " (2)" and so on, so no existing file is replaced. If a part fails,
  /// the parts already written are deleted and the error is rethrown.
  Future<List<File>> split(
    String sourcePath,
    List<SplitPart> parts, {
    ExportQuality quality = ExportQuality.high,
    void Function(int done, int total)? onProgress,
  }) async {
    if (parts.isEmpty || parts.any((p) => p.pages.isEmpty)) throw ArgumentError('Nothing to split');
    final total = parts.fold<int>(0, (sum, p) => sum + p.pages.length) + parts.length;
    var done = 0;
    final written = <File>[];
    try {
      for (final part in parts) {
        final pages = <FlattenPage>[];
        final rasters = _rasterizer.renderPages(
          sourcePath,
          part.pages,
          longEdge: quality.maxDimension,
          jpegQuality: quality.jpegQuality,
        );
        await for (final raster in rasters) {
          final w = raster.widthPt ?? _fallbackWidth;
          final h = raster.heightPt ?? _fallbackWidth * raster.height / raster.width;
          pages.add(FlattenPage(jpeg: raster.jpeg, widthPt: w, heightPt: h, annotations: const []));
          onProgress?.call(++done, total);
        }
        if (pages.length != part.pages.length) throw StateError('Some pages could not be read');
        final name = await _store.freeExportName(PdfEditSaver.safeFileName(part.name));
        final title = name.substring(0, name.length - 4);
        final bytes = await Isolate.run(() => buildEditedPdf(pages, title: title));
        written.add(await _store.writeExportAtomically(name, bytes));
        onProgress?.call(++done, total);
      }
    } on Object {
      for (final f in written) {
        if (f.existsSync()) f.deleteSync();
      }
      rethrow;
    }
    return written;
  }
}
