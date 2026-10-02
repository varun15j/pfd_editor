import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/scanner_service.dart';

/// [ScannerService] backed by cunning_document_scanner: ML Kit Document
/// Scanner on Android and VisionKit on iOS. Both give live edge detection,
/// auto capture, a corner-adjust crop step and multi-page capture.
class CunningScannerService implements ScannerService {
  @override
  Future<List<String>> scan({required ScanSource source, int maxPages = 100}) async {
    if (source == ScanSource.camera) {
      await _ensureCameraPermission();
    }
    try {
      final paths = await CunningDocumentScanner.getPictures(
        noOfPages: maxPages,
        scannerSource: source == ScanSource.camera ? ScannerSource.camera : ScannerSource.gallery,
        iosScannerOptions: IosScannerOptions(
          // JPEG keeps originals a few MB instead of tens of MB as PNG.
          imageFormat: IosImageFormat.jpg,
          jpgCompressionQuality: 0.92,
        ),
      );
      return paths ?? const [];
    } on CunningDocumentScannerException catch (e) {
      if (e.code == 'permission_denied') {
        throw const ScannerPermissionDenied();
      }
      throw ScannerFailure(e.message);
    }
  }

  Future<void> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isGranted || status.isLimited) return;
    if (status.isPermanentlyDenied || status.isRestricted) {
      throw const ScannerPermissionDenied(permanently: true);
    }
    status = await Permission.camera.request();
    if (status.isGranted || status.isLimited) return;
    throw ScannerPermissionDenied(permanently: status.isPermanentlyDenied || status.isRestricted);
  }

  @override
  Future<void> cleanUp() async {
    try {
      await CunningDocumentScanner.cleanCache();
    } on CunningDocumentScannerException {
      // Leftover cache files are harmless; the OS reclaims them on iOS.
    }
  }
}
