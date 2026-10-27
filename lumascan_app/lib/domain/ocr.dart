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

/// A piece of text and where it sits on the page, as fractions (0 to 1) of
/// the page's width and height.
@immutable
class OcrBox {
  const OcrBox({required this.text, required this.left, required this.top, required this.right, required this.bottom});

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
}

/// One line of text on a page. [words] are its words with their own boxes,
/// when the engine reports them (Auto mask uses them to place a mask
/// exactly).
class OcrLine extends OcrBox {
  const OcrLine({
    required super.text,
    required super.left,
    required super.top,
    required super.right,
    required super.bottom,
    this.words = const [],
  });

  final List<OcrBox> words;
}

/// A block of text and where it sits on the page. [lines] are the lines in
/// it, when the engine reports them.
@immutable
class OcrBlock extends OcrBox {
  const OcrBlock({
    required super.text,
    required super.left,
    required super.top,
    required super.right,
    required super.bottom,
    this.lines = const [],
  });

  final List<OcrLine> lines;
}

/// The text on a page, block by block with positions.
@immutable
class OcrLayout {
  const OcrLayout(this.blocks);

  final List<OcrBlock> blocks;

  String get text => blocks.map((b) => b.text).join('\n');
}

/// An engine that also reports where the text is, so a text PDF can keep
/// the parts of a page it could not read as pictures.
abstract interface class OcrLayoutEngine {
  Future<OcrLayout> recognizeLayout(ScanPage page, {required String languageCode});
}
