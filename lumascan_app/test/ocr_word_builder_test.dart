import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/ocr.dart';
import 'package:lumascan/features/ocr_word/ocr_word_builder.dart';
import 'package:luma_docx/luma_docx.dart';

/// The OCR test images in sample_photos/word_pages/ are the pages of the
/// Word feature test document; expected.json says where every line sits.
/// Built into an OcrLayout, that is what a perfect OCR engine would report,
/// so these tests check the Word file the OCR to Word path writes from it.
List<OcrWordPage> _samplePages() {
  final json = jsonDecode(File('sample_photos/word_pages/expected.json').readAsStringSync()) as Map<String, dynamic>;
  OcrBox box(Map<String, dynamic> e, String text) {
    final b = (e['box'] as List).cast<num>();
    return OcrBox(
      text: text,
      left: b[0].toDouble(),
      top: b[1].toDouble(),
      right: b[2].toDouble(),
      bottom: b[3].toDouble(),
    );
  }

  return [
    for (final p in (json['pages'] as List).cast<Map<String, dynamic>>())
      () {
        final blocks = <OcrBlock>[];
        for (final b in (p['blocks'] as List).cast<Map<String, dynamic>>()) {
          final lines = [
            for (final l in (b['lines'] as List).cast<Map<String, dynamic>>())
              () {
                final o = box(l, l['text'] as String);
                return OcrLine(text: o.text, left: o.left, top: o.top, right: o.right, bottom: o.bottom);
              }(),
          ];
          final o = box(b, lines.map((l) => l.text).join('\n'));
          blocks.add(OcrBlock(text: o.text, left: o.left, top: o.top, right: o.right, bottom: o.bottom, lines: lines));
        }
        final layout = OcrLayout(blocks);
        final size = (p['size'] as List).cast<num>();
        return OcrWordPage(text: layout.text, layout: layout, landscape: size[0] > size[1]);
      }(),
  ];
}

Iterable<WordTable> _tables(WordSection s) => s.blocks.whereType<WordTable>();

String _words(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  final pages = _samplePages();
  late final WordDocument read;

  setUpAll(() {
    final bytes = buildOcrWordFile(pages, title: 'Word feature test (OCR)');
    final out = Platform.environment['OCR_WORD_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
    read = WordReader.read(bytes);
  });

  test('the sample images and their expected text are bundled', () {
    expect(pages, hasLength(35));
    for (var i = 1; i <= 35; i++) {
      expect(File('sample_photos/word_pages/page_${i.toString().padLeft(2, '0')}.jpg').existsSync(), isTrue);
    }
  });

  test('every page becomes one page of the Word file', () {
    expect(read.sections, hasLength(35));
    expect(read.properties.title, 'Word feature test (OCR)');
  });

  test('every recognised word is in the Word file, in reading order', () {
    final text = _words(read.plainText);
    var missing = 0;
    var total = 0;
    for (final p in pages) {
      // Bare numbers are left out: the line numbers down the margin become
      // Word's own line numbering, not text.
      for (final word in p.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty && int.tryParse(w) == null)) {
        total++;
        if (!text.contains(word.replaceFirst(RegExp(r'^[•●▪◦○■□➢►✓·]$'), ''))) missing++;
      }
    }
    // List markers move from the text to the list label.
    expect(missing / total, lessThan(0.01), reason: '$missing of $total words missing');
    expect(
      text.indexOf('Microsoft Word Feature Test'),
      lessThan(text.indexOf('Paragraph shading (solid and pattern)')),
    );
  });

  test('numbers down the margin become line numbering, not a table', () {
    final body = read.sections[13]; // section 3 of the test document, numbered lines
    expect(body.lineNumbers, isNotNull);
    expect(_tables(body), isEmpty);
    expect(_tables(read.sections[4]), hasLength(1)); // the feature list stays one table
  });

  test('the landscape pages stay landscape', () {
    expect(
      [
        for (final (i, s) in read.sections.indexed)
          if (s.pageWidth > s.pageHeight) i + 1,
      ],
      [32, 33],
    );
  });

  test('the cover title is a heading', () {
    final h = read.headings.map((h) => _words(h.text)).toList();
    expect(h.any((t) => t.contains('Microsoft Word Feature Test')), isTrue, reason: '$h');
    final title = read.sections.first.blocks.whereType<WordParagraph>().firstWhere(
      (p) => p.text.contains('Microsoft Word'),
    );
    expect(title.style.align, WordAlign.center);
  });

  test('the feature list pages become tables with their columns', () {
    final page5 = read.sections[4];
    final table = _tables(page5).first;
    expect(table.columns.length, 4);
    String cell(WordTableRow r, int c) => _words((r.cells[c].blocks.first as WordParagraph).text);
    expect(cell(table.rows.first, 2), 'Feature');
    final row = table.rows.firstWhere((r) => cell(r, 0) == '25');
    expect(cell(row, 1), 'Home > Paragraph');
    expect(cell(row, 2), 'Paragraph shading (solid and pattern)');
    expect(cell(row, 3), 'Section 3.4');
    // A wrapped cell keeps its second line.
    final wrapped = table.rows.firstWhere((r) => cell(r, 0) == '28');
    expect(cell(wrapped, 2), 'Bulleted lists: multi-level, custom symbol, Wingdings, picture bullet');
  });

  group('real OCR noise', () {
    // What ML Kit did on BlueStacks with these pages: blocks out of order,
    // line numbers joined to their lines, a row number misread.
    OcrWordPage noisy(
      OcrWordPage p, {
      bool shuffle = false,
      bool joinNumbers = false,
      Map<String, String> misread = const {},
    }) {
      var blocks = [...p.layout!.blocks];
      if (shuffle) blocks = [...blocks.reversed];
      final out = <OcrBlock>[];
      final numbers = <OcrLine>[];
      for (final b in blocks) {
        final lines = <OcrLine>[];
        for (final l in b.lines) {
          final text = misread[l.text] ?? l.text;
          if (text.isEmpty) continue;
          if (joinNumbers && RegExp(r'^\d+$').hasMatch(text) && l.left < 0.1) {
            numbers.add(l);
            continue;
          }
          lines.add(OcrLine(text: text, left: l.left, top: l.top, right: l.right, bottom: l.bottom));
        }
        if (lines.isNotEmpty) {
          out.add(OcrBlock(text: '', left: b.left, top: b.top, right: b.right, bottom: b.bottom, lines: lines));
        }
      }
      if (joinNumbers) {
        // Each margin number becomes the start of the first line beside it.
        for (final n in numbers) {
          for (final (bi, b) in out.indexed) {
            final i = b.lines.indexWhere((l) => (l.top + l.bottom) / 2 > n.top && (l.top + l.bottom) / 2 < n.bottom);
            if (i < 0) continue;
            final l = b.lines[i];
            final lines = [...b.lines];
            lines[i] = OcrLine(text: '${n.text} ${l.text}', left: n.left, top: l.top, right: l.right, bottom: l.bottom);
            out[bi] = OcrBlock(text: '', left: b.left, top: b.top, right: b.right, bottom: b.bottom, lines: lines);
            break;
          }
        }
      }
      final layout = OcrLayout(out);
      return OcrWordPage(text: layout.text, layout: layout);
    }

    String cell(WordTableRow r, int c) => _words((r.cells[c].blocks.first as WordParagraph).text);

    test('blocks out of order still give one table, top to bottom', () {
      final doc = WordReader.read(
        buildOcrWordFile([
          noisy(pages[4], shuffle: true, misread: {'40': '4;'}),
        ]),
      );
      final tables = _tables(doc.sections.first).toList();
      expect(tables, hasLength(1));
      final first = [for (final r in tables.first.rows) cell(r, 0)];
      expect(first.take(4), ['#', '25', '26', '27']);
      expect(first.last, '56');
      final text = _words(doc.plainText);
      expect(text.indexOf('Even page header'), lessThan(text.indexOf('Paragraph shading')));
    });

    test('a header row whose # was not read stays the first row of the table', () {
      final doc = WordReader.read(
        buildOcrWordFile([
          noisy(pages[4], shuffle: true, misread: {'#': ''}),
        ]),
      );
      final table = _tables(doc.sections.first).single;
      expect(
        [for (var c = 1; c < 4; c++) cell(table.rows.first, c)],
        ['Ribbon tab / area', 'Feature', 'Sample in this document'],
      );
      expect(cell(table.rows[1], 0), '25');
    });

    test('a watermark that crosses no text is still left out when it is on many pages', () {
      final doc = WordReader.read(buildOcrWordFile(pages));
      final paras = [
        for (final s in doc.sections)
          for (final b in s.blocks.whereType<WordParagraph>()) _words(b.text),
      ];
      expect(paras.where((t) => t == 'SAMPLE'), isEmpty);
    });

    test('two margin numbers (header and footer lines) are taken off', () {
      final doc = WordReader.read(buildOcrWordFile([pages[4]]));
      final paras = doc.sections.first.blocks.whereType<WordParagraph>().map((p) => _words(p.text)).toList();
      expect(paras.where((t) => RegExp(r'^\d+$').hasMatch(t)), isEmpty, reason: '$paras');
      expect(doc.sections.first.lineNumbers, isNotNull);
    });

    test('line numbers joined to their lines are taken off', () {
      final doc = WordReader.read(buildOcrWordFile([noisy(pages[13], joinNumbers: true)]));
      expect(doc.sections.first.lineNumbers, isNotNull);
      final paras = doc.sections.first.blocks.whereType<WordParagraph>().map((p) => p.text).toList();
      expect(paras, containsAll(['Styles', '4.1 Built-in styles', 'This paragraph uses the built-in Quote style.']));
      expect(paras.where((t) => RegExp(r'^16\d ').hasMatch(t)), isEmpty);
    });
  });

  group('layout from line positions', () {
    OcrLine line(String t, double l, double top, double r, {double h = 0.016}) =>
        OcrLine(text: t, left: l, top: top, right: r, bottom: top + h);
    OcrWordPage page(List<List<OcrLine>> blocks) {
      final layout = OcrLayout([
        for (final ls in blocks)
          OcrBlock(
            text: ls.map((l) => l.text).join('\n'),
            left: ls.first.left,
            top: ls.first.top,
            right: ls.first.right,
            bottom: ls.last.bottom,
            lines: ls,
          ),
      ]);
      return OcrWordPage(text: layout.text, layout: layout);
    }

    WordDocument roundTrip(OcrWordPage p) => WordReader.read(buildOcrWordFile([p]));

    test('large type becomes a heading, centred lines stay centred', () {
      final doc = roundTrip(
        page([
          [line('Growing Tomatoes', 0.3, 0.08, 0.7, h: 0.04)],
          [line('A guide for small gardens', 0.35, 0.13, 0.65)],
          [
            line('Tomatoes need at least six hours of direct sunlight every day and', 0.1, 0.2, 0.9),
            line('a pot that holds twenty litres of soil.', 0.1, 0.22, 0.5),
          ],
        ]),
      );
      final ps = doc.sections.first.blocks.cast<WordParagraph>();
      expect(ps[0].headingLevel, 1);
      expect(ps[0].style.align, WordAlign.center);
      expect(ps[1].headingLevel, isNull);
      expect(ps[1].style.align, WordAlign.center);
      expect(
        ps[2].text,
        'Tomatoes need at least six hours of direct sunlight every day and a pot that holds twenty litres of soil.',
      );
    });

    test('bullets and numbers become Word lists', () {
      final doc = roundTrip(
        page([
          [line('• Water bottle', 0.1, 0.1, 0.4), line('• Packed lunch', 0.1, 0.12, 0.4)],
          [
            line('1. Reach the gate by 7:30.', 0.1, 0.18, 0.5),
            line('2. Give your slip to the teacher.', 0.1, 0.2, 0.55),
          ],
        ]),
      );
      final ps = doc.sections.first.blocks.cast<WordParagraph>();
      expect(ps.map((p) => p.text), [
        'Water bottle',
        'Packed lunch',
        'Reach the gate by 7:30.',
        'Give your slip to the teacher.',
      ]);
      expect(ps[0].list?.format, 'bullet');
      expect(ps[2].list?.text, '1.');
      expect(ps[3].list?.text, '2.');
    });

    test('right-aligned lines and short address lines keep their shape', () {
      final doc = roundTrip(
        page([
          [line('4 November 2026', 0.7, 0.1, 0.9)],
          [line('Ms Anita Rao', 0.1, 0.15, 0.3), line('Station Road, Pune', 0.1, 0.17, 0.35)],
          [line('Dear Ms Rao, thank you for choosing our studio for the redesign work', 0.1, 0.25, 0.9)],
        ]),
      );
      final ps = doc.sections.first.blocks.cast<WordParagraph>();
      expect(ps[0].style.align, WordAlign.right);
      expect(ps[1].text, 'Ms Anita Rao\nStation Road, Pune');
    });

    test('a page without a layout keeps its paragraphs', () {
      final doc = WordReader.read(
        buildOcrWordFile([const OcrWordPage(text: 'First line\nsecond line\n\nNext paragraph')]),
      );
      expect(doc.plainText, 'First line\nsecond line\nNext paragraph\n');
    });
  });
}
