import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../model.dart';

/// A small .xlsx workbook holding a chart's data: categories in column A,
/// one column per series from B, names in row 1. Word opens it with
/// Chart Design > Edit Data. The cell ranges match the formulas the
/// writer puts in the chart (`Sheet1!$A$2:$A$n` and so on).
Uint8List chartWorkbook(WordChart c) {
  final rows = <List<Object?>>[
    [null, for (final s in c.series) s.name],
    for (var r = 0; r < c.categories.length; r++)
      [
        r < c.categories.length ? c.categories[r] : '',
        for (final s in c.series) r < s.values.length ? s.values[r] : null,
      ],
  ];
  return simpleWorkbook(rows);
}

/// Writes [rows] (strings, numbers or null) to one sheet called Sheet1.
Uint8List simpleWorkbook(List<List<Object?>> rows) {
  final sheet = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheetData>',
  );
  for (var r = 0; r < rows.length; r++) {
    sheet.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      if (v == null) continue;
      final ref = '${columnName(c)}${r + 1}';
      if (v is num) {
        sheet.write('<c r="$ref"><v>${v == v.roundToDouble() ? v.toInt() : v}</v></c>');
      } else {
        sheet.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${_esc(v.toString())}</t></is></c>');
      }
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData></worksheet>');

  const head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
  final files = <String, String>{
    '[Content_Types].xml':
        '$head<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>',
    '_rels/.rels':
        '$head<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml':
        '$head<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':
        '$head<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
    'xl/styles.xml':
        '$head<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>',
    'xl/worksheets/sheet1.xml': sheet.toString(),
  };
  final archive = Archive();
  for (final e in files.entries) {
    final data = utf8.encode(e.value);
    archive.addFile(ArchiveFile(e.key, data.length, data));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// 0 -> A, 25 -> Z, 26 -> AA.
String columnName(int index) {
  var n = index + 1;
  var out = '';
  while (n > 0) {
    out = String.fromCharCode(0x41 + (n - 1) % 26) + out;
    n = (n - 1) ~/ 26;
  }
  return out;
}

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
