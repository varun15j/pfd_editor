import 'package:flutter/widgets.dart';

/// The live camera behind Batch capture. Unlike the native document scanner
/// it stays open between shots, so pages can be taken one after another
/// without a review screen after each. Tests swap in a fake.
///
/// [open] throws ScannerPermissionDenied when camera access is refused and
/// ScannerFailure for any other camera error.
abstract interface class BatchCamera {
  Future<void> open();

  /// True once [open] finished and until [close] or [pause].
  bool get isReady;

  /// Whether the camera has a torch that [setTorch] can switch.
  bool get hasTorch;

  /// The live preview. Only shown while [isReady].
  Widget buildPreview();

  /// Takes one photo and returns the path of the file the camera wrote.
  /// The file is the caller's to move.
  Future<String> takePicture();

  Future<void> setTorch(bool on);

  /// Releases the camera while the app is in the background or another
  /// screen covers it, and takes it back on [resume].
  Future<void> pause();
  Future<void> resume();

  Future<void> close();
}

typedef BatchCameraFactory = BatchCamera Function();
