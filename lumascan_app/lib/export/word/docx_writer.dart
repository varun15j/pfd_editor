import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One paragraph of editable text on a Word page.
class DocxParagraph {
  const DocxParagraph(this.text, {this.fontSizePt = 11, this.spaceBeforePt = 0, this.indentPt = 0});

  final String text;
  final double fontSizePt;

  /// Space above the paragraph, in points.
  final double spaceBeforePt;

  /// Space between the left margin and the text, in points.
  final double indentPt;
}

/// One Word page: either a picture placed full size, or paragraphs of text
/// that can be edited in Word.
class DocxPage {
  const DocxPage({
    required Uint8List this.jpeg,
    required this.imageWidth,
    required this.imageHeight,
    required this.pageWidthPt,
    required this.pageHeightPt,
  }) : paragraphs = const [];

  const DocxPage.text({required this.paragraphs, required this.pageWidthPt, required this.pageHeightPt})
    : jpeg = null,
      imageWidth = 0,
      imageHeight = 0;

  /// The picture, as JPEG bytes. Null on a text page.
  final Uint8List? jpeg;

  /// The text of a text page, in order. Empty on a picture page.
  final List<DocxParagraph> paragraphs;

  bool get isText => jpeg == null;

  /// Size of the picture in pixels. Only its shape matters here.
  final int imageWidth;
  final int imageHeight;

  /// Size of the Word page in points (1/72 inch).
  final double pageWidthPt;
  final double pageHeightPt;
}

/// Writes a Word (.docx) file page by page: a picture page holds one picture
/// sized to fit, a text page holds paragraphs Word wraps and lets you edit.
/// Every page is a section of its own, so a page can be portrait or
/// landscape. The file is a zip of XML parts that Word, Pages
/// and Google Docs open; no Word library is needed.
class DocxWriter {
  DocxWriter._();

  /// Space kept between a picture and the page edge, in points.
  static const marginPt = 18.0;

  /// Word's largest page side is 22 inches.
  static const _maxSidePt = 1584.0;

  /// Space between the text and the page edge on a text page, in points.
  static const textMarginPt = 36.0;

  /// Room left under a picture for the line it sits on, in points, so the
  /// picture never pushes the page onto a second one.
  static const _lineAllowancePt = 8.0;

  static const _relationshipsNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  static const _imageType = '$_relationshipsNs/image';
  static const _documentType = '$_relationshipsNs/officeDocument';

  static Uint8List build(List<DocxPage> pages) {
    if (pages.isEmpty) throw ArgumentError('No pages to write');
    final archive = Archive()
      ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypes))
      ..addFile(ArchiveFile.string('_rels/.rels', _rootRels))
      ..addFile(ArchiveFile.string('word/_rels/document.xml.rels', _documentRels(pages.where((p) => !p.isText).length)))
      ..addFile(ArchiveFile.string('word/document.xml', _document(pages)));
    var image = 0;
    for (final page in pages) {
      if (!page.isText) archive.addFile(ArchiveFile.bytes('word/media/image${++image}.jpg', page.jpeg!));
    }
    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }

  static String _document(List<DocxPage> pages) {
    final body = StringBuffer();
    var image = 0;
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final last = i == pages.length - 1;
      // The section break sits in the paragraph that ends each page.
      final sectPr = last ? '' : _sectPr(page);
      if (page.isText) {
        _writeText(body, page.paragraphs, sectPr);
        continue;
      }
      image++;
      final size = _fit(page);
      body.write(
        '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>'
        '<w:jc w:val="center"/>$sectPr</w:pPr>'
        '<w:r>${_drawing(image, 'rId$image', size)}</w:r></w:p>',
      );
    }
    body.write(_sectPr(pages.last));
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="$_relationshipsNs" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>$body</w:body></w:document>';
  }

  static void _writeText(StringBuffer body, List<DocxParagraph> paragraphs, String sectPr) {
    if (paragraphs.isEmpty) {
      body.write('<w:p><w:pPr>$sectPr</w:pPr></w:p>');
      return;
    }
    for (var i = 0; i < paragraphs.length; i++) {
      final para = paragraphs[i];
      final halfPoints = (para.fontSizePt * 2).round();
      final before = (para.spaceBeforePt * 20).round();
      final indent = (para.indentPt * 20).round();
      body.write(
        '<w:p><w:pPr><w:spacing w:before="$before" w:after="0"/>'
        '${indent > 0 ? '<w:ind w:left="$indent"/>' : ''}'
        '${i == paragraphs.length - 1 ? sectPr : ''}</w:pPr>'
        '<w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/>'
        '<w:sz w:val="$halfPoints"/><w:szCs w:val="$halfPoints"/></w:rPr>'
        '<w:t xml:space="preserve">${escapeText(para.text)}</w:t></w:r></w:p>',
      );
    }
  }

  /// [text] made safe for XML: markup characters escaped, and characters XML
  /// cannot hold (control characters, broken surrogate pairs) dropped.
  static String escapeText(String text) {
    final out = StringBuffer();
    final runes = text.runes;
    for (final r in runes) {
      if (r == 0x09 || r == 0x0A || r == 0x0D) {
        out.write(' ');
      } else if (r < 0x20 || (r >= 0xD800 && r <= 0xDFFF) || r == 0xFFFE || r == 0xFFFF) {
        continue;
      } else if (r == 0x26) {
        out.write('&amp;');
      } else if (r == 0x3C) {
        out.write('&lt;');
      } else if (r == 0x3E) {
        out.write('&gt;');
      } else {
        out.writeCharCode(r);
      }
    }
    return out.toString();
  }

  /// The page's size in Word's units, with its side limit applied.
  static (double, double) _pageSize(DocxPage page) {
    final scale = page.pageWidthPt > _maxSidePt || page.pageHeightPt > _maxSidePt
        ? _maxSidePt / (page.pageWidthPt > page.pageHeightPt ? page.pageWidthPt : page.pageHeightPt)
        : 1.0;
    return (page.pageWidthPt * scale, page.pageHeightPt * scale);
  }

  /// The picture's size in points, shrunk to fit inside the margins.
  static (double, double) _fit(DocxPage page) {
    final (w, h) = _pageSize(page);
    final maxW = w - 2 * marginPt;
    final maxH = h - 2 * marginPt - _lineAllowancePt;
    final scale = math.min(1.0, math.min(maxW / page.imageWidth, maxH / page.imageHeight));
    return (page.imageWidth * scale, page.imageHeight * scale);
  }

  static String _sectPr(DocxPage page) {
    final (w, h) = _pageSize(page);
    final orient = w > h ? ' w:orient="landscape"' : '';
    final margin = ((page.isText ? textMarginPt : marginPt) * 20).round();
    return '<w:sectPr>'
        '<w:pgSz w:w="${(w * 20).round()}" w:h="${(h * 20).round()}"$orient/>'
        '<w:pgMar w:top="$margin" w:right="$margin" w:bottom="$margin" w:left="$margin" '
        'w:header="0" w:footer="0" w:gutter="0"/>'
        '${page.isText ? '' : '<w:vAlign w:val="center"/>'}'
        '</w:sectPr>';
  }

  static String _drawing(int id, String relId, (double, double) size) {
    final cx = (size.$1 * 12700).round();
    final cy = (size.$2 * 12700).round();
    return '<w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/>'
        '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:docPr id="$id" name="Page $id"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic>'
        '<pic:nvPicPr><pic:cNvPr id="$id" name="page$id.jpg"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$relId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic>'
        '</a:graphicData></a:graphic>'
        '</wp:inline>'
        '</w:drawing>';
  }

  static String _documentRels(int pageCount) {
    final rels = StringBuffer();
    for (var i = 1; i <= pageCount; i++) {
      rels.write('<Relationship Id="rId$i" Type="$_imageType" Target="media/image$i.jpg"/>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$rels</Relationships>';
  }

  static const _contentTypes =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="jpg" ContentType="image/jpeg"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>';

  static const _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="$_documentType" Target="word/document.xml"/>'
      '</Relationships>';
}
