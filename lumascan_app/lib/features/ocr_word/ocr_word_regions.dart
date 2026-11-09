import 'dart:typed_data';

import '../../domain/ocr.dart';
import '../../imaging/rgb_image.dart';

/// A part of the page with something on it that is not recognised text: a
/// photo, a chart, a coloured box. Box in pixels of the page image.
typedef PictureBox = ({int x0, int y0, int x1, int y1});

/// Finds the pictures on [page], in both directions: beside text as well as
/// between it. Every recognised line is first painted out, then what is
/// left on the paper is grouped into regions. Text inside a picture (chart
/// labels, a caption written on a photo) is part of that picture: a region
/// takes in the lines whose middle lies within it. Regions that are only
/// straight lines (a page border, rules, table grid lines) are not
/// pictures. Pure Dart, for an isolate.
List<PictureBox> findPictureBoxes(RgbImage page, List<OcrBox> lines) {
  final w = page.width, h = page.height, d = page.data;
  if (w < 16 || h < 16) return const [];
  final luma = Uint8List(w * h);
  final histogram = List.filled(256, 0);
  for (var i = 0; i < w * h; i++) {
    final v = (d[i * 3] * 77 + d[i * 3 + 1] * 150 + d[i * 3 + 2] * 29) >> 8;
    luma[i] = v;
    histogram[v]++;
  }
  final paper = _median(histogram, w * h);

  // The text, a little larger than its boxes, is not ink for this search.
  final text = Uint8List(w * h);
  for (final l in lines) {
    final b = _pixels(l, w, h, grow: 0.25);
    for (var y = b.y0; y < b.y1; y++) {
      text.fillRange(y * w + b.x0, y * w + b.x1, 1);
    }
  }

  // A coarse grid: a cell is inked when enough of it differs from the paper.
  final cell = (w > h ? w : h) ~/ 200 < 4 ? 4 : (w > h ? w : h) ~/ 200;
  final gw = (w + cell - 1) ~/ cell, gh = (h + cell - 1) ~/ cell;
  final inked = Uint8List(gw * gh);
  for (var gy = 0; gy < gh; gy++) {
    for (var gx = 0; gx < gw; gx++) {
      var ink = 0, all = 0;
      for (var y = gy * cell; y < (gy + 1) * cell && y < h; y++) {
        for (var x = gx * cell; x < (gx + 1) * cell && x < w; x++) {
          final i = y * w + x;
          all++;
          if (text[i] == 0 && (luma[i] - paper).abs() > 40) ink++;
        }
      }
      if (ink * 10 >= all) inked[gy * gw + gx] = 1;
    }
  }

  // Close small gaps (a white line inside a photo, bars of a chart), then
  // group the touching cells.
  const reach = 2;
  final grown = Uint8List(gw * gh);
  for (var gy = 0; gy < gh; gy++) {
    for (var gx = 0; gx < gw; gx++) {
      if (inked[gy * gw + gx] == 0) continue;
      for (var y = gy - reach; y <= gy + reach; y++) {
        for (var x = gx - reach; x <= gx + reach; x++) {
          if (x >= 0 && y >= 0 && x < gw && y < gh) grown[y * gw + x] = 1;
        }
      }
    }
  }
  final seen = Uint8List(gw * gh);
  var boxes = <PictureBox>[];
  for (var start = 0; start < gw * gh; start++) {
    if (grown[start] == 0 || seen[start] == 1) continue;
    var minX = gw, minY = gh, maxX = -1, maxY = -1, cells = 0;
    final stack = [start];
    seen[start] = 1;
    while (stack.isNotEmpty) {
      final c = stack.removeLast();
      final cx = c % gw, cy = c ~/ gw;
      if (inked[c] == 1) {
        cells++;
        if (cx < minX) minX = cx;
        if (cx > maxX) maxX = cx;
        if (cy < minY) minY = cy;
        if (cy > maxY) maxY = cy;
      }
      for (final n in [c - 1, c + 1, c - gw, c + gw]) {
        if (n < 0 || n >= gw * gh || seen[n] == 1 || grown[n] == 0) continue;
        if ((n == c - 1 && cx == 0) || (n == c + 1 && cx == gw - 1)) continue;
        seen[n] = 1;
        stack.add(n);
      }
    }
    if (cells == 0) continue;
    final box = (
      x0: minX * cell,
      y0: minY * cell,
      x1: ((maxX + 1) * cell).clamp(0, w),
      y1: ((maxY + 1) * cell).clamp(0, h),
    );
    // Specks, stray marks and thin slivers are not pictures.
    if (box.x1 - box.x0 < w * 0.06 || box.y1 - box.y0 < h * 0.025) continue;
    if (cells * cell * cell < w * h * 0.004) continue;
    boxes.add(box);
  }

  // Text with rules or shading around it stays text. This is judged on the
  // ink alone, before the labels near it are taken in: they would make a
  // shaded paragraph and the lines beside it look like a picture.
  boxes = [
    for (final b in boxes)
      if (!_mostlyText(b, lines, w, h) && !_onlyLines(luma, text, w, b, paper)) b,
  ];
  // Lines inside a picture, or just over or under it, belong to it; boxes
  // that now overlap are one.
  // Judged again once whole: a table that a watermark cut in two is only
  // seen as a table now.
  boxes = _merged([for (final b in boxes) _withLinesInside(b, lines, w, h)]);
  return [
    for (final b in boxes)
      if (!_mostlyText(b, lines, w, h) && !_onlyLines(luma, text, w, b, paper)) _padded(b, w, h),
  ]..sort((a, b) => a.y0.compareTo(b.y0));
}

/// The part of [src] inside [b].
RgbImage cropPicture(RgbImage src, PictureBox b) {
  final w = b.x1 - b.x0, h = b.y1 - b.y0;
  final out = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    final from = ((b.y0 + y) * src.width + b.x0) * 3;
    out.setRange(y * w * 3, (y + 1) * w * 3, src.data, from);
  }
  return RgbImage(w, h, out);
}

/// True when the line's middle lies inside [box] (pixels of a [w] x [h] page).
bool lineInPicture(OcrBox line, PictureBox box, int w, int h) {
  final cx = (line.left + line.right) / 2 * w, cy = (line.top + line.bottom) / 2 * h;
  return cx >= box.x0 && cx <= box.x1 && cy >= box.y0 && cy <= box.y1;
}

PictureBox _withLinesInside(PictureBox b, List<OcrBox> lines, int w, int h) {
  var box = b;
  // A label just over or under a picture (a chart's title, its axis
  // labels) belongs to it too: within a little of its top or bottom edge
  // and no wider than it.
  final near = (h * 0.012).round();
  for (final l in lines) {
    final cx = (l.left + l.right) / 2 * w;
    if (cx < b.x0 || cx > b.x1) continue;
    // The line's own edge, not its middle, is what lies near the picture.
    if (l.bottom * h < b.y0 - near || l.top * h > b.y1 + near) continue;
    if ((l.right - l.left) * w > b.x1 - b.x0) continue;
    final p = _pixels(l, w, h);
    box = (
      x0: p.x0 < box.x0 ? p.x0 : box.x0,
      y0: p.y0 < box.y0 ? p.y0 : box.y0,
      x1: p.x1 > box.x1 ? p.x1 : box.x1,
      y1: p.y1 > box.y1 ? p.y1 : box.y1,
    );
  }
  return box;
}

List<PictureBox> _merged(List<PictureBox> boxes) {
  final out = [...boxes];
  var changed = true;
  while (changed) {
    changed = false;
    for (var i = 0; i < out.length && !changed; i++) {
      for (var j = i + 1; j < out.length && !changed; j++) {
        final a = out[i], b = out[j];
        if (a.x0 < b.x1 && b.x0 < a.x1 && a.y0 < b.y1 && b.y0 < a.y1) {
          out[i] = (
            x0: a.x0 < b.x0 ? a.x0 : b.x0,
            y0: a.y0 < b.y0 ? a.y0 : b.y0,
            x1: a.x1 > b.x1 ? a.x1 : b.x1,
            y1: a.y1 > b.y1 ? a.y1 : b.y1,
          );
          out.removeAt(j);
          changed = true;
        }
      }
    }
  }
  return out;
}

/// True when [b] is text with lines or shading around it (a table, a
/// bordered or shaded paragraph) rather than a picture with a few labels:
/// many lines in it, or text over much of it. That text stays editable.
bool _mostlyText(PictureBox b, List<OcrBox> lines, int w, int h) {
  final inside = [
    for (final l in lines)
      if (lineInPicture(l, b, w, h)) l,
  ];
  final area = (b.x1 - b.x0) * (b.y1 - b.y0);
  if (inside.isEmpty || area == 0) return false;
  var covered = 0.0;
  for (final l in inside) {
    covered += (l.right - l.left) * w * (l.bottom - l.top) * h;
  }
  final share = covered / area;
  // A table: many lines. A bordered or shaded paragraph: a line or two
  // filling much of its box. A chart or photo has a few small labels.
  return inside.length >= 10 ||
      (inside.length >= 4 && share >= 0.1) ||
      (inside.length <= 2 && share >= 0.2) ||
      share >= 0.4 ||
      _inGrid(inside) >= 4;
}

/// How many of [lines] sit in a grid: in the same column as a line of
/// another row. Table cells do; a chart's labels run along one row (the
/// x axis) or one column (the y axis), not both.
int _inGrid(List<OcrBox> lines) {
  var n = 0;
  for (final a in lines) {
    final ax = (a.left + a.right) / 2, ay = (a.top + a.bottom) / 2, ah = a.bottom - a.top;
    final column = lines.any((b) {
      if (identical(a, b)) return false;
      final bx = (b.left + b.right) / 2, by = (b.top + b.bottom) / 2;
      return (ax - bx).abs() < 0.01 && (ay - by).abs() > ah;
    });
    final row = lines.any((b) {
      if (identical(a, b)) return false;
      final bx = (b.left + b.right) / 2, by = (b.top + b.bottom) / 2;
      return (ay - by).abs() < ah / 2 && (ax - bx).abs() > a.right - a.left;
    });
    if (column && row) n++;
  }
  return n;
}

/// True when, with the text painted out, all that is in [b] is long straight
/// runs of ink: a border, rules, the grid of a table whose text was read.
bool _onlyLines(Uint8List luma, Uint8List text, int w, PictureBox b, int paper) {
  final bw = b.x1 - b.x0, bh = b.y1 - b.y0;
  bool ink(int x, int y) {
    final i = (b.y0 + y) * w + b.x0 + x;
    return text[i] == 0 && (luma[i] - paper).abs() > 40;
  }

  final lineRow = List.filled(bh, false), lineCol = List.filled(bw, false);
  for (var y = 0; y < bh; y++) {
    var run = 0;
    for (var x = 0; x < bw && !lineRow[y]; x++) {
      run = ink(x, y) ? run + 1 : 0;
      if (run >= bw / 3) lineRow[y] = true;
    }
  }
  for (var x = 0; x < bw; x++) {
    var run = 0;
    for (var y = 0; y < bh && !lineCol[x]; y++) {
      run = ink(x, y) ? run + 1 : 0;
      if (run >= bh / 3) lineCol[x] = true;
    }
  }
  // Many of them make a filled area (a coloured box, a photo), not lines.
  if (lineRow.where((l) => l).length > bh * 0.15 || lineCol.where((l) => l).length > bw * 0.15) return false;
  var off = 0;
  for (var y = 0; y < bh; y++) {
    if (lineRow[y]) continue;
    for (var x = 0; x < bw; x++) {
      if (!lineCol[x] && ink(x, y)) off++;
    }
  }
  return off < bw * bh * 0.01;
}

PictureBox _padded(PictureBox b, int w, int h) {
  final pad = (w * 0.006).round();
  return (
    x0: (b.x0 - pad).clamp(0, w),
    y0: (b.y0 - pad).clamp(0, h),
    x1: (b.x1 + pad).clamp(0, w),
    y1: (b.y1 + pad).clamp(0, h),
  );
}

PictureBox _pixels(OcrBox l, int w, int h, {double grow = 0}) {
  final g = (l.bottom - l.top) * grow;
  return (
    x0: ((l.left - g * h / w) * w).floor().clamp(0, w),
    y0: ((l.top - g) * h).floor().clamp(0, h),
    x1: ((l.right + g * h / w) * w).ceil().clamp(0, w),
    y1: ((l.bottom + g) * h).ceil().clamp(0, h),
  );
}

int _median(List<int> histogram, int count) {
  var seen = 0;
  for (var v = 0; v < 256; v++) {
    seen += histogram[v];
    if (seen * 2 >= count) return v;
  }
  return 255;
}
