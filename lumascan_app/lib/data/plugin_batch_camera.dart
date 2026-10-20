import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/app_settings.dart';
import '../domain/scanner_service.dart';
import '../features/batch_capture/batch_camera.dart';
import '../features/batch_capture/camera_frame.dart';

/// [BatchCamera] backed by the camera plugin (CameraX on Android,
/// AVFoundation on iOS): the back camera, no audio, JPEG photos, and
/// preview frames for auto capture and QR reading.
class PluginBatchCamera implements BatchCamera {
  /// High is about 8 MP on most phones: sharp enough for small print, and
  /// quick to save, so the shutter is ready again almost at once. Maximum
  /// makes each shot slower and each page several times larger.
  static ResolutionPreset _preset(CaptureResolution r) => switch (r) {
    CaptureResolution.standard => ResolutionPreset.veryHigh,
    CaptureResolution.high => ResolutionPreset.ultraHigh,
    CaptureResolution.maximum => ResolutionPreset.max,
  };

  CameraDescription? _description;
  CameraController? _controller;
  CaptureResolution _resolution = CaptureResolution.high;
  bool _torch = false;
  void Function(CameraFrame)? _onFrame;

  @override
  bool get isReady => _controller?.value.isInitialized ?? false;

  @override
  bool get hasTorch => _description?.lensDirection == CameraLensDirection.back;

  @override
  Future<void> open({CaptureResolution resolution = CaptureResolution.high}) async {
    _resolution = resolution;
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
      _preset(_resolution),
      enableAudio: false,
      // The preview frames' format; photos are JPEG either way. NV21 starts
      // with the brightness plane, and BGRA is what iOS streams natively.
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
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
    if (_onFrame != null) await _stream(controller);
  }

  Future<void> _stream(CameraController controller) async {
    final rotation = _description!.sensorOrientation;
    await _quietly(
      () => controller.startImageStream((image) {
        final plane = image.planes.first;
        _onFrame?.call(
          CameraFrame(
            width: image.width,
            height: image.height,
            bytesPerRow: plane.bytesPerRow,
            bytes: plane.bytes,
            pixels: image.format.group == ImageFormatGroup.bgra8888 ? FramePixels.bgra : FramePixels.luma,
            rotation: rotation,
          ),
        );
      }),
    );
  }

  @override
  Future<void> startFrames(void Function(CameraFrame frame) onFrame) async {
    final streaming = _onFrame != null;
    _onFrame = onFrame;
    final controller = _controller;
    if (!streaming && controller != null && controller.value.isInitialized) await _stream(controller);
  }

  @override
  Future<void> stopFrames() async {
    _onFrame = null;
    final controller = _controller;
    if (controller != null && controller.value.isStreamingImages) {
      await _quietly(controller.stopImageStream);
    }
  }

  @override
  Future<void> setResolution(CaptureResolution resolution) async {
    if (resolution == _resolution) return;
    _resolution = resolution;
    if (_controller != null) {
      await pause();
      await resume();
    }
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
  Widget buildPreview({Widget? overlay}) => CameraPreview(_controller!, child: overlay);

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
