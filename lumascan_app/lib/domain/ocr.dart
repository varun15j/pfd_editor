import 'package:flutter/foundation.dart';

import 'models.dart';

/// Whether text recognition can run for a language on this device.
enum OcrReadiness {
  /// Ready to recognise text.
  ready,

  /// Supported, but the language model must be downloaded first.
  needsDownload,

  /// Not available at all, for example in a build without an OCR engine.
  unavailable,
}

@immutable
class OcrCapability {
  const OcrCapability({required this.readiness, required this.language, this.reason});

  final OcrReadiness readiness;

  /// Human-readable language name, such as "English".
  final String language;

  /// Why OCR cannot run yet, shown to the user.
  final String? reason;
}

/// A text recognition engine (EP-07). Implementations run on the device;
/// pages never leave it.
abstract interface class OcrEngine {
  Future<OcrCapability> capability(String languageCode);

  /// Downloads what [capability] reported as missing.
  Future<void> prepare(String languageCode);

  /// Returns the text on [page] as rendered with its recipe. An empty string
  /// means the page has no readable text. Throws when recognition fails.
  Future<String> recognize(ScanPage page, {required String languageCode});

  /// Returns the text in a photo file as it is, for Text mode in the camera.
  Future<String> recognizeFile(String path);
}

/// The engine used until LumaScan ships one: it reports OCR as unavailable,
/// so the batch action explains that instead of failing.
class UnavailableOcrEngine implements OcrEngine {
  const UnavailableOcrEngine();

  @override
  Future<OcrCapability> capability(String languageCode) async => const OcrCapability(
    readiness: OcrReadiness.unavailable,
    language: 'English',
    reason: 'Text recognition is not available in this version of LumaScan yet. Your pages are not affected.',
  );

  @override
  Future<void> prepare(String languageCode) async {}

  @override
  Future<String> recognize(ScanPage page, {required String languageCode}) =>
      Future.error(UnsupportedError('No OCR engine'));

  @override
  Future<String> recognizeFile(String path) => Future.error(UnsupportedError('No OCR engine'));
}
