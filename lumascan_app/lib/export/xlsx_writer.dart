import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Writes one sheet of rows to an Excel (.xlsx) file. The first row is bold
/// and stays in view when scrolling, cells that hold a plain number become
/// numbers Excel can add up, and everything else stays text. The file is a
/// zip of XML parts that Excel, Google Sheets and LibreOffice open; no Excel
/// library is needed.
class XlsxWriter {
  XlsxWriter._();

  static const mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  static Uint8List write(List<List<String>> rows, {String sheetName = 'Table'}) {
    final archive = Archive()
      ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypes))
      ..addFile(ArchiveFile.string('_rels/.rels', _rootRels))
      ..addFile(ArchiveFile.string('xl/workbook.xml', _workbook(sheetName)))
      ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', _workbookRels))
      ..addFile(ArchiveFile.string('xl/styles.xml', _styles))
      ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', _sheet(rows)));
    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }

  /// The value of [text] as a number, or null when it should stay text.
  /// "1,234.50", "₹ 250" and "-3" are numbers; "007", "12/10/2026" and
  /// "98765 43210" stay text, so codes, dates and phone numbers keep their
  /// look.
  static num? numberIn(String text) {
    var t = text.trim().replaceFirst(RegExp(r'^(₹|Rs\.?|\$|€|£)\s*'), '');
    if (!RegExp(r'^-?(\d{1,3}(,\d{2,3})+|\d+)(\.\d+)?$').hasMatch(t)) return null;
    t = t.replaceAll(',', '');
    final whole = t.startsWith('-') ? t.substring(1) : t;
    if (whole.length > 1 && whole.startsWith('0') && !whole.startsWith('0.')) return null;
    if (whole.split('.').first.length > 15) return null;
    return num.tryParse(t);
  }

  /// "A" for column 0, "Z" for 25, "AA" for 26.
  static String columnName(int index) {
    var name = '';
    for (var n = index + 1; n > 0; n = (n - 1) ~/ 26) {
      name = String.fromCharCode(65 + (n - 1) % 26) + name;
    }
    return name;
  }

  static String _sheet(List<List<String>> rows) {
    final columns = rows.fold(0, (m, r) => math.max(m, r.length));
    final out = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
      ..write('<sheetViews><sheetView workbookViewId="0">');
    if (rows.length > 1) out.write('<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>');
    out.write('</sheetView></sheetViews>');
    if (columns > 0) {
      out.write('<cols>');
      for (var c = 0; c < columns; c++) {
        final longest = rows.fold(0, (m, r) => c < r.length ? math.max(m, r[c].length) : m);
        out.write(
          '<col min="${c + 1}" max="${c + 1}" width="${math.min(60, math.max(8, longest + 2))}" customWidth="1"/>',
        );
      }
      out.write('</cols>');
    }
    out.write('<sheetData>');
    for (var r = 0; r < rows.length; r++) {
      out.write('<row r="${r + 1}">');
      for (var c = 0; c < rows[r].length; c++) {
        final text = rows[r][c];
        if (text.isEmpty) continue;
        final ref = '${columnName(c)}${r + 1}';
        final style = r == 0 ? ' s="1"' : '';
        final number = numberIn(text);
        if (number != null) {
          out.write('<c r="$ref"$style><v>$number</v></c>');
        } else {
          out.write('<c r="$ref"$style t="inlineStr"><is><t xml:space="preserve">${_escape(text)}</t></is></c>');
        }
      }
      out.write('</row>');
    }
    return (out..write('</sheetData></worksheet>')).toString();
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      // XML 1.0 has no place for control characters other than tab and newlines.
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

  static String _workbook(String sheetName) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="${_escape(sheetName)}" sheetId="1" r:id="rId1"/></sheets></workbook>';

  static const _contentTypes =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/styles.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '</Types>';

  static const _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="xl/workbook.xml"/></Relationships>';

  static const _workbookRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
      'Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
      'Target="styles.xml"/></Relationships>';

  /// Style 0 is plain, style 1 is bold for the first row.
  static const _styles =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';
}
