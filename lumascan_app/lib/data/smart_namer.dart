import '../domain/models.dart';
import '../domain/ocr.dart';
import '../domain/smart_name.dart';

/// Reads the first page of a scan on the device and suggests a name from
/// its text (Auto file naming, Pro). Never throws: a page that cannot be
/// read, or reads as nothing useful, gives null and the name is left alone.
class SmartNamer {
  const SmartNamer(this._ocr, {this.timeout = const Duration(seconds: 8)});

  final OcrEngine _ocr;

  /// A slow phone must not leave the save sheet waiting on a name.
  final Duration timeout;

  Future<String?> suggest(List<ScanPage> pages, {String languageCode = 'en'}) async {
    if (pages.isEmpty) return null;
    // Text read earlier (Read text in batch edit) saves reading it again.
    final known = pages.first.text;
    if (known != null && known.trim().isNotEmpty) return suggestDocumentName(known);
    try {
      final ready = await _ocr.capability(languageCode);
      if (ready.readiness != OcrReadiness.ready) return null;
      final text = await _ocr.recognize(pages.first, languageCode: languageCode).timeout(timeout);
      return suggestDocumentName(text);
    } on Object {
      return null;
    }
  }
}
