import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/id_copy.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/photo_import.dart';
import 'package:lumascan/domain/scan_document.dart';
import 'package:lumascan/export/pdf_exporter.dart';
import 'package:lumascan/features/id_card/id_card_capture_screen.dart';
import 'package:lumascan/features/id_card/id_card_session.dart';
import 'package:lumascan/features/id_card/id_card_type_screen.dart';
import 'package:lumascan/features/library/library_controller.dart';
import 'package:lumascan/features/pages/scan_controller.dart';
import 'package:lumascan/imaging/id_copy_composer.dart';
import 'package:lumascan/imaging/page_renderer.dart';
import 'package:lumascan/imaging/render_service.dart';
import 'package:lumascan/pdf_edit/annotations.dart';

import 'support/fake_batch_camera.dart';
import 'support/screen_harness.dart';

class _NoCard implements PhotoAnalyzer {
  @override
  Future<CropQuad?> analyze(String path) async => null;
}

class _Composed {
  _Composed(this.paperMm, this.slots, this.imagePaths, this.watermark);

  final Size paperMm;
  final List<Rect> slots;
  final List<String> imagePaths;
  final String? watermark;
}

class _FakeExporter implements PdfExporter {
  _FakeExporter(this.dir);

  final Directory dir;
  final calls = <(List<ScanPage>, ExportOptions)>[];

  @override
  Future<File> export(
    List<ScanPage> pages,
    ExportOptions options, {
    void Function(int done, int total)? onProgress,
  }) async {
    calls.add((pages, options));
    return File('${dir.path}/${options.fileName}')..writeAsBytesSync([37, 80, 68, 70]);
  }
}

class _MaskedRender extends RenderService {
  _MaskedRender(super.store);

  final masked = <String>[];

  @override
  Future<RenderedImage> renderMasked(ScanPage page, {int maxDimension = RenderService.previewSize}) async {
    masked.add(page.id);
    return const RenderedImage('/masked.jpg', 10, 10);
  }
}

Uint8List _jpeg(int w, int h, img.Color color) => img.encodeJpg(img.Image(width: w, height: h)..clear(color));

void main() {
  group('layout', () {
    test('an ID card puts front over back at real size, centred inside the margins', () {
      final slots = idCopySlots(IdCopyType.idCard);
      expect(slots, hasLength(2));
      for (final s in slots) {
        expect(s.width * 210, closeTo(85.6, 0.01));
        expect(s.height * 297, closeTo(53.98, 0.01));
        expect(s.center.dx, closeTo(0.5, 1e-9));
        expect(s.left * 210, greaterThanOrEqualTo(15));
      }
      expect(slots[0].bottom, lessThan(slots[1].top), reason: 'front above back, not overlapping');
      expect((slots[1].top - slots[0].bottom) * 297, closeTo(15, 0.01));
      expect((slots[0].top + slots[1].bottom) / 2, closeTo(0.5, 1e-9), reason: 'the pair is centred');
    });

    test('Single Side and Passport have one slot; Passport is portrait', () {
      expect(idCopySlots(IdCopyType.singleSide), hasLength(1));
      final passport = idCopySlots(IdCopyType.passport).single;
      expect(passport.width * 210, closeTo(125, 0.01));
      expect(passport.height * 297, closeTo(176, 0.01));
    });

    test('Large is half as big again, but never leaves the margins', () {
      final large = idCopySlots(IdCopyType.idCard, scale: IdCopyScale.large);
      expect(large.first.width * 210, closeTo(128.4, 0.01));
      final passport = idCopySlots(IdCopyType.passport, paper: PdfPageSize.letter, scale: IdCopyScale.large).single;
      expect(passport.top * 279.4, greaterThanOrEqualTo(15 - 1e-9));
      expect(passport.bottom * 279.4, lessThanOrEqualTo(279.4 - 15 + 1e-9));
      expect(passport.width / passport.height * 215.9 / 279.4, closeTo(125 / 176, 1e-9), reason: 'shape kept');
    });

    test('collages fill the page in one column up to two, then two columns', () {
      expect(collageSlots(2).map((r) => r.left).toSet(), hasLength(1));
      final four = collageSlots(4);
      expect(four.map((r) => r.left).toSet(), hasLength(2));
      expect(four.map((r) => r.top).toSet(), hasLength(2));
      for (var i = 0; i < four.length; i++) {
        for (var j = i + 1; j < four.length; j++) {
          expect(four[i].overlaps(four[j]), isFalse);
        }
      }
    });

    test('the camera guide has the shape of the document and fits the preview', () {
      final card = cardGuide(const Size(400, 600), IdCopyType.idCard);
      expect(card.width * 400 / (card.height * 600), closeTo(IdCopyType.idCard.aspect, 1e-9));
      final passport = cardGuide(const Size(400, 600), IdCopyType.passport);
      expect(passport.height, lessThanOrEqualTo(0.7 + 1e-9));
      expect(passport.width * 400 / (passport.height * 600), closeTo(IdCopyType.passport.aspect, 1e-9));
    });

    test('a page found far smaller or larger than the guide is not taken for the card', () {
      const guide = CropQuad(NormPoint(0.1, 0.3), NormPoint(0.9, 0.3), NormPoint(0.9, 0.7), NormPoint(0.1, 0.7));
      const close = CropQuad(NormPoint(0.12, 0.32), NormPoint(0.88, 0.3), NormPoint(0.9, 0.68), NormPoint(0.1, 0.7));
      const tiny = CropQuad(NormPoint(0.4, 0.4), NormPoint(0.5, 0.4), NormPoint(0.5, 0.45), NormPoint(0.4, 0.45));
      expect(isCardLike(close, guide), isTrue);
      expect(isCardLike(tiny, guide), isFalse);
      expect(isCardLike(CropQuad.full, guide), isFalse);
    });
  });

  group('draft', () {
    test('sides are kept in order, retaken in place and swapped without changing pictures', () {
      var d = const IdCopyDraft(type: IdCopyType.idCard);
      expect(d.nextSide, 0);
      d = d.withSide(0, 'front');
      expect(d.complete, isFalse);
      expect(d.nextSide, 1);
      d = d.withSide(1, 'back').withSide(0, 'front2');
      expect(d.sideIds, ['front2', 'back']);
      expect(d.complete, isTrue);
      expect(d.swapped().sideIds, ['back', 'front2']);
    });

    test('a side retaken in place, or the retake undone, stays that side; a removed side stays missing', () {
      const copy = IdCopyDraft(type: IdCopyType.idCard, sideIds: ['front', 'back'], compositeId: 'copy');
      final retaken = copy.followPages(['copy', 'front', 'back'], ['copy', 'front2', 'back']);
      expect(retaken.sideIds, ['front2', 'back']);
      expect(retaken.compositeId, 'copy');
      expect(retaken.followPages(['copy', 'front2', 'back'], ['copy', 'front', 'back']), copy, reason: 'undo');
      expect(copy.followPages(['copy', 'front', 'back'], ['back', 'copy', 'front']), same(copy), reason: 'moved');
      expect(copy.followPages(['copy', 'front', 'back'], ['copy', 'back']).sideIds, ['front', 'back']);
    });

    test('the copy is kept with the document, so it is there after a restart', () {
      final info = ScanDocInfo(
        name: 'Aadhaar',
        createdAt: DateTime.utc(2026, 10, 31, 9),
        idCopy: const IdCopyDraft(
          type: IdCopyType.idCard,
          sideIds: ['front', 'back'],
          watermark: 'For bank KYC only',
          paper: PdfPageSize.letter,
          scale: IdCopyScale.large,
          compositeId: 'copy',
        ),
      );
      final back = ScanDocInfo.fromJson(jsonDecode(jsonEncode(info.toJson())) as Map<String, Object?>)!;
      expect(back.idCopy, info.idCopy);
      expect(back.copyWith(name: 'PAN').idCopy, info.idCopy, reason: 'renaming keeps it');
      expect(ScanDocInfo.fromJson({'name': 'Old scan'})!.idCopy, isNull);
    });

    test('a watermark must say something and fit across a card', () {
      expect(validateWatermark('  '), isNotNull);
      expect(validateWatermark('x' * 61), isNotNull);
      expect(validateWatermark('For bank KYC only'), isNull);
      const d = IdCopyDraft(type: IdCopyType.idCard);
      expect(d.withWatermark('  For KYC  ').watermark, 'For KYC');
      expect(d.withWatermark('For KYC').withWatermark(null).watermark, isNull);
    });
  });

  group('composed page', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('lumascan_idcopy'));
    tearDown(() => tmp.deleteSync(recursive: true));

    testWidgets('each side lands in its slot on white A4 at 200 dpi, and the watermark marks it', (tester) async {
      final front = File('${tmp.path}/front.jpg')..writeAsBytesSync(_jpeg(172, 108, img.ColorRgb8(200, 20, 20)));
      final back = File('${tmp.path}/back.jpg')..writeAsBytesSync(_jpeg(172, 108, img.ColorRgb8(20, 20, 200)));
      final slots = idCopySlots(IdCopyType.idCard);
      Future<img.Image> compose({String? watermark}) async {
        final bytes = await tester.runAsync(
          () => composePage(
            paperMm: paperSizeMm(PdfPageSize.a4),
            slots: slots,
            imagePaths: [front.path, back.path],
            watermark: watermark,
          ),
        );
        return img.decodeJpg(bytes!)!;
      }

      final page = await compose();
      expect(page.width, 1654);
      expect(page.height, 2339);
      img.Pixel at(img.Image im, Offset o) => im.getPixel((o.dx * im.width).round(), (o.dy * im.height).round());
      final f = at(page, slots[0].center), b = at(page, slots[1].center), corner = at(page, const Offset(0.05, 0.05));
      expect(f.r, greaterThan(150));
      expect(f.b, lessThan(80));
      expect(b.b, greaterThan(150));
      expect(b.r, lessThan(80));
      expect(corner.r, greaterThan(245), reason: 'paper is white');
      // The front fills its slot at real size: 85.6 mm at 200 dpi is 674 px.
      final row = (slots[0].center.dy * page.height).round();
      final red = [for (var x = 0; x < page.width; x++) page.getPixel(x, row).r > 150 && page.getPixel(x, row).b < 80];
      expect(red.where((v) => v).length, closeTo(674, 6));

      final marked = await compose(watermark: 'FOR KYC ONLY');
      var changed = 0;
      final s = slots[0];
      for (var y = (s.top * page.height).round(); y < (s.bottom * page.height).round(); y += 3) {
        for (var x = (s.left * page.width).round(); x < (s.right * page.width).round(); x += 3) {
          if ((marked.getPixel(x, y).g - page.getPixel(x, y).g).abs() > 20) changed++;
        }
      }
      expect(changed, greaterThan(200), reason: 'the watermark shows on the card');
      expect(at(marked, const Offset(0.05, 0.05)).r, greaterThan(245), reason: 'and not outside it');
    });
  });

  test('each side goes on the copy rendered with its masks burned in', () async {
    final service = _MaskedRender(PageStore(rootDir: () async => Directory.systemTemp));
    final container = ProviderContainer(overrides: [renderServiceProvider.overrideWithValue(service)]);
    addTearDown(container.dispose);
    const page = ScanPage(
      id: 'p',
      originalPath: '/x.jpg',
      annotations: [MaskAnnotation(id: 'm', left: 0.1, top: 0.4, right: 0.9, bottom: 0.6)],
    );
    expect(await container.read(sideImageMakerProvider)(page), '/masked.jpg');
    expect(service.masked, ['p']);
  });

  group('studio', () {
    final harness = ScreenHarness();
    late Directory shots;
    late FakeBatchCamera camera;
    late _FakeExporter exporter;
    late List<_Composed> composed;

    tearDown(() {
      harness.dispose();
      shots.deleteSync(recursive: true);
    });

    Future<void> open(WidgetTester tester, {bool deny = false}) async {
      shots = Directory.systemTemp.createTempSync('lumascan_id_shots');
      camera = FakeBatchCamera(shots, deny: deny);
      exporter = _FakeExporter(shots);
      composed = [];
      await tester.runAsync(
        () => harness.setUp(
          pageCount: 0,
          overrides: [
            batchCameraProvider.overrideWithValue(() => camera),
            photoAnalyzerProvider.overrideWithValue(_NoCard()),
            pdfExporterProvider.overrideWithValue(exporter),
            sideImageMakerProvider.overrideWithValue((page) async => page.originalPath),
            pageComposerProvider.overrideWithValue(({
              required paperMm,
              required slots,
              required imagePaths,
              watermark,
            }) async {
              composed.add(_Composed(paperMm, slots, imagePaths, watermark));
              return _jpeg(42, 59, img.ColorRgb8(255, 255, 255));
            }),
          ],
        ),
      );
      await harness.pumpRoute(tester, (_) => const IdCardTypeScreen());
    }

    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump();
      await harness.settle(tester);
    }

    /// Saving runs real file work, which takes a few more frames.
    Future<void> until(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 10 && finder.evaluate().isEmpty; i++) {
        await harness.settle(tester);
      }
    }

    /// Waits for [future], which runs in the test's clock, while the file
    /// work behind it runs for real.
    Future<T> finish<T>(WidgetTester tester, Future<T> future) async {
      late T value;
      var done = false;
      unawaited(
        future.then((v) {
          value = v;
          done = true;
        }),
      );
      for (var i = 0; i < 10 && !done; i++) {
        await harness.settle(tester);
      }
      expect(done, isTrue);
      return value;
    }

    testWidgets('picking a type moves the selection and keeps every control in place', (tester) async {
      await open(tester);
      expect(find.text('A4 paper example'), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const ValueKey('id-type-id_card'))), isSemantics(isSelected: true));
      final make = tester.getTopLeft(find.text('Make it now'));
      await tap(tester, find.byKey(const ValueKey('id-type-passport')));
      expect(tester.getSemantics(find.byKey(const ValueKey('id-type-passport'))), isSemantics(isSelected: true));
      expect(tester.getSemantics(find.byKey(const ValueKey('id-type-id_card'))), isSemantics(isSelected: false));
      expect(tester.getTopLeft(find.text('Make it now')), make);
    });

    testWidgets('front, then back, then the review; the watermark; then the saved grid in the Library', (tester) async {
      await open(tester);
      await tap(tester, find.text('Make it now'));
      expect(find.text('Front page'), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
      for (final label in ['Close', 'Import']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }

      await tap(tester, find.bySemanticsLabel('Take front page'));
      expect(find.text('Back page'), findsOneWidget);
      expect(find.text('2 of 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Front page taken. Retake front'), findsOneWidget);
      // No card found in the photo: it is cropped to the guide, not left whole.
      expect(harness.pages.single.recipe.crop.isFull, isFalse);

      await tap(tester, find.bySemanticsLabel('Take back page'));
      expect(harness.pages, hasLength(2));
      expect(find.text('Tap the title above to rename; tap the picture to crop or rotate'), findsOneWidget);
      final x = [
        for (final l in ['Add Watermark', 'Edit', 'Filter']) tester.getCenter(find.text(l)).dx,
      ];
      expect(x, orderedEquals([...x]..sort()));
      expect(tester.getCenter(find.bySemanticsLabel('Save the copy')).dx, greaterThan(x.last));

      await tap(tester, find.text('Add Watermark'));
      expect(find.text('Enter the content for the watermark'), findsOneWidget);
      await tap(tester, find.text('OK'));
      expect(find.text('Add a purpose or remove the watermark.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'For bank KYC only');
      await tap(tester, find.text('OK'));
      expect(find.text('Enter the content for the watermark'), findsNothing);

      await tap(tester, find.bySemanticsLabel('Save the copy'));
      expect(composed.single.watermark, 'For bank KYC only');
      expect(composed.single.slots, idCopySlots(IdCopyType.idCard));
      expect(composed.single.imagePaths, [for (final p in harness.pages.skip(1)) p.originalPath]);
      expect(harness.pages, hasLength(3), reason: 'the copy first, then both sides');

      await until(tester, find.text('Collage'));
      for (final label in ['Add', 'Collage', 'Share', 'Edit PDF', 'More']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final n in ['01', '02', '03']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(find.text('Tap to add new pages'), findsOneWidget);
      expect(exporter.calls.single.$2.fitImageDpi, composeDpi);
      final docs = harness.container.read(libraryProvider).value!.documents;
      expect(docs.single.type, ScanType.idCard);
    });

    testWidgets('a side retaken after saving goes on the copy page, and undo puts the old one back', (tester) async {
      await open(tester);
      await tap(tester, find.text('Make it now'));
      await tap(tester, find.bySemanticsLabel('Take front page'));
      await tap(tester, find.bySemanticsLabel('Take back page'));
      await tap(tester, find.bySemanticsLabel('Save the copy'));
      await until(tester, find.text('Collage'));
      final controller = harness.container.read(scanControllerProvider.notifier);
      final session = harness.container.read(idCopyDraftProvider.notifier);
      final [copy, front, back] = harness.pages;
      final undoSteps = harness.container.read(scanControllerProvider).undoStack.length;

      // Opened again from Home, the front is retaken from the pages, not from
      // the ID card screens.
      final photo = File('${shots.path}/front2.jpg')..writeAsBytesSync(_jpeg(80, 50, img.ColorRgb8(200, 30, 30)));
      final newFront = (await finish(tester, controller.addCapture(photo.path, replacing: front.id)))!;
      await finish(tester, session.remade);

      var draft = harness.container.read(idCopyDraftProvider)!;
      expect(draft.sideIds, [newFront.id, back.id], reason: 'the retaken page is still the front');
      expect(composed, hasLength(2), reason: 'the copy page was made again');
      expect(composed.last.imagePaths, [newFront.originalPath, back.originalPath]);
      expect(composed.last.watermark, composed.first.watermark);
      final pages = harness.pages;
      expect(pages, hasLength(3));
      expect(pages[0].id, isNot(copy.id), reason: 'a new copy page, first as before');
      expect(pages[0].id, draft.compositeId);
      expect([pages[1].id, pages[2].id], [newFront.id, back.id]);
      expect(
        harness.container.read(scanControllerProvider).undoStack.length,
        undoSteps + 1,
        reason: 'the retake is one undo step; making the copy again is part of it',
      );

      controller.undo();
      await finish(tester, session.remade);
      draft = harness.container.read(idCopyDraftProvider)!;
      expect(draft.sideIds, [front.id, back.id]);
      expect(composed, hasLength(3));
      expect(composed.last.imagePaths, [front.originalPath, back.originalPath]);
      expect(harness.pages.first.id, draft.compositeId);
    });

    testWidgets('a collage of two picked pages is added at the end', (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const ValueKey('id-type-single_side')));
      await tap(tester, find.text('Make it now'));
      await tap(tester, find.bySemanticsLabel('Take front page'));
      await tap(tester, find.bySemanticsLabel('Save the copy'));
      await until(tester, find.text('Collage'));
      expect(harness.pages, hasLength(2));

      await tap(tester, find.text('Collage'));
      await tap(tester, find.bySemanticsLabel('Page 01, ID copy'));
      await tap(tester, find.bySemanticsLabel('Page 02, Front page'));
      await tap(tester, find.text('Make'));
      await until(tester, find.text('Collage added as the last page.'));
      expect(composed.last.slots, collageSlots(2));
      expect(composed.last.watermark, isNull);
      expect(harness.pages, hasLength(3));
    });

    testWidgets('with the camera off, it says so and offers Import and settings', (tester) async {
      await open(tester, deny: true);
      await tap(tester, find.text('Make it now'));
      expect(find.text('Camera access is off'), findsOneWidget);
      expect(find.text('Import a photo or allow camera access.'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
      expect(find.text('Import'), findsWidgets);
    });

    testWidgets('the front can be retaken from the back camera, and the sides swapped in review', (tester) async {
      await open(tester);
      await tap(tester, find.text('Make it now'));
      await tap(tester, find.bySemanticsLabel('Take front page'));
      final first = harness.pages.single.id;
      await tap(tester, find.bySemanticsLabel('Front page taken. Retake front'));
      expect(find.text('Front page'), findsOneWidget);
      await tap(tester, find.bySemanticsLabel('Take front page'));
      expect(harness.pages.single.id, isNot(first), reason: 'the new front replaced the old one');
      expect(find.text('Back page'), findsOneWidget, reason: 'and the camera went back to the back');

      await tap(tester, find.bySemanticsLabel('Take back page'));
      final front = harness.pages[0].id, back = harness.pages[1].id;
      await tap(tester, find.bySemanticsLabel('Front page. Edit'));
      await tap(tester, find.text('Swap front and back'));
      expect(harness.container.read(idCopyDraftProvider)!.sideIds, [back, front]);
      expect([for (final p in harness.pages) p.id], [front, back], reason: 'the pages themselves are unchanged');
    });
  });
}
