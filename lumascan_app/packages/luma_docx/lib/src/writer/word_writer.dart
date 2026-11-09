import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../model.dart';
import '../reader/xml_util.dart' show highlightColors;
import 'xlsx.dart';

/// Saves a [WordDocument] as a .docx file.
///
/// Everything the reader takes out of a file is written back: sections and
/// page setup, headers and footers, paragraphs with their formatting, lists,
/// tables, pictures, shapes and text boxes, charts, equations, links and
/// bookmarks, fields, content controls, footnotes and endnotes, comments
/// with replies, tracked changes and document properties.
///
/// Formatting is written on each paragraph and run (styles keep only their
/// names and outline levels), so the file looks the same in any Word
/// version. Things the model does not keep are not written: SmartArt and
/// embedded objects (they come out as their placeholder), the form field
/// settings of legacy form fields, and the data workbook behind a chart
/// (the chart keeps its numbers).
class WordWriter {
  WordWriter._(this.doc);

  final WordDocument doc;

  /// Writes [doc] as the bytes of a .docx file.
  static Uint8List write(WordDocument doc) => WordWriter._(doc)._build();

  // ------------------------------------------------------------ package

  final _files = <String, List<int>>{};
  final _overrides = <String, String>{};
  final _media = <String, String>{}; // content hash -> media path
  var _mediaCount = 0;
  var _chartCount = 0;
  var _docPrId = 0;
  var _revisionId = 0;
  var _paraId = 0x10000000;
  var _shapeOrder = 251658240;

  final _lists = <String, _ListDef>{};
  final _picBullets = <String, int>{}; // hash -> numPicBulletId
  final _picBulletXml = <int, String>{};
  final _styles = <String, _StyleUse>{};
  final _tableStyles = <String>{};
  final _commentParaIds = <String, String>{};

  Uint8List _build() {
    final mainPart = _Part('word/document.xml');
    final body = StringBuffer();
    final sections = doc.sections;
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      final sectPr = _sectPr(s, mainPart);
      final last = i == sections.length - 1;
      _blocks(body, s.blocks, mainPart, trailingSectPr: last ? null : sectPr);
      if (last) body.write(sectPr);
    }
    final background = doc.pageColor == null ? '' : '<w:background w:color="${_hex(doc.pageColor!)}"/>';
    _xmlPart(mainPart, 'w:document', '$background<w:body>$body</w:body>', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml');

    _notes(mainPart, 'footnotes', 'footnote', doc.footnotes);
    _notes(mainPart, 'endnotes', 'endnote', doc.endnotes);
    _comments(mainPart);

    _add(mainPart, 'styles', 'styles.xml', _stylesXml(), 'application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml');
    _add(mainPart, 'settings', 'settings.xml', _settingsXml(), 'application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml');
    if (_lists.isNotEmpty) {
      _add(mainPart, 'numbering', 'numbering.xml', _numberingXml(mainPart), 'application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml');
      _writeRels(_numberingPart);
    }
    _writeRels(mainPart);
    _properties();

    final types = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Default Extension="jpeg" ContentType="image/jpeg"/>'
      '<Default Extension="gif" ContentType="image/gif"/>'
      '<Default Extension="bmp" ContentType="image/bmp"/>'
      '<Default Extension="tiff" ContentType="image/tiff"/>'
      '<Default Extension="svg" ContentType="image/svg+xml"/>'
      '<Default Extension="xlsx" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"/>',
    );
    for (final e in _overrides.entries) {
      types.write('<Override PartName="/${e.key}" ContentType="${e.value}"/>');
    }
    types.write('</Types>');
    _files['[Content_Types].xml'] = utf8.encode(types.toString());
    _files['_rels/.rels'] = utf8.encode(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="$_relBase/officeDocument" Target="word/document.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
      '<Relationship Id="rId3" Type="$_relBase/extended-properties" Target="docProps/app.xml"/>'
      '</Relationships>',
    );

    final archive = Archive();
    // [Content_Types].xml first, as Word writes it.
    for (final name in ['[Content_Types].xml', '_rels/.rels', ..._files.keys.where((k) => k != '[Content_Types].xml' && k != '_rels/.rels')]) {
      final data = _files[name]!;
      archive.addFile(ArchiveFile(name, data.length, data));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static const _relBase = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  void _add(_Part from, String relType, String target, String xml, String contentType) {
    from.rel('$_relBase/$relType', target);
    _files['word/$target'] = utf8.encode(xml);
    _overrides['word/$target'] = contentType;
  }

  void _xmlPart(_Part part, String root, String inner, String contentType) {
    _files[part.path] = utf8.encode('$_xmlHead<$root $_ns>$inner</$root>');
    _overrides[part.path] = contentType;
  }

  void _writeRels(_Part part) {
    if (part.rels.isEmpty) return;
    final dir = part.path.substring(0, part.path.lastIndexOf('/'));
    final name = part.path.substring(part.path.lastIndexOf('/') + 1);
    final b = StringBuffer('$_xmlHead<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (final r in part.rels) {
      b.write('<Relationship Id="${r.id}" Type="${r.type}" Target="${_esc(r.target)}"${r.external ? ' TargetMode="External"' : ''}/>');
    }
    b.write('</Relationships>');
    _files['$dir/_rels/$name.rels'] = utf8.encode(b.toString());
  }

  // ------------------------------------------------------------ blocks

  void _blocks(StringBuffer o, List<WordBlock> blocks, _Part part, {String? trailingSectPr, String? firstRuns, bool needsParagraph = false}) {
    var lead = firstRuns;
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final next = i + 1 < blocks.length ? blocks[i + 1] : null;
      final lastBlock = next == null;
      switch (b) {
        case WordParagraph():
          _paragraph(o, b, part, next: next, sectPr: lastBlock ? trailingSectPr : null, leadRuns: lead);
          lead = null;
        case WordTable():
          _table(o, b, part);
          if (lastBlock && (trailingSectPr != null || needsParagraph)) {
            o.write('<w:p><w:pPr>${trailingSectPr ?? ''}</w:pPr></w:p>');
            trailingSectPr = null;
          }
      }
    }
    if (blocks.isEmpty && (trailingSectPr != null || needsParagraph || lead != null)) {
      o.write('<w:p>${trailingSectPr == null ? '' : '<w:pPr>$trailingSectPr</w:pPr>'}${lead ?? ''}</w:p>');
    }
  }

  // ------------------------------------------------------------ paragraphs

  /// Fields still open at the end of the last paragraph (a table of
  /// contents spans many paragraphs).
  var _openFields = <String>[];
  final _openComments = <String>{};

  void _paragraph(StringBuffer o, WordParagraph p, _Part part, {WordBlock? next, String? sectPr, String? leadRuns, String? paraId}) {
    if (p.styleId != null) {
      final use = _styles.putIfAbsent(p.styleId!, () => _StyleUse(p.styleName ?? p.styleId!));
      if (p.headingLevel != null) use.outlineLevel ??= p.headingLevel! - 1;
    }
    o.write(paraId == null ? '<w:p>' : '<w:p w14:paraId="$paraId" w14:textId="77777777">');
    o.write(_pPr(p, sectPr));
    for (final name in p.bookmarks) {
      o.write('<w:bookmarkStart w:id="${_bookmarkId(name)}" w:name="${_esc(name)}"/>');
    }
    if (leadRuns != null) o.write(leadRuns);

    final c = _Containers(this);
    for (final inline in p.inlines) {
      switch (inline) {
        case WordText():
          _syncFields(o, inline.fields);
          c.sync(o, sdt: inline.contentControl, link: inline.link, revision: _wrapping(inline.revision), part: part, text: inline.text);
          _syncComments(o, inline.commentIds);
          final form = inline.formField;
          if (form != null && form.kind != WordFormFieldKind.text) {
            // Word draws check boxes and drop-downs itself from their settings.
            _openNewFields(o, inline.fields);
            final code = form.kind == WordFormFieldKind.checkBox ? 'FORMCHECKBOX' : 'FORMDROPDOWN';
            final rPr = _rPr(inline.style);
            o.write(
              '<w:r>$rPr<w:fldChar w:fldCharType="begin">${_ffData(form)}</w:fldChar></w:r>'
              '<w:r>$rPr<w:instrText xml:space="preserve"> $code </w:instrText></w:r>'
              '<w:r>$rPr<w:fldChar w:fldCharType="end"/></w:r>',
            );
            continue;
          }
          _openNewFields(o, inline.fields, form: form);
          o.write(_run(inline.style, _textXml(inline.text, deleted: inline.revision?.removes == true), change: inline.revision));
        case WordBreak():
          final br = switch (inline.kind) {
            WordBreakKind.line => '<w:br/>',
            WordBreakKind.page => '<w:br w:type="page"/>',
            WordBreakKind.column => '<w:br w:type="column"/>',
            WordBreakKind.textWrapping => '<w:br w:type="textWrapping" w:clear="all"/>',
          };
          o.write('<w:r>$br</w:r>');
        case WordTab():
          final tab = inline.absoluteAlign == null
              ? '<w:tab/>'
              : '<w:ptab w:relativeTo="margin" w:alignment="${inline.absoluteAlign}" w:leader="${inline.leader ?? 'none'}"/>';
          o.write(_run(inline.style, tab));
        case WordPicture():
          o.write('<w:r>${_pictureDrawing(inline, part)}</w:r>');
        case WordShape():
          o.write('<w:r>${_shapeDrawing(inline, part)}</w:r>');
        case WordChart():
          o.write('<w:r>${_chartDrawing(inline, part)}</w:r>');
        case WordEquation():
          c.close(o);
          final math = '<m:oMath>${_omml(inline.root)}</m:oMath>';
          o.write(inline.display ? '<m:oMathPara>$math</m:oMathPara>' : math);
        case WordNoteRef():
          final kind = inline.kind == WordNoteKind.footnote ? 'footnote' : 'endnote';
          // An empty id is the note's own number at the start of its text.
          final mark = inline.id.isEmpty ? '<w:${kind}Ref/>' : '<w:${kind}Reference w:id="${inline.id}"/>';
          o.write(_run(inline.style, mark, forceSuper: true));
        case WordCommentMark():
          if (!_openComments.contains(inline.id)) o.write('<w:commentRangeStart w:id="${inline.id}"/>');
          _openComments.remove(inline.id);
          o.write('<w:commentRangeEnd w:id="${inline.id}"/><w:r><w:commentReference w:id="${inline.id}"/></w:r>');
        case WordUnsupported():
          o.write('<w:r><w:t xml:space="preserve">[${_esc(inline.label)}]</w:t></w:r>');
      }
    }
    // Fields that go on into the next paragraph stay open.
    final nextFields = switch (next) {
      WordParagraph(inlines: [WordText(:final fields), ...]) => fields,
      _ => const <String>[],
    };
    var keep = 0;
    while (keep < _openFields.length && keep < nextFields.length && _openFields[keep] == nextFields[keep]) {
      keep++;
    }
    _closeFieldsTo(o, keep);
    c.close(o);
    for (final name in p.bookmarks) {
      o.write('<w:bookmarkEnd w:id="${_bookmarkId(name)}"/>');
    }
    o.write('</w:p>');
  }

  final _bookmarkIds = <String, int>{};
  int _bookmarkId(String name) => _bookmarkIds.putIfAbsent(name, () => _bookmarkIds.length + 1);

  /// Tracked changes that wrap runs; formatting changes go in the run itself.
  WordRevision? _wrapping(WordRevision? r) => r == null || r.kind == WordRevisionKind.format || r.kind == WordRevisionKind.paragraph ? null : r;

  void _syncFields(StringBuffer o, List<String> fields) {
    var keep = 0;
    while (keep < _openFields.length && keep < fields.length && _openFields[keep] == fields[keep]) {
      keep++;
    }
    _closeFieldsTo(o, keep);
  }

  void _closeFieldsTo(StringBuffer o, int keep) {
    while (_openFields.length > keep) {
      o.write('<w:r><w:fldChar w:fldCharType="end"/></w:r>');
      _openFields = _openFields.sublist(0, _openFields.length - 1);
    }
  }

  void _openNewFields(StringBuffer o, List<String> fields, {WordFormField? form}) {
    for (var i = _openFields.length; i < fields.length; i++) {
      final ff = form != null && fields[i].startsWith('FORMTEXT') ? _ffData(form) : null;
      o.write(
        '<w:r>${ff == null ? '<w:fldChar w:fldCharType="begin"/>' : '<w:fldChar w:fldCharType="begin">$ff</w:fldChar>'}</w:r>'
        '<w:r><w:instrText xml:space="preserve"> ${_esc(fields[i])} </w:instrText></w:r>'
        '<w:r><w:fldChar w:fldCharType="separate"/></w:r>',
      );
    }
    _openFields = [...fields];
  }

  void _syncComments(StringBuffer o, List<String> ids) {
    for (final id in _openComments.toList()) {
      if (!ids.contains(id)) {
        // The range ends here; the reference mark comes with WordCommentMark.
        o.write('<w:commentRangeEnd w:id="$id"/>');
        _openComments.remove(id);
        _endedComments.add(id);
      }
    }
    for (final id in ids) {
      if (!_openComments.contains(id) && !_endedComments.contains(id)) {
        o.write('<w:commentRangeStart w:id="$id"/>');
        _openComments.add(id);
      }
    }
  }

  final _endedComments = <String>{};

  /// A legacy form field's settings, in Word's order.
  String _ffData(WordFormField f) {
    final b = StringBuffer('<w:ffData>');
    if (f.name != null) b.write('<w:name w:val="${_esc(f.name!)}"/>');
    if (f.enabled) b.write('<w:enabled/>');
    b.write('<w:calcOnExit w:val="${f.calcOnExit ? 1 : 0}"/>');
    if (f.entryMacro != null) b.write('<w:entryMacro w:val="${_esc(f.entryMacro!)}"/>');
    if (f.exitMacro != null) b.write('<w:exitMacro w:val="${_esc(f.exitMacro!)}"/>');
    if (f.helpText != null) b.write('<w:helpText w:type="text" w:val="${_esc(f.helpText!)}"/>');
    if (f.statusText != null) b.write('<w:statusText w:type="text" w:val="${_esc(f.statusText!)}"/>');
    switch (f.kind) {
      case WordFormFieldKind.checkBox:
        b.write('<w:checkBox>');
        b.write(f.boxSize == null ? '<w:sizeAuto/>' : '<w:size w:val="${(f.boxSize! * 2).round()}"/>');
        b.write('<w:default w:val="${f.defaultChecked ? 1 : 0}"/>');
        if (f.checked != null) b.write('<w:checked w:val="${f.checked! ? 1 : 0}"/>');
        b.write('</w:checkBox>');
      case WordFormFieldKind.dropDown:
        b.write('<w:ddList>');
        if (f.selected != null) b.write('<w:result w:val="${f.selected}"/>');
        if (f.defaultSelected != 0) b.write('<w:default w:val="${f.defaultSelected}"/>');
        for (final e in f.entries) {
          b.write('<w:listEntry w:val="${_esc(e)}"/>');
        }
        b.write('</w:ddList>');
      case WordFormFieldKind.text:
        b.write('<w:textInput>');
        if (f.textType != 'regular') b.write('<w:type w:val="${f.textType}"/>');
        if (f.defaultText != null) b.write('<w:default w:val="${_esc(f.defaultText!)}"/>');
        if (f.maxLength != null) b.write('<w:maxLength w:val="${f.maxLength}"/>');
        if (f.format != null) b.write('<w:format w:val="${_esc(f.format!)}"/>');
        b.write('</w:textInput>');
    }
    b.write('</w:ffData>');
    return b.toString();
  }

  String _pPr(WordParagraph p, String? sectPr) {
    final s = p.style;
    final b = StringBuffer();
    if (p.styleId != null) b.write('<w:pStyle w:val="${_esc(p.styleId!)}"/>');
    if (s.keepNext) b.write('<w:keepNext/>');
    if (s.keepLines) b.write('<w:keepLines/>');
    if (s.pageBreakBefore) b.write('<w:pageBreakBefore/>');
    if (p.dropCap != null) {
      b.write('<w:framePr w:dropCap="${p.dropCap!.inMargin ? 'margin' : 'drop'}" w:lines="${p.dropCap!.lines}" w:wrap="around" w:vAnchor="text" w:hAnchor="${p.dropCap!.inMargin ? 'page' : 'text'}"/>');
    }
    if (!s.widowControl) b.write('<w:widowControl w:val="0"/>');
    final list = p.list;
    if (list != null) {
      final id = list.listId ?? '_${list.format}_${list.pattern}';
      final def = _lists.putIfAbsent(id, () => _ListDef(_lists.length + 1));
      def.levels.putIfAbsent(list.level, () => list);
      b.write('<w:numPr><w:ilvl w:val="${list.level}"/><w:numId w:val="${def.numId}"/></w:numPr>');
    }
    final borders = s.borders;
    if (borders != null) {
      final inner = StringBuffer();
      for (final (tag, border) in [('top', borders.top), ('left', borders.left), ('bottom', borders.bottom), ('right', borders.right), ('between', borders.between)]) {
        if (border != null) inner.write(_border(tag, border));
      }
      if (inner.isNotEmpty) b.write('<w:pBdr>$inner</w:pBdr>');
    }
    if (s.shading != null) b.write(_shd(s.shading!));
    if (s.tabs.isNotEmpty) {
      b.write('<w:tabs>');
      for (final t in s.tabs) {
        final leader = t.leader == 'none' || t.leader.isEmpty ? '' : ' w:leader="${t.leader}"';
        b.write('<w:tab w:val="${t.align.name}"$leader w:pos="${_tw(t.position)}"/>');
      }
      b.write('</w:tabs>');
    }
    if (s.rtl) b.write('<w:bidi/>');
    final line = s.lineExact != null
        ? ' w:line="${_tw(s.lineExact!)}" w:lineRule="exact"'
        : s.lineAtLeast != null
        ? ' w:line="${_tw(s.lineAtLeast!)}" w:lineRule="atLeast"'
        : ' w:line="${((s.lineMultiple ?? 1) * 240).round()}" w:lineRule="auto"';
    b.write('<w:spacing w:before="${_tw(s.spaceBefore)}" w:after="${_tw(s.spaceAfter)}"$line/>');
    final first = s.firstLine >= 0 ? ' w:firstLine="${_tw(s.firstLine)}"' : ' w:hanging="${_tw(-s.firstLine)}"';
    b.write('<w:ind w:left="${_tw(s.indentLeft)}" w:right="${_tw(s.indentRight)}"$first/>');
    if (s.contextualSpacing) b.write('<w:contextualSpacing/>');
    b.write('<w:jc w:val="${switch (s.align) {
      WordAlign.left => 'left',
      WordAlign.center => 'center',
      WordAlign.right => 'right',
      WordAlign.justify => 'both',
    }}"/>');
    if (s.outlineLevel != null && p.headingLevel == null) b.write('<w:outlineLvl w:val="${s.outlineLevel}"/>');
    // The reader gives an inserted paragraph mark as `paragraph` and a
    // tracked paragraph formatting change as `format`.
    final rev = p.revision;
    if (rev != null && rev.kind != WordRevisionKind.format) {
      final tag = switch (rev.kind) {
        WordRevisionKind.delete || WordRevisionKind.moveFrom => 'del',
        _ => 'ins',
      };
      b.write('<w:rPr><w:$tag ${_revAttrs(rev)}/></w:rPr>');
    }
    if (sectPr != null) b.write(sectPr);
    if (rev != null && rev.kind == WordRevisionKind.format) {
      b.write('<w:pPrChange ${_revAttrs(rev)}><w:pPr/></w:pPrChange>');
    }
    return '<w:pPr>$b</w:pPr>';
  }

  String _revAttrs(WordRevision r) {
    final date = r.date == null ? '' : ' w:date="${_date(r.date!)}"';
    return 'w:id="${++_revisionId}" w:author="${_esc(r.author ?? 'Unknown')}"$date';
  }

  // ------------------------------------------------------------ runs

  String _textXml(String text, {required bool deleted}) {
    final tag = deleted ? 'w:delText' : 'w:t';
    return '<$tag xml:space="preserve">${_esc(text)}</$tag>';
  }

  String _run(WordRunStyle style, String content, {WordRevision? change, bool forceSuper = false}) {
    final rPr = _rPr(style, change: change?.kind == WordRevisionKind.format ? change : null, forceSuper: forceSuper);
    return '<w:r>$rPr$content</w:r>';
  }

  String _rPr(WordRunStyle s, {WordRevision? change, bool forceSuper = false}) {
    final b = StringBuffer();
    if (s.font != null) {
      final f = _esc(s.font!);
      b.write('<w:rFonts w:ascii="$f" w:hAnsi="$f" w:eastAsia="$f" w:cs="$f"/>');
    }
    if (s.bold) b.write('<w:b/><w:bCs/>');
    if (s.italic) b.write('<w:i/><w:iCs/>');
    if (s.allCaps) b.write('<w:caps/>');
    if (s.smallCaps) b.write('<w:smallCaps/>');
    if (s.strike) b.write('<w:strike/>');
    if (s.doubleStrike) b.write('<w:dstrike/>');
    if (s.outline) b.write('<w:outline/>');
    if (s.shadow) b.write('<w:shadow/>');
    if (s.emboss) b.write('<w:emboss/>');
    if (s.imprint) b.write('<w:imprint/>');
    if (s.hidden) b.write('<w:vanish/>');
    if (s.color != null) b.write('<w:color w:val="${_hex(s.color!)}"/>');
    if (s.letterSpacing != 0) b.write('<w:spacing w:val="${_tw(s.letterSpacing)}"/>');
    if (s.scale != 1) b.write('<w:w w:val="${(s.scale * 100).round()}"/>');
    if (s.position != 0) b.write('<w:position w:val="${(s.position * 2).round()}"/>');
    final hp = (s.size * 2).round();
    b.write('<w:sz w:val="$hp"/><w:szCs w:val="$hp"/>');
    String? shading;
    if (s.highlight != null) {
      final name = _highlightName(s.highlight!);
      if (name != null) {
        b.write('<w:highlight w:val="$name"/>');
      } else {
        shading = _shd(s.highlight!);
      }
    }
    if (s.underline != WordUnderline.none) {
      final u = switch (s.underline) {
        WordUnderline.dashed => 'dash',
        final x => x.name,
      };
      b.write('<w:u w:val="$u"${s.underlineColor == null ? '' : ' w:color="${_hex(s.underlineColor!)}"'}/>');
    }
    if (s.border != null) b.write(_border('bdr', s.border!));
    if (s.shading != null) {
      b.write(_shd(s.shading!));
    } else if (shading != null) {
      b.write(shading);
    }
    final vert = forceSuper ? WordVertAlign.superscript : s.vertAlign;
    if (vert != WordVertAlign.baseline) b.write('<w:vertAlign w:val="${vert.name}"/>');
    if (s.rtl) b.write('<w:rtl/>');
    final e = s.effects;
    if (e != null) b.write(_effects(e));
    if (change != null) b.write('<w:rPrChange ${_revAttrs(change)}><w:rPr/></w:rPrChange>');
    return b.isEmpty ? '' : '<w:rPr>$b</w:rPr>';
  }

  String? _highlightName(int argb) {
    for (final e in highlightColors.entries) {
      if ((e.value & 0xFFFFFF) == (argb & 0xFFFFFF)) return e.key;
    }
    return null;
  }

  String _effects(WordTextEffects e) {
    final b = StringBuffer();
    if (e.glowColor != null) {
      b.write('<w14:glow w14:rad="${_emu(e.glowRadius)}">${_w14Color(e.glowColor!)}</w14:glow>');
    }
    if (e.shadowColor != null) {
      final dist = math.sqrt(e.shadowDx * e.shadowDx + e.shadowDy * e.shadowDy);
      var dir = math.atan2(e.shadowDy, e.shadowDx) * 180 / math.pi;
      if (dir < 0) dir += 360;
      b.write(
        '<w14:shadow w14:blurRad="${_emu(e.shadowBlur)}" w14:dist="${_emu(dist)}" w14:dir="${(dir * 60000).round()}" '
        'w14:sx="100000" w14:sy="100000" w14:kx="0" w14:ky="0" w14:algn="none">${_w14Color(e.shadowColor!)}</w14:shadow>',
      );
    }
    if (e.reflection) {
      b.write(
        '<w14:reflection w14:blurRad="6350" w14:stA="55000" w14:stPos="0" w14:endA="300" w14:endPos="45500" '
        'w14:dist="0" w14:dir="5400000" w14:fadeDir="5400000" w14:sx="100000" w14:sy="-100000" w14:kx="0" w14:ky="0" w14:algn="bl"/>',
      );
    }
    if (e.outlineColor != null) {
      b.write(
        '<w14:textOutline w14:w="${_emu(e.outlineWidth)}" w14:cap="flat" w14:cmpd="sng" w14:algn="ctr">'
        '<w14:solidFill>${_w14Color(e.outlineColor!)}</w14:solidFill><w14:prstDash w14:val="solid"/><w14:round/></w14:textOutline>',
      );
    }
    if (e.gradient.isNotEmpty) {
      b.write('<w14:textFill><w14:gradFill><w14:gsLst>');
      for (var i = 0; i < e.gradient.length; i++) {
        final pos = e.gradient.length == 1 ? 0 : (i * 100000 / (e.gradient.length - 1)).round();
        b.write('<w14:gs w14:pos="$pos">${_w14Color(e.gradient[i])}</w14:gs>');
      }
      b.write('</w14:gsLst><w14:lin w14:ang="5400000" w14:scaled="0"/></w14:gradFill></w14:textFill>');
    } else if (e.fillColor != null) {
      b.write('<w14:textFill><w14:solidFill>${_w14Color(e.fillColor!)}</w14:solidFill></w14:textFill>');
    }
    if (e.ligatures != null) b.write('<w14:ligatures w14:val="${e.ligatures}"/>');
    if (e.numberForm != null) b.write('<w14:numForm w14:val="${e.numberForm}"/>');
    if (e.numberSpacing != null) b.write('<w14:numSpacing w14:val="${e.numberSpacing}"/>');
    return b.toString();
  }

  String _w14Color(int argb) {
    final a = (argb >> 24) & 0xFF;
    // w14 stores transparency, not opacity.
    final alpha = a == 0xFF ? '' : '<w14:alpha w14:val="${((1 - a / 255) * 100000).round()}"/>';
    return '<w14:srgbClr w14:val="${_hex(argb)}">$alpha</w14:srgbClr>';
  }

  // ------------------------------------------------------------ tables

  void _table(StringBuffer o, WordTable t, _Part part) {
    final total = t.columns.fold<double>(0, (a, b) => a + b);
    o.write('<w:tbl><w:tblPr>');
    if (t.styleId != null) {
      _tableStyles.add(t.styleId!);
      o.write('<w:tblStyle w:val="${_esc(t.styleId!)}"/>');
    }
    if (t.floating) {
      final x = switch (t.align) {
        WordAlign.center => ' w:tblpXSpec="center"',
        WordAlign.right => ' w:tblpXSpec="right"',
        _ => '',
      };
      o.write('<w:tblpPr w:leftFromText="180" w:rightFromText="180" w:vertAnchor="text" w:horzAnchor="margin"$x w:tblpY="1"/>');
    }
    o.write('<w:tblW w:w="${_tw(total)}" w:type="dxa"/>');
    if (t.align != WordAlign.left) o.write('<w:jc w:val="${t.align == WordAlign.center ? 'center' : 'right'}"/>');
    if (t.cellSpacing > 0) o.write('<w:tblCellSpacing w:w="${_tw(t.cellSpacing / 2)}" w:type="dxa"/>');
    if (t.indent != 0) o.write('<w:tblInd w:w="${_tw(t.indent)}" w:type="dxa"/>');
    o.write('<w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar>');
    o.write('</w:tblPr><w:tblGrid>');
    for (final c in t.columns) {
      o.write('<w:gridCol w:w="${_tw(c)}"/>');
    }
    o.write('</w:tblGrid>');
    for (final row in t.rows) {
      o.write('<w:tr><w:trPr>');
      if (row.cantSplit) o.write('<w:cantSplit/>');
      if (row.height != null && row.height! > 0) {
        o.write('<w:trHeight w:val="${_tw(row.height!)}" w:hRule="${row.exactHeight ? 'exact' : 'atLeast'}"/>');
      }
      if (row.header) o.write('<w:tblHeader/>');
      final rev = row.revision;
      if (rev != null && (rev.adds || rev.removes)) o.write('<w:${rev.adds ? 'ins' : 'del'} ${_revAttrs(rev)}/>');
      o.write('</w:trPr>');
      var col = 0;
      for (final cell in row.cells) {
        var width = 0.0;
        for (var k = col; k < col + cell.colSpan && k < t.columns.length; k++) {
          width += t.columns[k];
        }
        col += cell.colSpan;
        o.write('<w:tc><w:tcPr><w:tcW w:w="${_tw(width)}" w:type="dxa"/>');
        if (cell.colSpan > 1) o.write('<w:gridSpan w:val="${cell.colSpan}"/>');
        if (cell.mergedAway) {
          o.write('<w:vMerge/>');
        } else if (cell.rowSpan > 1) {
          o.write('<w:vMerge w:val="restart"/>');
        }
        final b = cell.borders;
        final inner = StringBuffer();
        for (final (tag, border) in [
          ('top', b.top),
          ('left', b.left),
          ('bottom', b.bottom),
          ('right', b.right),
          ('tl2br', b.diagonalDown),
          ('tr2bl', b.diagonalUp),
        ]) {
          inner.write(border == null ? '<w:$tag w:val="nil"/>' : _border(tag, border));
        }
        o.write('<w:tcBorders>$inner</w:tcBorders>');
        if (cell.shading != null) o.write(_shd(cell.shading!));
        final m = cell.margins;
        o.write('<w:tcMar><w:top w:w="${_tw(m.top)}" w:type="dxa"/><w:left w:w="${_tw(m.left)}" w:type="dxa"/><w:bottom w:w="${_tw(m.bottom)}" w:type="dxa"/><w:right w:w="${_tw(m.right)}" w:type="dxa"/></w:tcMar>');
        if (cell.textDirection != null) o.write('<w:textDirection w:val="${cell.textDirection}"/>');
        if (cell.vAlign != WordCellVAlign.top) o.write('<w:vAlign w:val="${cell.vAlign.name}"/>');
        o.write('</w:tcPr>');
        final content = StringBuffer();
        _blocks(content, cell.mergedAway ? const [] : cell.blocks, part, needsParagraph: true);
        // A cell must end with a paragraph.
        if (cell.blocks.isNotEmpty && cell.blocks.last is WordTable && !cell.mergedAway) content.write('<w:p/>');
        o.write(content);
        o.write('</w:tc>');
      }
      o.write('</w:tr>');
    }
    o.write('</w:tbl>');
  }

  // ------------------------------------------------------------ sections

  final _headerParts = LinkedHashMap<List<WordBlock>, String>.identity();
  var _headerCount = 0;
  var _footerCount = 0;

  String _sectPr(WordSection s, _Part main) {
    final b = StringBuffer('<w:sectPr>');
    for (final (kind, map) in [('header', s.headers), ('footer', s.footers)]) {
      for (final e in map.entries) {
        final relId = _headerParts.putIfAbsent(e.value, () {
          final n = kind == 'header' ? ++_headerCount : ++_footerCount;
          final part = _Part('word/$kind$n.xml');
          final inner = StringBuffer();
          _blocks(inner, e.value, part, needsParagraph: true);
          _xmlPart(part, kind == 'header' ? 'w:hdr' : 'w:ftr', inner.toString(), 'application/vnd.openxmlformats-officedocument.wordprocessingml.$kind+xml');
          _writeRels(part);
          return main.rel('$_relBase/$kind', '$kind$n.xml');
        });
        b.write('<w:${kind}Reference w:type="${e.key}" r:id="$relId"/>');
      }
    }
    final type = switch (s.breakType) {
      WordBreakType.continuous => 'continuous',
      WordBreakType.oddPage => 'oddPage',
      WordBreakType.evenPage => 'evenPage',
      WordBreakType.nextColumn => 'nextColumn',
      WordBreakType.nextPage => 'nextPage',
    };
    b.write('<w:type w:val="$type"/>');
    b.write('<w:pgSz w:w="${_tw(s.pageWidth)}" w:h="${_tw(s.pageHeight)}"${s.landscape ? ' w:orient="landscape"' : ''}/>');
    final m = s.margins;
    b.write(
      '<w:pgMar w:top="${_tw(m.top)}" w:right="${_tw(m.right)}" w:bottom="${_tw(m.bottom)}" w:left="${_tw(m.left)}" '
      'w:header="${_tw(s.headerDistance)}" w:footer="${_tw(s.footerDistance)}" w:gutter="${_tw(s.gutter)}"/>',
    );
    final pb = s.pageBorders;
    if (pb != null) {
      b.write('<w:pgBorders w:offsetFrom="${s.pageBordersFromText ? 'text' : 'page'}">');
      for (final (tag, border) in [('top', pb.top), ('left', pb.left), ('bottom', pb.bottom), ('right', pb.right)]) {
        if (border != null) b.write(_border(tag, border));
      }
      b.write('</w:pgBorders>');
    }
    final ln = s.lineNumbers;
    if (ln != null) {
      b.write('<w:lnNumType w:countBy="${ln.countBy}" w:start="${math.max(0, ln.start - 1)}" w:distance="${_tw(ln.distance)}" w:restart="${ln.restart}"/>');
    }
    if (s.pageNumberFormat != 'decimal' || s.pageNumberStart != null) {
      b.write('<w:pgNumType w:fmt="${s.pageNumberFormat}"${s.pageNumberStart == null ? '' : ' w:start="${s.pageNumberStart}"'}/>');
    }
    final cols = s.columns;
    if (cols.count > 1) {
      final equal = cols.widths.isEmpty || cols.widths.toSet().length == 1;
      b.write('<w:cols w:num="${cols.count}" w:space="${_tw(cols.space)}"${cols.separator ? ' w:sep="1"' : ''}${equal ? '' : ' w:equalWidth="0"'}>');
      if (!equal) {
        for (final w in cols.widths) {
          b.write('<w:col w:w="${_tw(w)}" w:space="${_tw(cols.space)}"/>');
        }
      }
      b.write('</w:cols>');
    }
    if (s.verticalAlign != WordVerticalPageAlign.top) b.write('<w:vAlign w:val="${s.verticalAlign.name}"/>');
    if (s.titlePage) b.write('<w:titlePg/>');
    b.write('</w:sectPr>');
    return b.toString();
  }

  // ------------------------------------------------------------ notes, comments

  void _notes(_Part main, String part, String tag, Map<String, WordNote> notes) {
    if (notes.isEmpty) return;
    final p = _Part('word/$part.xml');
    final b = StringBuffer(
      '<w:$tag w:type="separator" w:id="-1"><w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:separator/></w:r></w:p></w:$tag>'
      '<w:$tag w:type="continuationSeparator" w:id="0"><w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:continuationSeparator/></w:r></w:p></w:$tag>',
    );
    for (final n in notes.values) {
      b.write('<w:$tag w:id="${n.id}">');
      final hasMark = n.blocks.whereType<WordParagraph>().any((p) => p.inlines.any((i) => i is WordNoteRef && i.id.isEmpty));
      final lead = hasMark ? null : '<w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:${tag}Ref/></w:r><w:r><w:t xml:space="preserve"> </w:t></w:r>';
      _blocks(b, n.blocks, p, firstRuns: lead, needsParagraph: true);
      b.write('</w:$tag>');
    }
    _xmlPart(p, 'w:$part', b.toString(), 'application/vnd.openxmlformats-officedocument.wordprocessingml.$part+xml');
    _writeRels(p);
    main.rel('$_relBase/$part', '$part.xml');
  }

  void _comments(_Part main) {
    if (doc.comments.isEmpty) return;
    final p = _Part('word/comments.xml');
    final b = StringBuffer();
    for (final c in doc.comments) {
      final date = c.date == null ? '' : ' w:date="${_date(c.date!)}"';
      final initials = c.initials == null ? '' : ' w:initials="${_esc(c.initials!)}"';
      b.write('<w:comment w:id="${c.id}" w:author="${_esc(c.author ?? 'Unknown')}"$date$initials>');
      final paraId = (_paraId++).toRadixString(16).toUpperCase();
      _commentParaIds[c.id] = paraId;
      final blocks = c.blocks;
      if (blocks.isEmpty) b.write('<w:p w14:paraId="$paraId" w14:textId="77777777"><w:r><w:annotationRef/></w:r></w:p>');
      for (var i = 0; i < blocks.length; i++) {
        final block = blocks[i];
        final lead = i == 0 ? '<w:r><w:rPr><w:sz w:val="16"/></w:rPr><w:annotationRef/></w:r>' : null;
        if (block is WordParagraph) {
          _paragraph(b, block, p, leadRuns: lead, paraId: i == blocks.length - 1 ? paraId : null);
        } else {
          _blocks(b, [block], p, firstRuns: lead);
        }
      }
      b.write('</w:comment>');
    }
    _xmlPart(p, 'w:comments', b.toString(), 'application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml');
    _writeRels(p);
    main.rel('$_relBase/comments', 'comments.xml');

    final ex = StringBuffer('$_xmlHead<w15:commentsEx $_ns>');
    for (final c in doc.comments) {
      final parent = c.parentId == null ? null : _commentParaIds[c.parentId];
      ex.write('<w15:commentEx w15:paraId="${_commentParaIds[c.id]}"${parent == null ? '' : ' w15:paraIdParent="$parent"'} w15:done="${c.resolved ? 1 : 0}"/>');
    }
    ex.write('</w15:commentsEx>');
    _files['word/commentsExtended.xml'] = utf8.encode(ex.toString());
    _overrides['word/commentsExtended.xml'] = 'application/vnd.openxmlformats-officedocument.wordprocessingml.commentsExtended+xml';
    main.rel('http://schemas.microsoft.com/office/2011/relationships/commentsExtended', 'commentsExtended.xml');
  }

  // ------------------------------------------------------------ drawings

  String _mediaRel(Uint8List bytes, String? contentType, _Part part) {
    final ext = _imageExt(bytes, contentType);
    final key = '${bytes.length}:${_hash(bytes)}';
    final path = _media.putIfAbsent(key, () {
      final p = 'media/image${++_mediaCount}.$ext';
      _files['word/$p'] = bytes;
      return p;
    });
    final target = part.path.startsWith('word/') && !part.path.substring(5).contains('/') ? path : '../$path';
    return part.rel('$_relBase/image', target);
  }

  static String _imageExt(Uint8List b, String? contentType) {
    if (contentType == 'image/svg+xml') return 'svg';
    if (b.length > 4 && b[0] == 0x89 && b[1] == 0x50) return 'png';
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'jpeg';
    if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'gif';
    if (b.length > 2 && b[0] == 0x42 && b[1] == 0x4D) return 'bmp';
    return switch (contentType) {
      'image/jpeg' => 'jpeg',
      'image/gif' => 'gif',
      'image/svg+xml' => 'svg',
      _ => 'png',
    };
  }

  static int _hash(Uint8List b) {
    var h = 0x811C9DC5;
    final step = math.max(1, b.length ~/ 4096);
    for (var i = 0; i < b.length; i += step) {
      h = ((h ^ b[i]) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  String _frame(WordAnchor? anchor, double width, double height, String name, String graphic, {String? descr, String? title, bool lockAspect = false}) {
    final cx = _emu(width), cy = _emu(height);
    final id = ++_docPrId;
    final docPr = '<wp:docPr id="$id" name="${_esc(name)} $id"${descr == null ? '' : ' descr="${_esc(descr)}"'}${title == null ? '' : ' title="${_esc(title)}"'}/>';
    final locks = '<wp:cNvGraphicFramePr>${lockAspect ? '<a:graphicFrameLocks noChangeAspect="1"/>' : ''}</wp:cNvGraphicFramePr>';
    if (anchor == null) {
      return '<w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="$cx" cy="$cy"/><wp:effectExtent l="0" t="0" r="0" b="0"/>$docPr$locks$graphic</wp:inline></w:drawing>';
    }
    final a = anchor;
    String pos(String axis, String relative, String? align, double offset) {
      final inner = align != null ? '<wp:align>$align</wp:align>' : '<wp:posOffset>${_emu(offset)}</wp:posOffset>';
      return '<wp:position$axis relativeFrom="$relative">$inner</wp:position$axis>';
    }

    const polygon = '<wp:wrapPolygon edited="0"><wp:start x="0" y="0"/><wp:lineTo x="0" y="21600"/><wp:lineTo x="21600" y="21600"/><wp:lineTo x="21600" y="0"/><wp:lineTo x="0" y="0"/></wp:wrapPolygon>';
    final wrap = switch (a.wrap) {
      'square' => '<wp:wrapSquare wrapText="bothSides"/>',
      'tight' => '<wp:wrapTight wrapText="bothSides">$polygon</wp:wrapTight>',
      'through' => '<wp:wrapThrough wrapText="bothSides">$polygon</wp:wrapThrough>',
      'topAndBottom' => '<wp:wrapTopAndBottom/>',
      _ => '<wp:wrapNone/>',
    };
    return '<w:drawing><wp:anchor distT="0" distB="0" distL="114300" distR="114300" simplePos="0" relativeHeight="${_shapeOrder++}" '
        'behindDoc="${a.behindText ? 1 : 0}" locked="0" layoutInCell="1" allowOverlap="1">'
        '<wp:simplePos x="0" y="0"/>${pos('H', a.relativeH, a.alignH, a.offsetX)}${pos('V', a.relativeV, a.alignV, a.offsetY)}'
        '<wp:extent cx="$cx" cy="$cy"/><wp:effectExtent l="0" t="0" r="0" b="0"/>$wrap$docPr$locks$graphic</wp:anchor></w:drawing>';
  }

  String _xfrm(WordDrawingStyle look, double width, double height) {
    final rot = look.rotation == 0 ? '' : ' rot="${(look.rotation * 60000).round()}"';
    final flip = '${look.flipH ? ' flipH="1"' : ''}${look.flipV ? ' flipV="1"' : ''}';
    return '<a:xfrm$rot$flip><a:off x="0" y="0"/><a:ext cx="${_emu(width)}" cy="${_emu(height)}"/></a:xfrm>';
  }

  String _lineAndShadow(WordDrawingStyle look, {required bool noLineByDefault}) {
    final b = StringBuffer();
    if (look.outlineColor != null) {
      final dash = look.outlineDash == null ? '' : '<a:prstDash val="${look.outlineDash}"/>';
      b.write('<a:ln w="${_emu(look.outlineWidth == 0 ? 0.75 : look.outlineWidth)}"><a:solidFill>${_aColor(look.outlineColor!)}</a:solidFill>$dash</a:ln>');
    } else if (noLineByDefault) {
      b.write('<a:ln><a:noFill/></a:ln>');
    }
    final sh = look.shadow;
    if (sh != null) {
      final dist = math.sqrt(sh.dx * sh.dx + sh.dy * sh.dy);
      var dir = math.atan2(sh.dy, sh.dx) * 180 / math.pi;
      if (dir < 0) dir += 360;
      b.write('<a:effectLst><a:outerShdw blurRad="${_emu(sh.blur)}" dist="${_emu(dist)}" dir="${(dir * 60000).round()}" algn="tl" rotWithShape="0">${_aColor(sh.color)}</a:outerShdw></a:effectLst>');
    }
    return b.toString();
  }

  String _pictureDrawing(WordPicture p, _Part part) {
    final rel = _mediaRel(p.bytes, p.contentType, part);
    final blipFx = StringBuffer();
    if (p.opacity < 1) blipFx.write('<a:alphaModFix amt="${(p.opacity * 100000).round()}"/>');
    if (p.grayscale) blipFx.write('<a:grayscl/>');
    if (p.svg != null) {
      final svgRel = _mediaRel(p.svg!, 'image/svg+xml', part);
      blipFx.write(
        '<a:extLst><a:ext uri="{96DAC541-7B7A-43D3-8B79-37D633B846F1}">'
        '<asvg:svgBlip xmlns:asvg="http://schemas.microsoft.com/office/drawing/2016/SVG/main" r:embed="$svgRel"/></a:ext></a:extLst>',
      );
    }
    final c = p.crop;
    final crop = c.left == 0 && c.top == 0 && c.right == 0 && c.bottom == 0
        ? ''
        : '<a:srcRect l="${(c.left * 100000).round()}" t="${(c.top * 100000).round()}" r="${(c.right * 100000).round()}" b="${(c.bottom * 100000).round()}"/>';
    final graphic =
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic>'
        '<pic:nvPicPr><pic:cNvPr id="0" name="Picture"${p.altText == null ? '' : ' descr="${_esc(p.altText!)}"'}/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$rel">$blipFx</a:blip>$crop<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr>${_xfrm(p.look, p.width, p.height)}<a:prstGeom prst="${p.shape ?? 'rect'}"><a:avLst/></a:prstGeom>${_lineAndShadow(p.look, noLineByDefault: false)}</pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic>';
    return _frame(p.anchor, p.width, p.height, 'Picture', graphic, descr: p.altText, title: p.title, lockAspect: true);
  }

  String _shapeDrawing(WordShape s, _Part part) {
    final fill = s.gradient.isNotEmpty
        ? '<a:gradFill rotWithShape="1"><a:gsLst>${[
            for (var i = 0; i < s.gradient.length; i++) '<a:gs pos="${s.gradient.length == 1 ? 0 : (i * 100000 / (s.gradient.length - 1)).round()}">${_aColor(s.gradient[i])}</a:gs>',
          ].join()}</a:gsLst><a:lin ang="${(s.gradientAngle * 60000).round()}" scaled="0"/></a:gradFill>'
        : s.fill == null
        ? '<a:noFill/>'
        : '<a:solidFill>${_aColor(s.fill!)}</a:solidFill>';
    final hasText = s.blocks.isNotEmpty;
    final text = StringBuffer();
    if (hasText) {
      // Fields and links don't run across a text box edge.
      final saved = _openFields;
      _openFields = [];
      _blocks(text, s.blocks, part);
      _openFields = saved;
    }
    final anchor = switch (s.textAnchor) {
      'ctr' || 'center' || 'middle' => 'ctr',
      'b' || 'bottom' => 'b',
      _ => 't',
    };
    final i = s.insets;
    final warp = s.wordArt == null || s.wordArt == 'vml' ? '' : '<a:prstTxWarp prst="${s.wordArt}"><a:avLst/></a:prstTxWarp>';
    final graphic =
        '<a:graphic><a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"><wps:wsp>'
        '<wps:cNvSpPr${hasText && s.geometry == 'rect' ? ' txBox="1"' : ''}/>'
        '<wps:spPr>${_xfrm(s.look, s.width, s.height)}<a:prstGeom prst="${s.geometry == 'custom' ? 'rect' : s.geometry}"><a:avLst/></a:prstGeom>$fill${_lineAndShadow(s.look, noLineByDefault: true)}</wps:spPr>'
        '${hasText ? '<wps:txbx><w:txbxContent>$text</w:txbxContent></wps:txbx>' : ''}'
        '<wps:bodyPr rot="0" vert="${s.verticalText ?? 'horz'}" wrap="square" lIns="${_emu(i.left)}" tIns="${_emu(i.top)}" rIns="${_emu(i.right)}" bIns="${_emu(i.bottom)}" anchor="$anchor" anchorCtr="0">'
        '$warp<a:noAutofit/></wps:bodyPr>'
        '</wps:wsp></a:graphicData></a:graphic>';
    return _frame(s.anchor, s.width, s.height, s.name ?? (hasText ? 'Text Box' : 'Shape'), graphic);
  }

  String _chartDrawing(WordChart c, _Part part) {
    final n = ++_chartCount;
    // The chart's numbers also go into an embedded workbook, so Word's
    // Edit Data opens them in Excel.
    final workbook = 'embeddings/Microsoft_Excel_Worksheet$n.xlsx';
    _files['word/$workbook'] = chartWorkbook(c);
    _files['word/charts/_rels/chart$n.xml.rels'] = utf8.encode(
      '$_xmlHead<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="$_relBase/package" Target="../$workbook"/></Relationships>',
    );
    _files['word/charts/chart$n.xml'] = utf8.encode(_chartXml(c));
    _overrides['word/charts/chart$n.xml'] = 'application/vnd.openxmlformats-officedocument.drawingml.chart+xml';
    final target = part.path.startsWith('word/') && !part.path.substring(5).contains('/') ? 'charts/chart$n.xml' : '../charts/chart$n.xml';
    final rel = part.rel('$_relBase/chart', target);
    final graphic = '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="$rel"/></a:graphicData></a:graphic>';
    return _frame(c.anchor, c.width, c.height, 'Chart', graphic, descr: c.title);
  }

  String _chartXml(WordChart c) {
    final pie = c.kind == WordChartKind.pie || c.kind == WordChartKind.doughnut;
    // The numbers are stored as the chart's cache (no data workbook).
    String col(int i) => columnName(i);
    String strRef(String f, List<String> v) =>
        '<c:strRef><c:f>$f</c:f><c:strCache><c:ptCount val="${v.length}"/>${[for (var i = 0; i < v.length; i++) '<c:pt idx="$i"><c:v>${_esc(v[i])}</c:v></c:pt>'].join()}</c:strCache></c:strRef>';
    String numRef(String f, List<double> v) =>
        '<c:numRef><c:f>$f</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val="${v.length}"/>${[for (var i = 0; i < v.length; i++) '<c:pt idx="$i"><c:v>${_num(v[i])}</c:v></c:pt>'].join()}</c:numCache></c:numRef>';
    final series = StringBuffer();
    for (var i = 0; i < c.series.length; i++) {
      final s = c.series[i];
      series.write('<c:ser><c:idx val="$i"/><c:order val="$i"/><c:tx>${strRef('Sheet1!\$${col(i + 1)}\$1', [s.name])}</c:tx>');
      if (s.color != null) {
        series.write(
          c.kind == WordChartKind.line
              ? '<c:spPr><a:ln w="28575"><a:solidFill>${_aColor(s.color!)}</a:solidFill></a:ln></c:spPr>'
              : '<c:spPr><a:solidFill>${_aColor(s.color!)}</a:solidFill></c:spPr>',
        );
      }
      if (c.kind == WordChartKind.column || c.kind == WordChartKind.bar) series.write('<c:invertIfNegative val="0"/>');
      if (c.kind == WordChartKind.line || c.kind == WordChartKind.scatter) series.write('<c:marker><c:symbol val="none"/></c:marker>');
      for (var k = 0; k < s.pointColors.length; k++) {
        final pc = s.pointColors[k];
        if (pc == null) continue;
        series.write('<c:dPt><c:idx val="$k"/>${c.kind == WordChartKind.column || c.kind == WordChartKind.bar ? '<c:invertIfNegative val="0"/><c:bubble3D val="0"/>' : '<c:bubble3D val="0"/>'}<c:spPr><a:solidFill>${_aColor(pc)}</a:solidFill></c:spPr></c:dPt>');
      }
      final n = math.max(1, c.categories.length) + 1;
      series.write('<c:cat>${strRef('Sheet1!\$A\$2:\$A\$$n', c.categories)}</c:cat><c:val>${numRef('Sheet1!\$${col(i + 1)}\$2:\$${col(i + 1)}\$$n', s.values)}</c:val>');
      if (c.kind == WordChartKind.line || c.kind == WordChartKind.scatter) series.write('<c:smooth val="0"/>');
      series.write('</c:ser>');
    }
    const axes = '<c:axId val="500000001"/><c:axId val="500000002"/>';
    final grouping = c.stacked ? 'stacked' : (c.kind == WordChartKind.line || c.kind == WordChartKind.scatter ? 'standard' : 'clustered');
    final plot = switch (c.kind) {
      WordChartKind.pie => '<c:pieChart><c:varyColors val="1"/>$series<c:firstSliceAng val="0"/></c:pieChart>',
      WordChartKind.doughnut => '<c:doughnutChart><c:varyColors val="1"/>$series<c:firstSliceAng val="0"/><c:holeSize val="50"/></c:doughnutChart>',
      WordChartKind.line || WordChartKind.scatter => '<c:lineChart><c:grouping val="$grouping"/><c:varyColors val="0"/>$series<c:marker val="1"/>$axes</c:lineChart>',
      WordChartKind.area => '<c:areaChart><c:grouping val="${c.stacked ? 'stacked' : 'standard'}"/><c:varyColors val="0"/>$series$axes</c:areaChart>',
      WordChartKind.bar ||
      WordChartKind.column ||
      WordChartKind.other => '<c:barChart><c:barDir val="${c.kind == WordChartKind.bar ? 'bar' : 'col'}"/><c:grouping val="$grouping"/><c:varyColors val="0"/>$series<c:gapWidth val="150"/>${c.stacked ? '<c:overlap val="100"/>' : ''}$axes</c:barChart>',
    };
    final horizontal = c.kind == WordChartKind.bar;
    final axisXml = pie
        ? ''
        : '<c:catAx><c:axId val="500000001"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="${horizontal ? 'l' : 'b'}"/>'
              '<c:numFmt formatCode="General" sourceLinked="0"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/>'
              '<c:crossAx val="500000002"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx>'
              '<c:valAx><c:axId val="500000002"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="${horizontal ? 'b' : 'l'}"/>'
              '<c:majorGridlines/><c:numFmt formatCode="General" sourceLinked="0"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/>'
              '<c:crossAx val="500000001"/><c:crosses val="autoZero"/><c:crossBetween val="between"/></c:valAx>';
    final title = c.title == null
        ? '<c:autoTitleDeleted val="1"/>'
        : '<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>${_esc(c.title!)}</a:t></a:r></a:p></c:rich></c:tx><c:overlay val="0"/></c:title><c:autoTitleDeleted val="0"/>';
    return '$_xmlHead<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="$_relBase">'
        '<c:roundedCorners val="0"/><c:chart>$title<c:plotArea><c:layout/>$plot$axisXml</c:plotArea>'
        '<c:legend><c:legendPos val="${pie ? 'r' : 'b'}"/><c:overlay val="0"/></c:legend><c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart>'
        '<c:externalData r:id="rId1"><c:autoUpdate val="0"/></c:externalData></c:chartSpace>';
  }

  // ------------------------------------------------------------ math

  String _omml(MathNode n) => switch (n) {
    MathText(:final text, :final plain, :final bold) =>
      '<m:r>${plain || bold ? '<m:rPr><m:sty m:val="${bold ? (plain ? 'b' : 'bi') : 'p'}"/></m:rPr>' : ''}<m:t xml:space="preserve">${_esc(text)}</m:t></m:r>',
    MathRow(:final children) => children.map(_omml).join(),
    MathFraction(:final numerator, :final denominator, :final bar) =>
      '<m:f>${bar ? '' : '<m:fPr><m:type m:val="noBar"/></m:fPr>'}<m:num>${_omml(numerator)}</m:num><m:den>${_omml(denominator)}</m:den></m:f>',
    MathRadical(:final base, :final degree) =>
      '<m:rad>${degree == null ? '<m:radPr><m:degHide m:val="1"/></m:radPr><m:deg/>' : '<m:deg>${_omml(degree)}</m:deg>'}<m:e>${_omml(base)}</m:e></m:rad>',
    MathScript(:final base, :final sup, :final sub) when sup != null && sub != null =>
      '<m:sSubSup><m:e>${_omml(base)}</m:e><m:sub>${_omml(sub)}</m:sub><m:sup>${_omml(sup)}</m:sup></m:sSubSup>',
    MathScript(:final base, :final sup) when sup != null => '<m:sSup><m:e>${_omml(base)}</m:e><m:sup>${_omml(sup)}</m:sup></m:sSup>',
    MathScript(:final base, :final sub) => '<m:sSub><m:e>${_omml(base)}</m:e><m:sub>${sub == null ? '' : _omml(sub)}</m:sub></m:sSub>',
    MathNary(:final operator, :final base, :final sub, :final sup, :final limitsUnderOver) =>
      '<m:nary><m:naryPr><m:chr m:val="${_esc(operator)}"/><m:limLoc m:val="${limitsUnderOver ? 'undOvr' : 'subSup'}"/>'
          '${sub == null ? '<m:subHide m:val="1"/>' : ''}${sup == null ? '<m:supHide m:val="1"/>' : ''}</m:naryPr>'
          '<m:sub>${sub == null ? '' : _omml(sub)}</m:sub><m:sup>${sup == null ? '' : _omml(sup)}</m:sup><m:e>${_omml(base)}</m:e></m:nary>',
    MathDelimiter(:final items, :final begin, :final end, :final separator) =>
      '<m:d><m:dPr><m:begChr m:val="${_esc(begin)}"/><m:sepChr m:val="${_esc(separator)}"/><m:endChr m:val="${_esc(end)}"/></m:dPr>'
          '${items.isEmpty ? '<m:e/>' : items.map((i) => '<m:e>${_omml(i)}</m:e>').join()}</m:d>',
    MathMatrix(:final rows) => '<m:m>${rows.map((r) => '<m:mr>${r.map((c) => '<m:e>${_omml(c)}</m:e>').join()}</m:mr>').join()}</m:m>',
    MathFunction(:final name, :final argument) => '<m:func><m:fName>${_omml(name)}</m:fName><m:e>${_omml(argument)}</m:e></m:func>',
    MathLimit(:final base, :final limit, :final upper) =>
      upper ? '<m:limUpp><m:e>${_omml(base)}</m:e><m:lim>${_omml(limit)}</m:lim></m:limUpp>' : '<m:limLow><m:e>${_omml(base)}</m:e><m:lim>${_omml(limit)}</m:lim></m:limLow>',
    MathAccent(:final base, :final mark, :final below) =>
      below
          ? '<m:groupChr><m:groupChrPr><m:chr m:val="${_esc(mark)}"/><m:pos m:val="bot"/></m:groupChrPr><m:e>${_omml(base)}</m:e></m:groupChr>'
          : '<m:acc><m:accPr><m:chr m:val="${_esc(mark)}"/></m:accPr><m:e>${_omml(base)}</m:e></m:acc>',
  };

  // ------------------------------------------------------------ styles, numbering, settings

  String _stylesXml() {
    final b = StringBuffer(
      '<w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-US" w:eastAsia="en-US" w:bidi="ar-SA"/></w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr><w:widowControl/><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
      '<w:style w:type="character" w:default="1" w:styleId="DefaultParagraphFont"><w:name w:val="Default Paragraph Font"/><w:uiPriority w:val="1"/><w:semiHidden/></w:style>'
      '<w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:semiHidden/>'
      '<w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>',
    );
    for (final e in _styles.entries) {
      if (e.key == 'Normal') continue;
      final level = e.value.outlineLevel;
      b.write(
        '<w:style w:type="paragraph" w:styleId="${_esc(e.key)}"><w:name w:val="${_esc(e.value.name)}"/><w:basedOn w:val="Normal"/><w:qFormat/>'
        '${level == null ? '' : '<w:pPr><w:outlineLvl w:val="$level"/></w:pPr>'}</w:style>',
      );
    }
    // Table styles keep their names only; the look is written on the cells.
    for (final id in _tableStyles) {
      if (id == 'TableNormal') continue;
      b.write('<w:style w:type="table" w:styleId="${_esc(id)}"><w:name w:val="${_esc(id)}"/><w:basedOn w:val="TableNormal"/></w:style>');
    }
    return '$_xmlHead<w:styles $_ns>$b</w:styles>';
  }

  String _numberingXml(_Part main) {
    final abstracts = StringBuffer();
    final nums = StringBuffer();
    for (final def in _lists.values) {
      abstracts.write('<w:abstractNum w:abstractNumId="${def.numId}"><w:multiLevelType w:val="multilevel"/>');
      for (var level = 0; level < 9; level++) {
        final l = def.levels[level];
        final format = l?.format ?? 'decimal';
        final pattern = l?.pattern ?? (format == 'bullet' ? '•' : '%${level + 1}.');
        final align = switch (l?.align) {
          WordAlign.center => 'center',
          WordAlign.right => 'right',
          _ => 'left',
        };
        var pic = '';
        if (l?.picture != null) {
          final id = _picBulletId(l!.picture!, main);
          pic = '<w:lvlPicBulletId w:val="$id"/>';
        }
        final rPr = l == null ? '' : _rPr(l.style);
        abstracts.write(
          '<w:lvl w:ilvl="$level"><w:start w:val="${l?.start ?? 1}"/><w:numFmt w:val="$format"/><w:lvlText w:val="${_esc(pattern)}"/>$pic'
          '<w:lvlJc w:val="$align"/>${l == null || l.suffix == 'tab' ? '' : '<w:suff w:val="${l.suffix}"/>'}'
          '<w:pPr><w:ind w:left="${720 * (level + 1)}" w:hanging="360"/></w:pPr>$rPr</w:lvl>',
        );
      }
      abstracts.write('</w:abstractNum>');
      nums.write('<w:num w:numId="${def.numId}"><w:abstractNumId w:val="${def.numId}"/></w:num>');
    }
    // numPicBullet ids were found while writing the levels, so put them first now.
    final head = StringBuffer();
    for (final e in _picBulletXml.entries) {
      head.write('<w:numPicBullet w:numPicBulletId="${e.key}">${e.value}</w:numPicBullet>');
    }
    return '$_xmlHead<w:numbering $_ns>$head$abstracts$nums</w:numbering>';
  }

  int _picBulletId(Uint8List bytes, _Part main) {
    final key = '${bytes.length}:${_hash(bytes)}';
    return _picBullets.putIfAbsent(key, () {
      final id = _picBullets.length;
      final rel = _mediaRel(bytes, null, _numberingPart);
      _picBulletXml[id] = '<w:pict><v:shape id="_x0000_i10$id" type="#_x0000_t75" style="width:9pt;height:9pt" o:bullet="t"><v:imagedata r:id="$rel" o:title=""/></v:shape></w:pict>';
      return id;
    });
  }

  final _numberingPart = _Part('word/numbering.xml');

  String _settingsXml() {
    final b = StringBuffer();
    if (doc.pageColor != null) b.write('<w:displayBackgroundShape/>');
    b.write('<w:defaultTabStop w:val="${_tw(doc.defaultTabStop)}"/>');
    if (doc.evenAndOddHeaders) b.write('<w:evenAndOddHeaders/>');
    b.write('<w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>');
    return '$_xmlHead<w:settings $_ns>$b</w:settings>';
  }

  void _properties() {
    final p = doc.properties;
    String el(String tag, String? v) => v == null || v.isEmpty ? '' : '<$tag>${_esc(v)}</$tag>';
    final now = DateTime.now().toUtc();
    final core =
        '$_xmlHead<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '${el('dc:title', p.title)}${el('dc:subject', p.subject)}${el('dc:creator', p.author)}${el('cp:keywords', p.keywords)}'
        '${el('dc:description', p.description)}${el('cp:lastModifiedBy', p.lastModifiedBy)}${el('cp:category', p.category)}'
        '<dcterms:created xsi:type="dcterms:W3CDTF">${_date(p.created ?? now)}</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">${_date(p.modified ?? now)}</dcterms:modified>'
        '</cp:coreProperties>';
    _files['docProps/core.xml'] = utf8.encode(core);
    _overrides['docProps/core.xml'] = 'application/vnd.openxmlformats-package.core-properties+xml';
    final app =
        '$_xmlHead<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
        'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
        '<Application>${_esc(p.application ?? 'LumaScan')}</Application>'
        '${p.pages == null ? '' : '<Pages>${p.pages}</Pages>'}${p.words == null ? '' : '<Words>${p.words}</Words>'}'
        '${el('Company', p.company)}</Properties>';
    _files['docProps/app.xml'] = utf8.encode(app);
    _overrides['docProps/app.xml'] = 'application/vnd.openxmlformats-officedocument.extended-properties+xml';
  }

  // ------------------------------------------------------------ helpers

  String _border(String tag, WordBorder b) =>
      '<w:$tag w:val="${b.style}" w:sz="${(b.width * 8).round().clamp(2, 96)}" w:space="${b.space.round()}" w:color="${_hex(b.color)}"/>';

  String _shd(int color) => '<w:shd w:val="clear" w:color="auto" w:fill="${_hex(color)}"/>';

  String _aColor(int argb) {
    final a = (argb >> 24) & 0xFF;
    return '<a:srgbClr val="${_hex(argb)}">${a == 0xFF ? '' : '<a:alpha val="${(a / 255 * 100000).round()}"/>'}</a:srgbClr>';
  }

  static String _hex(int argb) => (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  static int _tw(double pt) => (pt * 20).round();
  static int _emu(double pt) => (pt * 12700).round();
  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  static String _date(DateTime d) => '${d.toUtc().toIso8601String().split('.').first}Z';
}

const _xmlHead = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

const _ns =
    'xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas" '
    'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" '
    'xmlns:o="urn:schemas-microsoft-com:office:office" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math" '
    'xmlns:v="urn:schemas-microsoft-com:vml" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:w10="urn:schemas-microsoft-com:office:word" '
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" '
    'xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml" '
    'xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup" '
    'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" '
    'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
    'mc:Ignorable="w14 w15 wp14"';

String _esc(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    switch (r) {
      case 0x26:
        b.write('&amp;');
      case 0x3C:
        b.write('&lt;');
      case 0x3E:
        b.write('&gt;');
      case 0x22:
        b.write('&quot;');
      default:
        // Control characters are not allowed in XML 1.0.
        if (r < 0x20 && r != 0x09 && r != 0x0A && r != 0x0D) continue;
        b.writeCharCode(r);
    }
  }
  return b.toString();
}

class _Rel {
  _Rel(this.id, this.type, this.target, {this.external = false});

  final String id;
  final String type;
  final String target;
  final bool external;
}

/// One XML part and its relationships.
class _Part {
  _Part(this.path);

  final String path;
  final rels = <_Rel>[];

  String rel(String type, String target, {bool external = false}) {
    for (final r in rels) {
      if (r.type == type && r.target == target) return r.id;
    }
    final id = 'rId${rels.length + 1}';
    rels.add(_Rel(id, type, target, external: external));
    return id;
  }
}

class _ListDef {
  _ListDef(this.numId);

  final int numId;
  final levels = <int, WordListLabel>{};
}

class _StyleUse {
  _StyleUse(this.name);

  final String name;
  int? outlineLevel;
}

/// The content control, hyperlink and tracked-change wrappers around the
/// runs being written; opened and closed as the runs change.
class _Containers {
  _Containers(this.w);

  final WordWriter w;
  String? _sdt;
  WordLink? _link;
  WordRevision? _rev;
  final _closers = <String>[];

  static bool _sameLink(WordLink? a, WordLink? b) => identical(a, b) || (a != null && b != null && a.url == b.url && a.anchor == b.anchor && a.tooltip == b.tooltip);
  static bool _sameRev(WordRevision? a, WordRevision? b) => identical(a, b) || (a != null && b != null && a.kind == b.kind && a.author == b.author && a.date == b.date);

  void sync(StringBuffer o, {String? sdt, WordLink? link, WordRevision? revision, required _Part part, String text = ''}) {
    // Find the outermost wrapper that changes, close it and everything inside.
    var level = 3;
    if (_rev != null || revision != null) {
      if (!_sameRev(_rev, revision)) level = 2;
    }
    if (!_sameLink(_link, link)) level = 1;
    if (_sdt != sdt) level = 0;
    if (level == 3) return;
    _closeFrom(o, level);
    if (level <= 0 && sdt != null) {
      o.write('<w:sdt><w:sdtPr>${_sdtType(sdt, checked: text.contains('\u2612'))}</w:sdtPr><w:sdtContent>');
      _closers.add('</w:sdtContent></w:sdt>');
      _levels.add(0);
    }
    _sdt = sdt;
    if (level <= 1 && link != null) {
      final attrs = StringBuffer();
      if (link.url != null) {
        attrs.write(' r:id="${part.rel('${WordWriter._relBase}/hyperlink', link.url!, external: true)}"');
      }
      if (link.anchor != null) attrs.write(' w:anchor="${_esc(link.anchor!)}"');
      if (link.tooltip != null) attrs.write(' w:tooltip="${_esc(link.tooltip!)}"');
      o.write('<w:hyperlink$attrs w:history="1">');
      _closers.add('</w:hyperlink>');
      _levels.add(1);
    }
    _link = link;
    if (level <= 2 && revision != null) {
      final tag = switch (revision.kind) {
        WordRevisionKind.delete => 'del',
        WordRevisionKind.moveFrom => 'moveFrom',
        WordRevisionKind.moveTo => 'moveTo',
        _ => 'ins',
      };
      o.write('<w:$tag ${w._revAttrs(revision)}>');
      _closers.add('</w:$tag>');
      _levels.add(2);
    }
    _rev = revision;
  }

  final _levels = <int>[];

  void _closeFrom(StringBuffer o, int level) {
    while (_levels.isNotEmpty && _levels.last >= level) {
      o.write(_closers.removeLast());
      _levels.removeLast();
    }
    if (level <= 0) _sdt = null;
    if (level <= 1) _link = null;
    if (level <= 2) _rev = null;
  }

  void close(StringBuffer o) => _closeFrom(o, 0);

  static String _sdtType(String kind, {bool checked = false}) => switch (kind) {
    'plainText' || 'text' => '<w:text/>',
    'dropDown' || 'dropDownList' => '<w:dropDownList/>',
    'comboBox' => '<w:comboBox/>',
    'date' => '<w:date><w:dateFormat w:val="dd/MM/yyyy"/><w:lid w:val="en-US"/><w:storeMappedDataAs w:val="dateTime"/><w:calendar w:val="gregorian"/></w:date>',
    'checkBox' || 'checkbox' => '<w14:checkbox><w14:checked w14:val="${checked ? 1 : 0}"/><w14:checkedState w14:val="2612" w14:font="MS Gothic"/><w14:uncheckedState w14:val="2610" w14:font="MS Gothic"/></w14:checkbox>',
    'buildingBlock' => '<w:docPartObj><w:docPartGallery w:val="Quick Parts"/></w:docPartObj>',
    'picture' => '<w:picture/>',
    _ => '',
  };
}
