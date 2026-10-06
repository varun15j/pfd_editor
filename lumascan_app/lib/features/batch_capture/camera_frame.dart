import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../imaging/book_split.dart';
import '../../imaging/page_detector.dart';
import '../../imaging/rgb_image.dart';
import 'auto_capture.dart';

/// How the bytes of a [CameraFrame] are laid out.
enum FramePixels {
  /// One byte of brightness per pixel: the Y plane of NV21 or YUV 4:2:0,
  /// which is what Android sends.
  luma,

  /// Four bytes per pixel, blue first: what iOS sends.
  bgra,
}

/// One preview frame, as the camera sends it. Only the brightness is used:
/// page edges and QR codes both show in it, and it is the cheapest part of a
/// frame to copy.
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
    if (pixels == FramePixels.luma && bytesPerRow == width) return bytes.sublist(0, width * height);
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
    if (pixels == FramePixels.luma) return bytes[row + x];
    final i = row + x * 4;
    return (bytes[i] * 29 + bytes[i + 1] * 150 + bytes[i + 2] * 77) >> 8;
  }

  /// A small grey copy, upright, at most [size] pixels on its long side.
  RgbImage uprightGray({int size = 200}) {
    final scale = size / math.max(width, height);
    final w = math.max(8, (width * math.min(1.0, scale)).round());
    final h = math.max(8, (height * math.min(1.0, scale)).round());
    final turned = rotation % 180 != 0;
    final out = RgbImage(turned ? h : w, turned ? w : h);
    final fx = width / w, fy = height / h;
    for (var y = 0; y < h; y++) {
      final row = (y * fy).floor() * bytesPerRow;
      for (var x = 0; x < w; x++) {
        final v = _lumaAt(row, (x * fx).floor());
        final (ox, oy) = switch (rotation % 360) {
          90 => (h - 1 - y, x),
          180 => (w - 1 - x, h - 1 - y),
          270 => (y, w - 1 - x),
          _ => (x, y),
        };
        final o = (oy * out.width + ox) * 3;
        out.data[o] = v;
        out.data[o + 1] = v;
        out.data[o + 2] = v;
      }
    }
    return out;
  }
}

/// What one preview frame shows: the page in it, if any, upright and
/// normalized to the frame, a coarse [pageSignature] of what is printed on
/// it, and how bright the frame is (0..255).
@immutable
class FrameAnalysis {
  const FrameAnalysis({this.quad, this.signature, this.brightness = 128});

  final CropQuad? quad;
  final Float32List? signature;
  final double brightness;

  /// Too dark for auto capture to trust what it sees.
  bool get tooDark => brightness < 45;
}

/// Pure Dart, so it can run in an isolate.
FrameAnalysis analyzeFrame(CameraFrame frame) {
  final gray = frame.uprightGray();
  final quad = detectPageQuad(gray, workSize: 160, minArea: 0.2);
  return FrameAnalysis(
    quad: quad,
    signature: quad == null ? null : pageSignature(gray, quad),
    brightness: meanLuma(gray),
  );
}

typedef FrameAnalyzer = Future<FrameAnalysis> Function(CameraFrame frame);

/// Analyses preview frames off the UI thread. Tests swap in a direct call.
final frameAnalyzerProvider = Provider<FrameAnalyzer>(
  (ref) =>
      (frame) => Isolate.run(() => analyzeFrame(frame)),
);

typedef SpreadSplitter = Future<(CropQuad, CropQuad)> Function(String photoPath);

/// Finds the left and right page in a photo of an open book, off the UI
/// thread (Book mode).
final spreadSplitterProvider = Provider<SpreadSplitter>(
  (ref) =>
      (path) => Isolate.run(() => splitSpread(RgbImage.decode(File(path).readAsBytesSync(), maxDimension: 640))),
);
