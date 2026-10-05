import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/live_capture.dart';
import 'package:lumascan/domain/models.dart';

import 'support/fake_live_capture.dart';

CropQuad _quad(double shift) => CropQuad(
  NormPoint(0.1 + shift, 0.1),
  NormPoint(0.9 + shift, 0.1),
  NormPoint(0.9 + shift, 0.9),
  NormPoint(0.1 + shift, 0.9),
);

DetectionResult _frame({
  double shift = 0,
  double confidence = 0.9,
  CaptureGuidance guidance = CaptureGuidance.holdSteady,
  int trackingId = 1,
  bool found = true,
  int ms = 0,
}) => DetectionResult(
  quads: found ? [_quad(shift)] : const [],
  confidence: confidence,
  guidance: guidance,
  timestamp: Duration(milliseconds: ms),
  trackingId: trackingId,
);

void main() {
  group('ReadinessTracker', () {
    test('needs five steady frames before auto capture', () {
      final tracker = ReadinessTracker(const CaptureConfig(mode: CaptureMode.document));
      for (var i = 0; i < 4; i++) {
        expect(tracker.add(_frame(shift: i * 0.001)), DetectionPhase.holdSteady);
        expect(tracker.canAutoCapture, isFalse);
      }
      expect(tracker.add(_frame(shift: 0.004)), DetectionPhase.ready);
      expect(tracker.canAutoCapture, isTrue);
    });

    test('drift above 2.5% of the diagonal restarts the count', () {
      final tracker = ReadinessTracker(const CaptureConfig(mode: CaptureMode.document));
      for (var i = 0; i < 4; i++) {
        tracker.add(_frame());
      }
      expect(tracker.add(_frame(shift: 0.1)), DetectionPhase.holdSteady);
      for (var i = 0; i < 3; i++) {
        tracker.add(_frame(shift: 0.1));
      }
      expect(tracker.phase, DetectionPhase.holdSteady);
      expect(tracker.add(_frame(shift: 0.1)), DetectionPhase.ready);
    });

    test('measures drift against the preview diagonal', () {
      final tracker = ReadinessTracker(const CaptureConfig(mode: CaptureMode.document), previewAspect: 1);
      expect(tracker.cornerDrift(_quad(0), _quad(0.1)), closeTo(0.1 / 1.41421356, 1e-6));
    });

    test('no page, clipped page and blocking guidance are not ready', () {
      final tracker = ReadinessTracker(const CaptureConfig(mode: CaptureMode.document));
      expect(tracker.add(_frame(found: false)), DetectionPhase.searching);
      expect(tracker.add(_frame(guidance: CaptureGuidance.clipped)), DetectionPhase.partial);
      expect(tracker.add(_frame(guidance: CaptureGuidance.glare)), DetectionPhase.unstable);
      expect(tracker.add(_frame(confidence: 0.3)), DetectionPhase.unstable);
    });

    test('hysteresis keeps Ready through a small confidence dip', () {
      final tracker = ReadinessTracker(const CaptureConfig(mode: CaptureMode.document));
      for (var i = 0; i < 5; i++) {
        tracker.add(_frame());
      }
      expect(tracker.add(_frame(confidence: 0.55)), DetectionPhase.ready);
      expect(tracker.add(_frame(confidence: 0.45)), DetectionPhase.unstable);
      expect(tracker.add(_frame(confidence: 0.55)), DetectionPhase.unstable, reason: 'must reach 0.6 again');
    });

    test('a new tracking ID starts over', () {
      final tracker = ReadinessTracker(const CaptureConfig(mode: CaptureMode.document));
      for (var i = 0; i < 5; i++) {
        tracker.add(_frame());
      }
      expect(tracker.add(_frame(trackingId: 2)), DetectionPhase.holdSteady);
    });

    test('auto capture off never fires', () {
      final tracker = ReadinessTracker(const CaptureConfig(mode: CaptureMode.document, autoCapture: false));
      for (var i = 0; i < 6; i++) {
        tracker.add(_frame());
      }
      expect(tracker.phase, DetectionPhase.ready);
      expect(tracker.canAutoCapture, isFalse);
    });
  });

  group('capture session contract', () {
    test('streams detections, pauses and captures the detected quad', () async {
      final service = FakeLiveCaptureService();
      final session = await service.start(const CaptureConfig(mode: CaptureMode.document)) as FakeCaptureSession;
      final seen = <DetectionResult>[];
      final sub = session.detections.listen(seen.add);

      session.emit(_frame());
      await session.pause();
      session.emit(_frame(shift: 0.01));
      await session.resume();
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(1));

      final page = await session.capture();
      expect(page.quads.single, _quad(0.01));
      expect(page.mode, CaptureMode.document);
      expect(page.needsManualCrop, isFalse);
      await sub.cancel();
      await session.close();
    });

    test('a capture without a reliable outline keeps the whole image for manual crop', () async {
      final session = await FakeLiveCaptureService().start(const CaptureConfig(mode: CaptureMode.book));
      (session as FakeCaptureSession).emit(_frame(confidence: 0.2));
      final page = await session.capture();
      expect(page.quads.single, CropQuad.full);
      expect(page.needsManualCrop, isTrue);
    });

    test('retake drops a page, accept keeps it, and the page limit holds', () async {
      final session = await FakeLiveCaptureService().start(
        const CaptureConfig(mode: CaptureMode.id, maximumPages: 2),
      ) as FakeCaptureSession;
      final a = await session.capture();
      final b = await session.capture();
      await expectLater(session.capture(), throwsStateError);
      await session.retake(a.pageId);
      await session.accept(b.pageId);
      expect([for (final p in session.captured) p.pageId], [b.pageId]);
      expect(session.accepted, {b.pageId});
    });

    test('guidance labels match the camera spec', () {
      expect(CaptureGuidance.clipped.label, 'Entire page in frame');
      expect(CaptureGuidance.lowLight.label, 'More light needed');
      expect(CaptureGuidance.ready.blocksAutoCapture, isFalse);
      expect(CaptureGuidance.searching.blocksAutoCapture, isTrue);
    });
  });
}
