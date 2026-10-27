import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'ocr.dart';

/// A table read from a page: rows of cells, every row as long as the
/// widest one. An empty string is an empty cell.
@immutable
class ExtractedTable {
  const ExtractedTable(this.rows);

  final List<List<String>> rows;

  int get rowCount => rows.length;
  int get columnCount => rows.isEmpty ? 0 : rows.first.length;
  bool get isEmpty => rows.isEmpty;

  ExtractedTable withCell(int row, int column, String text) => ExtractedTable([
    for (var r = 0; r < rows.length; r++)
      r == row ? [for (var c = 0; c < rows[r].length; c++) c == column ? text : rows[r][c]] : rows[r],
  ]);
}

/// Turns the words OCR found on a photo of a table into rows and columns,
/// on the device. It needs no ruled lines: words at the same height make a
/// row, words close together make a cell, and the gaps that run down the
/// whole table split the columns.
class TableExtractor {
  const TableExtractor();

  /// A gap wider than this many text heights ends a cell. A space between
  /// two words is about a third of a text height.
  static const _cellGap = 0.9;

  ExtractedTable extract(OcrLayout layout) {
    final words = [
      for (final block in layout.blocks)
        for (final line
            in block.lines.isEmpty
                ? [
                    OcrLine(
                      text: block.text,
                      left: block.left,
                      top: block.top,
                      right: block.right,
                      bottom: block.bottom,
                    ),
                  ]
                : block.lines)
          if (line.words.isEmpty) line else ...line.words,
    ].where((w) => w.text.trim().isNotEmpty && w.bottom > w.top).toList();
    if (words.isEmpty) return const ExtractedTable([]);

    final height = _median([for (final w in words) w.bottom - w.top]);
    final rows = _rows(words).map((row) => _cells(row, height)).toList();
    final bands = _columnBands(rows);

    final table = <List<String>>[];
    for (final row in rows) {
      final cells = List.filled(bands.length, '');
      for (final cell in row) {
        // A single wide line, such as a title over the table, starts at the left.
        final spansMany = row.length == 1 && bands.where((b) => _overlap(cell, b) > 0).length > 1;
        final column = spansMany ? 0 : _bestBand(cell, bands);
        cells[column] = cells[column].isEmpty ? cell.text : '${cells[column]} ${cell.text}';
      }
      table.add(cells);
    }
    return ExtractedTable(_dropEmptyColumns(table));
  }

  /// A word joins the row above when at least half of its height overlaps
  /// the row's band, so a tall word such as "Sugar" or a slight tilt does
  /// not split a row. Rows run top to bottom, words in a row left to right.
  static List<List<OcrBox>> _rows(List<OcrBox> words) {
    final sorted = [...words]..sort((a, b) => _middleY(a).compareTo(_middleY(b)));
    final rows = <List<OcrBox>>[];
    var top = 0.0, bottom = 0.0;
    for (final w in sorted) {
      final overlap = math.min(bottom, w.bottom) - math.max(top, w.top);
      if (rows.isEmpty || overlap < 0.5 * math.min(w.bottom - w.top, bottom - top)) {
        rows.add([w]);
        top = w.top;
        bottom = w.bottom;
      } else {
        final row = rows.last..add(w);
        top = row.map((b) => b.top).reduce((a, b) => a + b) / row.length;
        bottom = row.map((b) => b.bottom).reduce((a, b) => a + b) / row.length;
      }
    }
    for (final row in rows) {
      row.sort((a, b) => a.left.compareTo(b.left));
    }
    return rows;
  }

  /// Joins the words of one row into cells: a gap wider than [_cellGap] text
  /// heights starts a new cell.
  static List<OcrBox> _cells(List<OcrBox> row, double height) {
    final cells = <OcrBox>[];
    for (final w in row) {
      final last = cells.isEmpty ? null : cells.last;
      if (last != null && w.left - last.right < height * _cellGap) {
        cells[cells.length - 1] = OcrBox(
          text: '${last.text} ${w.text}',
          left: last.left,
          top: math.min(last.top, w.top),
          right: math.max(last.right, w.right),
          bottom: math.max(last.bottom, w.bottom),
        );
      } else {
        cells.add(OcrBox(text: w.text.trim(), left: w.left, top: w.top, right: w.right, bottom: w.bottom));
      }
    }
    return cells;
  }

  /// The columns, as left and right edges. Every row with two or more cells
  /// marks the width its cells cover; a strip of the page that almost no
  /// row covers is a gap between columns. One stray cell that bridges a gap
  /// does not merge two columns.
  static List<(double, double)> _columnBands(List<List<OcrBox>> rows) {
    final tableRows = rows.where((r) => r.length > 1).toList();
    if (tableRows.isEmpty) return [(0, 1)];
    const bins = 500;
    final cover = List.filled(bins, 0);
    for (final row in tableRows) {
      final hit = List.filled(bins, false);
      for (final cell in row) {
        final from = (cell.left * bins).floor().clamp(0, bins - 1);
        final to = (cell.right * bins).ceil().clamp(0, bins - 1);
        for (var i = from; i <= to; i++) {
          hit[i] = true;
        }
      }
      for (var i = 0; i < bins; i++) {
        if (hit[i]) cover[i]++;
      }
    }
    final threshold = math.max(0, (tableRows.length * 0.1).floor());
    final bands = <(double, double)>[];
    int? start;
    for (var i = 0; i <= bins; i++) {
      final covered = i < bins && cover[i] > threshold;
      if (covered && start == null) start = i;
      if (!covered && start != null) {
        bands.add((start / bins, i / bins));
        start = null;
      }
    }
    return bands.isEmpty ? [(0, 1)] : bands;
  }

  static int _bestBand(OcrBox cell, List<(double, double)> bands) {
    var best = 0;
    var bestScore = double.negativeInfinity;
    for (var i = 0; i < bands.length; i++) {
      final overlap = _overlap(cell, bands[i]);
      // With no overlap at all, the nearest band wins.
      final score = overlap > 0 ? overlap : -_distance(cell, bands[i]);
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
  }

  static double _overlap(OcrBox cell, (double, double) band) =>
      math.max(0, math.min(cell.right, band.$2) - math.max(cell.left, band.$1));

  static double _distance(OcrBox cell, (double, double) band) =>
      cell.right < band.$1 ? band.$1 - cell.right : cell.left - band.$2;

  static List<List<String>> _dropEmptyColumns(List<List<String>> table) {
    if (table.isEmpty) return table;
    final keep = [
      for (var c = 0; c < table.first.length; c++)
        if (table.any((row) => row[c].isNotEmpty)) c,
    ];
    return [
      for (final row in table) [for (final c in keep) row[c]],
    ];
  }

  static double _middleY(OcrBox b) => (b.top + b.bottom) / 2;

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }
}
