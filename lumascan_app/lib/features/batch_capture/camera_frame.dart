import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../domain/models.dart';
import '../../domain/plan.dart';
import '../../imaging/book_split.dart';
import '../../imaging/page_detector.dart';
import '../../imaging/rgb_image.dart';
import 'auto_capture.dart';

/// How the bytes of a [CameraFrame] are laid out.
enum FramePixels {
  /// One byte of brightness per pixel: the Y plane of NV21 or YUV 4:2:0,
  /// which is what Android sends.
  luma,

  /// Packed Android NV21: Y followed by interleaved V,U at half resolution.
  nv21,

  /// Four bytes per pixel, blue first: what iOS sends.
  bgra,
}

/// One preview frame, as the camera sends it. Colour is sampled only at the
/// small detection resolution; QR reading can still use the Y plane alone.
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

  /// A small grey copy, upright, at most [size] pixels on its long side.
  RgbImage uprightGray({int size = 200}) {
    return _upright(size: size, colour: false);
  }

  /// Retains chroma for equal-brightness page/background boundaries. Converts
  /// only sampled pixels, never a full camera-sized RGB allocation.
  RgbImage uprightRgb({int size = 200}) => _upright(size: size, colour: true);

  RgbImage _upright({required int size, required bool colour}) {
    final scale = size / math.max(width, height);
    final w = math.max(1, (width * math.min(1.0, scale)).round());
    final h = math.max(1, (height * math.min(1.0, scale)).round());
    final turned = rotation % 180 != 0;
    final out = RgbImage(turned ? h : w, turned ? w : h);
    final fx = width / w, fy = height / h;
    for (var y = 0; y < h; y++) {
      final sy = (y * fy).floor();
      final row = sy * bytesPerRow;
      for (var x = 0; x < w; x++) {
        final sx = (x * fx).floor();
        final v = _lumaAt(row, sx);
        final (ox, oy) = switch (rotation % 360) {
          90 => (h - 1 - y, x),
          180 => (w - 1 - x, h - 1 - y),
          270 => (y, w - 1 - x),
          _ => (x, y),
        };
        final o = (oy * out.width + ox) * 3;
        if (colour && pixels == FramePixels.bgra) {
          final i = row + sx * 4;
          out.data[o] = bytes[i + 2];
          out.data[o + 1] = bytes[i + 1];
          out.data[o + 2] = bytes[i];
        } else if (colour && pixels == FramePixels.nv21) {
          final uv = bytesPerRow * height + (sy ~/ 2) * bytesPerRow + (sx ~/ 2) * 2;
          // Some camera backends expose Y only. Keep detection working if
          // chroma is absent instead of reading past the supplied buffer.
          if (uv + 1 < bytes.length) {
            final cr = bytes[uv] - 128, cb = bytes[uv + 1] - 128;
            final yy = math.max(0, v - 16) * 298;
            out.data[o] = ((yy + 409 * cr + 128) >> 8).clamp(0, 255);
            out.data[o + 1] = ((yy - 100 * cb - 208 * cr + 128) >> 8).clamp(0, 255);
            out.data[o + 2] = ((yy + 516 * cb + 128) >> 8).clamp(0, 255);
          } else {
            out.data[o] = out.data[o + 1] = out.data[o + 2] = v;
          }
        } else {
          out.data[o] = out.data[o + 1] = out.data[o + 2] = v;
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

/// Pure Dart, so it can run in an isolate.
FrameAnalysis analyzeFrame(CameraFrame frame, {bool smart = true}) {
  final preview = smart ? frame.uprightRgb() : frame.uprightGray();
  final quad = detectPageQuad(preview, workSize: 160, minArea: 0.2, smart: smart);
  // Tracking signatures and the low-light gate retain their original Y-plane semantics.
  final gray = smart ? frame.uprightGray() : preview;
  return FrameAnalysis(
    quad: quad,
    signature: quad == null ? null : pageSignature(gray, quad),
    scene: sceneSignature(gray),
    brightness: meanLuma(gray),
  );
}

typedef FrameAnalyzer = Future<FrameAnalysis> Function(CameraFrame frame);

/// Analyses preview frames off the UI thread. Tests swap in a direct call.
final frameAnalyzerProvider = Provider<FrameAnalyzer>((ref) {
  final smart = ref.watch(planIncludesProvider(PlanFeature.smartScan));
  return (frame) => Isolate.run(() => analyzeFrame(frame, smart: smart));
});

typedef SpreadSplitter = Future<(CropQuad, CropQuad)> Function(String photoPath);

/// Finds the left and right page in a photo of an open book, off the UI
/// thread (Book mode).
final spreadSplitterProvider = Provider<SpreadSplitter>((ref) {
  final smart = ref.watch(planIncludesProvider(PlanFeature.smartScan));
  return (path) =>
      Isolate.run(() => splitSpread(RgbImage.decode(File(path).readAsBytesSync(), maxDimension: 640), smart: smart));
});
