import 'dart:io';

import '../domain/document_text.dart';
import '../domain/ocr.dart';
import '../export/word/pdf_text_reader.dart';
import '../pdf_edit/pdf_saver.dart';

/// Reads the text of a saved PDF for search. A PDF with a text layer (a
/// text PDF, or a PDF made elsewhere) gives its text straight away; a scan
/// of pictures is read page by page with on-device OCR. Nothing leaves the
/// phone.
class DocumentTextReader {
  DocumentTextReader(this._layer, this._rasterizer, this._ocr);

  final PdfTextReader _layer;
  final PdfRasterizer _rasterizer;
  final OcrEngine _ocr;

  /// Pages with fewer letters than this in their text layer count as
  /// pictures, and are read with OCR.
  static const minLayerCharacters = 20;

  /// The document's text, pages separated by blank lines. Throws when the
  /// file cannot be opened; a page OCR cannot read is left out.
  Future<String> read(String pdfPath, {required int pageCount, String languageCode = 'en'}) async {
    final layer = await _layer.readPages(pdfPath, pageCount: pageCount);
    final texts = [for (final p in layer) p.lines.map((l) => l.text).join('\n')];
    final pictures = [
      for (var i = 0; i < pageCount; i++)
        if (i >= layer.length || layer[i].characterCount < minLayerCharacters) i + 1,
    ];
    while (texts.length < pageCount) {
      texts.add('');
    }
    if (pictures.isNotEmpty && (await _ocr.capability(languageCode)).readiness == OcrReadiness.ready) {
      final temp = await Directory.systemTemp.createTemp('lumascan_search');
      try {
        var k = 0;
        await for (final r in _rasterizer.renderPages(pdfPath, pictures, longEdge: 2000, jpegQuality: 85)) {
          final number = pictures[k++];
          final file = File('${temp.path}/p$number.jpg');
          await file.writeAsBytes(r.jpeg, flush: true);
          try {
            texts[number - 1] = await _ocr.recognizeFile(file.path, languageCode: languageCode);
          } on Object {
            // One unreadable page must not lose the rest.
          }
        }
      } finally {
        await temp.delete(recursive: true);
      }
    }
    final all = texts.where((t) => t.trim().isNotEmpty).join('\n\n');
    return all.length > DocumentText.maxLength ? all.substring(0, DocumentText.maxLength) : all;
  }
}
