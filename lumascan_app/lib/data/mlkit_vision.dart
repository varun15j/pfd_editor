import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Size;

import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/models.dart';
import '../domain/ocr.dart';
import '../domain/ocr_languages.dart';
import '../domain/qr_reader.dart';
import '../features/batch_capture/camera_frame.dart';

/// Text recognition with ML Kit, on the device. The Latin and Devanagari
/// models ship with the app, so nothing is downloaded and pages never leave
/// the phone. Devanagari's model also reads Latin text, so English words in
/// a Hindi or Marathi page are kept.
class MlKitOcrEngine implements OcrEngine, OcrLayoutEngine, OcrFileLayoutEngine {
  MlKitOcrEngine({required this.imageFor});

  /// The page as rendered with its crop, rotation and filter, as an image
  /// file ML Kit can read.
  final Future<String> Function(ScanPage page) imageFor;

  final _recognizers = <TextRecognitionScript, TextRecognizer>{};

  static bool get _supportedPlatform => Platform.isAndroid || Platform.isIOS;

  /// The bundled model that reads [script], or null when none does.
  static TextRecognitionScript? modelFor(OcrScript script) => switch (script) {
    OcrScript.latin => TextRecognitionScript.latin,
    OcrScript.devanagari => TextRecognitionScript.devanagiri,
    _ => null,
  };

  /// Why [languageCode] cannot be read, or null when it can.
  static String? unsupportedReason(String languageCode) {
    final language = OcrLanguage.byCode(languageCode);
    if (language == null) return 'This language is not supported yet. English, Hindi and Marathi are.';
    if (modelFor(language.script) != null) return null;
    return 'Reading ${language.name} (${language.script.label} script) is not available on this device yet. '
        'English, Hindi, Marathi and other languages in the Latin or Devanagari script are.';
  }

  @override
  Future<OcrCapability> capability(String languageCode) async {
    final name = OcrLanguage.byCode(languageCode)?.name ?? languageCode;
    if (!_supportedPlatform) {
      return OcrCapability(
        readiness: OcrReadiness.unavailable,
        language: name,
        reason: 'Text recognition runs on Android and iOS only.',
      );
    }
    final reason = unsupportedReason(languageCode);
    if (reason != null) return OcrCapability(readiness: OcrReadiness.unavailable, language: name, reason: reason);
    return OcrCapability(readiness: OcrReadiness.ready, language: name);
  }

  TextRecognizer _recognizerFor(String languageCode) {
    final model = modelFor(OcrLanguage.of(languageCode).script) ?? TextRecognitionScript.latin;
    return _recognizers[model] ??= TextRecognizer(script: model);
  }

  @override
  Future<void> prepare(String languageCode) async {}

  @override
  Future<String> recognize(ScanPage page, {required String languageCode}) async =>
      recognizeFile(await imageFor(page), languageCode: languageCode);

  @override
  Future<OcrLayout> recognizeLayout(ScanPage page, {required String languageCode}) async =>
      recognizeLayoutFile(await imageFor(page), languageCode: languageCode);

  @override
  Future<OcrLayout> recognizeLayoutFile(String path, {String languageCode = 'en'}) async {
    final result = await _recognizerFor(languageCode).processImage(InputImage.fromFilePath(path));
    final buffer = await ui.ImmutableBuffer.fromUint8List(await File(path).readAsBytes());
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width.toDouble(), h = descriptor.height.toDouble();
    descriptor.dispose();
    buffer.dispose();
    double unit(double v, double of) => (v / of).clamp(0.0, 1.0);
    return OcrLayout([
      for (final b in result.blocks)
        if (b.text.trim().isNotEmpty)
          OcrBlock(
            text: b.text,
            left: unit(b.boundingBox.left, w),
            top: unit(b.boundingBox.top, h),
            right: unit(b.boundingBox.right, w),
            bottom: unit(b.boundingBox.bottom, h),
            lines: [
              for (final l in b.lines)
                if (l.text.trim().isNotEmpty)
                  OcrLine(
                    text: l.text,
                    left: unit(l.boundingBox.left, w),
                    top: unit(l.boundingBox.top, h),
                    right: unit(l.boundingBox.right, w),
                    bottom: unit(l.boundingBox.bottom, h),
                    words: [
                      for (final e in l.elements)
                        if (e.text.trim().isNotEmpty)
                          OcrBox(
                            text: e.text,
                            left: unit(e.boundingBox.left, w),
                            top: unit(e.boundingBox.top, h),
                            right: unit(e.boundingBox.right, w),
                            bottom: unit(e.boundingBox.bottom, h),
                          ),
                    ],
                  ),
            ],
          ),
    ]);
  }

  @override
  Future<String> recognizeFile(String path, {String languageCode = 'en'}) async {
    final result = await _recognizerFor(languageCode).processImage(InputImage.fromFilePath(path));
    return result.text;
  }
}

/// QR codes with ML Kit's barcode scanner, on the device.
class MlKitQrReader implements QrReader {
  final _scanner = BarcodeScanner(formats: const [BarcodeFormat.qrCode]);

  @override
  Future<QrResult?> readFrame(CameraFrame frame) => _read(_frameImage(frame));

  @override
  Future<QrResult?> readFile(String path) => _read(InputImage.fromFilePath(path));

  Future<QrResult?> _read(InputImage image) async {
    final codes = await _scanner.processImage(image);
    for (final code in codes) {
      final raw = code.rawValue;
      if (raw != null && raw.isNotEmpty) return QrResult(raw: raw, kind: _kind(code.type));
    }
    return null;
  }

  static QrKind _kind(BarcodeType type) => switch (type) {
    BarcodeType.url => QrKind.link,
    BarcodeType.wifi => QrKind.wifi,
    BarcodeType.email => QrKind.email,
    BarcodeType.phone => QrKind.phone,
    BarcodeType.contactInfo => QrKind.contact,
    _ => QrKind.text,
  };

  /// iOS frames go in as they came (BGRA). Android frames go in as NV21 made
  /// from the brightness alone, with neutral colour: QR codes need no colour.
  static InputImage _frameImage(CameraFrame frame) {
    final size = Size(frame.width.toDouble(), frame.height.toDouble());
    final rotation = InputImageRotationValue.fromRawValue(frame.rotation) ?? InputImageRotation.rotation0deg;
    if (frame.pixels == FramePixels.bgra) {
      return InputImage.fromBytes(
        bytes: frame.bytes,
        metadata: InputImageMetadata(
          size: size,
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: frame.bytesPerRow,
        ),
      );
    }
    final luma = frame.luma();
    final nv21 = Uint8List(luma.length + luma.length ~/ 2)
      ..setRange(0, luma.length, luma)
      ..fillRange(luma.length, luma.length + luma.length ~/ 2, 128);
    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: size,
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: frame.width,
      ),
    );
  }

  @override
  Future<void> close() => _scanner.close();
}
