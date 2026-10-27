import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/export/pdf_exporter.dart';
import 'package:lumascan/export/pdf_lock/pdf_encryption.dart';
import 'package:lumascan/export/pdf_lock/pdf_locker.dart';
import 'package:lumascan/export/pdf_lock/pdf_objects.dart';
import 'package:lumascan/features/share/lock_pdf_sheet.dart';
import 'package:lumascan/features/share/pdf_sharer.dart';
import 'package:lumascan/features/share/send_pdf_sheet.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pointycastle/export.dart';

class _FakeSharer implements PdfSharer {
  final sent = <String>[];

  @override
  Future<SendOutcome> send(String path, {Rect? origin}) async {
    sent.add(path);
    return SendOutcome.sent;
  }
}

Future<Uint8List> _photoPdf() => buildPdfFromJpegs([
  (Uint8List.fromList(img.encodeJpg(img.Image(width: 60, height: 80)..clear(img.ColorRgb8(90, 120, 200)))), 60, 80),
  (Uint8List.fromList(img.encodeJpg(img.Image(width: 80, height: 60))), 80, 60),
], PdfPageSize.a4);

Future<Uint8List> _textPdf() {
  final doc = pw.Document(title: 'Lease (draft)', author: 'Tenant');
  doc.addPage(pw.Page(build: (_) => pw.Text('Rent is due on the first of the month.')));
  return doc.save();
}

Uint8List _aesCbcDecrypt(Uint8List key, Uint8List iv, Uint8List data) {
  final cipher = CBCBlockCipher(AESEngine())..init(false, ParametersWithIV(KeyParameter(key), iv));
  final out = Uint8List(data.length);
  for (var i = 0; i < data.length; i += 16) {
    cipher.processBlock(data, i, out, i);
  }
  return out;
}

/// The file key, if [password] opens [locked] (Algorithm 2.A, user password).
Uint8List? _openWith(PdfObjectFile locked, String password) {
  final enc = locked.resolve(locked.trailer['Encrypt']) as PdfDict;
  final u = (enc['U'] as PdfString).bytes;
  final pwBytes = PdfSecurity.passwordBytes(password);
  final check = PdfSecurity.hash2B(pwBytes, u.sublist(32, 40), const []);
  for (var i = 0; i < 32; i++) {
    if (check[i] != u[i]) return null;
  }
  final key = PdfSecurity.hash2B(pwBytes, u.sublist(40, 48), const []);
  return _aesCbcDecrypt(key, Uint8List(16), (enc['UE'] as PdfString).bytes);
}

Uint8List _decrypt(Uint8List fileKey, Uint8List data) {
  final plain = _aesCbcDecrypt(fileKey, data.sublist(0, 16), data.sublist(16));
  return plain.sublist(0, plain.length - plain.last);
}

/// Every stream of [original] is in [locked], encrypted with [fileKey], and
/// decrypts to the same bytes.
void _expectSameStreams(Uint8List original, Uint8List locked, Uint8List fileKey) {
  final a = PdfObjectFile.parse(original);
  final b = PdfObjectFile.parse(locked);
  var streams = 0;
  for (final n in a.objectNumbers) {
    final v = a.object(n);
    if (v is! PdfStream || v.dict.name('Type') == 'XRef' || v.dict.name('Type') == 'ObjStm') continue;
    final w = b.object(n) as PdfStream;
    expect(w.data, isNot(v.data), reason: 'stream $n is encrypted');
    expect(_decrypt(fileKey, w.data), v.data, reason: 'stream $n decrypts to the original');
    streams++;
  }
  expect(streams, greaterThan(0));
}

void main() {
  group('lockPdfBytes', () {
    test('locks a scan PDF with AES-256 that only the password opens', () async {
      final original = await _photoPdf();
      final locked = lockPdfBytes(original, 'open sesame', random: Random(7));
      expect(String.fromCharCodes(locked.sublist(0, 8)), '%PDF-1.7');

      final file = PdfObjectFile.parse(locked);
      final enc = file.resolve(file.trailer['Encrypt']) as PdfDict;
      expect(enc.name('Filter'), 'Standard');
      expect((enc['V'] as PdfNumber).asInt, 5);
      expect((enc['R'] as PdfNumber).asInt, 6);
      expect(((enc['CF'] as PdfDict)['StdCF'] as PdfDict).name('CFM'), 'AESV3');

      expect(_openWith(file, 'wrong password'), isNull);
      final key = _openWith(file, 'open sesame');
      expect(key, isNotNull);
      _expectSameStreams(original, locked, key!);
    });

    test('keeps the text, and encrypts strings such as the title', () async {
      final original = await _textPdf();
      final locked = lockPdfBytes(original, 'secret1');
      final asText = String.fromCharCodes(locked);
      expect(asText, isNot(contains('Lease (draft)')));
      expect(asText, isNot(contains('Tenant')));

      final file = PdfObjectFile.parse(locked);
      final key = _openWith(file, 'secret1')!;
      _expectSameStreams(original, locked, key);
      final info = file.resolve(file.trailer['Info']) as PdfDict;
      expect(String.fromCharCodes(_decrypt(key, (info['Title'] as PdfString).bytes)), 'Lease (draft)');
    });

    test('reads object streams and cross-reference streams', () {
      // A PDF 1.5 file whose objects sit in a compressed object stream.
      const catalog = '<</Type/Catalog/Pages 2 0 R>> ';
      const pages = '<</Type/Pages/Kids[]/Count 0>>';
      final header = '1 0 2 ${catalog.length} ';
      final packed = ZLibEncoder().convert('$header$catalog$pages'.codeUnits);
      final b = BytesBuilder()..add('%PDF-1.5\n'.codeUnits);
      final objStm = b.length;
      b
        ..add(
          '3 0 obj <</Type/ObjStm/N 2/First ${header.length}/Filter/FlateDecode/Length ${packed.length}>>stream\n'
              .codeUnits,
        )
        ..add(packed)
        ..add('\nendstream endobj\n'.codeUnits);
      final xrefAt = b.length;
      // Rows: type (1 byte), field 2 (2 bytes), field 3 (1 byte).
      final rows = [
        ...[0, 0, 0, 255],
        ...[2, 0, 3, 0],
        ...[2, 0, 3, 1],
        ...[1, objStm >> 8, objStm & 255, 0],
        ...[1, xrefAt >> 8, xrefAt & 255, 0],
      ];
      final xrefData = ZLibEncoder().convert(rows);
      b
        ..add(
          '4 0 obj <</Type/XRef/Size 5/W[1 2 1]/Root 1 0 R/Filter/FlateDecode/Length ${xrefData.length}>>stream\n'
              .codeUnits,
        )
        ..add(xrefData)
        ..add('\nendstream endobj\nstartxref\n$xrefAt\n%%EOF\n'.codeUnits);

      final file = PdfObjectFile.parse(b.toBytes());
      expect((file.object(1) as PdfDict).name('Type'), 'Catalog');
      expect((file.object(2) as PdfDict).name('Type'), 'Pages');

      final locked = PdfObjectFile.parse(lockPdfBytes(b.toBytes(), 'secret1'));
      expect((locked.object(1) as PdfDict).name('Type'), 'Catalog');
      expect(locked.objectNumbers.map(locked.object).whereType<PdfStream>(), isEmpty, reason: 'no object streams left');
    });

    test('a PDF that already has a password is refused', () async {
      final locked = lockPdfBytes(await _photoPdf(), 'secret1');
      expect(() => lockPdfBytes(locked, 'secret2'), throwsA(isA<PdfAlreadyLockedException>()));
    });

    test('a file that is not a PDF is refused', () {
      expect(() => lockPdfBytes(Uint8List.fromList('hello'.codeUnits), 'secret1'), throwsA(isA<PdfReadException>()));
    });

    test('the copy is named after the document', () {
      expect(PdfLocker.lockedName('Lease'), 'Lease (locked).pdf');
      expect(PdfLocker.lockedName('Lease.PDF'), 'Lease (locked).pdf');
    });
  });

  group('Add a password', () {
    late Directory tmp;
    late File original;
    late _FakeSharer sharer;
    late ProviderContainer container;

    Future<void> setUpContainer(AppPlan plan) async {
      tmp = Directory.systemTemp.createTempSync('lumascan_lock');
      original = File('${tmp.path}/Lease.pdf')..writeAsBytesSync(await _photoPdf());
      sharer = _FakeSharer();
      container = ProviderContainer(
        overrides: [
          pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
          pdfSharerProvider.overrideWithValue(sharer),
          planProvider.overrideWithValue(plan),
        ],
      );
      addTearDown(() {
        container.dispose();
        tmp.deleteSync(recursive: true);
      });
    }

    Future<void> pump(WidgetTester tester, Widget Function(BuildContext) open) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(builder: (context) => Scaffold(body: open(context))),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Widget lockButton(BuildContext context) => TextButton(
      onPressed: () => showLockPdfSheet(context, pdfPath: original.path, name: 'Lease'),
      child: const Text('open'),
    );

    Future<void> tapLock(WidgetTester tester) async {
      await tester.tap(find.text('Lock PDF'));
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        if (find.text('Locking…').evaluate().isEmpty) break;
      }
      await tester.pumpAndSettle();
    }

    testWidgets('a short or mismatched password is not accepted', (tester) async {
      await tester.runAsync(() => setUpContainer(AppPlan.pro));
      await pump(tester, lockButton);
      expect(find.textContaining('Lease (locked).pdf'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'abc');
      await tapLock(tester);
      expect(find.text('Use at least 6 characters'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'abcdef');
      await tester.enterText(find.widgetWithText(TextField, 'Confirm password'), 'abcdeg');
      await tapLock(tester);
      expect(find.text('The passwords do not match'), findsOneWidget);
      expect(Directory('${tmp.path}/share').existsSync(), isFalse);
    });

    testWidgets('makes a locked copy, leaves the saved PDF alone and sends the copy', (tester) async {
      await tester.runAsync(() => setUpContainer(AppPlan.pro));
      final before = original.readAsBytesSync();
      await pump(tester, lockButton);
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'tenant-2026');
      await tester.enterText(find.widgetWithText(TextField, 'Confirm password'), 'tenant-2026');
      await tapLock(tester);

      expect(find.text('Locked PDF ready'), findsOneWidget);
      final copy = File('${tmp.path}/share/Lease (locked).pdf');
      expect(copy.existsSync(), isTrue);
      expect(original.readAsBytesSync(), before);
      final key = _openWith(PdfObjectFile.parse(copy.readAsBytesSync()), 'tenant-2026');
      expect(key, isNotNull);

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(sharer.sent, [copy.path]);
      expect(find.text('Locked PDF shared'), findsOneWidget);
    });

    Widget sendButton(BuildContext context) => TextButton(
      onPressed: () => showSendPdfSheet(context, pdfPath: original.path, name: 'Lease', pageCount: 2),
      child: const Text('open'),
    );

    testWidgets('Send with password is Pro: Basic sees the upgrade pop-up', (tester) async {
      await tester.runAsync(() => setUpContainer(AppPlan.basic));
      await pump(tester, sendButton);
      expect(find.text('Send with password'), findsOneWidget);
      await tester.tap(find.text('Send with password'));
      await tester.pumpAndSettle();
      expect(find.text('Upgrade to Pro'), findsWidgets);
      expect(find.text('Add a password'), findsNothing);
    });

    testWidgets('Send with password opens the lock sheet on Gold', (tester) async {
      await tester.runAsync(() => setUpContainer(AppPlan.gold));
      await pump(tester, sendButton);
      await tester.tap(find.text('Send with password'));
      await tester.pumpAndSettle();
      expect(find.text('Add a password'), findsOneWidget);
    });
  });
}
