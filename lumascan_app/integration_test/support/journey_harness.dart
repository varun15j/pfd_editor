import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/app.dart';
import 'package:lumascan/app/device_load.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/app_settings.dart';
import 'package:lumascan/domain/launch_action.dart';
import 'package:lumascan/domain/photo_import.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/domain/scanner_service.dart';
import 'package:lumascan/domain/ui_prefs.dart';
import 'package:lumascan/features/batch_capture/batch_camera.dart';
import 'package:lumascan/features/batch_capture/camera_frame.dart';
import 'package:lumascan/features/capture/scan_tips.dart';
import 'package:lumascan/features/markup/markup_canvas.dart';
import 'package:lumascan/features/pages/scan_controller.dart';

import '../../test/support/memory_stores.dart';

/// Real phone photos bundled with the app (see sample_photos/README.md):
/// handwritten maths revision pages on a desk, fingers and torn edges
/// included.
const mathsPhotos = [
  'sample_photos/01_revision1_palindrome_lengths.jpg',
  'sample_photos/02_revision2_multiplication.jpg',
  'sample_photos/03_revision3_conversions_shapes.jpg',
  'sample_photos/04_revision4_lengths.jpg',
  'sample_photos/05_revision_grocery_table.jpg',
];

/// Real photos of an open printed book, used for retakes and later pages.
const bookPhotos = [
  'sample_photos/book/02_drinking_straw.jpg',
  'sample_photos/book/05_bend_a_straw.jpg',
  'sample_photos/book/14_magnifying_glass.jpg',
];

/// Copies a bundled photo into [dir] as the camera would write it.
Future<String> photoFile(String asset, Directory dir, String name) async {
  final bytes = (await rootBundle.load(asset)).buffer.asUint8List();
  final file = File('${dir.path}/$name.jpg');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// An ID card lying on a dark table, with a 12-digit number in the style of
/// an Aadhaar card. Drawn, not photographed: no real ID card belongs in the
/// repository. [side] 0 is the front, 1 the back.
List<int> idCardPhoto(int side) {
  const width = 1600, height = 1200;
  final photo = img.Image(width: width, height: height)..clear(img.ColorRgb8(58, 50, 46));
  img.fillRect(photo, x1: 200, y1: 250, x2: 1400, y2: 1010, color: img.ColorRgb8(246, 244, 236), radius: 30);
  final ink = img.ColorRgb8(20, 20, 20);
  if (side == 0) {
    img.drawString(photo, 'GOVERNMENT OF INDIA', font: img.arial48, x: 260, y: 290, color: ink);
    img.fillRect(photo, x1: 260, y1: 380, x2: 500, y2: 680, color: img.ColorRgb8(160, 150, 140));
    img.drawString(photo, 'Test Person', font: img.arial48, x: 540, y: 400, color: ink);
    img.drawString(photo, 'DOB: 12/04/1990', font: img.arial48, x: 540, y: 480, color: ink);
  } else {
    img.drawString(photo, 'Address: 12 Test Street', font: img.arial48, x: 260, y: 300, color: ink);
    img.drawString(photo, 'Bengaluru 560001', font: img.arial48, x: 260, y: 380, color: ink);
  }
  img.drawString(photo, '2345 6789 0123', font: img.arial48, x: 560, y: 860, color: ink);
  return img.encodeJpg(photo, quality: 92);
}

/// A camera whose shots are the real photos above, in turn. Set [idCard] to
/// photograph the two sides of an ID card instead.
class PhotoBatchCamera implements BatchCamera {
  PhotoBatchCamera(this.dir);

  final Directory dir;
  bool idCard = false;
  int shots = 0;
  int _idSide = 0;
  bool _ready = false;

  @override
  Future<void> open({CaptureResolution resolution = CaptureResolution.high}) async => _ready = true;

  @override
  bool get isReady => _ready;

  @override
  bool get hasTorch => false;

  @override
  Widget buildPreview({Widget? overlay}) => SizedBox.expand(
    child: Stack(fit: StackFit.expand, children: [const ColoredBox(color: Color(0xFF2E2A28)), ?overlay]),
  );

  @override
  Future<void> setResolution(CaptureResolution resolution) async {}

  @override
  Future<void> startFrames(void Function(CameraFrame frame) onFrame) async {}

  @override
  Future<void> stopFrames() async {}

  @override
  Future<String> takePicture() async {
    final n = shots++;
    if (idCard) {
      final file = File('${dir.path}/id_${n}_${_idSide % 2}.jpg');
      await file.writeAsBytes(idCardPhoto(_idSide++ % 2), flush: true);
      return file.path;
    }
    return photoFile(mathsPhotos[n % mathsPhotos.length], dir, 'shot$n');
  }

  @override
  Future<void> setTorch(bool on) async {}

  @override
  Future<void> pause() async => _ready = false;

  @override
  Future<void> resume() async => _ready = true;

  @override
  Future<void> close() async => _ready = false;
}

/// Stands in for the platform document scanner, which Retake on the Pages
/// screen opens: each call returns the next real book photo.
class PhotoScanner implements ScannerService {
  PhotoScanner(this.dir);

  final Directory dir;
  int scans = 0;

  @override
  Future<List<String>> scan({required ScanSource source, int maxPages = 100}) async {
    final n = scans++;
    return [await photoFile(bookPhotos[n % bookPhotos.length], dir, 'retake$n')];
  }

  @override
  Future<void> cleanUp() async {}
}

/// The gallery: picking returns the next real book photo.
class PhotoGallery implements PhotoPicker {
  PhotoGallery(this.dir);

  final Directory dir;
  int picks = 0;

  @override
  Future<List<PickedPhoto>> pick({bool fromFiles = false}) async {
    final n = picks++;
    final path = await photoFile(bookPhotos[(n + 1) % bookPhotos.length], dir, 'gallery$n');
    return [PickedPhoto(path: path, name: 'gallery$n.jpg')];
  }
}

/// Everything one journey needs: a private folder for pages and exports,
/// the camera, scanner and gallery above, and in-memory stores, so the real
/// Library on the device is never touched.
class Journey {
  Journey._(this.root, this.camera, this.scanner, this.gallery, this.library);

  static Future<Journey> create() async {
    final root = Directory.systemTemp.createTempSync('journey');
    final shots = Directory('${root.path}/camera')..createSync();
    return Journey._(root, PhotoBatchCamera(shots), PhotoScanner(shots), PhotoGallery(shots), MemoryLibraryStore());
  }

  final Directory root;
  final PhotoBatchCamera camera;
  final PhotoScanner scanner;
  final PhotoGallery gallery;
  final MemoryLibraryStore library;

  late final PageStore pageStore = PageStore(rootDir: () async => root);

  void dispose() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // The app may still hold a page open; the OS clears its temp folder.
    }
  }

  /// Starts the app on Gold (every feature open), past the intro.
  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pageStoreProvider.overrideWithValue(pageStore),
          libraryStoreProvider.overrideWithValue(library),
          draftStoreProvider.overrideWithValue(MemoryDraftStore()),
          uiPrefsStoreProvider.overrideWithValue(MemoryUiPrefsStore(const UiPrefs(dismissedCards: {scanTipsId}))),
          appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore(const AppSettings(onboardingSeen: true))),
          documentTextStoreProvider.overrideWithValue(MemoryDocumentTextStore()),
          launchActionSourceProvider.overrideWithValue(const NoLaunchActions()),
          planProvider.overrideWithValue(AppPlan.gold),
          batchCameraProvider.overrideWithValue(() => camera),
          scannerServiceProvider.overrideWithValue(scanner),
          photoPickerProvider.overrideWithValue(gallery),
          // The camera's "same page again?" text check runs after a shot and can
          // outlive the test; a busy phone skips it, as the app does.
          deviceLoadProbeProvider.overrideWithValue(const _BusyPhone()),
        ],
        child: const LumaScanApp(),
      ),
    );
    await settle(tester);
  }
}

/// pumpAndSettle with a ceiling: the camera screen animates for ever, so
/// this pumps frames until nothing is scheduled or [max] passes.
Future<void> settle(WidgetTester tester, {Duration max = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(max);
  do {
    await tester.pump(const Duration(milliseconds: 100));
  } while (tester.binding.hasScheduledFrame && DateTime.now().isBefore(end));
}

/// Waits, pumping frames, until [finder] finds something. Real file and
/// image work runs on the device, so fixed pumps are not enough.
Future<void> waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 60)}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      final shown = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().toSet();
      throw TestFailure('Timed out waiting for $finder. On screen: ${shown.join(' | ')}');
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Waits for [finder], taps its first match and lets the screen settle.
Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await waitFor(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await settle(tester);
}

/// The document being edited, as the app holds it.
ScanState scanState(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(LumaScanApp))).read(scanControllerProvider);

/// Draws a stroke across the middle of the markup page, or along its lower
/// part with [lower] (where an ID card's number is).
Future<void> drawOnPage(WidgetTester tester, {bool lower = false}) async {
  // The page picture loads first; the canvas comes with it.
  await waitFor(tester, find.byType(MarkupCanvas));
  await settle(tester);
  final page = tester.getRect(find.byType(MarkupCanvas));
  final start = Offset(page.left + page.width * 0.2, page.top + page.height * (lower ? 0.62 : 0.5));
  await tester.timedDragFrom(start, Offset(page.width * 0.6, page.height * 0.06), const Duration(milliseconds: 800));
  await settle(tester);
}

/// Waits, pumping frames, until [finder] finds nothing.
Future<void> waitGone(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(end)) throw TestFailure('Still showing after $timeout: $finder');
    await tester.pump(const Duration(milliseconds: 250));
  }
  await settle(tester);
}

class _BusyPhone implements DeviceLoadProbe {
  const _BusyPhone();

  @override
  Future<DeviceLoad?> sample() async => const DeviceLoad(availableMb: 1, totalMb: 4096, lowMemory: true);
}

/// Waits, pumping frames, until [done] is true.
Future<void> waitUntil(WidgetTester tester, bool Function() done, {Duration timeout = const Duration(minutes: 2)}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('Timed out after $timeout');
    await tester.pump(const Duration(milliseconds: 250));
  }
  await settle(tester);
}
