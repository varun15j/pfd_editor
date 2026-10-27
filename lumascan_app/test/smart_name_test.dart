import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/data/smart_namer.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/ocr.dart';
import 'package:lumascan/domain/smart_name.dart';

class _FakeOcr implements OcrEngine {
  _FakeOcr(this.text, {this.readiness = OcrReadiness.ready, this.fail = false});
  final String text;
  final OcrReadiness readiness;
  final bool fail;
  final read = <String>[];

  @override
  Future<OcrCapability> capability(String languageCode) async =>
      OcrCapability(readiness: readiness, language: 'English');

  @override
  Future<void> prepare(String languageCode) async {}

  @override
  Future<String> recognize(ScanPage page, {required String languageCode}) async {
    if (fail) throw StateError('engine crashed');
    read.add(page.originalPath);
    return text;
  }

  @override
  Future<String> recognizeFile(String path, {String languageCode = 'en'}) async => text;
}

void main() {
  group('suggestDocumentName', () {
    test('names an invoice by its kind, number and date', () {
      const page = '''
SHARMA ELECTRONICS
12 MG Road, Pune
TAX INVOICE
Invoice No: INV-2041        Date: 26/10/2026
Bill to: Varun
''';
      expect(suggestDocumentName(page), 'Tax Invoice INV-2041 2026-10-26');
    });

    test('reads dates written with month names, day first', () {
      expect(suggestDocumentName('Receipt\nReceipt no. 4471\nPaid on 3rd March 2026'), 'Receipt 4471 2026-03-03');
      expect(suggestDocumentName('Receipt\nMarch 3, 2026'), 'Receipt 2026-03-03');
    });

    test('a number label with no digits is not a number', () {
      expect(suggestDocumentName('INVOICE\nInvoice No: Date'), 'Invoice');
    });

    test('slashes in a number become dashes, so it is a safe file name', () {
      expect(suggestDocumentName('BILL\nBill No: 88/2026'), 'Bill 88-2026');
    });

    test('a kind word in the small print does not name the document', () {
      final page = ['Monthly Newsletter', ...List.filled(14, 'Some ordinary text here'), 'invoice'].join('\n');
      expect(suggestDocumentName(page), 'Monthly Newsletter');
    });

    test('without a known kind, the first title-like line is used, in title case', () {
      expect(suggestDocumentName('12/04/2025\n\nRENTAL DEED OF FLAT 4B\nThis deed is made...'), 'Rental Deed Of Flat 4B 2025-04-12');
      expect(suggestDocumentName('www.example.com\nKendriya Vidyalaya Half Yearly Exam'), 'Kendriya Vidyalaya Half Yearly Exam');
    });

    test('gives null for empty text or text with no title, number or date', () {
      expect(suggestDocumentName(''), isNull);
      expect(suggestDocumentName('   \n  '), isNull);
      expect(suggestDocumentName('1234 5678\n+91 98765 43210'), isNull);
    });

    test('impossible dates are ignored', () {
      expect(findDocumentDate('31/02/2026'), isNull);
      expect(findDocumentDate('due 2026-02-28'), DateTime(2026, 2, 28));
      expect(findDocumentDate('on 05-11-26'), DateTime(2026, 11, 5));
    });

    test('long names are cut at a word, with no characters files reject', () {
      final name = suggestDocumentName('Annual Report Of The "Housing Committee": Findings? And Recommendations For Members')!;
      expect(name.length, lessThanOrEqualTo(60));
      expect(name, isNot(matches(RegExp(r'[\\/:*?"<>|]'))));
      expect(name.endsWith(' '), isFalse);
    });
  });

  group('SmartNamer', () {
    final pages = [
      const ScanPage(id: 'a', originalPath: '/a.jpg'),
      const ScanPage(id: 'b', originalPath: '/b.jpg'),
    ];

    test('reads only the first page', () async {
      final ocr = _FakeOcr('CERTIFICATE\nThis is to certify');
      expect(await SmartNamer(ocr).suggest(pages), 'Certificate');
      expect(ocr.read, ['/a.jpg']);
    });

    test('uses text already read from the page instead of reading it again', () async {
      final ocr = _FakeOcr('nothing');
      final read = [const ScanPage(id: 'a', originalPath: '/a.jpg', text: 'RECEIPT\nReceipt No: 77')];
      expect(await SmartNamer(ocr).suggest(read), 'Receipt 77');
      expect(ocr.read, isEmpty);
    });

    test('gives null, never throws, when the engine is not ready or fails', () async {
      expect(await SmartNamer(_FakeOcr('Invoice', readiness: OcrReadiness.needsDownload)).suggest(pages), isNull);
      expect(await SmartNamer(_FakeOcr('Invoice', fail: true)).suggest(pages), isNull);
      expect(await SmartNamer(const UnavailableOcrEngine()).suggest(pages), isNull);
      expect(await SmartNamer(_FakeOcr('Invoice')).suggest(const []), isNull);
    });
  });
}
