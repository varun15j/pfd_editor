import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/scanner_service.dart';
import '../features/batch_capture/batch_camera.dart';

/// [BatchCamera] backed by the camera plugin (CameraX on Android,
/// AVFoundation on iOS): the back camera, no audio, JPEG output.
class PluginBatchCamera implements BatchCamera {
  /// About 8 MP on most phones: sharp enough for small print, and quick to
  /// save, so the shutter is ready again almost at once. Full sensor size
  /// would make each shot slower and each page several times larger.
  static const _resolution = ResolutionPreset.ultraHigh;

  CameraDescription? _description;
  CameraController? _controller;
  bool _torch = false;

  @override
  bool get isReady => _controller?.value.isInitialized ?? false;

  @override
  bool get hasTorch => _description?.lensDirection == CameraLensDirection.back;

  @override
  Future<void> open() async {
    await _ensurePermission();
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw const ScannerFailure('No camera found on this device');
      _description = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
    } on CameraException catch (e) {
      throw _failure(e);
    }
    await _start();
  }

  Future<void> _start() async {
    final controller = CameraController(
      _description!,
      _resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      throw _failure(e);
    }
    _controller = controller;
    // Pages are held upright; locking stops a tilt from turning a photo sideways.
    await _quietly(() => controller.lockCaptureOrientation(DeviceOrientation.portraitUp));
    await _quietly(() => controller.setFlashMode(_torch ? FlashMode.torch : FlashMode.off));
    await _quietly(() => controller.setFocusMode(FocusMode.auto));
  }

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } on CameraException {
      // Not every camera supports every setting; capture works without it.
    }
  }

  static Exception _failure(CameraException e) => switch (e.code) {
    'CameraAccessDenied' => const ScannerPermissionDenied(),
    'CameraAccessDeniedWithoutPrompt' || 'CameraAccessRestricted' => const ScannerPermissionDenied(permanently: true),
    _ => ScannerFailure(e.description ?? e.code),
  };

  static Future<void> _ensurePermission() async {
    var status = await Permission.camera.status;
    if (status.isGranted || status.isLimited) return;
    if (status.isPermanentlyDenied || status.isRestricted) throw const ScannerPermissionDenied(permanently: true);
    status = await Permission.camera.request();
    if (status.isGranted || status.isLimited) return;
    throw ScannerPermissionDenied(permanently: status.isPermanentlyDenied || status.isRestricted);
  }

  @override
  Widget buildPreview() => CameraPreview(_controller!);

  @override
  Future<String> takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) throw const ScannerFailure('The camera is not ready');
    try {
      return (await controller.takePicture()).path;
    } on CameraException catch (e) {
      throw _failure(e);
    }
  }

  @override
  Future<void> setTorch(bool on) async {
    _torch = on;
    final controller = _controller;
    if (controller != null) await _quietly(() => controller.setFlashMode(on ? FlashMode.torch : FlashMode.off));
  }

  @override
  Future<void> pause() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }

  @override
  Future<void> resume() async {
    if (_description != null && _controller == null) await _start();
  }

  @override
  Future<void> close() => pause();
}
