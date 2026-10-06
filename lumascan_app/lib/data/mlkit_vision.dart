import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/models.dart';
import '../domain/ocr.dart';
import '../domain/qr_reader.dart';
import '../features/batch_capture/camera_frame.dart';

/// Text recognition with ML Kit, on the device. The Latin-script model ships
/// with the app, so nothing is downloaded and pages never leave the phone.
class MlKitOcrEngine implements OcrEngine {
  MlKitOcrEngine({required this.imageFor});

  /// The page as rendered with its crop, rotation and filter, as an image
  /// file ML Kit can read.
  final Future<String> Function(ScanPage page) imageFor;

  TextRecognizer? _recognizer;

  /// Languages written in the Latin script, which the bundled model reads.
  static const _latin = {
    'en': 'English', 'de': 'German', 'fr': 'French', 'es': 'Spanish', 'it': 'Italian', //
    'pt': 'Portuguese', 'nl': 'Dutch', 'sv': 'Swedish', 'da': 'Danish', 'no': 'Norwegian',
    'fi': 'Finnish', 'pl': 'Polish', 'cs': 'Czech', 'tr': 'Turkish', 'id': 'Indonesian',
  };

  static bool get _supportedPlatform => Platform.isAndroid || Platform.isIOS;

  @override
  Future<OcrCapability> capability(String languageCode) async {
    final language = _latin[languageCode];
    if (!_supportedPlatform) {
      return OcrCapability(
        readiness: OcrReadiness.unavailable,
        language: language ?? languageCode,
        reason: 'Text recognition runs on Android and iOS only.',
      );
    }
    if (language == null) {
      return OcrCapability(
        readiness: OcrReadiness.unavailable,
        language: languageCode,
        reason: 'This language is not supported yet. Latin-script languages such as English are.',
      );
    }
    return OcrCapability(readiness: OcrReadiness.ready, language: language);
  }

  @override
  Future<void> prepare(String languageCode) async {}

  @override
  Future<String> recognize(ScanPage page, {required String languageCode}) async => recognizeFile(await imageFor(page));

  @override
  Future<String> recognizeFile(String path) async {
    final recognizer = _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    final result = await recognizer.processImage(InputImage.fromFilePath(path));
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
