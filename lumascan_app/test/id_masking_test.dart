import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/app/theme.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/id_masking.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/ocr.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/domain/scanner_service.dart';
import 'package:lumascan/features/batch_edit/batch_review_screen.dart';
import 'package:lumascan/features/markup/auto_mask.dart';
import 'package:lumascan/features/markup/markup_screen.dart';
import 'package:lumascan/features/pages/scan_controller.dart';
import 'package:lumascan/features/pdf_editor/annotation_layer.dart';
import 'package:lumascan/imaging/masking.dart';
import 'package:lumascan/imaging/page_renderer.dart';
import 'package:lumascan/imaging/render_service.dart';
import 'package:lumascan/imaging/rgb_image.dart';
import 'package:lumascan/pdf_edit/annotations.dart';
import 'package:lumascan/pdf_edit/pdf_flattener.dart';

import 'support/memory_stores.dart';
import 'support/screen_harness.dart';

/// A valid Aadhaar number (it passes the Verhoeff check), as the test data.
const _aadhaar = '234567890120';

OcrLine _line(String text, {double top = 0.5, double bottom = 0.56, double left = 0.1, double right = 0.9}) {
  // Word boxes laid out across the line, as ML Kit reports them.
  final words = RegExp(r'\S+').allMatches(text).toList();
  final total = text.length;
  return OcrLine(
    text: text,
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    words: [
      for (final w in words)
        OcrBox(
          text: w.group(0)!,
          left: left + (right - left) * w.start / total,
          top: top,
          right: left + (right - left) * w.end / total,
          bottom: bottom,
        ),
    ],
  );
}

OcrLayout _layout(List<OcrLine> lines) => OcrLayout([
  for (final l in lines) OcrBlock(text: l.text, left: l.left, top: l.top, right: l.right, bottom: l.bottom, lines: [l]),
]);

/// Answers with a fixed layout, so Auto mask can be tested without ML Kit.
class _FakeLayoutOcr implements OcrEngine, OcrLayoutEngine {
  _FakeLayoutOcr(this.layout);

  OcrLayout layout;
  OcrReadiness readiness = OcrReadiness.ready;
  final readPages = <ScanPage>[];

  @override
  Future<OcrCapability> capability(String languageCode) async =>
      OcrCapability(readiness: readiness, language: 'English', reason: 'No text recognition here');

  @override
  Future<void> prepare(String languageCode) async {}

  @override
  Future<String> recognize(ScanPage page, {required String languageCode}) async => layout.text;

  @override
  Future<String> recognizeFile(String path, {String languageCode = 'en'}) async => layout.text;

  @override
  Future<OcrLayout> recognizeLayout(ScanPage page, {required String languageCode}) async {
    readPages.add(page);
    return layout;
  }
}

/// Shows the original file so widget tests settle without the render isolate.
class _NoRender extends RenderService {
  _NoRender(super.store);

  @override
  Future<RenderedImage> render(ScanPage page, {EditRecipe? recipe, int maxDimension = RenderService.previewSize}) =>
      Future.value(RenderedImage(page.originalPath, 300, 400));

  @override
  Future<RenderedImage> renderMasked(ScanPage page, {int maxDimension = RenderService.previewSize}) =>
      Future.value(RenderedImage(page.originalPath, 300, 400));
}

void main() {
  const finder = IdNumberFinder();

  group('finding ID numbers', () {
    test('an Aadhaar number printed in groups is found and only the last four digits stay', () {
      final hits = finder.findInLine(_line('2345 6789 0120'));
      expect(hits, hasLength(1));
      final hit = hits.single;
      expect((hit.kind, hit.text), (IdKind.aadhaar, _aadhaar));
      // One box per hidden group, four Xs each; the last group stays.
      final words = _line('2345 6789 0120').words;
      expect(hit.pieces.map((p) => p.chars), [4, 4]);
      expect(hit.pieces.first.right, closeTo(words[0].right, 0.001));
      expect(hit.pieces.last.left, lessThan(words[1].left));
      expect(hit.right, lessThanOrEqualTo(words.last.left + 0.001));
      expect(hit.left, lessThanOrEqualTo(0.11));
    });

    test('a 12-digit Aadhaar written as one word keeps its last four digits', () {
      final hit = finder.findInLine(_line(_aadhaar)).single;
      expect(hit.kind, IdKind.aadhaar);
      final word = _line(_aadhaar).words.single;
      final eighth = word.left + (word.right - word.left) * 8 / 12;
      expect(hit.right, closeTo(eighth, 0.001));
      expect(hit.pieces.single.chars, 8);
    });

    test('a 16-digit VID is found, and four groups of four are read as a VID not an Aadhaar', () {
      expect(finder.findInLine(_line('9123 4567 8901 2349')).single.kind, IdKind.vid);
    });

    test('letters OCR read for digits are fixed before matching', () {
      expect(finder.findInLine(_line('2345 67B9 O120')).single.text, _aadhaar);
    });

    test('PAN, voter ID, passport and driving licence numbers are found', () {
      expect(finder.findInLine(_line('PAN ABCDE1234F')).single.kind, IdKind.pan);
      expect(finder.findInLine(_line('ABC1234567')).single.kind, IdKind.voterId);
      expect(finder.findInLine(_line('Passport M1234567')).single.kind, IdKind.passport);
      expect(finder.findInLine(_line('MH12 20110012345')).single.kind, IdKind.drivingLicence);
      expect(finder.findInLine(_line('MH1220110012345')).single.kind, IdKind.drivingLicence);
    });

    test('a driving licence mask covers everything but the last four characters', () {
      final line = _line('MH12 20110012345');
      final hit = finder.findInLine(line).single;
      expect(hit.left, lessThanOrEqualTo(line.words.first.left + 0.001));
      expect(hit.right, greaterThan(line.words.last.left), reason: 'it reaches into the second word');
      expect(hit.right, lessThan(line.words.last.right));
    });

    test('ordinary numbers on a page are left alone', () {
      for (final text in [
        'Invoice 2024 total 1800',
        'Pin code 560001',
        '0123 4567 8912', // Aadhaar numbers never start with 0
        '1234 5678 9012', // nor with 1
        'Issued 01/01/1990',
        'Total 4111111111111112', // one run that fails the Luhn check
        'Call 123-45-6789x', // not an SSN shape
        'Order 900-12-3456', // SSNs never start with 9
        'Phone 9876543210',
      ]) {
        expect(finder.findInLine(_line(text)), isEmpty, reason: text);
      }
    });

    test('a long run of digits must pass the check digit, grouped ones need not', () {
      expect(finder.findInLine(_line('234567890123')), isEmpty, reason: 'check digit fails');
      expect(finder.findInLine(_line('2345 6789 0123')).single.kind, IdKind.aadhaar, reason: 'grouped is enough');
      expect(IdNumberFinder.verhoeffValid(_aadhaar), isTrue);
      expect(IdNumberFinder.verhoeffValid('234567890123'), isFalse);
    });

    test('a line without word boxes still gets a mask, estimated from the line', () {
      const line = OcrLine(text: '2345 6789 0120', left: 0.2, top: 0.4, right: 0.8, bottom: 0.45);
      final hit = finder.findInLine(line).single;
      expect(hit.left, lessThan(0.25));
      expect(hit.right, inInclusiveRange(0.55, 0.62));
    });

    test('card numbers that pass the Luhn check keep their last four digits', () {
      final hit = finder.findInLine(_line('4111 1111 1111 1111')).single;
      expect(hit.kind, IdKind.card);
      expect(hit.pieces.map((p) => p.chars), [4, 4, 4]);
      expect(finder.findInLine(_line('Visa 4111111111111111')).single.kind, IdKind.card);
      expect(finder.findInLine(_line('3782 822463 10005')).single.kind, IdKind.card, reason: 'Amex 4-6-5');
      expect(IdNumberFinder.luhnValid('4111111111111111'), isTrue);
      expect(IdNumberFinder.luhnValid('4111111111111112'), isFalse);
    });

    test('US Social Security numbers are found, written with dashes or spaces', () {
      final dashed = finder.findInLine(_line('SSN 123-45-6789'));
      expect(dashed.single.kind, IdKind.ssn);
      expect(dashed.single.pieces.single.chars, 5);
      expect(finder.findInLine(_line('123 45 6789')).single.kind, IdKind.ssn);
      expect(finder.findInLine(_line('000-12-3456')), isEmpty);
      expect(finder.findInLine(_line('666-12-3456')), isEmpty);
    });

    test('a UK National Insurance number is found', () {
      expect(finder.findInLine(_line('NI AB123456C')).single.kind, IdKind.nationalId);
    });

    test('a date of birth after a label is crossed out whole', () {
      for (final text in [
        'DOB: 01/01/1990',
        'जन्म तिथि/DOB: 01/01/1990',
        'Date of Birth 1990-01-31',
        'D.O.B 31.01.1990',
      ]) {
        final hit = finder.findInLine(_line(text)).single;
        expect(hit.kind, IdKind.dateOfBirth, reason: text);
        expect(hit.pieces.single.chars, hit.text.length, reason: 'nothing of a birth date is left: $text');
      }
      final spelled = finder.findInLine(_line('Born 12 Jan 1990')).single;
      expect(spelled.pieces, hasLength(3));
      expect(finder.findInLine(_line('Year of Birth 1990')).single.kind, IdKind.dateOfBirth);
      expect(finder.findInLine(_line('DOB:01/01/1990')).single.text, '01/01/1990');
    });

    test('a date without a birth label is left alone', () {
      expect(finder.findInLine(_line('Issue date 01/01/2020')), isEmpty);
    });

    test('a labelled number from any country is masked, keeping its last four', () {
      for (final text in [
        'Passport No. X1234567',
        'Document No: AB 1234567',
        'ID Number 9001015009087',
        'National ID 1234-5678-9',
        'SIN 046 454 286',
        'Card No 1234567890',
        'Licence No DL-0420110149646',
      ]) {
        final hits = finder.findInLine(_line(text));
        expect(hits, isNotEmpty, reason: text);
        final hit = hits.last;
        final hidden = hit.pieces.fold<int>(0, (n, p) => n + p.chars);
        expect(hidden, hit.text.length - 4, reason: text);
      }
    });

    test('a label alone on its line masks the number on the line below', () {
      final hits = finder.find(
        OcrLayout([
          OcrBlock(
            text: 'Passport No.\nZ9876543',
            left: 0.1,
            top: 0.4,
            right: 0.9,
            bottom: 0.6,
            lines: [_line('Passport No.', top: 0.4, bottom: 0.45), _line('Z9876543', top: 0.5, bottom: 0.55)],
          ),
        ]),
      );
      // Z9876543 is also an Indian passport shape, so it may be found on its
      // own line too; either way it is masked.
      expect(hits, isNotEmpty);
      expect(hits.every((h) => h.top >= 0.45), isTrue);
    });

    test('a number after a label that OCR could not read gets a black box', () {
      final hit = finder.findInLine(_line('DOB: 0l/?1/l9B0')).single;
      expect(hit.kind, IdKind.dateOfBirth);
      expect(hit.unreadable, isTrue);
      expect(hit.pieces.single.chars, 0, reason: '0 means a solid box');
      expect(finder.findInLine(_line('Passport No: ????')), isEmpty, reason: 'nothing number-like to hide');
    });

    test('a number already found by its shape is not masked again by its label', () {
      final hits = finder.findInLine(_line('Aadhaar No: 2345 6789 0120'));
      expect(hits.single.kind, IdKind.aadhaar);
      final card = finder.findInLine(_line('Card No 4111 1111 1111 1111 exp 12/29'));
      expect(card.single.kind, IdKind.card, reason: 'the expiry date is left alone');
    });

    test("a passport's machine-readable lines are hidden whole", () {
      final hit = finder.findInLine(_line('P<INDKUMAR<<ANIL<<<<<<<<<<<<<<<<<<<<<<<<<<<<')).single;
      expect(hit.kind, IdKind.passportMrz);
      expect(hit.pieces.single.chars, hit.text.length);
      expect(finder.findInLine(_line('Z9876543<1IND9001015M3001017<<<<<<<<<<<<<<04')).single.kind, IdKind.passportMrz);
    });

    test('every line of every block is read', () {
      final hits = finder.find(
        _layout([_line('Name A Kumar', top: 0.2), _line('2345 6789 0120', top: 0.5), _line('ABCDE1234F', top: 0.7)]),
      );
      expect(hits.map((h) => h.kind), [IdKind.aadhaar, IdKind.pan]);
    });

    test('a block with no lines is read as one line', () {
      final hits = finder.find(
        OcrLayout(const [OcrBlock(text: '2345 6789 0120', left: 0.1, top: 0.5, right: 0.9, bottom: 0.56)]),
      );
      expect(hits.single.kind, IdKind.aadhaar);
    });
  });

  group('mask marks', () {
    test('a mask survives a JSON round trip, and other marks still load', () {
      const mask = MaskAnnotation(
        id: 'm1',
        left: 0.1,
        top: 0.2,
        right: 0.5,
        bottom: 0.3,
        label: 'Aadhaar number',
        crosses: 8,
      );
      final back = Annotation.listFromJson(jsonDecode(jsonEncode([mask.toJson()])));
      final read = back.single as MaskAnnotation;
      expect((read.crosses, read.crossesOut), (8, true));
      expect(
        const MaskAnnotation(id: 'b', left: 0, top: 0, right: 1, bottom: 1).toJson().containsKey('crosses'),
        isFalse,
      );
      expect(read.movedBy(0.1, 0).crosses, 8);
      expect(read.scaledBy(1.2).crosses, 8);
      expect(
        (read.id, read.left, read.right, read.label, read.color),
        ('m1', 0.1, 0.5, 'Aadhaar number', MaskAnnotation.black),
      );
    });

    test('a mask is built from two corners in any order and stays on the page', () {
      final a = MaskAnnotation.between('m', const NormPoint(0.6, 0.7), const NormPoint(0.2, 0.3));
      expect((a.left, a.top, a.right, a.bottom), (0.2, 0.3, 0.6, 0.7));
      final out = MaskAnnotation.between('m', const NormPoint(-1, -1), const NormPoint(2, 2));
      expect((out.left, out.top, out.right, out.bottom), (0.0, 0.0, 1.0, 1.0));
      expect(MaskAnnotation.between('m', const NormPoint(0.5, 0.5), const NormPoint(0.5, 0.5)).isTooSmall, isTrue);
    });

    test('moving and resizing keep the mask on the page', () {
      const m = MaskAnnotation(id: 'm', left: 0.4, top: 0.4, right: 0.6, bottom: 0.5);
      final moved = m.movedBy(0.9, -0.9);
      expect((moved.right, moved.top), (1.0, 0.0));
      expect(moved.width, closeTo(m.width, 1e-9));
      final big = m.scaledBy(2);
      expect(big.width, closeTo(0.4, 1e-9));
      expect(m.contains(const NormPoint(0.5, 0.45)), isTrue);
      expect(m.contains(const NormPoint(0.1, 0.45)), isFalse);
    });

    test('the mask tool and masksIn pick masks out of a page', () {
      const marks = [
        TextAnnotation(id: 't', origin: NormPoint(0, 0), text: 'x', color: 0xFF000000),
        MaskAnnotation(id: 'm', left: 0, top: 0, right: 0.2, bottom: 0.1),
      ];
      expect(masksIn(marks).map((m) => m.id), ['m']);
      expect(hitMask(marks, const NormPoint(0.1, 0.05))?.id, 'm');
      expect(hitMask(marks, const NormPoint(0.9, 0.9)), isNull);
      expect(EditorTool.values.contains(EditorTool.mask), isTrue);
    });
  });

  group('masks are burned into the picture', () {
    test('the pixels under a mask are replaced, so nothing is recoverable', () {
      final image = RgbImage(20, 10)..data.fillRange(0, 600, 255);
      burnMasks(image, const [MaskAnnotation(id: 'm', left: 0.0, top: 0.0, right: 0.5, bottom: 0.5)]);
      int at(int x, int y) => image.data[(y * 20 + x) * 3];
      expect(at(0, 0), 0, reason: 'inside the mask');
      expect(at(9, 4), 0);
      expect(at(15, 4), 255, reason: 'outside the mask');
      expect(at(5, 8), 255);
    });

    test('a crossed-out mask is the paper colour with one X per hidden character', () {
      // Light grey paper with a black "number" in the middle.
      final image = RgbImage(80, 20)..data.fillRange(0, 80 * 20 * 3, 230);
      for (var y = 6; y < 14; y++) {
        for (var x = 10; x < 70; x++) {
          final i = (y * 80 + x) * 3;
          image.data[i] = image.data[i + 1] = image.data[i + 2] = 0;
        }
      }
      burnMasks(image, const [MaskAnnotation(id: 'm', left: 0.1, top: 0.25, right: 0.875, bottom: 0.75, crosses: 4)]);
      int at(int x, int y) => image.data[(y * 80 + x) * 3];
      // The box edge, between Xs, is paper again: the number is gone.
      expect(at(11, 6), 230);
      expect(at(10 + 15, 7), 230, reason: 'the gap between two Xs');
      // The centre of each X is ink.
      final cells = crossCells(8, 5, 70, 15, 4);
      for (final (i, c) in cells.indexed) {
        final cx = ((c.left + c.right) / 2).floor(), cy = ((c.top + c.bottom) / 2).floor();
        final near = [
          for (var dy = -1; dy <= 1; dy++)
            for (var dx = -1; dx <= 1; dx++) at(cx + dx, cy + dy),
        ];
        expect(near.any((v) => v < 60), isTrue, reason: 'X $i has ink at its centre');
      }
      expect(at(2, 2), 230, reason: 'outside is untouched');
    });

    test('on dark paper the Xs are light', () {
      final image = RgbImage(40, 20)..data.fillRange(0, 40 * 20 * 3, 20);
      burnMasks(image, const [MaskAnnotation(id: 'm', left: 0.2, top: 0.2, right: 0.8, bottom: 0.8, crosses: 1)]);
      expect(image.data[(10 * 40 + 20) * 3], greaterThan(200));
    });

    test('X cells are spread evenly and stay inside the box', () {
      final cells = crossCells(0, 0, 100, 20, 5);
      expect(cells, hasLength(5));
      for (final c in cells) {
        expect(c.left, greaterThanOrEqualTo(0));
        expect(c.right, lessThanOrEqualTo(100));
        expect(c.top, greaterThan(0));
        expect(c.bottom, lessThan(20));
      }
      expect(cells[1].left - cells[0].left, closeTo(20, 1e-9));
      expect(crossCells(0, 0, 10, 10, 0), isEmpty);
    });

    test('a mask edge is rounded outwards so no sliver of the number shows', () {
      final image = RgbImage(10, 10)..data.fillRange(0, 300, 255);
      // 0.41 to 0.49 of 10 pixels is less than one whole pixel.
      burnMasks(image, const [MaskAnnotation(id: 'm', left: 0.41, top: 0.41, right: 0.49, bottom: 0.49)]);
      expect(image.data[(4 * 10 + 4) * 3], 0);
    });

    test('a JPEG keeps its size and loses what the mask covered', () {
      final white = RgbImage(40, 20)..data.fillRange(0, 2400, 255);
      final jpeg = white.encodeJpg();
      final masked = burnMasksIntoJpeg(jpeg, const [MaskAnnotation(id: 'm', left: 0, top: 0, right: 0.5, bottom: 1)]);
      final back = img.decodeJpg(masked)!;
      expect((back.width, back.height), (40, 20));
      expect(back.getPixel(2, 10).r, lessThan(40));
      expect(back.getPixel(37, 10).r, greaterThan(200));
      expect(burnMasksIntoJpeg(jpeg, const []), same(jpeg));
    });

    test('renderRecipe burns the masks in last, after the filter', () {
      final white = RgbImage(30, 30)..data.fillRange(0, 2700, 255);
      final out = renderRecipe(
        white.encodeJpg(),
        const EditRecipe(filter: DocumentFilter.blackWhite),
        masks: const [MaskAnnotation(id: 'm', left: 0, top: 0, right: 1, bottom: 0.5)],
      );
      expect(out.data[0], 0, reason: 'black and white would have left this white');
      expect(out.data[(25 * 30 + 15) * 3], greaterThan(200));
    });

    test('an edited PDF is written with the mask burned in', () async {
      final white = RgbImage(60, 30)..data.fillRange(0, 5400, 255);
      final bytes = await buildEditedPdf([
        FlattenPage(
          jpeg: white.encodeJpg(),
          widthPt: 600,
          heightPt: 300,
          annotations: const [MaskAnnotation(id: 'm', left: 0, top: 0, right: 0.5, bottom: 1)],
        ),
      ]);
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(8)), startsWith('%PDF'));
    });
  });

  group('masking in the app', () {
    late Directory tmp;
    late ProviderContainer container;
    late _FakeLayoutOcr ocr;

    Future<void> setUpContainer({AppPlan plan = AppPlan.pro, OcrLayout? layout}) async {
      tmp = Directory.systemTemp.createTempSync('lumascan_mask');
      final path = (File(
        '${tmp.path}/scan.jpg',
      )..writeAsBytesSync(img.encodeJpg(img.Image(width: 300, height: 400)))).path;
      final store = PageStore(rootDir: () async => tmp);
      ocr = _FakeLayoutOcr(layout ?? _layout([_line('2345 6789 0120')]));
      container = ProviderContainer(
        overrides: [
          appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore()),
          planProvider.overrideWithValue(plan),
          scannerServiceProvider.overrideWithValue(_OnePage(path)),
          pageStoreProvider.overrideWithValue(store),
          renderServiceProvider.overrideWithValue(_NoRender(store)),
          ocrEngineProvider.overrideWithValue(ocr),
        ],
      );
      addTearDown(() {
        container.dispose();
        tmp.deleteSync(recursive: true);
      });
      await container.read(scanControllerProvider.notifier).scan(ScanSource.camera);
    }

    List<ScanPage> pages() => container.read(scanControllerProvider).pages;

    Future<void> pumpMarkup(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildLumaTheme(Brightness.light),
            home: MarkupScreen(pageId: pages().first.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> selectTool(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('dragging with the Mask tool hides that part of the page', (tester) async {
      await tester.runAsync(setUpContainer);
      await pumpMarkup(tester);
      await selectTool(tester, 'Mask');
      expect(find.textContaining('burned into the saved file'), findsOneWidget);

      final rect = tester.getRect(find.byType(AnnotationLayer));
      final gesture = await tester.startGesture(rect.topLeft + Offset(rect.width * 0.2, rect.height * 0.3));
      await gesture.moveBy(Offset(rect.width * 0.4, rect.height * 0.08));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      final mask = pages().single.annotations.single as MaskAnnotation;
      expect(mask.left, closeTo(0.2, 0.03));
      expect(mask.right, closeTo(0.6, 0.03));
      expect(mask.label, isNull, reason: 'drawn by hand, so no label');
    });

    testWidgets('a mask too small to see is dropped', (tester) async {
      await tester.runAsync(setUpContainer);
      await pumpMarkup(tester);
      await selectTool(tester, 'Mask');
      await tester.tap(find.byType(AnnotationLayer));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(pages().single.annotations, isEmpty);
    });

    testWidgets('Auto mask on Pro masks the ID numbers it finds', (tester) async {
      await tester.runAsync(setUpContainer);
      await pumpMarkup(tester);
      await selectTool(tester, 'Mask');
      expect(find.text('Pro'), findsNothing, reason: 'Pro has it, so no badge');

      await tester.tap(find.text('Auto mask ID numbers'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Masked 1 number'), findsOneWidget);
      expect(find.textContaining('Aadhaar number'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      final masks = pages().single.annotations.cast<MaskAnnotation>();
      expect(masks.map((m) => m.crosses), [4, 4], reason: 'two groups crossed out, the last one left');
      expect(masks.first.label, 'Aadhaar number');
      expect(masks.first.top, lessThan(0.5));
    });

    testWidgets('Auto mask on Basic opens the upgrade pop-up and changes nothing', (tester) async {
      await tester.runAsync(() => setUpContainer(plan: AppPlan.basic));
      await pumpMarkup(tester);
      await selectTool(tester, 'Mask');
      expect(find.text('Pro'), findsOneWidget, reason: 'the button shows it is a Pro feature');

      await tester.tap(find.text('Auto mask ID numbers'));
      await tester.pumpAndSettle();
      expect(find.text('Upgrade to Pro'), findsWidgets);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(ocr.readPages, isEmpty);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(pages().single.annotations, isEmpty);
    });

    testWidgets('Auto mask says so when it finds nothing', (tester) async {
      await tester.runAsync(() => setUpContainer(layout: _layout([_line('Invoice total 1800')])));
      await pumpMarkup(tester);
      await selectTool(tester, 'Mask');
      await tester.tap(find.text('Auto mask ID numbers'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No ID numbers found'), findsOneWidget);
    });

    testWidgets('Auto mask reads the page with the masks already on it', (tester) async {
      await tester.runAsync(setUpContainer);
      await pumpMarkup(tester);
      await selectTool(tester, 'Mask');
      await tester.tap(find.text('Auto mask ID numbers'));
      await tester.pumpAndSettle();
      // Let the "masked 1 number" message go, so it does not cover the button.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Auto mask ID numbers'));
      await tester.pumpAndSettle();
      expect(ocr.readPages, hasLength(2));
      expect(ocr.readPages.last.annotations.whereType<MaskAnnotation>(), hasLength(2));
    });

    test('adding a mask forgets text read earlier, in case it holds the number', () async {
      await setUpContainer();
      final controller = container.read(scanControllerProvider.notifier);
      final id = pages().single.id;
      controller.setPageText(id, 'Aadhaar $_aadhaar');
      expect(pages().single.text, isNotNull);

      controller.setAnnotations(id, const [MaskAnnotation(id: 'm', left: 0, top: 0, right: 0.5, bottom: 0.1)]);
      expect(pages().single.text, isNull);

      // Removing a mask leaves the (already empty) text alone.
      controller.setPageText(id, 'read again');
      controller.setAnnotations(id, const []);
      expect(pages().single.text, 'read again');
    });
  });

  group('Mask IDs in Batch Review', () {
    final harness = ScreenHarness();
    tearDown(harness.dispose);

    Future<_FakeLayoutOcr> open(WidgetTester tester, {AppPlan plan = AppPlan.pro, OcrLayout? layout}) async {
      final ocr = _FakeLayoutOcr(
        layout ?? _layout([_line('2345 6789 0120', top: 0.3), _line('DOB: 01/01/1990', top: 0.6)]),
      );
      await tester.runAsync(
        () => harness.setUp(
          pageCount: 3,
          overrides: [planProvider.overrideWithValue(plan), ocrEngineProvider.overrideWithValue(ocr)],
        ),
      );
      await harness.pumpRoute(tester, (_) => const BatchReviewScreen());
      return ocr;
    }

    Future<void> tapMaskIds(WidgetTester tester) async {
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mask IDs'));
      await tester.pumpAndSettle();
    }

    int maskedPages() => harness.pages.where((p) => p.annotations.whereType<MaskAnnotation>().isNotEmpty).length;

    testWidgets('masks the numbers on every selected page as one undo step', (tester) async {
      final ocr = await open(tester);
      await tapMaskIds(tester);
      final read = ocr.readPages.length;
      expect(read, greaterThan(0));
      expect(maskedPages(), read);
      final first = harness.pages.firstWhere((p) => p.annotations.isNotEmpty);
      final masks = first.annotations.cast<MaskAnnotation>();
      expect(masks.map((m) => m.label).toSet(), {'Aadhaar number', 'Date of birth'});
      expect(masks.every((m) => m.crossesOut), isTrue);
      expect(find.textContaining('Masked'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(maskedPages(), 0);
    });

    testWidgets('on Basic it opens the upgrade pop-up and reads nothing', (tester) async {
      final ocr = await open(tester, plan: AppPlan.basic);
      await tapMaskIds(tester);
      expect(find.text('Upgrade to Pro'), findsWidgets);
      expect(ocr.readPages, isEmpty);
      expect(maskedPages(), 0);
    });

    testWidgets('says so when there is nothing to mask', (tester) async {
      await open(tester, layout: _layout([_line('Invoice total 1800')]));
      await tapMaskIds(tester);
      expect(find.text('No ID numbers found.'), findsOneWidget);
      expect(maskedPages(), 0);
    });
  });

  group('auto mask summary', () {
    test('counts the numbers and says which ones got a black box', () {
      final found = const IdNumberFinder().find(
        _layout([_line('2345 6789 0120', top: 0.2), _line('DOB: 0l/?1/l9B0', top: 0.5)]),
      );
      final text = autoMaskSummary(found);
      expect(text, contains('Masked 2 numbers'));
      expect(text, contains('One could not be read, so it is covered with a black box.'));
      final masks = masksFor(found, () => 'id');
      expect(masks.map((m) => m.crosses), [4, 4, 0]);
    });
  });
}

class _OnePage implements ScannerService {
  _OnePage(this.path);
  final String path;

  @override
  Future<List<String>> scan({required ScanSource source, int maxPages = 100}) async => [path];

  @override
  Future<void> cleanUp() async {}
}
