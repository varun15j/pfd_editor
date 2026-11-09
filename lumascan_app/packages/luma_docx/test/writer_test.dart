// Saves the Word feature test file with WordWriter, reads the result back
// and runs the same feature checks as the reader test, then compares the
// two documents.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_docx/luma_docx.dart';
import 'package:xml/xml.dart';

import 'support/feature_checks.dart';

final original = WordReader.read(File('test/fixtures/Word_Feature_Test.docx').readAsBytesSync());
final Uint8List written = WordWriter.write(original);

void main() {
  test('every part is well-formed XML', () {
    final out = Platform.environment['WRITER_OUT'];
    if (out != null) File(out).writeAsBytesSync(written);
    final zip = ZipDecoder().decodeBytes(written);
    for (final f in zip.files) {
      if (f.name.endsWith('.xml') || f.name.endsWith('.rels')) {
        expect(() => XmlDocument.parse(String.fromCharCodes(f.content)), returnsNormally, reason: f.name);
      }
    }
  });

  test('round trip keeps text, structure and counts', () {
    final copy = WordReader.read(written);
    expect(copy.warnings, isEmpty);
    expect(copy.plainText, original.plainText);
    expect(copy.sections.length, original.sections.length);
    expect(copy.headings.map((h) => h.text), original.headings.map((h) => h.text));
    expect(copy.comments.length, original.comments.length);
    expect(copy.footnotes.length, original.footnotes.length);
    expect(copy.endnotes.length, original.endnotes.length);
    expect(copy.bookmarks.keys.toSet(), original.bookmarks.keys.toSet());
    expect(copy.properties.title, original.properties.title);
    expect(copy.pageColor, original.pageColor);
  });

  test('each chart carries a workbook with its data', () {
    final zip = ZipDecoder().decodeBytes(written);
    final charts = <WordChart>[];
    void walk(List<WordBlock> blocks) {
      for (final b in blocks) {
        if (b is WordParagraph) charts.addAll(b.inlines.whereType<WordChart>());
        if (b is WordTable) {
          for (final r in b.rows) {
            for (final c in r.cells) {
              walk(c.blocks);
            }
          }
        }
      }
    }

    for (final s in original.sections) {
      walk(s.blocks);
    }
    expect(charts, isNotEmpty);
    for (var i = 0; i < charts.length; i++) {
      final n = i + 1;
      final rels = String.fromCharCodes(zip.findFile('word/charts/_rels/chart$n.xml.rels')!.content);
      expect(rels, contains('embeddings/Microsoft_Excel_Worksheet$n.xlsx'));
      expect(String.fromCharCodes(zip.findFile('word/charts/chart$n.xml')!.content), contains('<c:externalData r:id="rId1">'));
      final book = ZipDecoder().decodeBytes(zip.findFile('word/embeddings/Microsoft_Excel_Worksheet$n.xlsx')!.content);
      final sheet = XmlDocument.parse(utf8.decode(book.findFile('xl/worksheets/sheet1.xml')!.content));
      final cells = {for (final c in sheet.findAllElements('c')) c.getAttribute('r'): c.innerText};
      final chart = charts[i];
      expect(cells['B1'], chart.series.first.name);
      expect(cells['A2'], chart.categories.first);
      expect(double.parse(cells['B2']!), chart.series.first.values.first);
    }
  });

  group('written file', () => featureChecks(() => written));
}
