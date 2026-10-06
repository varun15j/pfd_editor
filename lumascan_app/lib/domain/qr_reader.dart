import 'package:flutter/foundation.dart';

import '../features/batch_capture/camera_frame.dart';

/// What a QR code holds.
enum QrKind { link, text, wifi, email, phone, contact }

@immutable
class QrResult {
  const QrResult({required this.raw, required this.kind});

  /// The code's content exactly as read.
  final String raw;
  final QrKind kind;

  /// A web link that is safe to offer to open: http or https only.
  Uri? get webLink {
    if (kind != QrKind.link) return null;
    final uri = Uri.tryParse(raw.trim());
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty ? uri : null;
  }
}

/// Reads QR codes on the device (QR mode).
abstract interface class QrReader {
  /// The first QR code in a preview frame, or null.
  Future<QrResult?> readFrame(CameraFrame frame);

  /// The first QR code in a photo file, or null.
  Future<QrResult?> readFile(String path);

  Future<void> close();
}

/// Used where no reader is available (tests, desktop): finds nothing.
class NoQrReader implements QrReader {
  const NoQrReader();

  @override
  Future<QrResult?> readFrame(CameraFrame frame) async => null;

  @override
  Future<QrResult?> readFile(String path) async => null;

  @override
  Future<void> close() async {}
}
