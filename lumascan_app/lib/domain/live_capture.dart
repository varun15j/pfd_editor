import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'models.dart';

/// Live capture contract for the custom ADR-008 camera (batch_edit.md
/// section 7). The native quick scanner behind [ScannerService] stays the
/// fallback; this contract is what the Android and iOS camera adapters will
/// implement. Preview frames stay native; only normalized metadata crosses
/// into Dart.
enum CaptureMode { document, book, id, text }

/// Short guidance shown over the preview (BE-01).
enum CaptureGuidance {
  searching('Searching'),
  moveCloser('Move closer'),
  moveFarther('Move farther'),
  clipped('Entire page in frame'),
  holdSteady('Hold steady'),
  lowLight('More light needed'),
  blur('Hold steady'),
  glare('Reduce glare'),
  ready('Ready');

  const CaptureGuidance(this.label);

  final String label;

  /// Guidance that pauses automatic capture until it clears. Manual capture
  /// always stays available.
  bool get blocksAutoCapture => this != holdSteady && this != ready;
}

/// Problems seen in a frame or a captured page, shown as badges in review.
enum QualityFlag { blur, glare, clippedEdge, lowLight, manualReview }

@immutable
class CaptureConfig {
  const CaptureConfig({
    required this.mode,
    this.autoCapture = true,
    this.stableFrames = 5,
    this.maxCornerDrift = 0.025,
    this.minConfidence = 0.6,
    this.maximumPages = 100,
  });

  final CaptureMode mode;
  final bool autoCapture;

  /// Qualifying analysed frames in a row before auto capture.
  final int stableFrames;

  /// Largest average corner movement between frames, as a fraction of the
  /// preview diagonal, that still counts as steady.
  final double maxCornerDrift;

  /// Confidence a candidate needs to count towards readiness.
  final double minConfidence;
  final int maximumPages;
}

/// One analysed preview frame. [quads] holds one quad per page region (two
/// for an open book), normalized to the preview.
@immutable
class DetectionResult {
  const DetectionResult({
    required this.quads,
    required this.confidence,
    required this.guidance,
    this.qualityFlags = const {},
    required this.timestamp,
    required this.trackingId,
  });

  final List<CropQuad> quads;
  final double confidence;
  final CaptureGuidance guidance;
  final Set<QualityFlag> qualityFlags;
  final Duration timestamp;

  /// Stays the same while the same page is followed from frame to frame.
  final int trackingId;
}

/// A page committed by [CaptureSession.capture]. [stagedPath] is the full
/// original in app-private storage; low-confidence captures keep the whole
/// image and are flagged for manual crop.
@immutable
class CapturedPageResult {
  const CapturedPageResult({
    required this.pageId,
    required this.stagedPath,
    required this.quads,
    required this.mode,
    required this.confidence,
    this.qualityFlags = const {},
    this.quarterTurns = 0,
    required this.capturedAt,
  });

  final String pageId;
  final String stagedPath;
  final List<CropQuad> quads;
  final CaptureMode mode;
  final double confidence;
  final Set<QualityFlag> qualityFlags;
  final int quarterTurns;
  final DateTime capturedAt;

  bool get needsManualCrop => qualityFlags.contains(QualityFlag.manualReview);
}

abstract interface class CaptureSession {
  Stream<DetectionResult> get detections;
  Future<CapturedPageResult> capture();
  Future<void> pause();
  Future<void> resume();
  Future<void> setTorch(bool enabled);
  Future<void> retake(String pageId);
  Future<void> accept(String pageId);
  Future<void> close();
}

abstract interface class LiveCaptureService {
  Future<CaptureSession> start(CaptureConfig config);
}

/// Where the live detector is in the detection state model (section 5).
enum DetectionPhase { searching, partial, unstable, holdSteady, ready }

/// Turns analysed frames into a steady readiness signal: auto capture needs
/// [CaptureConfig.stableFrames] qualifying frames in a row with corners
/// moving no more than [CaptureConfig.maxCornerDrift] of the preview
/// diagonal. Once steady, confidence must drop [hysteresis] below the
/// threshold to reset, so the overlay does not flicker between Ready and
/// Searching.
class ReadinessTracker {
  ReadinessTracker(this.config, {this.previewAspect = 3 / 4, this.hysteresis = 0.1});

  final CaptureConfig config;

  /// Preview width divided by height, to measure drift in screen terms.
  final double previewAspect;
  final double hysteresis;

  DetectionPhase _phase = DetectionPhase.searching;
  DetectionResult? _last;
  int _streak = 0;

  DetectionPhase get phase => _phase;

  bool get canAutoCapture => config.autoCapture && _phase == DetectionPhase.ready;

  DetectionPhase add(DetectionResult frame) {
    final last = _last;
    _last = frame;
    if (frame.quads.isEmpty) return _reset(DetectionPhase.searching);
    if (frame.guidance == CaptureGuidance.clipped) return _reset(DetectionPhase.partial);
    final steady = _phase == DetectionPhase.holdSteady || _phase == DetectionPhase.ready;
    final threshold = steady ? config.minConfidence - hysteresis : config.minConfidence;
    if (frame.confidence < threshold || frame.guidance.blocksAutoCapture) return _reset(DetectionPhase.unstable);
    final sameTarget = last != null && last.quads.isNotEmpty && last.trackingId == frame.trackingId && _streak > 0;
    if (!sameTarget || cornerDrift(last.quads.first, frame.quads.first) > config.maxCornerDrift) {
      _streak = 1;
    } else {
      _streak++;
    }
    return _phase = _streak >= config.stableFrames ? DetectionPhase.ready : DetectionPhase.holdSteady;
  }

  void reset() {
    _last = null;
    _reset(DetectionPhase.searching);
  }

  DetectionPhase _reset(DetectionPhase phase) {
    _streak = 0;
    return _phase = phase;
  }

  /// Average corner movement between [a] and [b] as a fraction of the
  /// preview diagonal.
  double cornerDrift(CropQuad a, CropQuad b) {
    final diagonal = math.sqrt(previewAspect * previewAspect + 1);
    var sum = 0.0;
    for (var i = 0; i < 4; i++) {
      final dx = (a.points[i].x - b.points[i].x) * previewAspect;
      final dy = a.points[i].y - b.points[i].y;
      sum += math.sqrt(dx * dx + dy * dy);
    }
    return sum / 4 / diagonal;
  }
}
