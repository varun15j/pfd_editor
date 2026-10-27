import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/page_store.dart';
import '../domain/models.dart';
import '../imaging/page_renderer.dart';
import '../pdf_edit/annotations.dart';

/// Saves the pages of a scan as JPG files, one per page, with their crop,
/// rotation and filter, in a folder of their own under the exports folder:
/// `exports/2026-10-11 Scan/2026-10-11 Scan 01.jpg`. Pen, text and signature
/// marks are drawn only in PDFs, but masks are burned into the JPGs too, so a
/// hidden ID number never leaves the app. The page images of the scan are not
/// changed.
class JpgExporter {
  JpgExporter(this._files, {this.maxDimension = 4096, this.quality = 90});

  final PageStore _files;
  final int maxDimension;
  final int quality;

  Future<List<File>> export(List<ScanPage> pages, String name, {void Function(int done, int total)? onProgress}) async {
    final stem = safeStem(name);
    final exports = (await _files.exportsDir).path;
    // A folder that is already there gets a number, so earlier JPGs are kept.
    var folder = stem;
    for (var n = 2; Directory(p.join(exports, folder)).existsSync(); n++) {
      folder = '$stem ($n)';
    }
    final dir = await Directory(p.join(exports, folder)).create(recursive: true);
    final width = pages.length.toString().length < 2 ? 2 : pages.length.toString().length;
    final files = <File>[];
    try {
      for (var i = 0; i < pages.length; i++) {
        final out = p.join(dir.path, '$stem ${(i + 1).toString().padLeft(width, '0')}.jpg');
        final rendered = await renderToFile(
          originalPath: pages[i].originalPath,
          recipe: pages[i].recipe,
          outPath: out,
          maxDimension: maxDimension,
          quality: quality,
          masks: masksIn(pages[i].annotations).toList(),
        );
        files.add(File(rendered.path));
        onProgress?.call(i + 1, pages.length);
      }
    } catch (_) {
      // No half-finished set is left behind.
      await dir.delete(recursive: true);
      rethrow;
    }
    return files;
  }

  /// [name] without characters that file systems reject.
  static String safeStem(String name) {
    var stem = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    if (stem.toLowerCase().endsWith('.jpg')) stem = stem.substring(0, stem.length - 4);
    if (stem.isEmpty || stem.startsWith('.')) stem = 'Scan$stem';
    return stem;
  }
}
