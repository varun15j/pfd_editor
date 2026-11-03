import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../model.dart';
import 'chart_reader.dart';
import 'math_reader.dart';
import 'numbering.dart';
import 'styles.dart';
import 'symbols.dart';
import 'theme.dart';
import 'xml_util.dart';

/// Reads a Word (.docx) file into a [WordDocument].
///
/// Pure Dart: it runs in an isolate and in plain `dart test`. Damaged parts
/// are skipped and listed in [WordDocument.warnings]; only a file that is
/// not a Word document at all throws a [FormatException].
class WordReader {
  WordReader._();

  static WordDocument read(Uint8List bytes) => _Parser(_Package.open(bytes)).parse();
}

class _Rel {
  const _Rel(this.type, this.target, {this.external = false});

  final String type;

  /// Path inside the zip, or the outside address when [external].
  final String target;
  final bool external;
}

class _Package {
  _Package(this.archive);

  final Archive archive;
  final _xmlCache = <String, XmlDocument?>{};
  final _relsCache = <String, Map<String, _Rel>>{};

  static _Package open(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw const FormatException('This file is not a Word document.');
    }
    final pkg = _Package(archive);
    if (pkg.mainPart == null) throw const FormatException('This file is not a Word document.');
    return pkg;
  }

  Uint8List? bytes(String path) {
    final f = archive.findFile(path);
    if (f == null) return null;
    final content = f.readBytes();
    return content == null ? null : Uint8List.fromList(content);
  }

  XmlDocument? xml(String path) => _xmlCache.putIfAbsent(path, () {
    final b = bytes(path);
    if (b == null) return null;
    try {
      return XmlDocument.parse(utf8.decode(b, allowMalformed: true));
    } on Object {
      return null;
    }
  });

  /// The main document part, found through `_rels/.rels`.
  late final String? mainPart = () {
    final root = rels('');
    for (final r in root.values) {
      if (r.type.endsWith('/officeDocument')) return r.target;
    }
    return archive.findFile('word/document.xml') == null ? null : 'word/document.xml';
  }();

  /// Relationships of [part], by id. '' means the package itself.
  Map<String, _Rel> rels(String part) => _relsCache.putIfAbsent(part, () {
    final dir = part.contains('/') ? part.substring(0, part.lastIndexOf('/')) : '';
    final name = part.contains('/') ? part.substring(part.lastIndexOf('/') + 1) : part;
    final relsPath = part.isEmpty ? '_rels/.rels' : '${dir.isEmpty ? '' : '$dir/'}_rels/$name.rels';
    final doc = xml(relsPath);
    if (doc == null) return const {};
    final out = <String, _Rel>{};
    for (final r in doc.rootElement.childElements) {
      final id = r.getAttribute('Id');
      final target = r.getAttribute('Target');
      if (id == null || target == null) continue;
      final external = r.getAttribute('TargetMode') == 'External';
      out[id] = _Rel(r.getAttribute('Type') ?? '', external ? target : _resolve(dir, target), external: external);
    }
    return out;
  });

  /// The first part [from] links to with a relationship type ending in [type].
  String? related(String from, String type) {
    for (final r in rels(from).values) {
      if (!r.external && r.type.endsWith('/$type')) return r.target;
    }
    return null;
  }

  static String _resolve(String dir, String target) {
    if (target.startsWith('/')) return target.substring(1);
    final parts = [if (dir.isNotEmpty) ...dir.split('/')];
    for (final p in target.split('/')) {
      if (p == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (p != '.' && p.isNotEmpty) {
        parts.add(p);
      }
    }
    return parts.join('/');
  }
}

/// Reading state of one story (body, header, note, comment): fields can
/// span paragraphs, and so can comment ranges.
class _Story {
  _Story(this.part);

  final String part;
  final fields = <_Field>[];
  final activeComments = <String>[];
}

class _Field {
  _Field({this.ffData, String instr = ''}) : instr = StringBuffer(instr);

  final XmlElement? ffData;
  final StringBuffer instr;
  bool inResult = false;
  bool shownSomething = false;

  String get code => instr.toString().trim();
}

/// What a paragraph's runs share while they are read.
class _InlineCtx {
  _InlineCtx({required this.base, this.link, this.revision, this.control});

  final RunProps base;
  WordLink? link;
  WordRevision? revision;
  String? control;

  _InlineCtx child({WordLink? link, WordRevision? revision, String? control}) => _InlineCtx(
    base: base,
    link: link ?? this.link,
    revision: revision ?? this.revision,
    control: control ?? this.control,
  );
}

/// Table style formatting passed down to the paragraphs of a cell.
class _CellFormat {
  const _CellFormat(this.run, this.para);

  final RunProps run;
  final ParaProps para;
}

class _Parser {
  _Parser(this.pkg) : main = pkg.mainPart!;

  final _Package pkg;
  final String main;
  late final WordTheme theme;
  late final StyleSheet styles;
  late final Numbering numbering;
  final warnings = <String>[];
  final bookmarks = <String, int>{};
  final headings = <WordHeading>[];
  final footnoteLabels = <String, String>{};
  final endnoteLabels = <String, String>{};
  String footnoteFormat = 'decimal';
  String endnoteFormat = 'lowerRoman';
  double defaultTabStop = 36;
  var _paragraphIndex = 0;

  /// The label of the note being read, for its own `w:footnoteRef` mark.
  String? _currentNoteLabel;

  WordDocument parse() {
    final themePath = pkg.related(main, 'theme');
    theme = WordTheme.parse(themePath == null ? null : pkg.xml(themePath));
    final stylesPath = pkg.related(main, 'styles');
    styles = StyleSheet(theme, stylesPath == null ? null : pkg.xml(stylesPath));
    final numberingPath = pkg.related(main, 'numbering');
    numbering = Numbering(
      numberingPath == null ? null : pkg.xml(numberingPath),
      picture: (id) {
        final r = pkg.rels(numberingPath!)[id];
        return r == null || r.external ? null : pkg.bytes(r.target);
      },
    );
    var evenAndOdd = false;
    final settingsPath = pkg.related(main, 'settings');
    final settings = settingsPath == null ? null : pkg.xml(settingsPath)?.rootElement;
    if (settings != null) {
      evenAndOdd = onOff(settings.w('evenAndOddHeaders')) ?? false;
      defaultTabStop = twips(settings.wVal('defaultTabStop')) ?? 36;
      footnoteFormat = settings.w('footnotePr')?.wVal('numFmt') ?? footnoteFormat;
      endnoteFormat = settings.w('endnotePr')?.wVal('numFmt') ?? endnoteFormat;
    }

    final doc = pkg.xml(main);
    final body = doc?.rootElement.w('body');
    if (body == null) throw const FormatException('The Word document is damaged.');
    final pageColor = hexColor(doc!.rootElement.w('background')?.attr('color')) ??
        theme.color(doc.rootElement.w('background')?.attr('themeColor'));

    final sections = _body(body);
    final footnotes = _notes(WordNoteKind.footnote);
    final endnotes = _notes(WordNoteKind.endnote);
    final comments = _comments();
    return WordDocument(
      sections: sections,
      footnotes: footnotes,
      endnotes: endnotes,
      comments: comments,
      properties: _properties(),
      pageColor: pageColor,
      evenAndOddHeaders: evenAndOdd,
      defaultTabStop: defaultTabStop,
      bookmarks: bookmarks,
      headings: headings,
      warnings: warnings,
    );
  }

  // ------------------------------------------------------------ body and sections

  List<WordSection> _body(XmlElement body) {
    final story = _Story(main);
    final sections = <WordSection>[];
    var blocks = <WordBlock>[];
    Map<String, List<WordBlock>> headers = {}, footers = {};

    void closeSection(XmlElement? sectPr) {
      final s = _section(sectPr, blocks, headers, footers);
      headers = s.headers;
      footers = s.footers;
      sections.add(s);
      blocks = <WordBlock>[];
    }

    void visit(XmlElement child) {
      if (isEl(child, 'w', 'p')) {
        blocks.add(_safeParagraph(child, story, null));
        final sectPr = child.w('pPr')?.w('sectPr');
        if (sectPr != null) closeSection(sectPr);
      } else if (isEl(child, 'w', 'tbl')) {
        blocks.add(_table(child, story));
      } else if (isEl(child, 'w', 'sdt') || isEl(child, 'w', 'customXml')) {
        final content = child.w('sdtContent') ?? child;
        for (final c in content.childElements) {
          visit(c);
        }
      } else if (isEl(child, 'mc', 'AlternateContent')) {
        final choice = child.el('mc', 'Choice') ?? child.el('mc', 'Fallback');
        for (final c in choice?.childElements ?? const <XmlElement>[]) {
          visit(c);
        }
      } else if (isEl(child, 'w', 'bookmarkStart')) {
        _bookmark(child, _paragraphIndex);
      }
    }

    for (final child in body.childElements) {
      visit(child);
    }
    final last = body.w('sectPr');
    if (blocks.isNotEmpty || sections.isEmpty || last != null) closeSection(last);
    return sections;
  }

  WordSection _section(XmlElement? sectPr, List<WordBlock> blocks, Map<String, List<WordBlock>> prevHeaders, Map<String, List<WordBlock>> prevFooters) {
    double tw(XmlElement? e, String a, double fallback) => twips(e?.attr(a)) ?? fallback;
    final size = sectPr?.w('pgSz');
    final mar = sectPr?.w('pgMar');
    final cols = sectPr?.w('cols');
    final headers = Map.of(prevHeaders), footers = Map.of(prevFooters);
    for (final ref in sectPr?.childElements ?? const <XmlElement>[]) {
      final isHeader = isEl(ref, 'w', 'headerReference');
      if (!isHeader && !isEl(ref, 'w', 'footerReference')) continue;
      final rel = pkg.rels(main)[ref.attr('id')];
      if (rel == null || rel.external) continue;
      final xml = pkg.xml(rel.target);
      if (xml == null) continue;
      final content = _blocks(xml.rootElement, _Story(rel.target));
      (isHeader ? headers : footers)[ref.attr('type') ?? 'default'] = content;
    }
    final borders = sectPr?.w('pgBorders');
    final ln = sectPr?.w('lnNumType');
    final pgNum = sectPr?.w('pgNumType');
    return WordSection(
      pageWidth: tw(size, 'w', 595.3),
      pageHeight: tw(size, 'h', 841.9),
      landscape: size?.attr('orient') == 'landscape',
      margins: WordInsets(top: tw(mar, 'top', 72), right: tw(mar, 'right', 72), bottom: tw(mar, 'bottom', 72), left: tw(mar, 'left', 72)),
      headerDistance: tw(mar, 'header', 36),
      footerDistance: tw(mar, 'footer', 36),
      gutter: tw(mar, 'gutter', 0),
      columns: WordColumns(
        count: int.tryParse(cols?.attr('num') ?? '') ?? (cols?.els('w', 'col').length ?? 0).clamp(1, 45),
        space: tw(cols, 'space', 36),
        separator: isTrue(cols?.attr('sep')),
        widths: cols?.attr('equalWidth') == '0' || cols?.attr('equalWidth') == 'false'
            ? [for (final c in cols!.els('w', 'col')) twips(c.attr('w')) ?? 0]
            : const [],
      ),
      breakType: switch (sectPr?.wVal('type')) {
        'continuous' => WordBreakType.continuous,
        'oddPage' => WordBreakType.oddPage,
        'evenPage' => WordBreakType.evenPage,
        'nextColumn' => WordBreakType.nextColumn,
        _ => WordBreakType.nextPage,
      },
      verticalAlign: switch (sectPr?.wVal('vAlign')) {
        'center' => WordVerticalPageAlign.center,
        'bottom' => WordVerticalPageAlign.bottom,
        'both' => WordVerticalPageAlign.both,
        _ => WordVerticalPageAlign.top,
      },
      pageBorders: bordersOf(borders, theme),
      pageBordersFromText: borders?.attr('offsetFrom') != 'page',
      lineNumbers: ln == null
          ? null
          : WordLineNumbers(
              countBy: int.tryParse(ln.attr('countBy') ?? '') ?? 1,
              start: (int.tryParse(ln.attr('start') ?? '') ?? 0) + 1,
              distance: twips(ln.attr('distance')) ?? 18,
              restart: ln.attr('restart') ?? 'newPage',
            ),
      titlePage: onOff(sectPr?.w('titlePg')) ?? false,
      headers: headers,
      footers: footers,
      pageNumberFormat: pgNum?.attr('fmt') ?? 'decimal',
      pageNumberStart: int.tryParse(pgNum?.attr('start') ?? ''),
      blocks: blocks,
    );
  }

  /// Block content of a container: body part, header, cell, text box, note.
  List<WordBlock> _blocks(XmlElement container, _Story story, [_CellFormat? cell]) {
    final out = <WordBlock>[];
    void visit(XmlElement c) {
      if (isEl(c, 'w', 'p')) {
        out.add(_safeParagraph(c, story, cell));
      } else if (isEl(c, 'w', 'tbl')) {
        out.add(_table(c, story));
      } else if (isEl(c, 'w', 'sdt') || isEl(c, 'w', 'customXml')) {
        for (final x in (c.w('sdtContent') ?? c).childElements) {
          visit(x);
        }
      } else if (isEl(c, 'mc', 'AlternateContent')) {
        for (final x in (c.el('mc', 'Choice') ?? c.el('mc', 'Fallback'))?.childElements ?? const <XmlElement>[]) {
          visit(x);
        }
      }
    }

    for (final c in container.childElements) {
      visit(c);
    }
    return out;
  }

  void _bookmark(XmlElement e, int paragraphIndex) {
    final name = e.attr('name');
    if (name != null && name != '_GoBack') bookmarks.putIfAbsent(name, () => paragraphIndex);
  }

  // ------------------------------------------------------------ paragraphs

  WordParagraph _safeParagraph(XmlElement p, _Story story, _CellFormat? cell) {
    try {
      return _paragraph(p, story, cell);
    } on Object catch (e) {
      warnings.add('A paragraph could not be read ($e).');
      return WordParagraph(index: _paragraphIndex++, style: const WordParagraphStyle(), inlines: const []);
    }
  }

  WordParagraph _paragraph(XmlElement p, _Story story, _CellFormat? cell) {
    final index = _paragraphIndex++;
    final pPr = p.w('pPr');
    final styleId = pPr?.wVal('pStyle') ?? styles.defaultParagraphStyle;
    final props = styles.defaultPara.copy();
    if (cell != null) props.merge(cell.para);
    props.merge(styles.stylePara(styleId));
    final direct = ParaProps()..apply(pPr, theme);
    final numId = direct.numId ?? props.numId;
    final ilvl = direct.ilvl ?? props.ilvl ?? 0;
    final level = numId == null ? null : numbering.level(numId, ilvl);
    if (level != null) props.apply(level.pPr, theme);
    props.merge(direct);

    final base = styles.defaultRun.copy();
    if (cell != null) base.merge(cell.run);
    base.merge(styles.styleRun(styleId));

    WordListLabel? list;
    if (numId != null && level != null) {
      final next = numbering.next(numId, ilvl);
      if (next != null) {
        final labelProps = base.copy()..apply(pPr?.w('rPr'), theme);
        // Underline and strike of the paragraph mark don't reach the label in Word.
        labelProps.underline = null;
        labelProps.apply(next.level.rPr, theme);
        list = WordListLabel(
          text: next.text,
          style: labelProps.toStyle(),
          picture: next.picture,
          suffix: next.level.suffix,
          align: next.level.align,
          level: ilvl,
          listId: numId,
          format: next.level.format,
          pattern: next.level.text,
          start: next.level.start,
        );
      }
    }

    final frame = pPr?.w('framePr');
    final dropCapKind = frame?.attr('dropCap');
    final dropCap = dropCapKind == null || dropCapKind == 'none'
        ? null
        : WordDropCap(lines: int.tryParse(frame!.attr('lines') ?? '') ?? 3, inMargin: dropCapKind == 'margin');

    WordRevision? revision;
    final markIns = pPr?.w('rPr')?.w('ins');
    final pChange = pPr?.w('pPrChange');
    if (markIns != null) {
      revision = _revision(markIns, WordRevisionKind.paragraph);
    } else if (pChange != null) {
      revision = _revision(pChange, WordRevisionKind.format);
    }

    final paraBookmarks = <String>[];
    final inlines = <WordInline>[];
    _inlines(p, _InlineCtx(base: base), story, inlines, index, paraBookmarks);

    final styleName = styles.nameOf(styleId);
    int? headingLevel;
    final lowerName = styleName?.toLowerCase();
    if (lowerName == 'title') {
      headingLevel = 0;
    } else if (props.outlineLevel != null) {
      headingLevel = props.outlineLevel! + 1;
    } else if (lowerName != null && RegExp(r'^heading [1-9]$').hasMatch(lowerName)) {
      headingLevel = int.parse(lowerName.substring(8));
    }
    final paragraph = WordParagraph(
      index: index,
      style: props.toStyle(),
      inlines: inlines,
      styleId: styleId,
      styleName: styleName,
      list: list,
      dropCap: dropCap,
      headingLevel: headingLevel,
      revision: revision,
      bookmarks: paraBookmarks,
    );
    if (headingLevel != null && story.part == main) {
      final text = paragraph.text.trim();
      if (text.isNotEmpty) headings.add(WordHeading(level: headingLevel, text: text, paragraphIndex: index));
    }
    return paragraph;
  }

  WordRevision _revision(XmlElement e, WordRevisionKind kind) =>
      WordRevision(kind: kind, author: e.attr('author'), date: parseDate(e.attr('date')));

  /// Walks paragraph content: runs, links, tracked changes, fields, content
  /// controls, bookmarks, comments and equations.
  void _inlines(XmlElement container, _InlineCtx ic, _Story story, List<WordInline> out, int pIndex, List<String> pBookmarks) {
    for (final c in container.childElements) {
      final ns = nsOf(c);
      if (ns == 'm') {
        if (c.name.local == 'oMath') {
          out.add(WordEquation(MathReader.read(c), style: ic.base.toStyle()));
        } else if (c.name.local == 'oMathPara') {
          for (final m in c.els('m', 'oMath')) {
            out.add(WordEquation(MathReader.read(m), display: true, style: ic.base.toStyle()));
          }
        }
        continue;
      }
      if (ns == 'mc' && c.name.local == 'AlternateContent') {
        final choice = c.el('mc', 'Choice') ?? c.el('mc', 'Fallback');
        if (choice != null) _inlines(choice, ic, story, out, pIndex, pBookmarks);
        continue;
      }
      if (ns != 'w') continue;
      switch (c.name.local) {
        case 'r':
          _run(c, ic, story, out);
        case 'hyperlink':
          final rel = c.attr('id') == null ? null : pkg.rels(story.part)[c.attr('id')];
          final link = WordLink(
            url: rel?.target,
            anchor: c.attr('anchor'),
            tooltip: c.attr('tooltip'),
          );
          _inlines(c, ic.child(link: link), story, out, pIndex, pBookmarks);
        case 'ins':
          _inlines(c, ic.child(revision: _revision(c, WordRevisionKind.insert)), story, out, pIndex, pBookmarks);
        case 'del':
          _inlines(c, ic.child(revision: _revision(c, WordRevisionKind.delete)), story, out, pIndex, pBookmarks);
        case 'moveFrom':
          _inlines(c, ic.child(revision: _revision(c, WordRevisionKind.moveFrom)), story, out, pIndex, pBookmarks);
        case 'moveTo':
          _inlines(c, ic.child(revision: _revision(c, WordRevisionKind.moveTo)), story, out, pIndex, pBookmarks);
        case 'fldSimple':
          final field = _Field(instr: c.attr('instr') ?? '')..inResult = true;
          story.fields.add(field);
          _inlines(c, ic.child(link: _fieldLink(field.code)), story, out, pIndex, pBookmarks);
          story.fields.remove(field);
        case 'sdt':
          final kind = _controlKind(c.w('sdtPr'));
          final content = c.w('sdtContent');
          if (content != null) _inlines(content, ic.child(control: kind), story, out, pIndex, pBookmarks);
        case 'smartTag' || 'customXml' || 'dir' || 'bdo':
          _inlines(c, ic, story, out, pIndex, pBookmarks);
        case 'bookmarkStart':
          final name = c.attr('name');
          if (name != null && name != '_GoBack') {
            pBookmarks.add(name);
            _bookmark(c, pIndex);
          }
        case 'commentRangeStart':
          final id = c.attr('id');
          if (id != null) story.activeComments.add(id);
        case 'commentRangeEnd':
          story.activeComments.remove(c.attr('id'));
      }
    }
  }

  String? _controlKind(XmlElement? sdtPr) {
    if (sdtPr == null) return 'richText';
    for (final e in sdtPr.childElements) {
      switch (e.name.local) {
        case 'checkbox':
          return 'checkBox';
        case 'dropDownList':
          return 'dropDown';
        case 'comboBox':
          return 'comboBox';
        case 'date':
          return 'date';
        case 'picture':
          return 'picture';
        case 'text':
          return 'plainText';
        case 'repeatingSection' || 'repeatingSectionItem':
          return 'repeatingSection';
        case 'docPartObj' || 'docPartList':
          return 'buildingBlock';
        case 'citation' || 'bibliography':
          return null;
      }
    }
    return 'richText';
  }

  /// Links made by fields: HYPERLINK, and REF or PAGEREF with \h.
  WordLink? _fieldLink(String code) {
    final m = RegExp(r'^\s*(\w+)\s*(.*)$', dotAll: true).firstMatch(code);
    if (m == null) return null;
    final name = m.group(1)!.toUpperCase();
    final rest = m.group(2)!;
    String? quoted(String s) => RegExp(r'"([^"]*)"').firstMatch(s)?.group(1);
    if (name == 'HYPERLINK') {
      final anchor = RegExp(r'\\l\s+"([^"]*)"').firstMatch(rest)?.group(1);
      final tip = RegExp(r'\\o\s+"([^"]*)"').firstMatch(rest)?.group(1);
      final url = rest.trimLeft().startsWith('"') ? quoted(rest) : null;
      return WordLink(url: url, anchor: anchor, tooltip: tip);
    }
    if ((name == 'REF' || name == 'PAGEREF' || name == 'NOTEREF') && rest.contains(r'\h')) {
      final target = rest.trim().split(RegExp(r'\s+')).first;
      return WordLink(anchor: target);
    }
    return null;
  }

  // ------------------------------------------------------------ runs

  void _run(XmlElement r, _InlineCtx ic, _Story story, List<WordInline> out) {
    final rPr = r.w('rPr');
    final props = ic.base.copy();
    final rStyle = rPr?.wVal('rStyle');
    if (rStyle != null) props.merge(styles.styleRun(rStyle));
    props.apply(rPr, theme);
    final style = props.toStyle();
    var revision = ic.revision;
    if (revision == null && rPr?.w('rPrChange') != null) {
      revision = _revision(rPr!.w('rPrChange')!, WordRevisionKind.format);
    }
    final fields = story.fields;

    bool hiddenByField() => fields.isNotEmpty && !fields.last.inResult;

    List<String> fieldCodes() => List.unmodifiable([
      for (final f in fields)
        if (f.inResult) f.code,
    ]);

    String? fieldCode() {
      for (var i = fields.length - 1; i >= 0; i--) {
        if (fields[i].inResult) return fields[i].code;
      }
      return null;
    }

    WordLink? link() {
      if (ic.link != null) return ic.link;
      for (var i = fields.length - 1; i >= 0; i--) {
        final l = _fieldLink(fields[i].code);
        if (l != null) return l;
      }
      return null;
    }

    void text(String t) {
      if (t.isEmpty || hiddenByField()) return;
      for (final f in fields) {
        f.shownSomething = true;
      }
      out.add(
        WordText(
          t,
          style,
          link: link(),
          revision: revision,
          commentIds: List.unmodifiable(story.activeComments),
          field: fieldCode(),
          fields: fieldCodes(),
          contentControl: ic.control,
        ),
      );
    }

    void visit(XmlElement c) {
      final ns = nsOf(c);
      if (ns == 'mc' && c.name.local == 'AlternateContent') {
        for (final x in (c.el('mc', 'Choice') ?? c.el('mc', 'Fallback'))?.childElements ?? const <XmlElement>[]) {
          visit(x);
        }
        return;
      }
      if (ns != 'w') return;
      switch (c.name.local) {
        case 'fldChar':
          switch (c.attr('fldCharType')) {
            case 'begin':
              fields.add(_Field(ffData: c.w('ffData')));
            case 'separate':
              if (fields.isNotEmpty) fields.last.inResult = true;
            case 'end':
              if (fields.isEmpty) return;
              final f = fields.removeLast();
              final shown = _formFieldText(f);
              if (shown != null) {
                text(shown);
              } else if (!f.shownSomething && !hiddenByField() && RegExp(r'^(PAGE|NUMPAGES|SECTIONPAGES|SECTION)\b').hasMatch(f.code)) {
                // Page fields saved without a value: the viewer fills them in.
                out.add(WordText('1', style, field: f.code, fields: [...fieldCodes(), f.code], link: ic.link, revision: revision));
                for (final o in fields) {
                  o.shownSomething = true;
                }
              }
          }
        case 'instrText':
          if (fields.isNotEmpty && !fields.last.inResult) fields.last.instr.write(c.innerText);
        case 't' || 'delText':
          // A tab typed straight into the text acts like <w:tab/>.
          final parts = c.innerText.split('\t');
          for (var k = 0; k < parts.length; k++) {
            if (k > 0 && !hiddenByField()) out.add(WordTab(style));
            text(parts[k]);
          }
        case 'tab':
          if (!hiddenByField()) out.add(WordTab(style));
        case 'ptab':
          if (!hiddenByField()) out.add(WordTab(style, absoluteAlign: c.attr('alignment') ?? 'left', leader: c.attr('leader')));
        case 'br':
          if (hiddenByField()) return;
          out.add(
            WordBreak(switch (c.attr('type')) {
              'page' => WordBreakKind.page,
              'column' => WordBreakKind.column,
              'textWrapping' => c.attr('clear') == null || c.attr('clear') == 'none' ? WordBreakKind.line : WordBreakKind.textWrapping,
              _ => WordBreakKind.line,
            }),
          );
        case 'cr':
          if (!hiddenByField()) out.add(const WordBreak(WordBreakKind.line));
        case 'sym':
          final code = int.tryParse(c.attr('char') ?? '', radix: 16);
          if (code == null || hiddenByField()) return;
          final font = c.attr('font');
          final f = font?.toLowerCase() ?? '';
          final isSymbolFont = f.startsWith('wingdings') || f == 'symbol' || f.startsWith('webdings');
          if (isSymbolFont || font == null) {
            text(mapSymbolChar(code, font));
          } else {
            // A plain font named on the symbol (e.g. MS Gothic for check boxes).
            final symProps = props.copy()..font = font;
            for (final f in fields) {
              f.shownSomething = true;
            }
            out.add(WordText(mapSymbolChar(code, font), symProps.toStyle(), link: link(), revision: revision, commentIds: List.unmodifiable(story.activeComments), contentControl: ic.control));
          }
        case 'noBreakHyphen':
          text('\u2011');
        case 'softHyphen':
          text('\u00AD');
        case 'drawing':
          if (hiddenByField()) return;
          final d = _drawing(c, story);
          if (d != null) out.add(d);
        case 'pict' || 'object':
          if (hiddenByField()) return;
          final d = _vml(c, story);
          if (d != null) out.add(d);
        case 'footnoteReference' || 'endnoteReference':
          final id = c.attr('id');
          if (id == null) return;
          final foot = c.name.local == 'footnoteReference';
          final labels = foot ? footnoteLabels : endnoteLabels;
          final label = isTrue(c.attr('customMarkFollows'))
              ? ''
              : labels.putIfAbsent(id, () => formatNumber(labels.length + 1, foot ? footnoteFormat : endnoteFormat));
          out.add(WordNoteRef(kind: foot ? WordNoteKind.footnote : WordNoteKind.endnote, id: id, label: label, style: style));
        case 'footnoteRef' || 'endnoteRef':
          final label = _currentNoteLabel ?? '';
          out.add(
            WordNoteRef(
              kind: c.name.local == 'footnoteRef' ? WordNoteKind.footnote : WordNoteKind.endnote,
              id: '',
              label: label,
              style: style,
            ),
          );
        case 'commentReference':
          final id = c.attr('id');
          if (id != null) out.add(WordCommentMark(id));
      }
    }

    for (final c in r.childElements) {
      visit(c);
    }
  }

  /// Legacy form fields keep their state in ffData: a check box draws a box,
  /// a drop-down shows its chosen entry.
  String? _formFieldText(_Field f) {
    final ff = f.ffData;
    if (ff == null || f.shownSomething) return null;
    final box = ff.w('checkBox');
    if (box != null) {
      final checked = onOff(box.w('checked')) ?? onOff(box.w('default')) ?? false;
      return checked ? '☒' : '☐';
    }
    final dd = ff.w('ddList');
    if (dd != null) {
      final entries = [for (final e in dd.els('w', 'listEntry')) e.attr('val') ?? ''];
      final idx = int.tryParse(dd.wVal('result') ?? dd.wVal('default') ?? '0') ?? 0;
      return entries.isEmpty ? null : '${entries[idx.clamp(0, entries.length - 1)]} ▾';
    }
    final input = ff.w('textInput');
    if (input != null) return input.wVal('default') ?? '     ';
    return null;
  }

  // ------------------------------------------------------------ drawings

  WordInline? _drawing(XmlElement drawing, _Story story) {
    final frame = drawing.childElements.where((e) => nsOf(e) == 'wp').firstOrNull;
    if (frame == null) return null;
    final extent = frame.el('wp', 'extent');
    final width = emu(extent?.attr('cx')), height = emu(extent?.attr('cy'));
    final docPr = frame.el('wp', 'docPr');
    final anchor = frame.name.local == 'anchor' ? _anchor(frame) : null;
    final data = frame.find('a', 'graphicData');
    if (data == null) return null;
    final uri = data.attr('uri') ?? '';
    try {
      if (uri.endsWith('/picture')) {
        final pic = data.el('pic', 'pic');
        if (pic == null) return null;
        return _picture(pic, story, width: width, height: height, alt: docPr?.attr('descr'), title: docPr?.attr('title'), anchor: anchor);
      }
      if (uri.endsWith('/wordprocessingShape')) {
        final wsp = data.el('wps', 'wsp');
        if (wsp == null) return null;
        return _shape(wsp, story, width: width, height: height, anchor: anchor, name: docPr?.attr('name'));
      }
      if (uri.endsWith('/chart')) {
        final rel = pkg.rels(story.part)[data.el('c', 'chart')?.attr('id')];
        final xml = rel == null ? null : pkg.xml(rel.target);
        if (xml == null) return WordUnsupported('Chart', width: width, height: height);
        return ChartReader.read(xml, theme, width: width, height: height, anchor: anchor);
      }
      if (uri.endsWith('/wordprocessingGroup')) {
        return _group(data.el('wpg', 'wgp'), story, width: width, height: height, anchor: anchor);
      }
      if (uri.endsWith('/diagram')) return WordUnsupported('SmartArt', width: width, height: height);
      return WordUnsupported('Object', width: width, height: height);
    } on Object catch (e) {
      warnings.add('A picture or shape could not be read ($e).');
      return WordUnsupported('Picture', width: width, height: height);
    }
  }

  WordAnchor _anchor(XmlElement a) {
    String wrap = 'none';
    for (final c in a.childElements) {
      if (c.name.local.startsWith('wrap')) {
        wrap = switch (c.name.local) {
          'wrapSquare' => 'square',
          'wrapTight' => 'tight',
          'wrapThrough' => 'through',
          'wrapTopAndBottom' => 'topAndBottom',
          _ => 'none',
        };
      }
    }
    final h = a.el('wp', 'positionH'), v = a.el('wp', 'positionV');
    return WordAnchor(
      wrap: wrap,
      behindText: isTrue(a.attr('behindDoc')),
      alignH: h?.el('wp', 'align')?.innerText,
      alignV: v?.el('wp', 'align')?.innerText,
      offsetX: emu(h?.el('wp', 'posOffset')?.innerText),
      offsetY: emu(v?.el('wp', 'posOffset')?.innerText),
      relativeH: h?.attr('relativeFrom') ?? 'column',
      relativeV: v?.attr('relativeFrom') ?? 'paragraph',
    );
  }

  WordDrawingStyle _look(XmlElement? spPr, {XmlElement? styleEl}) {
    final xfrm = spPr?.el('a', 'xfrm');
    final ln = spPr?.el('a', 'ln');
    int? lineColor;
    var lineWidth = 0.0;
    if (ln != null && ln.el('a', 'noFill') == null) {
      lineColor = theme.drawingColor(ln.el('a', 'solidFill')) ?? theme.drawingColor(styleEl?.el('a', 'lnRef'));
      lineWidth = ln.attr('w') == null ? 0.75 : emu(ln.attr('w'));
      if (lineColor == null && ln.el('a', 'gradFill') != null) {
        lineColor = theme.drawingColor(ln.el('a', 'gradFill')?.find('a', 'gs'));
      }
    } else if (ln == null && styleEl != null) {
      lineColor = theme.drawingColor(styleEl.el('a', 'lnRef'));
      lineWidth = lineColor == null ? 0 : 0.75;
    }
    final shdw = spPr?.el('a', 'effectLst')?.el('a', 'outerShdw');
    WordShadow? shadow;
    if (shdw != null) {
      final dist = emu(shdw.attr('dist'));
      final dir = (double.tryParse(shdw.attr('dir') ?? '') ?? 2700000) / 60000;
      shadow = WordShadow(
        color: theme.drawingColor(shdw) ?? 0x66000000,
        blur: emu(shdw.attr('blurRad')),
        dx: dist * _cos(dir),
        dy: dist * _sin(dir),
      );
    }
    return WordDrawingStyle(
      rotation: (double.tryParse(xfrm?.attr('rot') ?? '') ?? 0) / 60000,
      flipH: isTrue(xfrm?.attr('flipH')),
      flipV: isTrue(xfrm?.attr('flipV')),
      outlineColor: lineColor,
      outlineWidth: lineWidth,
      outlineDash: ln?.el('a', 'prstDash')?.attr('val'),
      shadow: shadow,
    );
  }

  WordInline _picture(XmlElement pic, _Story story, {required double width, required double height, String? alt, String? title, WordAnchor? anchor}) {
    final blip = pic.find('a', 'blip');
    final rel = pkg.rels(story.part)[blip?.attr('embed')];
    final bytes = rel == null || rel.external ? null : pkg.bytes(rel.target);
    if (bytes == null) return WordUnsupported(alt ?? 'Picture', width: width, height: height);
    final svgBlip = blip?.descendantElements.where((e) => e.name.local == 'svgBlip').firstOrNull;
    final svgRel = svgBlip == null ? null : pkg.rels(story.part)[svgBlip.attr('embed')];
    final ext = rel!.target.split('.').last.toLowerCase();
    if (ext == 'emf' || ext == 'wmf' || ext == 'tif' || ext == 'tiff') {
      return WordUnsupported(alt ?? 'Picture (${ext.toUpperCase()})', width: width, height: height);
    }
    final src = pic.find('a', 'srcRect');
    double pct(String a) => (double.tryParse(src?.attr(a) ?? '') ?? 0) / 100000;
    final spPr = pic.el('pic', 'spPr');
    final geom = spPr?.el('a', 'prstGeom')?.attr('prst');
    final alpha = blip!.el('a', 'alphaModFix')?.attr('amt');
    return WordPicture(
      bytes: bytes,
      width: width,
      height: height,
      contentType: ext,
      altText: alt,
      title: title,
      anchor: anchor,
      look: _look(spPr),
      crop: WordInsets(left: pct('l'), top: pct('t'), right: pct('r'), bottom: pct('b')),
      grayscale: blip.el('a', 'grayscl') != null,
      opacity: alpha == null ? 1 : (double.tryParse(alpha) ?? 100000) / 100000,
      shape: geom == null || geom == 'rect' ? null : geom,
      hasSvg: svgRel != null,
      svg: svgRel == null || svgRel.external ? null : pkg.bytes(svgRel.target),
    );
  }

  WordShape _shape(XmlElement wsp, _Story story, {required double width, required double height, WordAnchor? anchor, String? name}) {
    final spPr = wsp.el('wps', 'spPr');
    final styleEl = wsp.el('wps', 'style');
    final geom = spPr?.el('a', 'prstGeom')?.attr('prst') ?? (spPr?.el('a', 'custGeom') != null ? 'custom' : 'rect');
    int? fill;
    var gradient = <int>[];
    var angle = 0.0;
    final grad = spPr?.el('a', 'gradFill');
    if (spPr?.el('a', 'solidFill') != null) {
      fill = theme.drawingColor(spPr!.el('a', 'solidFill'));
    } else if (grad != null) {
      gradient = [for (final gs in grad.el('a', 'gsLst')?.els('a', 'gs') ?? const <XmlElement>[]) theme.drawingColor(gs) ?? 0xFF000000];
      angle = (double.tryParse(grad.el('a', 'lin')?.attr('ang') ?? '') ?? 0) / 60000;
    } else if (spPr?.el('a', 'noFill') == null && styleEl != null) {
      fill = theme.drawingColor(styleEl.el('a', 'fillRef'));
    }
    final txbx = wsp.el('wps', 'txbx')?.w('txbxContent');
    final body = wsp.el('wps', 'bodyPr');
    final vert = body?.attr('vert');
    double inset(String a, double fallback) => body?.attr(a) == null ? fallback : emu(body!.attr(a));
    return WordShape(
      geometry: geom,
      width: width,
      height: height,
      fill: fill,
      gradient: gradient,
      gradientAngle: angle,
      look: _look(spPr, styleEl: styleEl),
      blocks: txbx == null ? const [] : _blocks(txbx, story),
      anchor: anchor,
      verticalText: vert == null || vert == 'horz' ? null : vert,
      wordArt: body?.el('a', 'prstTxWarp')?.attr('prst'),
      insets: WordInsets(left: inset('lIns', 7.2), top: inset('tIns', 3.6), right: inset('rIns', 7.2), bottom: inset('bIns', 3.6)),
      textAnchor: body?.attr('anchor') ?? 't',
      name: name,
    );
  }

  /// A drawing group: its shapes and pictures are stacked as one text box.
  WordInline _group(XmlElement? wgp, _Story story, {required double width, required double height, WordAnchor? anchor}) {
    if (wgp == null) return WordUnsupported('Group', width: width, height: height);
    final parts = <WordInline>[];
    for (final c in wgp.childElements) {
      final xfrm = c.find('a', 'xfrm');
      final ext = xfrm?.el('a', 'ext');
      final w = emu(ext?.attr('cx')), h = emu(ext?.attr('cy'));
      if (isEl(c, 'wps', 'wsp')) parts.add(_shape(c, story, width: w, height: h));
      if (isEl(c, 'pic', 'pic')) parts.add(_picture(c, story, width: w, height: h));
    }
    return WordShape(
      geometry: 'rect',
      width: width,
      height: height,
      anchor: anchor,
      blocks: [WordParagraph(index: _paragraphIndex++, style: const WordParagraphStyle(), inlines: parts)],
      insets: const WordInsets(),
      name: 'Group',
    );
  }

  /// Old VML pictures, text boxes and WordArt (`w:pict`).
  WordInline? _vml(XmlElement pict, _Story story) {
    final shape = pict.descendantElements.where((e) => nsOf(e) == 'v' && const {'shape', 'rect', 'roundrect', 'oval', 'line'}.contains(e.name.local)).firstOrNull;
    if (shape == null) return null;
    final css = <String, String>{};
    for (final part in (shape.attr('style') ?? '').split(';')) {
      final kv = part.split(':');
      if (kv.length == 2) css[kv[0].trim()] = kv[1].trim();
    }
    double size(String k) => (parseNum(css[k]) ?? 1440) / 20;
    final w = size('width'), h = size('height');
    final image = shape.el('v', 'imagedata');
    if (image != null) {
      final rel = pkg.rels(story.part)[image.attr('id')];
      final bytes = rel == null || rel.external ? null : pkg.bytes(rel.target);
      if (bytes == null) return WordUnsupported(image.attr('title') ?? 'Picture', width: w, height: h);
      final ext = rel!.target.split('.').last.toLowerCase();
      if (ext == 'emf' || ext == 'wmf') return WordUnsupported(pict.name.local == 'object' ? 'Embedded object' : 'Picture', width: w, height: h);
      return WordPicture(bytes: bytes, width: w, height: h, contentType: ext, altText: image.attr('title'));
    }
    final textpath = shape.el('v', 'textpath');
    final textbox = shape.el('v', 'textbox')?.w('txbxContent');
    final fill = hexColor(shape.attr('fillcolor')?.replaceFirst('#', ''));
    final stroke = hexColor(shape.attr('strokecolor')?.replaceFirst('#', ''));
    final geom = switch (shape.name.local) {
      'oval' => 'ellipse',
      'roundrect' => 'roundRect',
      'line' => 'line',
      _ => 'rect',
    };
    List<WordBlock> blocks = const [];
    if (textbox != null) {
      blocks = _blocks(textbox, story);
    } else if (textpath != null) {
      blocks = [
        WordParagraph(
          index: _paragraphIndex++,
          style: const WordParagraphStyle(align: WordAlign.center),
          inlines: [WordText(textpath.attr('string') ?? '', WordRunStyle(size: h * 0.6, color: fill ?? 0xFFC0C0C0, bold: true))],
        ),
      ];
    }
    return WordShape(
      geometry: geom,
      width: w,
      height: h,
      fill: textpath != null || shape.attr('filled') == 'f' ? null : fill,
      look: WordDrawingStyle(
        outlineColor: shape.attr('stroked') == 'f' || textpath != null ? null : stroke ?? 0xFF000000,
        outlineWidth: 0.75,
        rotation: double.tryParse(css['rotation'] ?? '') ?? 0,
      ),
      blocks: blocks,
      wordArt: textpath == null ? null : 'vml',
      anchor: css['position'] == 'absolute' ? const WordAnchor(behindText: true) : null,
    );
  }

  // ------------------------------------------------------------ tables

  WordTable _table(XmlElement tbl, _Story story) {
    final tblPr = tbl.w('tblPr');
    final styleId = tblPr?.wVal('tblStyle') ?? styles.defaultTableStyle;
    final chain = styles.chain(styleId);
    // Table style parts, root of the basedOn chain first.
    XmlElement? styleTblPr, styleTcPr;
    final conditional = <String, XmlElement>{};
    var styleBorders = const WordBorders();
    WordInsets? styleMargins;
    final styleRun = RunProps(), stylePara = ParaProps();
    for (final s in chain) {
      styleTblPr = s.tblPr ?? styleTblPr;
      styleTcPr = s.tcPr ?? styleTcPr;
      styleBorders = styleBorders.merge(bordersOf(s.tblPr?.w('tblBorders'), theme));
      styleMargins = _margins(s.tblPr?.w('tblCellMar'), styleMargins);
      styleRun.apply(s.rPr, theme);
      stylePara.apply(s.pPr, theme);
      conditional.addAll(s.conditional);
    }
    final borders = styleBorders.merge(bordersOf(tblPr?.w('tblBorders'), theme));
    final defaultMargins = _margins(tblPr?.w('tblCellMar'), styleMargins) ?? const WordInsets(left: 5.4, right: 5.4);

    final look = tblPr?.w('tblLook');
    bool lookFlag(String name, int bit, bool fallback) {
      final a = look?.attr(name);
      if (a != null) return isTrue(a);
      final v = int.tryParse(look?.attr('val') ?? '', radix: 16);
      return v == null ? fallback : (v & bit) != 0;
    }

    final firstRow = lookFlag('firstRow', 0x20, true);
    final lastRow = lookFlag('lastRow', 0x40, false);
    final firstCol = lookFlag('firstColumn', 0x80, true);
    final lastCol = lookFlag('lastColumn', 0x100, false);
    final bandH = !lookFlag('noHBand', 0x200, false);
    final bandV = !lookFlag('noVBand', 0x400, true);

    final grid = [for (final g in tbl.w('tblGrid')?.els('w', 'gridCol') ?? const <XmlElement>[]) twips(g.attr('w')) ?? 0];
    final rowEls = <XmlElement>[];
    void collectRows(XmlElement e) {
      for (final c in e.childElements) {
        if (isEl(c, 'w', 'tr')) {
          rowEls.add(c);
        } else if (isEl(c, 'w', 'sdt') || isEl(c, 'w', 'customXml')) {
          collectRows(c.w('sdtContent') ?? c);
        }
      }
    }

    collectRows(tbl);
    final rows = <WordTableRow>[];
    final restartAt = <int, WordTableCell>{}; // grid column -> cell that started a vertical merge
    final bodyRowCount = rowEls.length;
    for (var ri = 0; ri < rowEls.length; ri++) {
      final tr = rowEls[ri];
      final trPr = tr.w('trPr');
      final isFirst = ri == 0, isLast = ri == bodyRowCount - 1;
      final bandIndex = ri - (firstRow ? 1 : 0);
      final cellEls = <XmlElement>[];
      void collectCells(XmlElement e) {
        for (final c in e.childElements) {
          if (isEl(c, 'w', 'tc')) {
            cellEls.add(c);
          } else if (isEl(c, 'w', 'sdt') || isEl(c, 'w', 'customXml')) {
            collectCells(c.w('sdtContent') ?? c);
          }
        }
      }

      collectCells(tr);
      final gridBefore = int.tryParse(trPr?.wVal('gridBefore') ?? '') ?? 0;
      var col = gridBefore;
      final cells = <WordTableCell>[];
      for (var ci = 0; ci < cellEls.length; ci++) {
        final tc = cellEls[ci];
        final tcPr = tc.w('tcPr');
        final span = int.tryParse(tcPr?.wVal('gridSpan') ?? '') ?? 1;
        final isFirstCol = col == 0, isLastCol = col + span >= grid.length;
        // Conditional formatting, weakest first.
        final types = <String>[
          if (bandV && !(firstCol && isFirstCol) && !(lastCol && isLastCol)) ((col - (firstCol ? 1 : 0)) % 2 == 0 ? 'band1Vert' : 'band2Vert'),
          if (bandH && !(firstRow && isFirst) && !(lastRow && isLast)) (bandIndex % 2 == 0 ? 'band1Horz' : 'band2Horz'),
          if (firstCol && isFirstCol) 'firstCol',
          if (lastCol && isLastCol) 'lastCol',
          if (firstRow && isFirst) 'firstRow',
          if (lastRow && isLast) 'lastRow',
          if (firstRow && isFirst && firstCol && isFirstCol) 'nwCell',
          if (firstRow && isFirst && lastCol && isLastCol) 'neCell',
          if (lastRow && isLast && firstCol && isFirstCol) 'swCell',
          if (lastRow && isLast && lastCol && isLastCol) 'seCell',
        ];
        final run = styleRun.copy(), para = stylePara.copy();
        int? shading = styleTcPr?.w('shd') == null ? null : shadingOf(styleTcPr!.w('shd')!, theme);
        var cellBorders = WordBorders(
          top: isFirst ? borders.top : borders.insideH,
          bottom: isLast ? borders.bottom : borders.insideH,
          left: isFirstCol ? borders.left : borders.insideV,
          right: isLastCol ? borders.right : borders.insideV,
        );
        for (final t in types) {
          final c = conditional[t];
          if (c == null) continue;
          run.apply(c.w('rPr'), theme);
          para.apply(c.w('pPr'), theme);
          final shd = c.w('tcPr')?.w('shd');
          if (shd != null) shading = shadingOf(shd, theme);
          final b = bordersOf(c.w('tcPr')?.w('tcBorders'), theme);
          if (b != null) {
            cellBorders = cellBorders.merge(b);
            // A part's inside lines apply between its own cells.
            if (b.insideH != null) {
              cellBorders = cellBorders.copyWith(top: isFirst ? null : b.insideH, bottom: isLast ? null : b.insideH);
            }
          }
          final tb = bordersOf(c.w('tblPr')?.w('tblBorders'), theme);
          if (tb != null) cellBorders = cellBorders.merge(tb);
        }
        if (tcPr?.w('shd') != null) shading = shadingOf(tcPr!.w('shd')!, theme);
        cellBorders = cellBorders.merge(bordersOf(tcPr?.w('tcBorders'), theme));

        final vMerge = tcPr?.w('vMerge');
        final vMergeVal = vMerge?.attr('val');
        final continues = vMerge != null && vMergeVal != 'restart';
        final margins = _margins(tcPr?.w('tcMar'), defaultMargins) ?? defaultMargins;
        final vAlign = switch (tcPr?.wVal('vAlign')) {
          'center' => WordCellVAlign.center,
          'bottom' => WordCellVAlign.bottom,
          _ => WordCellVAlign.top,
        };
        WordTableCell cell;
        if (continues && restartAt[col] != null) {
          final top = restartAt[col]!;
          top.rowSpan++;
          top.borders = top.borders.copyWith(clearBottom: true);
          cell = WordTableCell(
            blocks: const [],
            colSpan: span,
            mergedAway: true,
            shading: top.shading,
            borders: cellBorders.copyWith(clearTop: true, left: top.borders.left, right: top.borders.right),
            margins: margins,
          );
        } else {
          cell = WordTableCell(
            blocks: _blocks(tc, story, _CellFormat(run, para)),
            colSpan: span,
            shading: shading,
            borders: cellBorders,
            vAlign: vAlign,
            textDirection: tcPr?.wVal('textDirection'),
            margins: margins,
          );
          if (vMergeVal == 'restart') {
            restartAt[col] = cell;
          } else {
            restartAt.remove(col);
          }
        }
        cells.add(cell);
        col += span;
      }
      final height = trPr?.w('trHeight');
      final ins = trPr?.w('ins'), del = trPr?.w('del');
      rows.add(
        WordTableRow(
          cells: cells,
          header: onOff(trPr?.w('tblHeader')) ?? false,
          cantSplit: onOff(trPr?.w('cantSplit')) ?? false,
          height: twips(height?.attr('val')),
          exactHeight: height?.attr('hRule') == 'exact',
          revision: ins != null
              ? _revision(ins, WordRevisionKind.insert)
              : del != null
              ? _revision(del, WordRevisionKind.delete)
              : null,
        ),
      );
    }
    // A grid missing or too short: make equal columns.
    var columns = grid;
    final maxCols = rows.fold<int>(0, (m, r) => r.cells.fold<int>(0, (a, c) => a + c.colSpan) > m ? r.cells.fold<int>(0, (a, c) => a + c.colSpan) : m);
    if (columns.length < maxCols || columns.every((c) => c == 0)) {
      final total = twips(tblPr?.w('tblW')?.attr('w')) ?? 451;
      columns = List.filled(maxCols, total / (maxCols == 0 ? 1 : maxCols));
    }
    // A floating table's side comes from its position.
    final jc = tblPr?.w('tblpPr')?.attr('tblpXSpec') ?? tblPr?.wVal('jc');
    return WordTable(
      columns: columns,
      rows: rows,
      align: switch (jc) {
        'center' => WordAlign.center,
        'right' || 'end' => WordAlign.right,
        _ => WordAlign.left,
      },
      indent: twips(tblPr?.w('tblInd')?.attr('w')) ?? 0,
      cellSpacing: twips(tblPr?.w('tblCellSpacing')?.attr('w')) ?? 0,
      floating: tblPr?.w('tblpPr') != null,
      styleId: styleId,
    );
  }

  WordInsets? _margins(XmlElement? mar, WordInsets? fallback) {
    if (mar == null) return fallback;
    double side(String a, String b, double f) => twips(mar.w(a)?.attr('w') ?? mar.w(b)?.attr('w')) ?? f;
    final f = fallback ?? const WordInsets(left: 5.4, right: 5.4);
    return WordInsets(
      top: side('top', 'top', f.top),
      left: side('left', 'start', f.left),
      bottom: side('bottom', 'bottom', f.bottom),
      right: side('right', 'end', f.right),
    );
  }

  // ------------------------------------------------------------ notes, comments, properties

  Map<String, WordNote> _notes(WordNoteKind kind) {
    final foot = kind == WordNoteKind.footnote;
    final path = pkg.related(main, foot ? 'footnotes' : 'endnotes');
    final xml = path == null ? null : pkg.xml(path);
    if (xml == null) return const {};
    final labels = foot ? footnoteLabels : endnoteLabels;
    final out = <String, WordNote>{};
    for (final n in xml.rootElement.els('w', foot ? 'footnote' : 'endnote')) {
      final id = n.attr('id');
      final type = n.attr('type');
      if (id == null || (type != null && type != 'normal')) continue;
      final label = labels[id];
      if (label == null) continue;
      _currentNoteLabel = label;
      out[id] = WordNote(id: id, kind: kind, label: label, blocks: _blocks(n, _Story(path!)));
      _currentNoteLabel = null;
    }
    return out;
  }

  List<WordComment> _comments() {
    final path = pkg.related(main, 'comments');
    final xml = path == null ? null : pkg.xml(path);
    if (xml == null) return const [];
    final extPath = pkg.related(main, 'commentsExtended');
    final ext = extPath == null ? null : pkg.xml(extPath);
    final extended = <String, ({String? parent, bool done})>{};
    for (final c in ext?.rootElement.childElements ?? const <XmlElement>[]) {
      final pid = c.attr('paraId');
      if (pid != null) extended[pid] = (parent: c.attr('paraIdParent'), done: isTrue(c.attr('done')));
    }
    final raw = <({String id, String? paraId, XmlElement el})>[];
    for (final c in xml.rootElement.els('w', 'comment')) {
      final id = c.attr('id');
      if (id == null) continue;
      final paras = c.els('w', 'p').toList();
      raw.add((id: id, paraId: paras.isEmpty ? null : paras.last.attr('paraId'), el: c));
    }
    final idByPara = {for (final r in raw) if (r.paraId != null) r.paraId!: r.id};
    return [
      for (final r in raw)
        WordComment(
          id: r.id,
          author: r.el.attr('author'),
          initials: r.el.attr('initials'),
          date: parseDate(r.el.attr('date')),
          blocks: _blocks(r.el, _Story(path!)),
          parentId: idByPara[extended[r.paraId]?.parent],
          resolved: extended[r.paraId]?.done ?? false,
        ),
    ];
  }

  WordProperties _properties() {
    String? coreText(XmlElement? root, String local) {
      for (final e in root?.childElements ?? const <XmlElement>[]) {
        if (e.name.local == local) {
          final t = e.innerText.trim();
          return t.isEmpty ? null : t;
        }
      }
      return null;
    }

    String? corePath, appPath, customPath;
    for (final r in pkg.rels('').values) {
      if (r.type.endsWith('/core-properties')) corePath = r.target;
      if (r.type.endsWith('/extended-properties')) appPath = r.target;
      if (r.type.endsWith('/custom-properties')) customPath = r.target;
    }
    final core = pkg.xml(corePath ?? 'docProps/core.xml')?.rootElement;
    final app = pkg.xml(appPath ?? 'docProps/app.xml')?.rootElement;
    final custom = pkg.xml(customPath ?? 'docProps/custom.xml')?.rootElement;
    return WordProperties(
      title: coreText(core, 'title'),
      subject: coreText(core, 'subject'),
      author: coreText(core, 'creator'),
      keywords: coreText(core, 'keywords'),
      description: coreText(core, 'description'),
      category: coreText(core, 'category'),
      lastModifiedBy: coreText(core, 'lastModifiedBy'),
      created: parseDate(coreText(core, 'created')),
      modified: parseDate(coreText(core, 'modified')),
      company: coreText(app, 'Company'),
      application: coreText(app, 'Application'),
      pages: int.tryParse(coreText(app, 'Pages') ?? ''),
      words: int.tryParse(coreText(app, 'Words') ?? ''),
      custom: {
        for (final p in custom?.childElements ?? const <XmlElement>[])
          if (p.getAttribute('name') != null) p.getAttribute('name')!: p.innerText.trim(),
      },
    );
  }
}

double _cos(double deg) => math.cos(deg * math.pi / 180);
double _sin(double deg) => math.sin(deg * math.pi / 180);
