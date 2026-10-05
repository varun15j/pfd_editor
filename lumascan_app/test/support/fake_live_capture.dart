import 'dart:async';

import 'package:lumascan/domain/live_capture.dart';
import 'package:lumascan/domain/models.dart';

/// In-memory [LiveCaptureService] for tests: detections are pushed by the
/// test, and every capture produces a page with the latest detected quad.
class FakeLiveCaptureService implements LiveCaptureService {
  FakeCaptureSession? session;

  @override
  Future<CaptureSession> start(CaptureConfig config) async => session = FakeCaptureSession(config);
}

class FakeCaptureSession implements CaptureSession {
  FakeCaptureSession(this.config);

  final CaptureConfig config;
  final _detections = StreamController<DetectionResult>.broadcast();
  final captured = <CapturedPageResult>[];
  final accepted = <String>{};
  DetectionResult? _latest;
  bool paused = false;
  bool torch = false;
  bool closed = false;
  int _next = 0;

  void emit(DetectionResult result) {
    _latest = result;
    if (!paused) _detections.add(result);
  }

  @override
  Stream<DetectionResult> get detections => _detections.stream;

  @override
  Future<CapturedPageResult> capture() async {
    if (closed) throw StateError('Session closed');
    if (captured.length >= config.maximumPages) throw StateError('Page limit reached');
    final latest = _latest;
    final confident = latest != null && latest.quads.isNotEmpty && latest.confidence >= config.minConfidence;
    final page = CapturedPageResult(
      pageId: 'live-${_next++}',
      stagedPath: '/staged/${_next - 1}.jpg',
      // A capture without a reliable outline keeps the whole image for manual crop.
      quads: confident ? latest.quads : const [CropQuad.full],
      mode: config.mode,
      confidence: latest?.confidence ?? 0,
      qualityFlags: confident ? const {} : const {QualityFlag.manualReview},
      capturedAt: DateTime(2026, 10, 5),
    );
    captured.add(page);
    return page;
  }

  @override
  Future<void> pause() async => paused = true;

  @override
  Future<void> resume() async => paused = false;

  @override
  Future<void> setTorch(bool enabled) async => torch = enabled;

  @override
  Future<void> retake(String pageId) async => captured.removeWhere((p) => p.pageId == pageId);

  @override
  Future<void> accept(String pageId) async => accepted.add(pageId);

  @override
  Future<void> close() async {
    closed = true;
    await _detections.close();
  }
}
