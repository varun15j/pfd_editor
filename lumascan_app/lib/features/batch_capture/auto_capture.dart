import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/models.dart';
import '../../imaging/rgb_image.dart';

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
/// are stable"). Fed the page found in each analysed preview frame, and a
/// coarse [pageSignature] of what is on it, it asks for a capture once the
/// corners and the content have stayed still for [stableFrames] frames in a
/// row.
///
/// After a capture it waits for the next page, so the same page is never
/// taken twice. Turning a book page or swapping a sheet changes what the
/// camera sees: a hand and a turning page sweep over the view, and a
/// different page lies there afterwards. That is judged from a
/// [sceneSignature] of the whole frame, not from the outline, because the
/// outline can flicker out or jump between two guesses while nothing in
/// front of the camera moves. Only [disturbFrames] changed frames in a row
/// count as a new page. Once disturbed, the new page must settle and stay
/// still again before it is taken, so a page caught mid-turn is never taken
/// either.
///
/// A page held in the hand for half a minute or more drifts slowly, and the
/// light on it changes. Each frame then differs only a little from the one
/// before, but over many frames the view moves far from the captured one.
/// So while waiting, every quiet frame (one that changed less than
/// [quietChange] from the frame before) becomes the new reference: only a
/// sharp change, such as a hand or a page sweeping over the view, ever adds
/// up to a new page. Slow drift never does. A page turned slowly is not
/// followed: once the page in view no longer reads as the page taken (its
/// [pageSignature]), the changes add up again.
class AutoCaptureTracker {
  AutoCaptureTracker({
    this.stableFrames = 5,
    this.maxDrift = 0.025,
    this.rearmDrift = 0.12,
    this.disturbFrames = 2,
    this.steadyChange = 0.5,
    this.flipChange = 0.7,
    this.sceneChange = 0.4,
    this.quietChange = 0.15,
  });

  /// Steady frames in a row needed before a capture.
  int stableFrames;

  /// Whether the Pro plan's smarter tracking is on: following slow drift
  /// and capturing the next page sooner. Off, the tracker works as before.
  bool smart = true;

  /// Fewest steady frames needed after a page turn.
  static const minTurnFrames = 3;

  /// Largest average corner movement between frames, as a fraction of the
  /// frame, that still counts as steady.
  final double maxDrift;

  /// Movement of the outline from the captured page that disturbs the view.
  final double rearmDrift;

  /// Disturbed frames in a row that mean the page was turned or swapped.
  final int disturbFrames;

  /// Largest content change between two frames that still counts as steady.
  final double steadyChange;

  /// Content change, from the captured page or from the frame before, that
  /// disturbs the view: a hand or a turning page passing over it, or a
  /// clearly different page.
  final double flipChange;

  /// Change of the whole view, from the captured frame or from the frame
  /// before, that disturbs it.
  final double sceneChange;

  /// Largest change from the frame before that counts as the same view
  /// drifting, not something moving across it. Quiet frames replace the
  /// captured frame as the reference, so drift never adds up to a new page.
  final double quietChange;

  CropQuad? _last;
  Float32List? _lastSignature;
  Float32List? _lastScene;
  Float32List? _capturedScene;
  bool _waiting = false;
  bool _turned = false;
  CropQuad? _capturedQuad;
  Float32List? _capturedSignature;

  /// The page signature when the photo was taken; unlike
  /// [_capturedSignature] it does not follow drift.
  Float32List? _capturedPage;
  int _disturbed = 0;
  int _steady = 0;

  /// The page seen in the last frame, if any.
  CropQuad? get quad => _last;

  /// How far along the steady count is, from 0 to 1, for the ring around
  /// the shutter.
  double get progress => _waiting || _last == null ? 0 : (_steady / _needed).clamp(0.0, 1.0);

  /// Steady frames needed now: fewer right after a page turn, when the
  /// hand has just left the page and it settles fast, so the next page
  /// follows quickly.
  int get _needed => smart && _turned ? math.max(minTurnFrames, stableFrames - 2) : stableFrames;

  AutoCaptureState get state {
    if (_waiting) return AutoCaptureState.waitingForNext;
    if (_last == null) return AutoCaptureState.searching;
    return _steady >= _needed ? AutoCaptureState.capture : AutoCaptureState.steadying;
  }

  /// Takes the page found in the next frame (null when none, or when the
  /// frame is too dark to trust), its content [signature] and the
  /// [scene] signature of the whole frame, and returns true when a photo
  /// should be taken now.
  bool add(CropQuad? quad, [Float32List? signature, Float32List? scene]) {
    final previous = _last, previousSignature = _lastSignature, previousScene = _lastScene;
    _last = quad;
    _lastSignature = quad == null ? null : signature;
    _lastScene = scene;
    if (_waiting) {
      final disturbed = scene != null && _capturedScene != null
          ? _sceneChanged(scene, previousScene)
          : _disturbs(quad, signature, previousSignature);
      _disturbed = disturbed ? _disturbed + 1 : 0;
      if (_disturbed >= disturbFrames) {
        _forgetCaptured();
        _turned = true;
      } else if (!disturbed && smart) {
        _followDrift(quad, signature, scene, previous, previousSignature, previousScene);
      }
    }
    if (quad == null) {
      _steady = 0;
      return false;
    }
    final still =
        previous != null &&
        drift(quad, previous) <= maxDrift &&
        (signature == null || previousSignature == null || signatureDiff(signature, previousSignature) <= steadyChange);
    _steady = still ? _steady + 1 : 1;
    return !_waiting && _steady >= _needed;
  }

  /// Whether the view changed: from the frame captured, or sharply from the
  /// frame before (something moving across it).
  bool _sceneChanged(Float32List scene, Float32List? previousScene) =>
      signatureDiff(scene, _capturedScene!) >= sceneChange ||
      (previousScene != null && signatureDiff(scene, previousScene) >= sceneChange);

  /// Moves the captured reference along with a view that is only drifting:
  /// a page held in the hand, or light slowly changing on it.
  void _followDrift(
    CropQuad? quad,
    Float32List? signature,
    Float32List? scene,
    CropQuad? previous,
    Float32List? previousSignature,
    Float32List? previousScene,
  ) {
    // A page turned slowly changes the view only a little each frame too,
    // so the view is followed only while the page on it still reads as
    // the page taken.
    final samePage =
        _capturedPage == null || (signature != null && signatureDiff(signature, _capturedPage!) < steadyChange);
    if (samePage && scene != null && previousScene != null && signatureDiff(scene, previousScene) < quietChange) {
      _capturedScene = scene;
    }
    if (quad != null &&
        previous != null &&
        drift(quad, previous) <= maxDrift &&
        signature != null &&
        previousSignature != null &&
        signatureDiff(signature, previousSignature) < quietChange) {
      _capturedQuad = quad;
      _capturedSignature = signature;
    }
  }

  /// Without scene signatures: whether this frame looks unlike the captured
  /// page lying still.
  bool _disturbs(CropQuad? quad, Float32List? signature, Float32List? previousSignature) {
    if (quad == null) return true;
    final capturedQuad = _capturedQuad;
    if (capturedQuad != null && drift(quad, capturedQuad) > rearmDrift) return true;
    if (signature == null) return false;
    final captured = _capturedSignature;
    if (captured != null && signatureDiff(signature, captured) >= flipChange) return true;
    // Content moving under a still outline: a page turning over.
    return previousSignature != null && signatureDiff(signature, previousSignature) >= flipChange;
  }

  /// Call once a photo is taken: auto capture waits for the next page.
  void captured() {
    _steady = 0;
    _turned = false;
    _disturbed = 0;
    _waiting = true;
    _capturedQuad = _last;
    _capturedSignature = _lastSignature;
    _capturedPage = _lastSignature;
    _capturedScene = _lastScene;
  }

  void _forgetCaptured() {
    _waiting = false;
    _capturedQuad = null;
    _capturedSignature = null;
    _capturedPage = null;
    _capturedScene = null;
    _disturbed = 0;
  }

  void reset() {
    _turned = false;
    _last = null;
    _lastSignature = null;
    _lastScene = null;
    _steady = 0;
    _forgetCaptured();
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

/// Columns and rows of a [pageSignature].
const signatureColumns = 6, signatureRows = 8;

/// A coarse picture of what is printed on the page inside [quad]: the mean
/// brightness of a [signatureColumns] x [signatureRows] grid laid over the
/// page, so it stays the same when the camera moves but the page does not.
/// Values are centred on the page's mean and scaled by its contrast, so a
/// change of exposure does not look like a new page. A blank page keeps a
/// floor on the scale, so sensor noise is not blown up into content.
Float32List pageSignature(RgbImage gray, CropQuad quad) => _gridSignature(gray, quad, _inset);

/// A [pageSignature] of the whole frame, edge to edge: what the camera
/// sees, used to tell when something in front of it changed.
Float32List sceneSignature(RgbImage gray) => _gridSignature(gray, CropQuad.full, 0);

Float32List _gridSignature(RgbImage gray, CropQuad quad, double inset) {
  // Enough samples to cover every pixel of a cell, so a cell is the true
  // average of what is printed there and lines of text do not alias.
  final pageWidth = math.max((quad.tr.x - quad.tl.x).abs(), (quad.br.x - quad.bl.x).abs()) * gray.width;
  final pageHeight = math.max((quad.bl.y - quad.tl.y).abs(), (quad.br.y - quad.tr.y).abs()) * gray.height;
  final across = math.max(4, (pageWidth / signatureColumns).ceil() + 1);
  final down = math.max(4, (pageHeight / signatureRows).ceil() + 1);
  final out = Float32List(signatureColumns * signatureRows);
  final d = gray.data;
  for (var row = 0; row < signatureRows; row++) {
    for (var column = 0; column < signatureColumns; column++) {
      var sum = 0;
      for (var j = 0; j < down; j++) {
        final v = inset + (1 - 2 * inset) * (row + (j + 0.5) / down) / signatureRows;
        for (var i = 0; i < across; i++) {
          final u = inset + (1 - 2 * inset) * (column + (i + 0.5) / across) / signatureColumns;
          final x = _bilinear(quad.tl.x, quad.tr.x, quad.bl.x, quad.br.x, u, v);
          final y = _bilinear(quad.tl.y, quad.tr.y, quad.bl.y, quad.br.y, u, v);
          final px = (x * (gray.width - 1)).round().clamp(0, gray.width - 1);
          final py = (y * (gray.height - 1)).round().clamp(0, gray.height - 1);
          sum += d[(py * gray.width + px) * 3];
        }
      }
      out[row * signatureColumns + column] = sum / (across * down);
    }
  }
  var mean = 0.0;
  for (final value in out) {
    mean += value;
  }
  mean /= out.length;
  var variance = 0.0;
  for (final value in out) {
    variance += (value - mean) * (value - mean);
  }
  final scale = math.max(8.0, math.sqrt(variance / out.length));
  for (var i = 0; i < out.length; i++) {
    out[i] = (out[i] - mean) / scale;
  }
  return out;
}

/// How different two [pageSignature]s are: the mean absolute difference, in
/// units of page contrast. The same page lying still stays under about 0.3.
double signatureDiff(Float32List a, Float32List b) {
  if (a.length != b.length) return double.infinity;
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]).abs();
  }
  return sum / a.length;
}

/// Margin of the page left out of a [pageSignature], so a slightly loose
/// outline never lets the desk into it.
const _inset = 0.08;

double _bilinear(double tl, double tr, double bl, double br, double u, double v) {
  final top = tl + (tr - tl) * u, bottom = bl + (br - bl) * u;
  return top + (bottom - top) * v;
}
