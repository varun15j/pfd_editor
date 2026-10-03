import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import '../data/page_store.dart';
import '../domain/models.dart';
import 'annotations.dart';
import 'pdf_flattener.dart';

/// A source page rendered to JPEG.
class RasterPage {
  const RasterPage(this.jpeg, this.width, this.height, {this.widthPt, this.heightPt});
  final Uint8List jpeg;
  final int width;
  final int height;

  /// The page's size in PDF points, when the rasterizer knows it.
  final double? widthPt;
  final double? heightPt;
}

/// Renders pages of the source PDF to images. Behind an interface so the
/// save path can be tested without the native PDFium engine (ADR-009).
abstract class PdfRasterizer {
  /// Renders [pageNumbers] (1-based) in order, opening the file once.
  Stream<RasterPage> renderPages(
    String path,
    List<int> pageNumbers, {
    required int longEdge,
    required int jpegQuality,
    String? password,
  });
}

/// pdfrx (PDFium) rasterizer (ADR-012).
class PdfrxRasterizer implements PdfRasterizer {
  @override
  Stream<RasterPage> renderPages(
    String path,
    List<int> pageNumbers, {
    required int longEdge,
    required int jpegQuality,
    String? password,
  }) async* {
    await pdfrxFlutterInitialize();
    final doc = await PdfDocument.openFile(path, passwordProvider: createSimplePasswordProvider(password));
    try {
      for (final n in pageNumbers) {
        yield await _renderPage(doc.pages[n - 1], longEdge, jpegQuality);
      }
    } finally {
      await doc.dispose();
    }
  }

  Future<RasterPage> _renderPage(PdfPage page, int longEdge, int jpegQuality) async {
    final scale = longEdge / (page.width > page.height ? page.width : page.height);
    final w = (page.width * scale).round();
    final h = (page.height * scale).round();
    final image = await page.render(
      fullWidth: w.toDouble(),
      fullHeight: h.toDouble(),
      width: w,
      height: h,
      backgroundColor: 0xFFFFFFFF,
    );
    if (image == null) throw StateError('Could not render page ${page.pageNumber}');
    try {
      final pixels = Uint8List.fromList(image.pixels);
      final iw = image.width, ih = image.height;
      // JPEG encoding is CPU heavy, keep it off the UI isolate.
      final jpeg = await Isolate.run(
        () => img.encodeJpg(
          img.Image.fromBytes(
            width: iw,
            height: ih,
            bytes: pixels.buffer,
            numChannels: 4,
            order: img.ChannelOrder.bgra,
          ),
          quality: jpegQuality,
        ),
      );
      return RasterPage(jpeg, iw, ih, widthPt: page.width, heightPt: page.height);
    } finally {
      image.dispose();
    }
  }
}

/// Saves the edited document as a new PDF. The source file is never
/// written to.
///
/// No write engine for imported PDFs has been chosen yet (ADR-014), so each
/// page is rendered to an image and the annotations are drawn on top as
/// vector marks and real text. Text from the original pages is no longer
/// selectable in the output; the save sheet tells the user so (LLD §11:
/// rasterizing is never an undisclosed fallback).
class PdfEditSaver {
  PdfEditSaver(this._store, this._rasterizer);

  final PageStore _store;
  final PdfRasterizer _rasterizer;

  Future<File> save({
    required String sourcePath,
    required List<EditorPage> pages,
    required ExportQuality quality,
    required String fileName,
    String? password,
    void Function(int done, int total)? onProgress,
  }) async {
    if (pages.isEmpty) throw ArgumentError('No pages to save');
    // Snapshot so edits made while saving do not change this output.
    final snapshot = List<EditorPage>.unmodifiable(pages);
    final flat = <FlattenPage>[];
    final rasters = _rasterizer.renderPages(
      sourcePath,
      [for (final p in snapshot) p.sourcePage],
      longEdge: quality.maxDimension,
      jpegQuality: quality.jpegQuality,
      password: password,
    );
    await for (final raster in rasters) {
      final i = flat.length;
      final page = snapshot[i];
      flat.add(
        FlattenPage(jpeg: raster.jpeg, widthPt: page.widthPt, heightPt: page.heightPt, annotations: page.annotations),
      );
      onProgress?.call(i + 1, snapshot.length + 1);
    }
    final name = safeFileName(fileName);
    final bytes = await _buildInIsolate(flat, name.substring(0, name.length - 4));
    onProgress?.call(snapshot.length + 1, snapshot.length + 1);
    return _store.writeExportAtomically(name, bytes);
  }

  /// Strips path separators and characters that file systems reject, and
  /// makes sure the name ends in .pdf.
  static String safeFileName(String input) {
    var stem = input.trim();
    if (stem.toLowerCase().endsWith('.pdf')) stem = stem.substring(0, stem.length - 4);
    stem = stem.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    if (stem.isEmpty || stem.startsWith('.')) stem = 'Document$stem';
    return '$stem.pdf';
  }

  static String defaultFileName(String sourceName) {
    final stem = sourceName.toLowerCase().endsWith('.pdf')
        ? sourceName.substring(0, sourceName.length - 4)
        : sourceName;
    return '${stem}_edited.pdf';
  }
}

// Top level so the closure captures only its arguments.
Future<Uint8List> _buildInIsolate(List<FlattenPage> pages, String title) =>
    Isolate.run(() => buildEditedPdf(pages, title: title));
