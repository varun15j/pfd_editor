import 'package:flutter/widgets.dart';

import '../../domain/app_settings.dart';
import 'camera_frame.dart';

/// The live camera behind Batch capture. Unlike the native document scanner
/// it stays open between shots, so pages can be taken one after another
/// without a review screen after each. Tests swap in a fake.
///
/// [open] throws ScannerPermissionDenied when camera access is refused and
/// ScannerFailure for any other camera error.
abstract interface class BatchCamera {
  /// Opens the back camera, taking photos of [resolution].
  Future<void> open({CaptureResolution resolution = CaptureResolution.high});

  /// True once [open] finished and until [close] or [pause].
  bool get isReady;

  /// Whether the camera has a torch that [setTorch] can switch.
  bool get hasTorch;

  /// The live preview, with [overlay] drawn over exactly the preview's area
  /// (the page outline, guides). Only shown while [isReady].
  Widget buildPreview({Widget? overlay});

  /// Takes one photo and returns the path of the file the camera wrote.
  /// The file is the caller's to move.
  Future<String> takePicture();

  Future<void> setTorch(bool on);

  /// Changes the photo size; the camera restarts if it is open.
  Future<void> setResolution(CaptureResolution resolution);

  /// Sends preview frames to [onFrame] until [stopFrames], for auto capture
  /// and QR reading. The camera drops frames while [onFrame] is busy, so a
  /// slow listener never builds up a queue. Does nothing on a camera that
  /// cannot stream.
  Future<void> startFrames(void Function(CameraFrame frame) onFrame);
  Future<void> stopFrames();

  /// Releases the camera while the app is in the background or another
  /// screen covers it, and takes it back on [resume].
  Future<void> pause();
  Future<void> resume();

  Future<void> close();
}

typedef BatchCameraFactory = BatchCamera Function();
