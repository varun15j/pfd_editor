// Reads the Word feature test file (139 Word features, see
// doc/feature-support.md) and checks that each feature with a sample comes
// out of the reader.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma_docx/luma_docx.dart';

late WordDocument doc;
final paragraphs = <WordParagraph>[];
final tables = <WordTable>[];
final inlines = <WordInline>[];

void _walk(List<WordBlock> blocks) {
  for (final b in blocks) {
    switch (b) {
      case WordParagraph():
        paragraphs.add(b);
        for (final i in b.inlines) {
          inlines.add(i);
          if (i is WordShape) _walk(i.blocks);
        }
      case WordTable():
        tables.add(b);
        for (final r in b.rows) {
          for (final c in r.cells) {
            _walk(c.blocks);
          }
        }
    }
  }
}

Iterable<WordText> get texts => inlines.whereType<WordText>();
Iterable<WordRunStyle> get styles => texts.map((t) => t.style);

void main() {
  setUpAll(() {
    doc = WordReader.read(File('test/fixtures/Word_Feature_Test.docx').readAsBytesSync());
    for (final s in doc.sections) {
      _walk(s.blocks);
      for (final h in [...s.headers.values, ...s.footers.values]) {
        _walk(h);
      }
    }
    for (final n in [...doc.footnotes.values, ...doc.endnotes.values]) {
      _walk(n.blocks);
    }
  });

  test('reads the whole file without warnings', () {
    expect(doc.warnings, isEmpty);
    expect(doc.sections, hasLength(8));
    expect(doc.plainText, contains('Word Feature Test'));
  });

  group('Home > Font', () {
    test('families, theme fonts and sizes', () {
      final fonts = styles.map((s) => s.font).whereType<String>().toSet();
      expect(fonts, containsAll(['Times New Roman', 'Courier New']));
      expect(fonts.any((f) => f.contains('Calibri')), isTrue, reason: 'theme fonts resolve to Calibri / Calibri Light');
      final sizes = styles.map((s) => s.size).toSet();
      expect(sizes, containsAll([8.0, 36.0]));
    });

    test('bold, italic, underline, strike, caps, scripts', () {
      expect(styles.any((s) => s.bold && s.italic), isTrue);
      final underlines = styles.map((s) => s.underline).toSet();
      expect(underlines, containsAll(WordUnderline.values.where((u) => u != WordUnderline.none)));
      expect(styles.any((s) => s.underlineColor != null), isTrue);
      expect(styles.any((s) => s.strike), isTrue);
      expect(styles.any((s) => s.doubleStrike), isTrue);
      expect(styles.any((s) => s.vertAlign == WordVertAlign.superscript), isTrue);
      expect(styles.any((s) => s.vertAlign == WordVertAlign.subscript), isTrue);
      expect(styles.any((s) => s.smallCaps), isTrue);
      expect(styles.any((s) => s.allCaps), isTrue);
    });

    test('colours, highlights, shading and borders', () {
      final colors = styles.map((s) => s.color).whereType<int>().toSet();
      expect(colors.length, greaterThan(10), reason: 'RGB and theme colours with tints and shades');
      final highlights = styles.map((s) => s.highlight).whereType<int>().toSet();
      expect(highlights.length, greaterThanOrEqualTo(15));
      expect(styles.any((s) => s.shading != null), isTrue);
      expect(styles.any((s) => s.border != null), isTrue);
    });

    test('text effects, legacy effects, spacing, scale, position, OpenType', () {
      final effects = styles.map((s) => s.effects).whereType<WordTextEffects>().toList();
      expect(effects.any((e) => e.outlineColor != null), isTrue);
      expect(effects.any((e) => e.shadowColor != null), isTrue);
      expect(effects.any((e) => e.glowColor != null), isTrue);
      expect(effects.any((e) => e.reflection), isTrue);
      expect(effects.any((e) => e.gradient.isNotEmpty), isTrue);
      expect(effects.any((e) => e.ligatures != null), isTrue);
      expect(effects.any((e) => e.numberForm != null), isTrue);
      expect(styles.any((s) => s.outline), isTrue);
      expect(styles.any((s) => s.shadow), isTrue);
      expect(styles.any((s) => s.emboss), isTrue);
      expect(styles.any((s) => s.imprint), isTrue);
      expect(styles.any((s) => s.letterSpacing > 0), isTrue);
      expect(styles.any((s) => s.letterSpacing < 0), isTrue);
      expect(styles.any((s) => s.scale != 100 && s.scale != 1), isTrue);
      expect(styles.any((s) => s.position > 0), isTrue);
      expect(styles.any((s) => s.position < 0), isTrue);
      expect(styles.map((s) => s.position).every((p) => p.abs() <= 12), isTrue, reason: 'positions are in points');
    });

    test('hidden text', () => expect(styles.any((s) => s.hidden), isTrue));
  });

  group('Home > Paragraph', () {
    test('alignment, indents, spacing', () {
      final p = paragraphs.map((p) => p.style).toList();
      expect(p.map((s) => s.align).toSet(), containsAll(WordAlign.values));
      expect(p.any((s) => s.indentLeft > 0), isTrue);
      expect(p.any((s) => s.indentRight > 0), isTrue);
      expect(p.any((s) => s.firstLine > 0), isTrue);
      expect(p.any((s) => s.firstLine < 0), isTrue, reason: 'hanging indent');
      expect(p.any((s) => s.indentLeft < 0), isTrue, reason: 'negative indent');
      expect(p.any((s) => s.lineMultiple == 1.5), isTrue);
      expect(p.any((s) => s.lineMultiple == 2), isTrue);
      expect(p.any((s) => s.lineExact != null), isTrue);
      expect(p.any((s) => s.lineAtLeast != null), isTrue);
      expect(p.any((s) => s.spaceBefore > 0), isTrue);
    });

    test('borders and shading', () {
      final borders = paragraphs.map((p) => p.style.borders).whereType<WordBorders>().toList();
      final kinds = {for (final b in borders) ...[b.top, b.left, b.bottom].whereType<WordBorder>().map((x) => x.style)};
      expect(kinds, containsAll(['single', 'dashed', 'double']));
      expect(kinds.any((k) => k.startsWith('three')), isTrue, reason: '3-D border');
      expect(paragraphs.any((p) => p.style.shading != null), isTrue);
    });

    test('tab stops, leaders and positional tab', () {
      final stops = paragraphs.expand((p) => p.style.tabs).toList();
      expect(stops.map((t) => t.align).toSet(), containsAll(WordTabAlign.values));
      expect(stops.map((t) => t.leader).toSet(), containsAll(['dot', 'hyphen', 'underscore']));
      expect(inlines.whereType<WordTab>().any((t) => t.absoluteAlign != null), isTrue);
    });

    test('lists: bullets, symbols, picture bullets, numbering formats, outline, restart', () {
      final labels = paragraphs.map((p) => p.list).whereType<WordListLabel>().toList();
      final text = labels.map((l) => l.text).toSet();
      expect(text, containsAll(['•', '1.', 'a)', 'i.', 'I.', 'A.', '(1)', '1st', '1.1.1.', '➢', '✔']));
      expect(labels.any((l) => l.picture != null), isTrue);
      expect(labels.any((l) => l.level >= 2), isTrue);
      expect(labels.where((l) => l.text == '1.').length, greaterThan(1), reason: 'numbering restarts');
    });

    test('line break and right-to-left', () {
      expect(inlines.whereType<WordBreak>().any((b) => b.kind == WordBreakKind.line), isTrue);
      expect(paragraphs.any((p) => p.style.rtl), isTrue);
    });

    test('pagination options', () {
      final p = paragraphs.map((p) => p.style);
      expect(p.any((s) => s.keepNext), isTrue);
      expect(p.any((s) => s.keepLines), isTrue);
      expect(p.any((s) => s.pageBreakBefore), isTrue);
    });
  });

  group('Home > Styles', () {
    test('built-in and custom styles', () {
      final names = paragraphs.map((p) => p.styleName).whereType<String>().toSet();
      expect(names, containsAll(['Title', 'Subtitle', 'Heading 1', 'Heading 2', 'Heading 3', 'Quote', 'Intense Quote', 'caption', 'No Spacing', 'Code', 'Callout']));
      expect(doc.headings.map((h) => h.level).toSet(), containsAll([1, 2, 3, 4]));
      expect(doc.headings.length, 77);
    });
  });

  group('Insert', () {
    test('page breaks and section breaks', () {
      expect(inlines.whereType<WordBreak>().any((b) => b.kind == WordBreakKind.page), isTrue);
      expect(doc.sections.map((s) => s.breakType).toSet(), containsAll([WordBreakType.continuous, WordBreakType.oddPage]));
    });

    test('tables: header, merges, rotation, borders, nesting, spacing, floating, style', () {
      expect(tables.any((t) => t.rows.first.header), isTrue);
      final cells = tables.expand((t) => t.rows).expand((r) => r.cells).toList();
      expect(cells.any((c) => c.colSpan > 1), isTrue);
      expect(cells.any((c) => c.rowSpan > 1), isTrue);
      expect(cells.any((c) => c.textDirection != null), isTrue);
      expect(cells.any((c) => c.vAlign == WordCellVAlign.center), isTrue);
      expect(cells.any((c) => c.borders.diagonalDown != null || c.borders.diagonalUp != null), isTrue);
      expect(cells.any((c) => c.blocks.any((b) => b is WordTable)), isTrue, reason: 'nested table');
      expect(tables.any((t) => t.align == WordAlign.center), isTrue);
      expect(tables.any((t) => t.floating), isTrue);
      expect(tables.any((t) => t.cellSpacing > 0), isTrue);
      expect(tables.any((t) => t.styleId != null), isTrue);
      expect(tables.expand((t) => t.rows).any((r) => r.cantSplit), isTrue);
      expect(tables.expand((t) => t.rows).any((r) => r.revision != null), isTrue, reason: 'tracked table rows');
    });

    test('pictures: alt text, wrapping, rotate, flip, crop, grayscale, transparency, SVG icon', () {
      final pics = inlines.whereType<WordPicture>().toList();
      expect(pics.any((p) => p.anchor == null), isTrue);
      expect(pics.any((p) => p.altText?.isNotEmpty ?? false), isTrue);
      final wraps = pics.map((p) => p.anchor?.wrap).whereType<String>().toSet();
      expect(wraps, containsAll(['square', 'tight', 'topAndBottom']));
      expect(pics.any((p) => p.anchor?.behindText ?? false), isTrue);
      expect(pics.any((p) => p.look.rotation != 0), isTrue);
      expect(pics.any((p) => p.look.flipH), isTrue);
      expect(pics.any((p) => p.look.flipV), isTrue);
      expect(pics.any((p) => p.crop.left > 0 || p.crop.top > 0 || p.crop.right > 0 || p.crop.bottom > 0), isTrue);
      expect(pics.any((p) => p.shape != null && p.shape != 'rect'), isTrue);
      expect(pics.any((p) => p.look.shadow != null), isTrue);
      expect(pics.any((p) => p.grayscale), isTrue);
      expect(pics.any((p) => p.opacity < 1), isTrue);
      expect(pics.any((p) => p.hasSvg), isTrue);
    });

    test('shapes, text boxes and WordArt', () {
      final shapes = inlines.whereType<WordShape>().toList();
      final geometry = shapes.map((s) => s.geometry).toSet();
      expect(geometry, containsAll(['rect', 'roundRect', 'ellipse', 'triangle', 'diamond', 'heart', 'hexagon', 'line']));
      expect(geometry.any((g) => g.contains('Arrow')), isTrue);
      expect(geometry.any((g) => g.startsWith('star')), isTrue);
      expect(geometry.any((g) => g.contains('Callout')), isTrue);
      expect(shapes.any((s) => s.gradient.isNotEmpty), isTrue);
      expect(shapes.any((s) => s.look.shadow != null), isTrue);
      expect(shapes.any((s) => s.look.rotation != 0), isTrue);
      expect(shapes.any((s) => s.look.outlineDash != null), isTrue);
      expect(shapes.any((s) => s.blocks.isNotEmpty), isTrue, reason: 'text box');
      expect(shapes.any((s) => s.verticalText != null), isTrue);
      expect(shapes.any((s) => s.wordArt != null), isTrue);
    });

    test('charts from the cached values', () {
      final charts = inlines.whereType<WordChart>().toList();
      expect(charts.map((c) => c.kind).toSet(), containsAll([WordChartKind.column, WordChartKind.pie]));
      expect(charts.every((c) => c.series.isNotEmpty && c.categories.isNotEmpty), isTrue);
    });

    test('links, screen tips, bookmarks, internal links', () {
      final links = texts.map((t) => t.link).whereType<WordLink>().toList();
      final urls = links.map((l) => l.url).whereType<String>();
      expect(urls.any((u) => u.startsWith('http')), isTrue);
      expect(urls.any((u) => u.startsWith('mailto:')), isTrue);
      expect(urls.any((u) => u.startsWith('tel:')), isTrue);
      expect(links.any((l) => l.tooltip != null), isTrue);
      expect(links.any((l) => l.anchor != null), isTrue);
      expect(doc.bookmarks, isNotEmpty);
      for (final a in links.map((l) => l.anchor).whereType<String>()) {
        expect(doc.bookmarks.containsKey(a), isTrue, reason: 'link target $a');
      }
    });

    test('comments with replies and resolved state', () {
      expect(doc.comments, hasLength(5));
      expect(doc.comments.map((c) => c.author).toSet().length, greaterThan(1));
      expect(doc.comments.any((c) => c.parentId != null), isTrue);
      expect(doc.comments.any((c) => c.resolved), isTrue);
      expect(texts.any((t) => t.commentIds.isNotEmpty), isTrue);
    });

    test('headers and footers: first page, odd/even, own section header, page X of Y', () {
      expect(doc.evenAndOddHeaders, isTrue);
      expect(doc.sections.first.headers, isEmpty, reason: 'the cover page has no header');
      expect(doc.sections.any((s) => s.headers.containsKey('even')), isTrue);
      expect(doc.sections.map((s) => s.headers['default']).toSet().length, greaterThan(1));
      final fields = texts.map((t) => t.field).whereType<String>().toList();
      expect(fields.any((f) => f.startsWith('PAGE')), isTrue);
      expect(fields.any((f) => f.startsWith('NUMPAGES')), isTrue);
      expect(doc.sections.map((s) => s.pageNumberFormat).toSet(), contains('lowerRoman'));
      expect(doc.sections.any((s) => s.pageNumberStart == 1), isTrue);
    });

    test('drop caps, equations, symbols', () {
      final caps = paragraphs.map((p) => p.dropCap).whereType<WordDropCap>();
      expect(caps.any((c) => c.inMargin), isTrue);
      expect(caps.any((c) => !c.inMargin), isTrue);
      final eq = inlines.whereType<WordEquation>().toList();
      expect(eq.any((e) => e.display), isTrue);
      expect(eq.any((e) => !e.display), isTrue);
      final linear = eq.map((e) => e.root.linear).join(' ');
      expect(linear, contains('/'));
      expect(linear, contains('√'));
      expect(linear, contains('∑'));
      expect(linear, contains('∫'));
      expect(doc.plainText, contains('©'));
    });
  });

  group('Design and Layout', () {
    test('page colour, watermark, page borders', () {
      expect(doc.pageColor, isNotNull);
      final headerShapes = <WordInline>[];
      for (final s in doc.sections) {
        for (final h in s.headers.values) {
          for (final p in h.whereType<WordParagraph>()) {
            headerShapes.addAll(p.inlines.where((i) => i is WordShape || i is WordPicture));
          }
        }
      }
      expect(headerShapes, isNotEmpty, reason: 'watermark lives in the header');
      expect(doc.sections.any((s) => s.pageBorders != null), isTrue);
    });

    test('A4, margins, gutter, landscape, columns, line numbers, vertical alignment', () {
      final first = doc.sections.first;
      expect(first.pageWidth, closeTo(595.3, 1));
      expect(first.pageHeight, closeTo(841.9, 1));
      expect(doc.sections.any((s) => s.landscape), isTrue);
      expect(doc.sections.any((s) => s.gutter > 0), isTrue);
      expect(doc.sections.any((s) => s.columns.count == 2 && s.columns.separator), isTrue);
      expect(doc.sections.any((s) => s.columns.count == 3 && s.columns.widths.toSet().length > 1), isTrue);
      expect(inlines.whereType<WordBreak>().any((b) => b.kind == WordBreakKind.column), isTrue);
      expect(inlines.whereType<WordBreak>().any((b) => b.kind == WordBreakKind.textWrapping), isTrue);
      expect(doc.sections.any((s) => s.lineNumbers != null), isTrue);
      expect(doc.sections.any((s) => s.verticalAlign == WordVerticalPageAlign.center), isTrue);
    });
  });

  group('References, Mailings, Review', () {
    test('contents, notes, captions, citations, index', () {
      expect(doc.footnotes, hasLength(2));
      expect(doc.endnotes, hasLength(2));
      expect(inlines.whereType<WordNoteRef>().map((r) => r.label).toSet(), containsAll(['1', 'i']));
      final fields = texts.map((t) => t.field).whereType<String>().toList();
      for (final code in ['TOC', 'SEQ', 'CITATION', 'BIBLIOGRAPHY', 'INDEX', 'TOA', 'MERGEFIELD', 'IF', 'REF', 'PAGEREF']) {
        expect(fields.any((f) => f.startsWith(code)), isTrue, reason: '$code field');
      }
    });

    test('tracked changes from several reviewers', () {
      final kinds = {
        ...texts.map((t) => t.revision?.kind),
        ...paragraphs.map((p) => p.revision?.kind),
      }.whereType<WordRevisionKind>();
      expect(kinds, containsAll(WordRevisionKind.values));
      final authors = texts.map((t) => t.revision?.author).whereType<String>().toSet();
      expect(authors.length, greaterThan(1));
    });
  });

  group('Properties, controls, fields, language', () {
    test('document properties', () {
      final p = doc.properties;
      for (final v in [p.title, p.subject, p.author, p.keywords, p.category, p.description]) {
        expect(v, isNotNull);
      }
    });

    test('content controls and legacy form fields', () {
      final controls = texts.map((t) => t.contentControl).whereType<String>().toSet();
      expect(controls, containsAll(['richText', 'plainText', 'dropDown', 'comboBox', 'date', 'checkBox', 'buildingBlock']));
      expect(doc.plainText, anyOf(contains('☒'), contains('☐')));
      expect(doc.plainText, contains('▾'));
    });

    test('fields', () {
      final fields = texts.map((t) => t.field).whereType<String>().toList();
      for (final code in ['SECTION', 'DATE', 'TIME', 'CREATEDATE', 'SAVEDATE', 'AUTHOR', 'TITLE', 'SUBJECT', 'KEYWORDS', 'FILENAME', 'NUMWORDS', '=', 'QUOTE']) {
        expect(fields.any((f) => f.startsWith(code)), isTrue, reason: '$code field');
      }
    });

    test('scripts, emoji and special spaces', () {
      final text = doc.plainText;
      expect(text, contains('Ελληνικά'.substring(0, 2)));
      expect(RegExp('[Ѐ-ӿ]').hasMatch(text), isTrue, reason: 'Cyrillic');
      expect(RegExp('[ऀ-ॿ]').hasMatch(text), isTrue, reason: 'Devanagari');
      expect(RegExp('[஀-௿]').hasMatch(text), isTrue, reason: 'Tamil');
      expect(RegExp('[一-鿿]').hasMatch(text), isTrue, reason: 'CJK');
      expect(RegExp('[؀-ۿ]').hasMatch(text), isTrue, reason: 'Arabic');
      expect(RegExp('[֐-׿]').hasMatch(text), isTrue, reason: 'Hebrew');
      expect(RegExp('[\u{1F300}-\u{1FAFF}]', unicode: true).hasMatch(text), isTrue, reason: 'emoji');
      expect(text, contains(' '));
      expect(text, contains('‑'));
      expect(text, contains(' '));
    });
  });
}
