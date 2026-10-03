import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../data/page_store.dart';
import '../domain/models.dart';
import '../pdf_edit/pdf_flattener.dart';
import '../pdf_edit/pdf_saver.dart';
import 'pdf_exporter.dart';

/// Makes a smaller copy of a PDF for sending: every page is rendered to a
/// low-resolution image and written to a new file. The source is never
/// changed. Text in the copy is no longer selectable (no write engine for
/// imported PDFs yet, ADR-014), so the send sheet says so.
class PdfShrinker {
  PdfShrinker(this._store, this._rasterizer);

  final PageStore _store;
  final PdfRasterizer _rasterizer;

  static const quality = ExportQuality.small;

  /// "Lease (small).pdf" for "Lease" or "Lease.pdf".
  static String copyName(String name) {
    final stem = name.toLowerCase().endsWith('.pdf') ? name.substring(0, name.length - 4) : name;
    return PdfEditSaver.safeFileName('$stem (small)');
  }

  /// Rough size of the copy, for showing before it is made.
  static int estimateBytes(int pageCount) => PdfExporter.estimateBytes(pageCount, quality);

  Future<File> makeSmaller({
    required String sourcePath,
    required int pageCount,
    required String name,
    void Function(int done, int total)? onProgress,
  }) async {
    if (pageCount <= 0) throw ArgumentError('No pages to copy');
    final pages = <FlattenPage>[];
    final rasters = _rasterizer.renderPages(
      sourcePath,
      [for (var i = 1; i <= pageCount; i++) i],
      longEdge: quality.maxDimension,
      jpegQuality: quality.jpegQuality,
    );
    await for (final r in rasters) {
      // Keep the page's real size; fall back to 150 dpi when it is unknown.
      pages.add(
        FlattenPage(
          jpeg: r.jpeg,
          widthPt: r.widthPt ?? r.width * 72 / 150,
          heightPt: r.heightPt ?? r.height * 72 / 150,
          annotations: const [],
        ),
      );
      onProgress?.call(pages.length, pageCount + 1);
    }
    final fileName = copyName(name);
    final bytes = await _buildInIsolate(pages, fileName.substring(0, fileName.length - 4));
    onProgress?.call(pageCount + 1, pageCount + 1);
    return _store.writeFileAtomically('share/$fileName', bytes);
  }
}

// Top level so the closure captures only its arguments.
Future<Uint8List> _buildInIsolate(List<FlattenPage> pages, String title) =>
    Isolate.run(() => buildEditedPdf(pages, title: title));
