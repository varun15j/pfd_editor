import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// A Word document, read as its pages (sections) in order.
class DocxDocument {
  const DocxDocument(this.sections);

  final List<DocxSection> sections;
}

/// One section: a page size and the text and pictures on it.
class DocxSection {
  const DocxSection({
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.margins,
    this.blocks = const [],
  });

  /// Page size in points (1/72 inch).
  final double pageWidthPt;
  final double pageHeightPt;

  /// Space around the text, in points: top, right, bottom and left.
  final ({double top, double right, double bottom, double left}) margins;

  final List<DocxBlock> blocks;
}

/// What sits on a page: a paragraph of text or a picture.
sealed class DocxBlock {
  const DocxBlock();
}

class DocxText extends DocxBlock {
  const DocxText(this.text, {this.bold = false});

  final String text;
  final bool bold;
}

class DocxPicture extends DocxBlock {
  const DocxPicture(this.bytes, {required this.widthPt, required this.heightPt});

  /// The picture file as stored in the document (JPEG, PNG, ...).
  final Uint8List bytes;

  /// Size on the page, in points.
  final double widthPt;
  final double heightPt;
}

/// Reads the text and pictures of a .docx file (a zip of XML parts). Only
/// the body is read: headers, footers, comments and tracked changes are not.
class DocxReader {
  DocxReader._();

  static const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

  /// Word's default page when a section names none: A4.
  static const _defaultWidthTwips = 11906;
  static const _defaultHeightTwips = 16838;

  /// Word's default margin, one inch.
  static const _defaultMarginTwips = 1440;

  static DocxDocument parse(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw const FormatException('This file is not a Word document.');
    }
    final documentFile = archive.findFile('word/document.xml');
    if (documentFile == null) throw const FormatException('This file is not a Word document.');
    final XmlDocument xml;
    try {
      xml = XmlDocument.parse(utf8.decode(documentFile.readBytes()!));
    } on Object {
      throw const FormatException('The Word document is damaged.');
    }
    final body = xml.rootElement.childElements.where((e) => _isW(e, 'body')).firstOrNull;
    if (body == null) throw const FormatException('The Word document has no body.');

    final targets = _relationshipTargets(archive);
    final sections = <DocxSection>[];
    var blocks = <DocxBlock>[];
    for (final child in body.childElements) {
      if (_isW(child, 'p')) {
        blocks.addAll(_paragraphBlocks(child, archive, targets));
        final sectPr = _sectPrOf(child);
        if (sectPr != null) {
          sections.add(_section(sectPr, blocks));
          blocks = <DocxBlock>[];
        }
      } else if (_isW(child, 'tbl')) {
        for (final p in child.descendants.whereType<XmlElement>().where((e) => _isW(e, 'p'))) {
          blocks.addAll(_paragraphBlocks(p, archive, targets));
        }
      }
    }
    // The last section is described by the body itself.
    final finalSectPr = body.childElements.where((e) => _isW(e, 'sectPr')).lastOrNull;
    if (blocks.isNotEmpty || sections.isEmpty) sections.add(_section(finalSectPr, blocks));
    return DocxDocument(sections);
  }

  static bool _isW(XmlElement e, String local) => e.name.local == local && e.name.namespaceUri == _w;

  static XmlElement? _sectPrOf(XmlElement paragraph) {
    final pPr = paragraph.childElements.where((e) => _isW(e, 'pPr')).firstOrNull;
    return pPr?.childElements.where((e) => _isW(e, 'sectPr')).firstOrNull;
  }

  static DocxSection _section(XmlElement? sectPr, List<DocxBlock> blocks) {
    double pt(String? twips, int fallback) => (int.tryParse(twips ?? '') ?? fallback) / 20;
    final size = sectPr?.childElements.where((e) => _isW(e, 'pgSz')).firstOrNull;
    final margin = sectPr?.childElements.where((e) => _isW(e, 'pgMar')).firstOrNull;
    String? attr(XmlElement? e, String name) => e?.getAttribute(name, namespace: _w);
    return DocxSection(
      pageWidthPt: pt(attr(size, 'w'), _defaultWidthTwips),
      pageHeightPt: pt(attr(size, 'h'), _defaultHeightTwips),
      margins: (
        top: pt(attr(margin, 'top'), _defaultMarginTwips),
        right: pt(attr(margin, 'right'), _defaultMarginTwips),
        bottom: pt(attr(margin, 'bottom'), _defaultMarginTwips),
        left: pt(attr(margin, 'left'), _defaultMarginTwips),
      ),
      blocks: blocks,
    );
  }

  /// The paragraph's text first, then its pictures in order.
  static List<DocxBlock> _paragraphBlocks(XmlElement paragraph, Archive archive, Map<String, String> targets) {
    final text = StringBuffer();
    final pictures = <DocxBlock>[];
    var bold = false;
    for (final e in paragraph.descendants.whereType<XmlElement>()) {
      if (_isW(e, 't')) {
        text.write(e.innerText);
        if (_isBold(e)) bold = true;
      } else if (_isW(e, 'tab')) {
        text.write('\t');
      } else if (_isW(e, 'br') || _isW(e, 'cr')) {
        text.write('\n');
      } else if (e.name.local == 'blip') {
        final picture = _picture(e, archive, targets);
        if (picture != null) pictures.add(picture);
      }
    }
    return [if (text.toString().trim().isNotEmpty) DocxText(text.toString().trim(), bold: bold), ...pictures];
  }

  /// Whether the run holding [t] is bold.
  static bool _isBold(XmlElement t) {
    final run = t.parentElement;
    final rPr = run?.childElements.where((e) => _isW(e, 'rPr')).firstOrNull;
    final b = rPr?.childElements.where((e) => _isW(e, 'b')).firstOrNull;
    final val = b?.getAttribute('val', namespace: _w);
    return b != null && val != 'false' && val != '0';
  }

  static DocxPicture? _picture(XmlElement blip, Archive archive, Map<String, String> targets) {
    final embed = blip.attributes.where((a) => a.name.local == 'embed').firstOrNull?.value;
    final target = embed == null ? null : targets[embed];
    final file = target == null ? null : archive.findFile(target);
    if (file == null) return null;
    final frame = blip.ancestors
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'inline' || e.name.local == 'anchor')
        .firstOrNull;
    final extent = frame?.childElements.where((e) => e.name.local == 'extent').firstOrNull;
    final cx = double.tryParse(extent?.getAttribute('cx') ?? '');
    final cy = double.tryParse(extent?.getAttribute('cy') ?? '');
    return DocxPicture(file.readBytes()!, widthPt: cx == null ? 0 : cx / 12700, heightPt: cy == null ? 0 : cy / 12700);
  }

  /// Relationship id to the file's path inside the zip, e.g. `word/media/image1.jpg`.
  static Map<String, String> _relationshipTargets(Archive archive) {
    final rels = archive.findFile('word/_rels/document.xml.rels');
    if (rels == null) return const {};
    final targets = <String, String>{};
    final xml = XmlDocument.parse(utf8.decode(rels.readBytes()!));
    for (final rel in xml.rootElement.childElements) {
      final id = rel.getAttribute('Id');
      final target = rel.getAttribute('Target');
      if (id == null || target == null) continue;
      targets[id] = target.startsWith('/') ? target.substring(1) : 'word/$target';
    }
    return targets;
  }
}
