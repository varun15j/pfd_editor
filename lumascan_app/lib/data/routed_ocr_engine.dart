import '../domain/models.dart';
import '../domain/ocr.dart';

/// Sends each language to the engine that reads its script: [fallback]
/// (ML Kit) for Latin and Devanagari, [special] (Tesseract) for the languages
/// [handles] picks. Both run on the device.
class RoutedOcrEngine implements OcrEngine, OcrLayoutEngine {
  RoutedOcrEngine({required this.fallback, required this.special, required this.handles});

  final OcrEngine fallback;
  final OcrEngine special;
  final bool Function(String languageCode) handles;

  OcrEngine _for(String languageCode) => handles(languageCode) ? special : fallback;

  @override
  Future<OcrCapability> capability(String languageCode) => _for(languageCode).capability(languageCode);

  @override
  Future<void> prepare(String languageCode) => _for(languageCode).prepare(languageCode);

  @override
  Future<String> recognize(ScanPage page, {required String languageCode}) =>
      _for(languageCode).recognize(page, languageCode: languageCode);

  @override
  Future<String> recognizeFile(String path, {String languageCode = 'en'}) =>
      _for(languageCode).recognizeFile(path, languageCode: languageCode);

  @override
  Future<OcrLayout> recognizeLayout(ScanPage page, {required String languageCode}) async {
    final engine = _for(languageCode);
    if (engine is OcrLayoutEngine) {
      return (engine as OcrLayoutEngine).recognizeLayout(page, languageCode: languageCode);
    }
    final text = await engine.recognize(page, languageCode: languageCode);
    return OcrLayout([if (text.trim().isNotEmpty) OcrBlock(text: text, left: 0, top: 0, right: 1, bottom: 1)]);
  }
}
