import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/page_store.dart';
import '../domain/models.dart';
import '../imaging/page_renderer.dart';
import '../pdf_edit/annotations.dart';
import '../pdf_edit/pdf_flattener.dart';

class ExportOptions {
  const ExportOptions({this.pageSize = PdfPageSize.a4, this.quality = ExportQuality.medium, this.fileName});

  final PdfPageSize pageSize;
  final ExportQuality quality;
  final String? fileName;
}

class _PageImage {
  const _PageImage(this.jpeg, this.width, this.height, [this.annotations = const []]);
  final Uint8List jpeg;
  final int width;
  final int height;

  /// Marks drawn over the image, normalized to the image.
  final List<Annotation> annotations;
}

/// Builds a scan PDF with the `pdf` package (ADR-011). Each page is rendered
/// from its original and recipe on a background isolate, one at a time, so
/// peak memory stays at roughly one full-size page.
class PdfExporter {
  PdfExporter(this._store);

  final PageStore _store;

  Future<File> export(
    List<ScanPage> pages,
    ExportOptions options, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (pages.isEmpty) throw ArgumentError('No pages to export');
    // Snapshot so later edits do not change an export in progress.
    final snapshot = List<ScanPage>.unmodifiable(pages);
    final images = <_PageImage>[];
    for (var i = 0; i < snapshot.length; i++) {
      images.add(await _renderInIsolate(snapshot[i], options.quality));
      onProgress?.call(i + 1, snapshot.length + 1);
    }

    final bytes = await _buildPdfInIsolate(images, options.pageSize);
    onProgress?.call(snapshot.length + 1, snapshot.length + 1);

    final name = options.fileName ?? defaultFileName(DateTime.now());
    return _store.writeExportAtomically(name, bytes);
  }

  /// Name offered in the save sheet, e.g. "Scan 2026-10-03 14.30".
  static String defaultScanName(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Scan ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}.${two(t.minute)}';
  }

  /// Rough size of the finished PDF, for the quality options. Assumes A4-shaped
  /// pages: the long side is capped at the quality's `maxDimension` and a
  /// scanned document compresses to about [ExportQuality.bitsPerPixel].
  static int estimateBytes(int pageCount, ExportQuality quality) {
    final longSide = quality.maxDimension;
    final pixels = longSide * longSide * 0.707;
    return (pageCount * pixels * quality.bitsPerPixel / 8).round();
  }

  static String defaultFileName(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Scan_${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}.pdf';
  }
}

// Isolate entry points are top-level so their closures capture only the
// arguments, never the exporter or the caller's progress callback.
Future<_PageImage> _renderInIsolate(ScanPage page, ExportQuality q) => Isolate.run(() {
  final rendered = renderRecipe(File(page.originalPath).readAsBytesSync(), page.recipe, maxDimension: q.maxDimension);
  return _PageImage(rendered.encodeJpg(quality: q.jpegQuality), rendered.width, rendered.height, page.annotations);
});

Future<Uint8List> _buildPdfInIsolate(List<_PageImage> images, PdfPageSize size) =>
    Isolate.run(() => _buildPdf(images, size));

Future<Uint8List> _buildPdf(List<_PageImage> images, PdfPageSize size) {
  final doc = pw.Document(title: 'Scanned document', creator: 'LumaScan');
  for (final image in images) {
    final mem = pw.MemoryImage(image.jpeg);
    final landscape = image.width > image.height;
    final PdfPageFormat format;
    final double margin;
    switch (size) {
      case PdfPageSize.fitImage:
        // 150 dpi equivalent keeps the physical size sensible.
        format = PdfPageFormat(image.width * 72 / 150, image.height * 72 / 150);
        margin = 0;
      case PdfPageSize.a4:
        format = landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
        margin = 18;
      case PdfPageSize.letter:
        format = landscape ? PdfPageFormat.letter.landscape : PdfPageFormat.letter;
        margin = 18;
    }
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.all(margin),
        build: (_) {
          if (image.annotations.isEmpty) return pw.Center(child: pw.Image(mem, fit: pw.BoxFit.contain));
          // The marks are normalized to the image, so draw them in a box the
          // size of the image as it is fitted on the page.
          final scale = math.min(
            (format.width - 2 * margin) / image.width,
            (format.height - 2 * margin) / image.height,
          );
          final w = image.width * scale, h = image.height * scale;
          return pw.Center(
            child: pw.SizedBox(
              width: w,
              height: h,
              child: pw.Stack(
                fit: pw.StackFit.expand,
                children: [
                  pw.Image(mem, fit: pw.BoxFit.fill),
                  ...markWidgets(image.annotations, w, h),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  return doc.save();
}

/// Test hook: builds a PDF from raw JPEG bytes.
Future<Uint8List> buildPdfFromJpegs(
  List<(Uint8List, int, int)> pages,
  PdfPageSize size, {
  List<List<Annotation>> annotations = const [],
}) => _buildPdf([
  for (var i = 0; i < pages.length; i++)
    _PageImage(pages[i].$1, pages[i].$2, pages[i].$3, i < annotations.length ? annotations[i] : const []),
], size);
