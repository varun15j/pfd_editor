// End-to-end journeys a real user takes, run on a device or emulator:
//
//   flutter test integration_test/user_journeys_test.dart -d emulator-5554
//
// The camera, the platform document scanner and the gallery are replaced by
// real phone photos bundled with the app (support/journey_harness.dart);
// everything else (rendering, auto crop, filters, markup, PDF export, ID
// copies) is the real app on the device. The written cases are in
// docs/test-cases-user-journeys.md.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/pdf_edit/annotations.dart';

import 'support/journey_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Journey journey;
  setUp(() async => journey = await Journey.create());
  tearDown(() => journey.dispose());

  /// Shoots [count] photos on the open camera and waits for each to land.
  Future<void> shoot(WidgetTester tester, int count) async {
    final shutter = find.bySemanticsLabel(RegExp(r'^Take (the new )?photo$'));
    final before = journey.camera.shots;
    for (var i = 0; i < count; i++) {
      await tapOn(tester, shutter);
    }
    final total = journey.camera.shots;
    expect(total - before, count);
    await waitFor(tester, find.bySemanticsLabel(RegExp(r'^Open preview of \d+ captured photos?$')));
  }

  /// From the camera: Captured photos > Review all > Done > Review document.
  Future<void> reviewDocument(WidgetTester tester) async {
    await tapOn(tester, find.bySemanticsLabel(RegExp(r'^Open preview of \d+ captured photos?$')));
    await tapOn(tester, find.textContaining(RegExp(r'^Review all \d+ pages?$')));
    // A camera opened from Add pages goes back to the document from here;
    // a new scan shows Batch Review first, then Done > Review document.
    final pages = find.text('Export').hitTestable(), review = find.text('Done').hitTestable();
    for (var i = 0; i < 240 && pages.evaluate().isEmpty && review.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    if (pages.evaluate().isEmpty) {
      await tapOn(tester, find.text('Done'));
      await tapOn(tester, find.text('Review document'));
    }
    await waitFor(tester, find.text('Export'));
  }

  /// Export > Export as PDF > Save PDF, and returns the saved file.
  Future<File> exportPdf(WidgetTester tester) async {
    await tapOn(tester, find.text('Export'));
    await tapOn(tester, find.text('Export as PDF'));
    await tapOn(tester, find.text('Save PDF'));
    await waitFor(tester, find.text('PDF saved'), timeout: const Duration(minutes: 8));
    await tapOn(tester, find.text('Done'));
    // The Library entry is written just after the sheet says saved.
    await waitUntil(tester, () => journey.library.index.documents.isNotEmpty);
    final docs = [...journey.library.index.documents]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return File(docs.first.pdfPath);
  }

  /// The page in view on the Pages screen, as the controller holds it.
  ScanPage page(WidgetTester tester, int index) => scanState(tester).pages[index];

  Future<void> applyFilter(WidgetTester tester, String filter) async {
    await tapOn(tester, find.text('Filters'));
    await tapOn(tester, find.bySemanticsLabel('$filter filter'));
    await tapOn(tester, find.text('Apply'));
    final scope = find.text('Apply to this page');
    if (scope.evaluate().isNotEmpty) await tapOn(tester, scope);
    await waitFor(tester, find.text('Export'));
    // The confirmation offers Undo and Keep; Keep closes it.
    final keep = find.text('Keep');
    if (keep.evaluate().isNotEmpty) await tapOn(tester, keep);
  }

  testWidgets('J1: photograph pages, edit, retake, edit again, export; then add a photo and export again', (
    tester,
  ) async {
    await journey.launch(tester);

    // 1. Scan three pages with the camera.
    await tapOn(tester, find.byTooltip('Scan'));
    await shoot(tester, 3);
    await reviewDocument(tester);
    expect(scanState(tester).pages, hasLength(3));
    final firstName = scanState(tester).info?.name;

    // 2. Crop page 1 by dragging a corner in.
    final cropBefore = page(tester, 0).recipe.crop;
    await tapOn(tester, find.text('Crop'));
    await waitFor(tester, find.bySemanticsLabel('Top left corner'));
    await tester.drag(find.bySemanticsLabel('Top left corner'), const Offset(40, 50));
    await settle(tester);
    await tapOn(tester, find.text('Apply crop'));
    await waitFor(tester, find.text('Export'));
    expect(page(tester, 0).recipe.crop, isNot(cropBefore), reason: 'the crop was changed');

    // 3. Filter page 1 to black and white.
    await applyFilter(tester, 'B&W');
    expect(page(tester, 0).recipe.filter, DocumentFilter.blackWhite);

    // 4. Mark up page 1 with the pen.
    await tapOn(tester, find.text('Markup'));
    await waitFor(tester, find.text('Done'));
    await drawOnPage(tester);
    await tapOn(tester, find.text('Done'));
    await waitFor(tester, find.text('Export'));
    expect(page(tester, 0).annotations, isNotEmpty, reason: 'the pen stroke was kept');

    // 5. Retake page 2, then edit the new page.
    // Page 2 from the strip of thumbnails under the page.
    await tapOn(tester, find.text('2'));
    final oldSecond = page(tester, 1).id;
    await tapOn(tester, find.text('Retake'));
    // Retake opens the camera for one new photo (since #91), then comes back.
    await waitFor(tester, find.text('Retaking page 2. Take the new photo.'));
    await tapOn(tester, find.bySemanticsLabel(RegExp(r'^Take (the new )?photo$')));
    await waitFor(tester, find.text('Page 2 retaken'), timeout: const Duration(minutes: 2));
    // Its Undo bar sits over the page tools until it times out.
    await waitGone(tester, find.text('Page 2 retaken'));
    expect(page(tester, 1).id, isNot(oldSecond), reason: 'page 2 was replaced in place');
    expect(scanState(tester).pages, hasLength(3));
    await applyFilter(tester, 'Grayscale');
    expect(page(tester, 1).recipe.filter, DocumentFilter.grayscale);

    // 6. Save and export.
    final first = await exportPdf(tester);
    expect(first.existsSync(), isTrue);
    expect(journey.library.index.documents.single.pageCount, 3);

    // 7. Take one more photo into the same document, and export again.
    await tapOn(tester, find.text('Add pages'));
    await tapOn(tester, find.text('Scan with camera'));
    await shoot(tester, 1);
    await reviewDocument(tester);
    expect(scanState(tester).pages, hasLength(4));
    expect(scanState(tester).info?.name, firstName, reason: 'still the same document');

    // 8. And a photo from the gallery, then export the updated document.
    await tapOn(tester, find.text('Add pages'));
    await tapOn(tester, find.text('Import photos'));
    await tapOn(tester, find.textContaining(RegExp(r'^Add \d+ pages?$')));
    // The photo is cropped and added in the background ("Adding 1 page").
    await waitUntil(tester, () => scanState(tester).pages.length == 5 && !scanState(tester).busy);
    expect(scanState(tester).pages, hasLength(5));
    final second = await exportPdf(tester);
    expect(second.existsSync(), isTrue);
    // Saving never overwrites an earlier PDF: the update is a new PDF next
    // to the first one.
    final saved = journey.library.index.documents;
    expect(saved, hasLength(2));
    expect(saved.map((d) => d.pageCount), unorderedEquals([3, 5]));
  });

  testWidgets('J2: ID card front and back, hide the number, save and export; J3: then a new scan', (tester) async {
    await journey.launch(tester);

    // 1. Tools > ID Card > Make it now; photograph both sides.
    journey.camera.idCard = true;
    await tapOn(tester, find.text('Tools'));
    await tapOn(tester, find.text('ID Card'));
    await tapOn(tester, find.text('Make it now'));
    await tapOn(tester, find.bySemanticsLabel('Take front page'));
    await tapOn(tester, find.bySemanticsLabel('Take back page'));
    await waitFor(tester, find.bySemanticsLabel('Save the copy'));
    expect(scanState(tester).pages, hasLength(2));

    // 2. Hide the ID number on the front with the Mask tool.
    await tapOn(tester, find.bySemanticsLabel('Front page. Edit'));
    await tapOn(tester, find.text('Hide a number'));
    await waitFor(tester, find.text('Done'));
    // The number runs along the lower part of the card.
    await drawOnPage(tester, lower: true);
    await tapOn(tester, find.text('Done'));
    final front = scanState(tester).pages.first;
    expect(front.annotations.whereType<MaskAnnotation>(), isNotEmpty, reason: 'the number is masked');

    // 3. Save the copy, then export it as a PDF.
    await tapOn(tester, find.bySemanticsLabel('Save the copy'));
    await waitFor(tester, find.text('Collage'), timeout: const Duration(minutes: 5));
    expect(scanState(tester).pages, hasLength(3), reason: 'the copy, then both sides');
    final idDoc = journey.library.index.documents.single;
    expect(idDoc.type, ScanType.idCard);
    expect(File(idDoc.pdfPath).existsSync(), isTrue);
    expect(idDoc.pageCount, 3);

    // 4. J3: back to Home and scan a new document.
    journey.camera.idCard = false;
    await tapOn(tester, find.text('More'));
    await tapOn(tester, find.text('Done'));
    await waitFor(tester, find.byTooltip('Scan'));
    await tapOn(tester, find.byTooltip('Scan'));
    await shoot(tester, 2);
    await reviewDocument(tester);
    expect(scanState(tester).pages, hasLength(2), reason: 'a new document, not the ID card');
    await exportPdf(tester);
    final docs = journey.library.index.documents;
    expect(docs, hasLength(2));
    expect(docs.where((d) => d.type == ScanType.idCard), hasLength(1), reason: 'the ID copy is still there');
  });
}
