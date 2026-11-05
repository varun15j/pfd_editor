import 'dart:typed_data';

import 'package:luma_docx/luma_docx.dart';

import '../../domain/ocr.dart';

/// One page of recognised text to put in a Word file: the text, and where
/// each block and line sat when the engine reports it.
class OcrWordPage {
  const OcrWordPage({required this.text, this.layout, this.landscape = false});

  final String text;
  final OcrLayout? layout;

  /// A page wider than it is tall becomes a landscape A4 page.
  final bool landscape;
}

/// OCR to Word (Pro and Gold, the luma_docx library): builds an editable
/// .docx file from recognised pages. Kept apart from the Basic Word export
/// (lib/export/word), which stays as it is.
Uint8List buildOcrWordFile(List<OcrWordPage> pages, {String? title}) =>
    WordWriter.write(buildOcrWordDocument(pages, title: title));

/// The Word document behind [buildOcrWordFile]. Each scanned page becomes
/// one A4 page (its own section). The layout is rebuilt from where the
/// lines sat: headings from larger type, centred and right-aligned lines,
/// indents, bullet and numbered lists, and tables from text in rows and
/// columns. Without a layout the text goes in paragraph by paragraph.
WordDocument buildOcrWordDocument(List<OcrWordPage> pages, {String? title}) {
  final b = _Builder();
  final sections = <WordSection>[
    for (final p in pages)
      () {
        final blocks = b.page(p);
        return WordSection(
          pageWidth: b.width,
          pageHeight: b.height,
          landscape: p.landscape,
          margins: const WordInsets(top: 54, right: 54, bottom: 54, left: 54),
          // Numbers printed down the margin become Word's line numbering.
          lineNumbers: b.lineNumbers ? const WordLineNumbers(restart: 'newPage') : null,
          blocks: blocks,
        );
      }(),
  ];
  if (sections.isEmpty) {
    sections.add(
      WordSection(
        pageWidth: _pageW,
        pageHeight: _pageH,
        margins: const WordInsets(top: 72, right: 72, bottom: 72, left: 72),
        blocks: [b.para('')],
      ),
    );
  }
  return WordDocument(
    sections: sections,
    properties: WordProperties(title: title, application: 'LumaScan OCR to Word'),
    headings: b.headings,
  );
}

const _pageW = 595.3;
const _pageH = 841.9;
const _margin = 54.0;
const _font = 'Calibri';

/// A line's box is a little taller than its type (ascenders and descenders).
const _boxToFont = 1.2;

final _bullet = RegExp(r'^([•●▪◦○■□➢►✓\-–\*·])\s+');
final _number = RegExp(r'^(\d{1,3})[.)]\s+');

class _Line {
  _Line(this.text, this.left, this.top, this.right, this.bottom, this.block);

  final String text;
  final double left, top, right, bottom; // points on the A4 page
  final int block;
  int? table;

  double get height => bottom - top;
  double get size => _round(height / _boxToFont);
  double get centre => (left + right) / 2;
}

double _round(double v) => ((v * 2).round() / 2).clamp(6, 48).toDouble();

class _Builder {
  var _index = 0;
  var _lists = 0;
  final headings = <WordHeading>[];

  /// Whether the last page built had line numbers down its margin.
  var lineNumbers = false;

  WordParagraph para(String text, {WordRunStyle style = const WordRunStyle(), WordParagraphStyle? p}) => WordParagraph(
    index: _index++,
    style: p ?? const WordParagraphStyle(spaceAfter: 6),
    inlines: [if (text.isNotEmpty) WordText(text, style)],
  );

  /// Size of the page being built, in points.
  var width = _pageW;
  var height = _pageH;

  List<WordBlock> page(OcrWordPage page) {
    lineNumbers = false;
    width = page.landscape ? _pageH : _pageW;
    height = page.landscape ? _pageW : _pageH;
    final layout = page.layout;
    if (layout == null || layout.blocks.isEmpty) return _plain(page.text);
    final lines = <_Line>[];
    for (final (i, b) in layout.blocks.indexed) {
      final ls = b.lines.isEmpty ? <OcrBox>[b] : b.lines;
      for (final l in ls) {
        final t = l.text.trim();
        if (t.isEmpty) continue;
        lines.add(_Line(t, l.left * width, l.top * height, l.right * width, l.bottom * height, i));
      }
    }
    if (lines.isEmpty) return _plain(page.text);
    return _layout(_readingOrder(_withoutLineNumbers(_withoutOverprint(lines))));
  }

  /// Engines report blocks in their own order (ML Kit does not always go
  /// top to bottom). Blocks are put in order of where they start on the
  /// page, keeping each block's lines together.
  List<_Line> _readingOrder(List<_Line> lines) {
    final tops = <int, double>{};
    for (final l in lines) {
      tops[l.block] = tops[l.block] == null || l.top < tops[l.block]! ? l.top : tops[l.block]!;
    }
    final order = [...lines.indexed];
    order.sort((a, b) {
      final byBlock = tops[a.$2.block]!.compareTo(tops[b.$2.block]!);
      if (byBlock != 0 && a.$2.block != b.$2.block) return byBlock;
      if (a.$2.block != b.$2.block) return a.$2.block.compareTo(b.$2.block);
      return a.$1.compareTo(b.$1);
    });
    return [for (final (_, l) in order) l];
  }

  /// Drops large text printed across other text, such as a SAMPLE or
  /// DRAFT watermark: it is not part of the reading flow, and left in it
  /// would break the paragraphs and table rows it crosses.
  List<_Line> _withoutOverprint(List<_Line> lines) {
    bool crosses(_Line a, _Line b) =>
        a.block != b.block && a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
    final kept = [
      for (final l in lines)
        if (!(l.height > 2 * _median(lines) && lines.any((o) => crosses(l, o)))) l,
    ];
    return kept.isEmpty ? lines : kept;
  }

  /// Line numbers (Layout > Line Numbers) are small numbers in a column
  /// left of all the other text. Kept in the flow they would pair with
  /// every line and turn the page into a table, so they are taken out and
  /// the page gets Word's own line numbering instead.
  List<_Line> _withoutLineNumbers(List<_Line> lines) {
    // OCR may read a number alone ("12", "12.") or join it to the text of
    // its line ("12 Table of Contents").
    final alone = RegExp(r'^\d{1,4}[.;:,]?$');
    final joined = RegExp(r'^\d{1,4}\s+(?=\S)');
    final numbers = lines.where((l) => alone.hasMatch(l.text)).toList();
    final prefixed = lines.where((l) => joined.hasMatch(l.text)).toList();
    final edgeOf = numbers.length >= 3 ? numbers : (prefixed.length >= 5 ? prefixed : null);
    if (edgeOf == null) return lines;
    final edge = edgeOf.map((l) => l.left).reduce((a, b) => a < b ? a : b);
    final column = numbers.where((l) => l.left - edge < 12).toSet();
    final starts = prefixed.where((l) => l.left - edge < 12).toSet();
    if (column.length + starts.length < 3) return lines;
    final columnRight = column.isEmpty ? edge + 20 : column.map((l) => l.right).reduce((a, b) => a > b ? a : b);
    final others = lines.where((l) => !column.contains(l) && !starts.contains(l)).toList();
    // Nearly all the other text starts clear of the column (a line set out
    // into the margin may not).
    final clear = others.where((l) => l.left - columnRight >= 12).length;
    if (others.isNotEmpty && clear < others.length * 0.95) return lines;
    lineNumbers = true;
    return [
      for (final l in lines)
        if (column.contains(l))
          ...<_Line>[]
        else if (starts.contains(l))
          () {
            final cut = joined.firstMatch(l.text)!.end;
            final left = l.left + (l.right - l.left) * cut / l.text.length;
            return _Line(l.text.substring(cut), left, l.top, l.right, l.bottom, l.block);
          }()
        else
          l,
    ];
  }

  double _median(List<_Line> lines) {
    final h = [for (final l in lines) l.height]..sort();
    return h[h.length ~/ 2];
  }

  List<WordBlock> _plain(String text) {
    final out = <WordBlock>[];
    for (final chunk in text.split(RegExp(r'\n\s*\n'))) {
      final t = chunk.trim();
      if (t.isEmpty) continue;
      final parts = t.split('\n');
      out.add(
        WordParagraph(
          index: _index++,
          style: const WordParagraphStyle(spaceAfter: 8),
          inlines: [
            for (final (i, s) in parts.indexed) ...[
              if (i > 0) const WordBreak(WordBreakKind.line),
              WordText(s.trim(), const WordRunStyle(font: _font)),
            ],
          ],
        ),
      );
    }
    return out.isEmpty ? [para('')] : out;
  }

  List<WordBlock> _layout(List<_Line> lines) {
    // Body size: the size most of the text is in.
    final sizes = [
      for (final l in lines)
        for (var i = 0; i < l.text.length; i++) l.size,
    ]..sort();
    final body = sizes[sizes.length ~/ 2];
    final left = lines.map((l) => l.left).reduce((a, b) => a < b ? a : b);
    final right = lines.map((l) => l.right).reduce((a, b) => a > b ? a : b);
    final tables = _findTables(lines, body);

    final out = <WordBlock>[];
    double? lastBottom;
    final done = <int>{};
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (line.table != null) {
        if (done.add(line.table!)) {
          final rows = tables[line.table!];
          out.add(_table(rows, left, right));
          lastBottom = rows.last.map((l) => l.bottom).reduce((a, b) => a > b ? a : b);
        }
        i++;
        continue;
      }
      // A paragraph: lines of one block that follow on from each other.
      final group = <_Line>[line];
      var j = i + 1;
      while (j < lines.length) {
        final next = lines[j];
        final prev = group.last;
        if (next.table != null || next.block != line.block) break;
        if (_bullet.hasMatch(next.text) || _number.hasMatch(next.text)) break;
        if (next.top - prev.bottom > prev.height * 0.8) break;
        if ((next.size - prev.size).abs() > body * 0.25) break;
        group.add(next);
        j++;
      }
      out.add(_paragraph(group, body, left, right, lastBottom));
      lastBottom = group.last.bottom;
      i = j;
    }
    return out;
  }

  WordParagraph _paragraph(List<_Line> group, double body, double left, double right, double? lastBottom) {
    final sizes = [for (final l in group) l.size]..sort();
    final size = sizes[sizes.length ~/ 2];
    final first = group.first;
    final width = right - left;
    final heading = group.length <= 3 && size >= body * 1.3;
    final level = !heading ? null : (size >= body * 1.7 ? 1 : 2);

    WordAlign align = WordAlign.left;
    final centred = group.every(
      (l) => (l.centre - (left + right) / 2).abs() < width * 0.04 && l.left - left > width * 0.08,
    );
    final righted = group.every((l) => (right - l.right) < width * 0.02 && l.left - left > width * 0.3);
    if (centred) {
      align = WordAlign.center;
    } else if (righted) {
      align = WordAlign.right;
    } else if (group.length > 2 && group.sublist(0, group.length - 1).every((l) => right - l.right < width * 0.03)) {
      align = WordAlign.justify;
    }

    // Lists.
    var text0 = first.text;
    WordListLabel? list;
    final run = WordRunStyle(font: _font, size: size, bold: heading);
    final bullet = _bullet.firstMatch(text0);
    final number = _number.firstMatch(text0);
    if (bullet != null) {
      text0 = text0.substring(bullet.end);
      list = WordListLabel(text: '•', style: run, listId: 'ocr-bullet', format: 'bullet', pattern: '•');
    } else if (number != null) {
      final n = int.parse(number.group(1)!);
      if (n == 1) _lists++;
      text0 = text0.substring(number.end);
      list = WordListLabel(text: '$n.', style: run, listId: 'ocr-num-$_lists', pattern: '%1.', start: 1);
    }

    final indent = align == WordAlign.left && list == null ? (first.left - left).clamp(0, 144).toDouble() : 0.0;
    final gap = lastBottom == null ? 0.0 : (first.top - lastBottom - body * 0.6).clamp(0, 36).toDouble();
    // Short lines that do not reach the right side (an address, a poem)
    // keep their line breaks; full lines flow together.
    final inlines = <WordInline>[];
    for (final (k, l) in group.indexed) {
      final t = k == 0 ? text0 : l.text;
      if (k > 0) {
        final prev = group[k - 1];
        final short = align == WordAlign.left && right - prev.right > width * 0.25;
        if (short) {
          inlines.add(const WordBreak(WordBreakKind.line));
        } else {
          final last = inlines.last as WordText;
          inlines.last = WordText(last.text.endsWith('-') ? last.text : '${last.text} ', last.style);
        }
      }
      inlines.add(WordText(t, run));
    }

    final index = _index++;
    if (level != null) {
      headings.add(WordHeading(level: level, text: group.map((l) => l.text).join(' '), paragraphIndex: index));
    }
    return WordParagraph(
      index: index,
      style: WordParagraphStyle(
        align: align,
        indentLeft: list != null ? 36 : (indent < 12 ? 0 : indent),
        firstLine: list != null ? -18 : 0,
        spaceBefore: (gap / 3).roundToDouble() * 3,
        spaceAfter: 4,
        outlineLevel: level == null ? null : level - 1,
        keepNext: heading,
      ),
      styleId: level == null ? null : 'Heading$level',
      styleName: level == null ? null : 'heading $level',
      headingLevel: level,
      list: list,
      inlines: inlines,
    );
  }

  /// Marks lines that sit side by side in rows and columns as table cells
  /// and returns each table's rows, top to bottom, cells left to right.
  List<List<List<_Line>>> _findTables(List<_Line> lines, double body) {
    // Rows: lines whose middles share a band.
    final sorted = [...lines]..sort((a, b) => a.top.compareTo(b.top));
    final rows = <List<_Line>>[];
    for (final l in sorted) {
      final mid = (l.top + l.bottom) / 2;
      final row = rows.isEmpty ? null : rows.last;
      if (row != null && row.any((o) => mid > o.top && mid < o.bottom && o.block != l.block)) {
        row.add(l);
      } else {
        rows.add([l]);
      }
    }
    for (final r in rows) {
      r.sort((a, b) => a.left.compareTo(b.left));
    }
    // A run of at least two rows with two or more cells each, the cells
    // apart from each other, is a table. A line alone in a row between
    // them continues a cell above it (wrapped text).
    final tables = <List<List<_Line>>>[];
    var k = 0;
    bool multi(List<_Line> r) {
      if (r.length < 2) return false;
      for (var i = 1; i < r.length; i++) {
        if (r[i].left - r[i - 1].right < body * 0.8) return false;
      }
      return true;
    }

    while (k < rows.length) {
      if (!multi(rows[k])) {
        k++;
        continue;
      }
      final run = <List<_Line>>[rows[k]];
      // Column edges seen so far: each cell of a later row must line up with
      // one of them on its left or right side (numbers sit on the right).
      final lefts = [for (final l in rows[k]) l.left];
      final rights = [for (final l in rows[k]) l.right];
      bool fits(List<_Line> r) =>
          r.every((l) => lefts.any((x) => (x - l.left).abs() < body) || rights.any((x) => (x - l.right).abs() < body));
      var m = k + 1;
      while (m < rows.length) {
        final r = rows[m];
        final prevBottom = run.last.map((l) => l.bottom).reduce((a, b) => a > b ? a : b);
        if (r.first.top - prevBottom > body * 3) break;
        if (multi(r) && fits(r)) {
          lefts.addAll(r.map((l) => l.left));
          rights.addAll(r.map((l) => l.right));
          run.add(r);
        } else if (r.length == 1 &&
            r.first.left > run.first.first.left + body &&
            m + 1 < rows.length &&
            multi(rows[m + 1])) {
          run.add(r); // wrapped text of a cell
        } else {
          break;
        }
        m++;
      }
      final full = run.where(multi).length;
      if (full >= 2) {
        final id = tables.length;
        for (final r in run) {
          for (final l in r) {
            l.table = id;
          }
        }
        // The same table split by a row that was read badly: join them,
        // with the rows between.
        final last = tables.isEmpty ? null : tables.last;
        if (last != null && _sameColumns(last, run, body)) {
          final from = rows.indexOf(last.last) + 1;
          final between = rows.sublist(from, k);
          final gap = run.first.first.top - last.last.map((l) => l.bottom).reduce((a, b) => a > b ? a : b);
          if (between.length <= 3 && gap < body * 8) {
            for (final r in [...between, ...run]) {
              for (final l in r) {
                l.table = tables.length - 1;
              }
            }
            last.addAll([...between, ...run]);
            k = m;
            continue;
          }
        }
        tables.add(run);
        k = m;
      } else {
        k++;
      }
    }
    return tables;
  }

  bool _sameColumns(List<List<_Line>> a, List<List<_Line>> b, double body) {
    List<double> starts(List<List<_Line>> t) => [
      for (final l in t.reduce((x, y) => y.length > x.length ? y : x)) l.left,
    ];
    final sa = starts(a);
    final sb = starts(b);
    return sa.length == sb.length &&
        [for (var i = 0; i < sa.length; i++) (sa[i] - sb[i]).abs() < body * 2].every((v) => v);
  }

  WordTable _table(List<List<_Line>> rows, double left, double right) {
    // Columns: where cells start, from the row with the most cells.
    final widest = rows.reduce((a, b) => b.length > a.length ? b : a);
    final starts = [for (final l in widest) l.left];
    int columnOf(_Line l) {
      var best = 0;
      for (var c = 0; c < starts.length; c++) {
        if (l.left >= starts[c] - 8) best = c;
      }
      return best;
    }

    final grid = <List<List<_Line>>>[];
    for (final r in rows) {
      if (r.length == 1 && grid.isNotEmpty) {
        grid.last[columnOf(r.first)].add(r.first); // wrapped text of a cell
        continue;
      }
      final cells = List.generate(starts.length, (_) => <_Line>[]);
      for (final l in r) {
        cells[columnOf(l)].add(l);
      }
      grid.add(cells);
    }
    final edges = [...starts, right + 6];
    final widths = [for (var c = 0; c < starts.length; c++) (edges[c + 1] - edges[c]).clamp(24, 600).toDouble()];
    final total = widths.fold<double>(0, (a, b) => a + b);
    final usable = width - 2 * _margin;
    final scale = total > usable ? usable / total : 1.0;
    const line = WordBorder(style: 'single', width: 0.5);
    return WordTable(
      columns: [for (final w in widths) w * scale],
      rows: [
        for (final r in grid)
          WordTableRow(
            cells: [
              for (final c in r)
                WordTableCell(
                  borders: const WordBorders(top: line, bottom: line, left: line, right: line),
                  blocks: [
                    WordParagraph(
                      index: _index++,
                      style: WordParagraphStyle(
                        align: c.isNotEmpty && RegExp(r'^[\d.,%₹$-]+$').hasMatch(c.first.text)
                            ? WordAlign.right
                            : WordAlign.left,
                      ),
                      inlines: [
                        for (final (k, l) in c.indexed)
                          WordText(k == 0 ? l.text : ' ${l.text}', WordRunStyle(font: _font, size: l.size)),
                      ],
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}
