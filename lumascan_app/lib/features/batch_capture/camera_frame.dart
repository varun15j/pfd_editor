import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../domain/models.dart';
import '../../domain/plan.dart';
import '../../imaging/book_split.dart';
import '../../imaging/corner_model.dart';
import '../../imaging/page_detector.dart';
import '../../imaging/rgb_image.dart';
import 'auto_capture.dart';
import 'frame_worker.dart';

/// How the bytes of a [CameraFrame] are laid out.
enum FramePixels {
  /// One byte of brightness per pixel: the Y plane of YUV 4:2:0.
  luma,

  /// NV21, what Android sends: the brightness plane, then a half-size plane
  /// of colour, V then U for each 2 x 2 block, rows [CameraFrame.bytesPerRow]
  /// long.
  nv21,

  /// Four bytes per pixel, blue first: what iOS sends.
  bgra,
}

/// One preview frame, as the camera sends it. Page outlines are found in a
/// small colour copy ([uprightColour]), since a coloured page can be as
/// bright as the surface it lies on; everything else reads the brightness.
@immutable
class CameraFrame {
  const CameraFrame({
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.bytes,
    this.pixels = FramePixels.luma,
    this.rotation = 0,
  });

  /// A brightness-only frame, already upright. Used by tests.
  factory CameraFrame.gray(int width, int height, Uint8List luma) =>
      CameraFrame(width: width, height: height, bytesPerRow: width, bytes: luma);

  final int width;
  final int height;
  final int bytesPerRow;
  final Uint8List bytes;
  final FramePixels pixels;

  /// Clockwise turn, in degrees, that makes the frame upright on screen.
  final int rotation;

  /// Brightness at full frame size, row by row with no padding, as NV21 and
  /// NV12 expect for their first plane.
  Uint8List luma() {
    if (pixels != FramePixels.bgra && bytesPerRow == width) return bytes.sublist(0, width * height);
    final out = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      final row = y * bytesPerRow;
      for (var x = 0; x < width; x++) {
        out[y * width + x] = _lumaAt(row, x);
      }
    }
    return out;
  }

  int _lumaAt(int row, int x) {
    if (pixels != FramePixels.bgra) return bytes[row + x];
    final i = row + x * 4;
    return (bytes[i] * 29 + bytes[i + 1] * 150 + bytes[i + 2] * 77) >> 8;
  }

  /// Whether the frame carries colour: NV21 with its colour plane, or BGRA.
  bool get hasColour =>
      pixels == FramePixels.bgra ||
      (pixels == FramePixels.nv21 && bytes.length >= bytesPerRow * height + bytesPerRow * ((height + 1) ~/ 2));

  /// A small grey copy, upright, at most [size] pixels on its long side.
  RgbImage uprightGray({int size = 200}) => _upright(size, colour: false);

  /// A small colour copy, upright, at most [size] pixels on its long side;
  /// grey when the frame has no colour.
  RgbImage uprightColour({int size = 200}) => _upright(size, colour: hasColour);

  RgbImage _upright(int size, {required bool colour}) {
    final scale = size / math.max(width, height);
    final w = math.max(8, (width * math.min(1.0, scale)).round());
    final h = math.max(8, (height * math.min(1.0, scale)).round());
    final turned = rotation % 180 != 0;
    final out = RgbImage(turned ? h : w, turned ? w : h);
    final fx = width / w, fy = height / h;
    for (var y = 0; y < h; y++) {
      final row = (y * fy).floor() * bytesPerRow;
      for (var x = 0; x < w; x++) {
        final sx = (x * fx).floor();
        final (ox, oy) = switch (rotation % 360) {
          90 => (h - 1 - y, x),
          180 => (w - 1 - x, h - 1 - y),
          270 => (y, w - 1 - x),
          _ => (x, y),
        };
        final o = (oy * out.width + ox) * 3;
        if (!colour) {
          final v = _lumaAt(row, sx);
          out.data[o] = v;
          out.data[o + 1] = v;
          out.data[o + 2] = v;
        } else if (pixels == FramePixels.bgra) {
          final i = row + sx * 4;
          out.data[o] = bytes[i + 2];
          out.data[o + 1] = bytes[i + 1];
          out.data[o + 2] = bytes[i];
        } else {
          // NV21 to RGB, full range BT.601, as Android cameras send it.
          final l = bytes[row + sx];
          final c = bytesPerRow * height + ((y * fy).floor() >> 1) * bytesPerRow + (sx & ~1);
          final v = bytes[c] - 128, u = bytes[c + 1] - 128;
          out.data[o] = (l + 1.402 * v).round().clamp(0, 255);
          out.data[o + 1] = (l - 0.344 * u - 0.714 * v).round().clamp(0, 255);
          out.data[o + 2] = (l + 1.772 * u).round().clamp(0, 255);
        }
      }
    }
    return out;
  }
}

/// What one preview frame shows: the page in it, if any, upright and
/// normalized to the frame, a coarse [pageSignature] of what is printed on
/// it, a [sceneSignature] of the whole frame, and how bright the frame is
/// (0..255).
@immutable
class FrameAnalysis {
  const FrameAnalysis({this.quad, this.signature, this.scene, this.brightness = 128});

  final CropQuad? quad;
  final Float32List? signature;

  /// A [sceneSignature] of the whole frame.
  final Float32List? scene;
  final double brightness;

  /// Too dark for auto capture to trust what it sees.
  bool get tooDark => brightness < 45;
}

/// Pure Dart apart from [model], so it can run in an isolate. With [smart]
/// on and a [model], the model's outline is tried first, and the hand-made
/// detector is asked only when the model is not sure of every corner.
FrameAnalysis analyzeFrame(CameraFrame frame, {bool smart = true, CornerModel? model}) {
  final gray = frame.uprightGray();
  // Outlines are found in colour where the frame has it: a coloured page on
  // a surface of the same brightness only stands out by its colour.
  final picture = frame.hasColour ? frame.uprightColour() : gray;
  final fromModel = smart ? model?.find(picture) : null;
  final quad = fromModel ?? detectPageQuad(picture, workSize: 160, minArea: 0.2, smart: smart);
  return FrameAnalysis(
    quad: quad,
    signature: quad == null ? null : pageSignature(gray, quad),
    scene: sceneSignature(gray),
    brightness: meanLuma(gray),
  );
}

typedef FrameAnalyzer = Future<FrameAnalysis> Function(CameraFrame frame);

/// Analyses preview frames off the UI thread. Tests swap in a direct call.
/// With smart scanning (Pro), frames go to one long-lived isolate that holds
/// the corner model ([FrameWorker]); without it, or while the model loads
/// or if it cannot, each frame runs in a fresh isolate on the hand-made
/// detector alone.
final frameAnalyzerProvider = Provider<FrameAnalyzer>((ref) {
  final smart = ref.watch(planIncludesProvider(PlanFeature.smartScan));
  FrameAnalysis plain(CameraFrame frame) => analyzeFrame(frame, smart: smart);
  if (!smart) return (frame) => Isolate.run(() => plain(frame));
  final worker = FrameWorker.start();
  ref.onDispose(() => worker.then((w) => w?.stop()));
  return (frame) async {
    final w = await worker;
    return w == null ? Isolate.run(() => plain(frame)) : w.analyze(frame);
  };
});

typedef SpreadSplitter = Future<(CropQuad, CropQuad)> Function(String photoPath);

/// Finds the left and right page in a photo of an open book, off the UI
/// thread (Book mode).
final spreadSplitterProvider = Provider<SpreadSplitter>((ref) {
  final smart = ref.watch(planIncludesProvider(PlanFeature.smartScan));
  return (path) =>
      Isolate.run(() => splitSpread(RgbImage.decode(File(path).readAsBytesSync(), maxDimension: 640), smart: smart));
});
