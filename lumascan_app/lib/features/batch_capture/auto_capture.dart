import 'dart:math' as math;

import '../../domain/models.dart';

/// What auto capture is waiting for, shown in the guidance chip.
enum AutoCaptureState {
  /// No page in view.
  searching('Searching for a page'),

  /// A page is in view and the camera is still moving.
  steadying('Hold steady'),

  /// The page has been still long enough: take the photo now.
  capture('Capturing'),

  /// The last page was just taken; waiting for the next page to be put in
  /// view, so the same page is not taken twice.
  waitingForNext('Turn to the next page');

  const AutoCaptureState(this.label);

  final String label;
}

/// Decides when auto capture takes a photo (prototype: "Capture when edges
/// are stable"). Fed the page found in each analysed preview frame, it asks
/// for a capture once the corners have stayed within [maxDrift] of each
/// other for [stableFrames] frames in a row. After a capture it waits until
/// the page leaves the view or moves well away before arming again.
class AutoCaptureTracker {
  AutoCaptureTracker({this.stableFrames = 5, this.maxDrift = 0.025, this.rearmDrift = 0.12});

  /// Steady frames in a row needed before a capture.
  int stableFrames;

  /// Largest average corner movement between frames, as a fraction of the
  /// frame, that still counts as steady.
  final double maxDrift;

  /// Movement from the last captured page that counts as a new page.
  final double rearmDrift;

  CropQuad? _last;
  CropQuad? _captured;
  int _steady = 0;
  bool _armed = true;

  /// The page seen in the last frame, if any.
  CropQuad? get quad => _last;

  /// How far along the steady count is, from 0 to 1, for the ring around
  /// the shutter.
  double get progress => _armed ? (_steady / stableFrames).clamp(0.0, 1.0) : 0;

  AutoCaptureState get state {
    if (!_armed) return AutoCaptureState.waitingForNext;
    if (_last == null) return AutoCaptureState.searching;
    return _steady >= stableFrames ? AutoCaptureState.capture : AutoCaptureState.steadying;
  }

  /// Takes the page found in the next frame (null when none) and returns
  /// true when a photo should be taken now.
  bool add(CropQuad? quad) {
    final previous = _last;
    _last = quad;
    if (quad == null) {
      _steady = 0;
      _armed = true;
      _captured = null;
      return false;
    }
    if (!_armed) {
      if (drift(quad, _captured!) > rearmDrift) {
        _armed = true;
        _steady = 1;
      }
      return false;
    }
    _steady = previous != null && drift(quad, previous) <= maxDrift ? _steady + 1 : 1;
    return _steady >= stableFrames;
  }

  /// Call once the photo is taken: auto capture waits for the next page.
  void captured() {
    _armed = false;
    _captured = _last;
    _steady = 0;
  }

  void reset() {
    _last = null;
    _captured = null;
    _steady = 0;
    _armed = true;
  }

  /// Average distance between matching corners of two quads.
  static double drift(CropQuad a, CropQuad b) {
    var sum = 0.0;
    for (var i = 0; i < 4; i++) {
      final p = a.points[i], q = b.points[i];
      sum += math.sqrt(math.pow(p.x - q.x, 2) + math.pow(p.y - q.y, 2));
    }
    return sum / 4;
  }
}
