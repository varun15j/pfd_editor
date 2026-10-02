/// Where new pages come from.
enum ScanSource { camera, gallery }

/// Capture adapter (ADR-010). The MVP wraps the OS document scanner; a custom
/// camera surface can replace it later without touching the screens.
abstract interface class ScannerService {
  /// Opens the scanner and returns image file paths, one per page, already
  /// edge-detected and perspective-cropped by the platform scanner.
  /// Returns an empty list when the user cancels.
  ///
  /// Throws [ScannerPermissionDenied] when camera access is refused and
  /// [ScannerFailure] for any other scanner error.
  Future<List<String>> scan({required ScanSource source, int maxPages});

  /// Removes temporary files the scanner wrote. Call after pages are copied.
  Future<void> cleanUp();
}

class ScannerPermissionDenied implements Exception {
  const ScannerPermissionDenied({this.permanently = false});

  /// True when the OS will no longer show the prompt and the user must
  /// enable the camera in Settings.
  final bool permanently;
}

class ScannerFailure implements Exception {
  const ScannerFailure(this.message);
  final String message;

  @override
  String toString() => 'ScannerFailure: $message';
}
