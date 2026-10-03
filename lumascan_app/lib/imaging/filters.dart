import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/models.dart';
import 'rgb_image.dart';

/// Applies a document filter preset. Returns a new image; [src] is untouched.
RgbImage applyFilter(RgbImage src, DocumentFilter filter) => switch (filter) {
  DocumentFilter.original => src,
  DocumentFilter.grayscale => grayscale(src),
  DocumentFilter.blackWhite => blackAndWhite(src),
  DocumentFilter.magicColor => magicColor(src),
  DocumentFilter.whiteboard => whiteboard(src),
};

/// Manual brightness and contrast, each from -1 to 1. Brightness shifts every
/// value by up to half the range; contrast stretches around mid grey (-1 is
/// flat grey, 1 doubles the spread). Returns [src] when both are zero.
RgbImage adjustBrightnessContrast(RgbImage src, {double brightness = 0, double contrast = 0}) {
  if (brightness == 0 && contrast == 0) return src;
  final lut = Uint8List(256);
  final gain = 1 + contrast.clamp(-1.0, 1.0);
  final shift = brightness.clamp(-1.0, 1.0) * 128;
  for (var v = 0; v < 256; v++) {
    lut[v] = ((v - 128) * gain + 128 + shift).round().clamp(0, 255);
  }
  final out = RgbImage(src.width, src.height);
  for (var i = 0; i < src.data.length; i++) {
    out.data[i] = lut[src.data[i]];
  }
  return out;
}

/// Perceptual luminance (Rec. 601 weights), one byte per pixel.
Uint8List luminance(RgbImage src) {
  final n = src.width * src.height;
  final s = src.data;
  final out = Uint8List(n);
  for (var i = 0, j = 0; i < n; i++, j += 3) {
    out[i] = (0.299 * s[j] + 0.587 * s[j + 1] + 0.114 * s[j + 2]).round();
  }
  return out;
}

RgbImage _fromGray(int width, int height, Uint8List gray) {
  final out = RgbImage(width, height);
  final d = out.data;
  for (var i = 0, j = 0; i < gray.length; i++, j += 3) {
    d[j] = d[j + 1] = d[j + 2] = gray[i];
  }
  return out;
}

/// Grayscale with a mild contrast stretch so paper reads as near-white.
RgbImage grayscale(RgbImage src) {
  final gray = luminance(src);
  final (lo, hi) = _percentiles(gray, 0.01, 0.99);
  if (hi - lo > 10) {
    final scale = 255.0 / (hi - lo);
    for (var i = 0; i < gray.length; i++) {
      gray[i] = ((gray[i] - lo) * scale).round().clamp(0, 255);
    }
  }
  return _fromGray(src.width, src.height, gray);
}

/// Adaptive (Bradley–Roth) threshold: each pixel is compared against the mean
/// of its neighbourhood, so shadows and uneven light do not turn into black
/// blotches the way a single global cutoff would (docs/document.md 4.3).
RgbImage blackAndWhite(RgbImage src, {double sensitivity = 0.15}) {
  final w = src.width, h = src.height;
  final gray = luminance(src);

  // Integral image; Float64 avoids overflow on large photos.
  final integral = Float64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowSum = 0.0;
    for (var x = 0; x < w; x++) {
      rowSum += gray[y * w + x];
      integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + rowSum;
    }
  }

  final half = math.max(7, math.max(w, h) ~/ 24);
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = math.max(0, y - half), y1 = math.min(h - 1, y + half);
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - half), x1 = math.min(w - 1, x + half);
      final count = (x1 - x0 + 1) * (y1 - y0 + 1);
      final sum =
          integral[(y1 + 1) * (w + 1) + x1 + 1] -
          integral[y0 * (w + 1) + x1 + 1] -
          integral[(y1 + 1) * (w + 1) + x0] +
          integral[y0 * (w + 1) + x0];
      final i = y * w + x;
      out[i] = gray[i] * count < sum * (1.0 - sensitivity) ? 0 : 255;
    }
  }
  _despeckle(out, w, h);
  return _fromGray(w, h, out);
}

/// Removes isolated black pixels with no black 8-neighbours (sensor noise on
/// blank paper). Thin text strokes always have neighbours and survive.
void _despeckle(Uint8List bw, int w, int h) {
  final remove = <int>[];
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      if (bw[i] != 0) continue;
      var dark = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if ((dx != 0 || dy != 0) && bw[i + dy * w + dx] == 0) dark++;
        }
      }
      if (dark == 0) remove.add(i);
    }
  }
  for (final i in remove) {
    bw[i] = 255;
  }
}

/// Enhanced colour: neutralises the paper's colour cast, pushes paper to
/// white and ink to dark per channel, then restores some saturation so stamps
/// and highlighter stay visible.
RgbImage magicColor(RgbImage src) {
  final n = src.width * src.height;
  final s = src.data;
  final out = RgbImage(src.width, src.height);
  final d = out.data;

  final lut = List.generate(3, (_) => Uint8List(256));
  for (var c = 0; c < 3; c++) {
    final channel = Uint8List(n);
    for (var i = 0, j = c; i < n; i++, j += 3) {
      channel[i] = s[j];
    }
    // Paper usually dominates a document, so a high percentile approximates
    // the paper colour and becomes white.
    final (dark, hi) = _percentiles(channel, 0.005, 0.90);
    // Pages with little ink have no dark percentile to speak of, so cap the
    // black point well below the paper level.
    final lo = math.min(dark, (hi * 0.35).round());
    final range = math.max(30, hi - lo);
    for (var v = 0; v < 256; v++) {
      final t = ((v - lo) / range).clamp(0.0, 1.0);
      // Gentle S-curve deepens text without clipping mid tones.
      final curved = t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t);
      lut[c][v] = (255 * (0.35 * t + 0.65 * curved)).round();
    }
  }

  const saturation = 1.25;
  for (var j = 0; j < n * 3; j += 3) {
    final r = lut[0][s[j]], g = lut[1][s[j + 1]], b = lut[2][s[j + 2]];
    final l = 0.299 * r + 0.587 * g + 0.114 * b;
    d[j] = (l + (r - l) * saturation).round().clamp(0, 255);
    d[j + 1] = (l + (g - l) * saturation).round().clamp(0, 255);
    d[j + 2] = (l + (b - l) * saturation).round().clamp(0, 255);
  }
  return out;
}

/// Whiteboard clean-up: divides out the uneven lighting and glare (each
/// channel is compared with its wide-area average), so the board turns an even
/// white and marker strokes stay dark, then boosts colour so red, green and
/// blue pens stay distinct.
RgbImage whiteboard(RgbImage src) {
  final w = src.width, h = src.height;
  final s = src.data;
  final out = RgbImage(w, h);
  final d = out.data;
  final half = math.max(8, math.max(w, h) ~/ 10);

  for (var c = 0; c < 3; c++) {
    // Integral image of this channel; Float64 avoids overflow on big photos.
    final integral = Float64List((w + 1) * (h + 1));
    for (var y = 0; y < h; y++) {
      var rowSum = 0.0;
      for (var x = 0; x < w; x++) {
        rowSum += s[(y * w + x) * 3 + c];
        integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + rowSum;
      }
    }
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - half), y1 = math.min(h - 1, y + half);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - half), x1 = math.min(w - 1, x + half);
        final count = (x1 - x0 + 1) * (y1 - y0 + 1);
        final sum =
            integral[(y1 + 1) * (w + 1) + x1 + 1] -
            integral[y0 * (w + 1) + x1 + 1] -
            integral[(y1 + 1) * (w + 1) + x0] +
            integral[y0 * (w + 1) + x0];
        final local = math.max(1.0, sum / count);
        final i = (y * w + x) * 3 + c;
        // The local average sits a little below the board's own colour, so
        // aim a bit above it to land boards on white.
        d[i] = (s[i] / (local * 1.04) * 255).round().clamp(0, 255);
      }
    }
  }

  const saturation = 1.35;
  for (var j = 0; j < d.length; j += 3) {
    final l = 0.299 * d[j] + 0.587 * d[j + 1] + 0.114 * d[j + 2];
    d[j] = (l + (d[j] - l) * saturation).round().clamp(0, 255);
    d[j + 1] = (l + (d[j + 1] - l) * saturation).round().clamp(0, 255);
    d[j + 2] = (l + (d[j + 2] - l) * saturation).round().clamp(0, 255);
  }
  return out;
}

(int, int) _percentiles(Uint8List values, double low, double high) {
  final hist = List<int>.filled(256, 0);
  for (final v in values) {
    hist[v]++;
  }
  final loTarget = (values.length * low).floor(), hiTarget = (values.length * high).floor();
  var acc = 0, lo = 0, hi = 255;
  var loFound = false;
  for (var v = 0; v < 256; v++) {
    acc += hist[v];
    if (!loFound && acc > loTarget) {
      lo = v;
      loFound = true;
    }
    if (acc > hiTarget) {
      hi = v;
      break;
    }
  }
  return (lo, hi);
}
