import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/features/batch_capture/auto_capture.dart';
import 'package:lumascan/features/batch_capture/camera_frame.dart';
import 'package:lumascan/imaging/rgb_image.dart';

/// Preview frames made from the bundled book photos, so the tracker sees
/// what a camera held over a real page would.
class _Book {
  _Book(this.width, this.height, this.luma);

  final int width, height;
  final Uint8List luma;

  static Future<_Book> load(String name) async {
    final data = await rootBundle.load('sample_photos/book/$name');
    final photo = RgbImage.decode(data.buffer.asUint8List(), maxDimension: 480);
    final luma = Uint8List(photo.width * photo.height);
    for (var i = 0; i < luma.length; i++) {
      final r = photo.data[i * 3], g = photo.data[i * 3 + 1], b = photo.data[i * 3 + 2];
      luma[i] = (r * 299 + g * 587 + b * 114) ~/ 1000;
    }
    return _Book(photo.width, photo.height, luma);
  }

  /// Partway through turning to [next]: the part of the view left of
  /// [shown] (0..1) already shows the next page.
  FrameAnalysis turningTo(_Book next, double shown) {
    final out = Uint8List(width * height);
    final edge = (width * shown).round();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        out[y * width + x] = x < edge ? next.luma[y * width + x] : luma[y * width + x];
      }
    }
    return analyzeFrame(CameraFrame.gray(width, height, out));
  }

  /// The view moved by ([dx], [dy]) pixels with its brightness times [gain],
  /// optionally with a hand covering the left [covered] part of it.
  FrameAnalysis frame({int dx = 0, int dy = 0, double gain = 1, double covered = 0}) {
    final out = Uint8List(width * height);
    final hand = (width * covered).round();
    for (var y = 0; y < height; y++) {
      final sy = (y + dy).clamp(0, height - 1);
      for (var x = 0; x < width; x++) {
        final sx = (x + dx).clamp(0, width - 1);
        out[y * width + x] = x < hand ? 205 : (luma[sy * width + sx] * gain).round().clamp(0, 255);
      }
    }
    return analyzeFrame(CameraFrame.gray(width, height, out));
  }
}

int _shots(AutoCaptureTracker tracker, Iterable<FrameAnalysis> frames) {
  var shots = 0;
  for (final f in frames) {
    if (tracker.add(f.quad, f.signature, f.scene)) {
      shots++;
      tracker.captured();
    }
  }
  return shots;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a page held in the hand for a minute is taken once', () async {
    final page = await _Book.load('03_straw_pipette.jpg');
    expect(page.frame().quad, isNotNull, reason: 'the test page must be outlined');
    final tracker = AutoCaptureTracker();
    // 400 frames, about a minute of preview: the hand drifts 40 pixels
    // down and 20 across, and the light fades by a fifth, a little each
    // frame.
    final held = [for (var i = 0; i < 400; i++) page.frame(dx: i ~/ 20, dy: i ~/ 10, gain: 1 - 0.2 * i / 400)];
    expect(
      signatureDiff(held.first.scene!, held.last.scene!),
      greaterThan(tracker.sceneChange),
      reason: 'the view ends up far from where it was captured',
    );
    expect(_shots(tracker, held), 1);
    expect(tracker.state, AutoCaptureState.waitingForNext);
  });

  test('on the Basic plan a held page that drifts is taken again, as before', () async {
    final page = await _Book.load('03_straw_pipette.jpg');
    final tracker = AutoCaptureTracker()..smart = false;
    final held = [for (var i = 0; i < 400; i++) page.frame(dx: i ~/ 20, dy: i ~/ 10, gain: 1 - 0.2 * i / 400)];
    expect(_shots(tracker, held), greaterThan(1));
  });

  test('after a long hold, turning to the next page still takes it', () async {
    final first = await _Book.load('03_straw_pipette.jpg');
    final second = await _Book.load('19_hard_boiled_egg.jpg');
    expect(second.frame().quad, isNotNull, reason: 'the test page must be outlined');
    final tracker = AutoCaptureTracker();
    final frames = [
      for (var i = 0; i < 200; i++) first.frame(dx: i ~/ 20, dy: i ~/ 10),
      // The hand turns the page over.
      first.frame(dx: 10, dy: 20, covered: 0.5),
      second.frame(covered: 0.7),
      for (var i = 0; i < 20; i++) second.frame(),
    ];
    expect(_shots(tracker, frames), 2);
  });

  test('a page turned slowly is still taken', () async {
    final first = await _Book.load('03_straw_pipette.jpg');
    final second = await _Book.load('19_hard_boiled_egg.jpg');
    final tracker = AutoCaptureTracker();
    final frames = [
      for (var i = 0; i < 20; i++) first.frame(),
      // Two seconds to turn the page: each frame changes only a little.
      for (var i = 1; i <= 14; i++) first.turningTo(second, i / 14),
      for (var i = 0; i < 20; i++) second.frame(),
    ];
    expect(_shots(tracker, frames), 2);
  });
}
