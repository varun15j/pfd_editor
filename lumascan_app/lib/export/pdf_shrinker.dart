import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
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

  /// "Lease (under 200 KB).pdf" for "Lease" and [TargetSize.kb200].
  static String targetCopyName(String name, TargetSize target) {
    final stem = name.toLowerCase().endsWith('.pdf') ? name.substring(0, name.length - 4) : name;
    return PdfEditSaver.safeFileName('$stem (under ${target.label})');
  }

  /// The most attempts [makeUnder] makes; each one renders every page.
  static const maxAttempts = 5;

  /// Makes a copy no larger than [target], keeping as much resolution and
  /// quality as fits: it tries steps of [CompressionStep.ladder], guided by
  /// the size of each attempt, and keeps the best one that fits. When even the
  /// smallest step is too large, the smallest copy is returned with
  /// [TargetSizeCopy.fits] false, so the caller can say so.
  Future<TargetSizeCopy> makeUnder({
    required String sourcePath,
    required int pageCount,
    required String name,
    required TargetSize target,
    void Function(int done, int total)? onProgress,
  }) async {
    if (pageCount <= 0) throw ArgumentError('No pages to copy');
    final fileName = targetCopyName(name, target);
    final title = fileName.substring(0, fileName.length - 4);
    final total = maxAttempts * pageCount;
    var attempt = 0;
    final built = <int, Uint8List>{};
    final found = await findStep(
      target: target,
      pageCount: pageCount,
      measure: (index) async {
        final step = CompressionStep.ladder[index];
        final pages = <FlattenPage>[];
        final rasters = _rasterizer.renderPages(
          sourcePath,
          [for (var i = 1; i <= pageCount; i++) i],
          longEdge: step.longEdge,
          jpegQuality: step.jpegQuality,
        );
        await for (final r in rasters) {
          pages.add(
            FlattenPage(
              jpeg: r.jpeg,
              widthPt: r.widthPt ?? r.width * 72 / 150,
              heightPt: r.heightPt ?? r.height * 72 / 150,
              annotations: const [],
            ),
          );
          onProgress?.call(attempt * pageCount + pages.length, total);
        }
        final bytes = await _buildInIsolate(pages, title);
        attempt++;
        // Only the best fitting attempt and the smallest one can be the answer.
        built[index] = bytes;
        return bytes.length;
      },
    );
    onProgress?.call(total, total);
    final file = await _store.writeFileAtomically('share/$fileName', built[found.index]!);
    return TargetSizeCopy(file, found.bytes, fits: found.fits, step: CompressionStep.ladder[found.index]);
  }

  /// Picks the first (best) step of [CompressionStep.ladder] whose copy is no
  /// larger than [target], calling [measure] for the size of a step's copy at
  /// most [maxAttempts] times. It starts from an estimate and then predicts
  /// each next step from the sizes measured so far. Sizes fall down the
  /// ladder, so a step below one that fits also fits, and a step above one
  /// that is too large is too large.
  static Future<({int index, int bytes, bool fits})> findStep({
    required TargetSize target,
    required int pageCount,
    required Future<int> Function(int index) measure,
  }) async {
    final ladder = CompressionStep.ladder;
    final limit = target.bytes;
    final sizes = <int, int>{};
    int? bestFit; // smallest index known to fit
    var tooBig = -1; // largest index known to be too large

    var index = ladder.indexWhere((s) => s.estimateBytes(pageCount) <= limit);
    if (index < 0) index = ladder.length - 1;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final size = sizes[index] = await measure(index);
      final step = ladder[index];
      double predicted(int i) => size * ladder[i].weight / step.weight;
      if (size <= limit) {
        bestFit = index;
        // The best untried step above that the measured size says would
        // still fit, keeping a little headroom.
        final up = [for (var i = tooBig + 1; i < index; i++) i].where((i) => predicted(i) <= limit * 0.97);
        if (up.isEmpty) break;
        index = up.first;
      } else {
        tooBig = index;
        if (index == ladder.length - 1) break;
        // Jump down to the first step predicted to fit, with more headroom.
        var down = index + 1;
        while (down < ladder.length - 1 && predicted(down) > limit * 0.95) {
          down++;
        }
        if (bestFit != null && down >= bestFit) break;
        index = down;
      }
    }

    if (bestFit != null) return (index: bestFit, bytes: sizes[bestFit]!, fits: true);
    final smallest = sizes.keys.reduce((a, b) => a > b ? a : b);
    return (index: smallest, bytes: sizes[smallest]!, fits: false);
  }

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

/// A size limit that upload forms commonly set.
enum TargetSize {
  kb200('200 KB', 200),
  kb500('500 KB', 500),
  mb1('1 MB', 1000),
  mb2('2 MB', 2000);

  const TargetSize(this.label, this.kilobytes);

  final String label;
  final int kilobytes;

  /// The limit in bytes, counting a kilobyte as 1000 bytes so the copy fits
  /// forms that count either 1000 or 1024.
  int get bytes => kilobytes * 1000;
}

/// One resolution and JPEG quality the target-size search can use.
class CompressionStep {
  const CompressionStep(this.longEdge, this.jpegQuality);

  final int longEdge;
  final int jpegQuality;

  /// Best first. Below about 480 px a page of text stops being readable.
  static const ladder = [
    CompressionStep(2000, 85),
    CompressionStep(1700, 80),
    CompressionStep(1500, 75),
    CompressionStep(1300, 70),
    CompressionStep(1200, 62),
    CompressionStep(1050, 56),
    CompressionStep(900, 50),
    CompressionStep(780, 45),
    CompressionStep(660, 40),
    CompressionStep(560, 35),
    CompressionStep(480, 30),
  ];

  /// Rough bits per pixel of a scanned page at this quality, matching the
  /// figures in [ExportQuality].
  double get bitsPerPixel => math.max(0.1, (jpegQuality - 36) / 60);

  /// Relative size of a page at this step; only ratios between steps matter.
  double get weight => longEdge * longEdge * 0.707 * bitsPerPixel;

  int estimateBytes(int pageCount) => (pageCount * weight / 8).round();
}

/// A copy made to fit a [TargetSize].
class TargetSizeCopy {
  const TargetSizeCopy(this.file, this.bytes, {required this.fits, required this.step});

  final File file;
  final int bytes;

  /// False when even the smallest step is larger than the target.
  final bool fits;
  final CompressionStep step;
}

// Top level so the closure captures only its arguments.
Future<Uint8List> _buildInIsolate(List<FlattenPage> pages, String title) =>
    Isolate.run(() => buildEditedPdf(pages, title: title));
