// Saves the Word feature test file with WordWriter, reads the result back
// and runs the same feature checks as the reader test, then compares the
// two documents.
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

  group('written file', () => featureChecks(() => written));
}
