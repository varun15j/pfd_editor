import 'dart:math' as math;

import '../domain/models.dart';
import 'rgb_image.dart';

/// Trims a page outline down to the one page in focus when a second page is
/// only partly in view: an open book held over its left page with part of
/// the right page showing, or a sheet lying next to the edge of another.
///
/// The pages meet at a seam, a narrow line darker than the paper on both
/// sides of it (the gutter shadow of a book, or the shadowed edge of a
/// sheet). When the part beyond the seam runs off the edge of the frame and
/// is narrower than the page, it is a cut-off neighbour and is dropped. Two
/// whole pages side by side, a book spread both of whose pages are in view,
/// are kept together.
CropQuad focusOnePage(RgbImage image, CropQuad quad) {
  // Across (left and right pages), then down (pages above and below).
  return _trim(image, quad, across: true) ?? _trim(image, quad, across: false) ?? quad;
}

/// Frame edge closer than this counts as the page running off the frame.
const _edge = 0.02;

/// How much brighter the next page must be, within a few steps of the seam,
/// for a one-sided seam.
const _step = 18;

/// A cut-off part must be at most this wide, relative to the page kept.
const _partRatio = 0.85;

CropQuad? _trim(RgbImage image, CropQuad quad, {required bool across}) {
  final seam = _seam(image, quad, across: across);
  if (seam == null) return null;
  // The two outer sides of the quad along the seam direction.
  final startCut = across ? quad.tl.x <= _edge && quad.bl.x <= _edge : quad.tl.y <= _edge && quad.tr.y <= _edge;
  final endCut = across
      ? quad.tr.x >= 1 - _edge && quad.br.x >= 1 - _edge
      : quad.bl.y >= 1 - _edge && quad.br.y >= 1 - _edge;
  if (startCut == endCut) return null;
  final start = seam, end = 1 - seam;
  if (endCut && end <= start * _partRatio) return _part(quad, 0, seam, across: across);
  if (startCut && start <= end * _partRatio) return _part(quad, seam, 1, across: across);
  return null;
}

/// The part of [quad] between fractions [from] and [to] across (or down).
CropQuad _part(CropQuad quad, double from, double to, {required bool across}) {
  NormPoint lerp(NormPoint a, NormPoint b, double t) => NormPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
  if (across) {
    return CropQuad(
      lerp(quad.tl, quad.tr, from),
      lerp(quad.tl, quad.tr, to),
      lerp(quad.bl, quad.br, to),
      lerp(quad.bl, quad.br, from),
    );
  }
  return CropQuad(
    lerp(quad.tl, quad.bl, from),
    lerp(quad.tr, quad.br, from),
    lerp(quad.tr, quad.br, to),
    lerp(quad.tl, quad.bl, to),
  );
}

/// Where a seam crosses [quad], as a fraction across (or down) it, or null
/// when there is none. Paper brightness is measured along lines parallel to
/// the seam (the upper quartile, so ink does not count); the seam is the
/// deepest dip that is clearly darker than the paper just beside it on both
/// sides. A page curving into a book's gutter darkens gradually and then
/// meets the next page in a sharp step, so a dip that is the darkest point
/// around it with a sharp rise on one side counts too. Text columns and
/// paragraphs do not count: the paper next to them is as bright as they are.
double? _seam(RgbImage image, CropQuad quad, {required bool across}) {
  const steps = 100, samples = 40;
  final profile = List<double>.filled(steps + 1, 0);
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final line = <double>[];
    for (var j = 0; j < samples; j++) {
      // Skip the outer tenth, where page corners curl and fingers sit.
      final s = 0.1 + 0.8 * j / (samples - 1);
      final (u, v) = across ? (t, s) : (s, t);
      line.add(_luma(image, _at(quad, u, v)));
    }
    line.sort();
    profile[i] = line[samples * 3 ~/ 4];
  }
  final smooth = [
    for (var i = 0; i <= steps; i++)
      [for (var k = i - 1; k <= i + 1; k++) profile[k.clamp(0, steps)]].reduce((a, b) => a + b) / 3,
  ];
  double? best;
  var bestDepth = 0.0;
  for (var i = (steps * 0.15).round(); i <= (steps * 0.85).round(); i++) {
    // The paper beside the dip: the brightest of a band on each side.
    final before = smooth.sublist(i - 12, i - 2).reduce(math.max);
    final after = smooth.sublist(i + 3, i + 13).reduce(math.max);
    var depth = math.min(before, after) - smooth[i];
    if (depth < math.max(14, 0.12 * math.min(before, after))) {
      // One-sided: the darkest point around, with a sharp step up beside it.
      final around = smooth.sublist(i - 12, i + 13).reduce(math.min);
      final step = math.max(smooth.sublist(i + 1, i + 5).reduce(math.max), smooth.sublist(i - 4, i).reduce(math.max));
      depth = smooth[i] <= around && step - smooth[i] >= _step ? step - smooth[i] : 0;
    }
    if (depth > 0 && depth > bestDepth) {
      bestDepth = depth;
      best = i / steps;
    }
  }
  return best;
}

NormPoint _at(CropQuad q, double u, double v) {
  final top = NormPoint(q.tl.x + (q.tr.x - q.tl.x) * u, q.tl.y + (q.tr.y - q.tl.y) * u);
  final bottom = NormPoint(q.bl.x + (q.br.x - q.bl.x) * u, q.bl.y + (q.br.y - q.bl.y) * u);
  return NormPoint(top.x + (bottom.x - top.x) * v, top.y + (bottom.y - top.y) * v);
}

double _luma(RgbImage image, NormPoint p) {
  final x = (p.x * (image.width - 1)).round().clamp(0, image.width - 1);
  final y = (p.y * (image.height - 1)).round().clamp(0, image.height - 1);
  final i = (y * image.width + x) * 3;
  final d = image.data;
  return (d[i] * 77 + d[i + 1] * 150 + d[i + 2] * 29) / 256;
}
