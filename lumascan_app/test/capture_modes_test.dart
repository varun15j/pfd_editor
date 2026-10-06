import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/domain/app_settings.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/ocr.dart';
import 'package:lumascan/domain/qr_reader.dart';
import 'package:lumascan/features/batch_capture/auto_capture.dart';
import 'package:lumascan/features/batch_capture/batch_capture_screen.dart';
import 'package:lumascan/features/batch_capture/camera_frame.dart';
import 'package:lumascan/features/batch_capture/capture_settings_screen.dart';
import 'package:lumascan/imaging/book_split.dart';
import 'package:lumascan/imaging/rgb_image.dart';

import 'support/fake_batch_camera.dart';
import 'support/fake_photos.dart';
import 'support/memory_stores.dart';
import 'support/screen_harness.dart';

const _page = CropQuad(NormPoint(0.2, 0.15), NormPoint(0.8, 0.15), NormPoint(0.8, 0.85), NormPoint(0.2, 0.85));
const _left = CropQuad(NormPoint(0.1, 0.1), NormPoint(0.48, 0.1), NormPoint(0.48, 0.9), NormPoint(0.1, 0.9));
const _right = CropQuad(NormPoint(0.48, 0.1), NormPoint(0.9, 0.1), NormPoint(0.9, 0.9), NormPoint(0.48, 0.9));

class _FakeOcr implements OcrEngine {
  _FakeOcr({this.photoText = '', this.pageText = ''});

  final String photoText;
  final String pageText;

  @override
  Future<OcrCapability> capability(String languageCode) async =>
      const OcrCapability(readiness: OcrReadiness.ready, language: 'English');

  @override
  Future<void> prepare(String languageCode) async {}

  @override
  Future<String> recognize(ScanPage page, {required String languageCode}) async => pageText;

  @override
  Future<String> recognizeFile(String path) async => photoText;
}

class _FakeQr implements QrReader {
  _FakeQr({this.inFrames});

  final QrResult? inFrames;
  int frames = 0;

  @override
  Future<QrResult?> readFrame(CameraFrame frame) async {
    frames++;
    return inFrames;
  }

  @override
  Future<QrResult?> readFile(String path) async => null;

  @override
  Future<void> close() async {}
}

CameraFrame _frame() => CameraFrame.gray(4, 4, Uint8List(16));

void main() {
  group('AutoCaptureTracker', () {
    test('asks for a photo once the page holds still, then waits for the next page', () {
      final tracker = AutoCaptureTracker(stableFrames: 3);
      expect(tracker.state, AutoCaptureState.searching);
      expect([for (var i = 0; i < 3; i++) tracker.add(_page)], [false, false, true]);
      expect(tracker.state, AutoCaptureState.capture);

      tracker.captured();
      expect(tracker.state, AutoCaptureState.waitingForNext);
      for (var i = 0; i < 5; i++) {
        expect(tracker.add(_page), isFalse, reason: 'same page again');
      }

      // The page is turned: a clearly different outline arms it again.
      const next = CropQuad(NormPoint(0.05, 0.3), NormPoint(0.6, 0.25), NormPoint(0.65, 0.95), NormPoint(0.1, 0.95));
      expect(tracker.add(next), isFalse);
      expect(tracker.state, AutoCaptureState.steadying);
      expect([tracker.add(next), tracker.add(next)], [false, true]);
    });

    test('movement restarts the count, and losing the page re-arms it', () {
      final tracker = AutoCaptureTracker(stableFrames: 3);
      tracker.add(_page);
      tracker.add(_page);
      const moved = CropQuad(NormPoint(0.3, 0.15), NormPoint(0.9, 0.15), NormPoint(0.9, 0.85), NormPoint(0.3, 0.85));
      expect(tracker.add(moved), isFalse);
      expect(tracker.progress, closeTo(1 / 3, 1e-9));

      tracker.captured();
      tracker.add(null);
      expect(tracker.state, AutoCaptureState.searching);
    });
  });

  group('frames', () {
    test('a rotated frame comes out upright', () {
      // 40 x 20 frame, bright in the top-right corner; turned 90° clockwise
      // that corner is at the bottom right of a 20 x 40 image.
      final luma = Uint8List(40 * 20);
      for (var y = 0; y < 4; y++) {
        for (var x = 36; x < 40; x++) {
          luma[y * 40 + x] = 255;
        }
      }
      final frame = CameraFrame(width: 40, height: 20, bytesPerRow: 40, bytes: luma, rotation: 90);
      final gray = frame.uprightGray(size: 40);
      expect((gray.width, gray.height), (20, 40));
      expect(gray.data[((gray.height - 1) * gray.width + gray.width - 1) * 3], 255);
      expect(gray.data[0], 0);
    });

    test('the page outline is found in a frame', () {
      const w = 160, h = 120;
      final luma = Uint8List(w * h)..fillRange(0, w * h, 40);
      for (var y = 20; y < 100; y++) {
        for (var x = 40; x < 120; x++) {
          luma[y * w + x] = 230;
        }
      }
      final analysis = analyzeFrame(CameraFrame.gray(w, h, luma));
      expect(analysis.quad, isNotNull);
      expect(analysis.quad!.tl.x, closeTo(0.25, 0.05));
      expect(analysis.quad!.br.y, closeTo(0.83, 0.05));
      expect(analysis.tooDark, isFalse);
    });

    test('a book spread is split at the gutter shadow', () {
      final photo = RgbImage(200, 140);
      for (var y = 0; y < 140; y++) {
        for (var x = 0; x < 200; x++) {
          final gutter = (x - 110).abs() < 4;
          final v = gutter ? 120 : 235;
          final i = (y * 200 + x) * 3;
          photo.data[i] = v;
          photo.data[i + 1] = v;
          photo.data[i + 2] = v;
        }
      }
      final (left, right) = splitSpread(photo);
      expect(left.tr.x, closeTo(0.55, 0.03));
      expect(right.tl.x, closeTo(0.55, 0.03));
      expect(left.tl.x, lessThan(0.05));
      expect(right.tr.x, greaterThan(0.95));
    });

    test('only http and https links are offered to open', () {
      expect(const QrResult(raw: 'https://example.com/a', kind: QrKind.link).webLink, isNotNull);
      expect(const QrResult(raw: 'javascript:alert(1)', kind: QrKind.link).webLink, isNull);
      expect(const QrResult(raw: 'https://example.com', kind: QrKind.text).webLink, isNull);
    });

    test('capture settings are kept with the other settings', () {
      const settings = AppSettings(
        captureResolution: CaptureResolution.maximum,
        shutterSound: true,
        captureHaptics: false,
        autoCaptureSteadiness: AutoCaptureSteadiness.careful,
      );
      expect(AppSettings.fromJson(settings.toJson()), settings);
      expect(AppSettings.fromJson(const {}).captureResolution, CaptureResolution.high);
    });
  });

  group('Camera modes', () {
    final harness = ScreenHarness();
    late Directory shots;
    late FakeBatchCamera camera;

    tearDown(() {
      harness.dispose();
      shots.deleteSync(recursive: true);
    });

    Future<void> open(WidgetTester tester, {List overrides = const []}) async {
      shots = Directory.systemTemp.createTempSync('lumascan_shots');
      camera = FakeBatchCamera(shots);
      await tester.runAsync(
        () => harness.setUp(
          pageCount: 0,
          overrides: [
            batchCameraProvider.overrideWithValue(() => camera),
            photoAnalyzerProvider.overrideWithValue(FakePhotoAnalyzer()),
            frameAnalyzerProvider.overrideWithValue((frame) async => const FrameAnalysis(quad: _page)),
            spreadSplitterProvider.overrideWithValue((path) async => (_left, _right)),
            appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore()),
            ...overrides,
          ],
        ),
      );
      await harness.pumpRoute(tester, (_) => const BatchCaptureScreen());
    }

    Future<void> mode(WidgetTester tester, String name) async {
      await tester.ensureVisible(find.bySemanticsLabel('$name capture mode'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('$name capture mode'));
      await harness.settle(tester);
    }

    Future<void> shoot(WidgetTester tester, String label) async {
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pump();
      await harness.settle(tester);
    }

    /// Frames reach the camera screen at most every 150 ms (250 ms in QR
    /// mode), so each is sent after a real pause.
    Future<void> frames(WidgetTester tester, int count) async {
      for (var i = 0; i < count; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 270)));
        camera.sendFrame(_frame());
        await tester.pump();
        await tester.pump();
      }
      await harness.settle(tester);
    }

    testWidgets('the six modes are offered, with Docs first and selected', (tester) async {
      await open(tester);
      for (final m in ['Docs', 'Book', 'Text', 'OCR Doc', 'QR', 'Photo']) {
        expect(find.bySemanticsLabel('$m capture mode'), findsOneWidget, reason: m);
      }
      expect(tester.getSemantics(find.bySemanticsLabel('Docs capture mode')), isSemantics(isSelected: true));
    });

    testWidgets('auto capture takes the page once it holds still, and only once', (tester) async {
      await open(tester);
      expect(find.text('Searching for a page'), findsOneWidget);

      await frames(tester, 6);
      expect(camera.shots, 1);
      expect(harness.pages, hasLength(1));

      await frames(tester, 6);
      expect(camera.shots, 1, reason: 'the same page is not taken twice');
      expect(find.text('Turn to the next page'), findsOneWidget);
    });

    testWidgets('with Auto off the page outline shows but nothing is taken', (tester) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('Auto On'));
      await tester.pump();
      await frames(tester, 6);
      expect(camera.shots, 0);
      expect(find.text('Tap the shutter for each page'), findsOneWidget);
    });

    testWidgets('Book makes a left and a right page from one photo', (tester) async {
      await open(tester);
      await mode(tester, 'Book');
      expect(find.text('LEFT PAGE'), findsOneWidget);
      await shoot(tester, 'Capture left and right book pages');

      expect(harness.pages, hasLength(2));
      expect(harness.pages[0].originalPath, harness.pages[1].originalPath, reason: 'one spread photo kept');
      expect(harness.pages[0].recipe.crop, _left);
      expect(harness.pages[1].recipe.crop, _right);
    });

    testWidgets('Photo keeps the plain photo', (tester) async {
      await open(tester);
      await mode(tester, 'Photo');
      await shoot(tester, 'Take a plain photo');
      expect(harness.pages.single.recipe.crop.isFull, isTrue);
      expect(harness.pages.single.recipe.filter, DocumentFilter.original);
    });

    testWidgets('Text reads the photo, offers to copy, and adds no page unless asked', (tester) async {
      await open(
        tester,
        overrides: [ocrEngineProvider.overrideWithValue(_FakeOcr(photoText: 'Hello there\nhttps://example.com'))],
      );
      await mode(tester, 'Text');
      await shoot(tester, 'Capture recognized text');

      expect(find.text('Recognized text'), findsOneWidget);
      expect(find.text('Hello there'), findsOneWidget);
      expect(find.byTooltip('Open link'), findsOneWidget);
      expect(find.text('Copy all text'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await harness.settle(tester);
      expect(harness.pages, isEmpty);

      await shoot(tester, 'Capture recognized text');
      await tester.tap(find.text('Add photo as a page'));
      await harness.settle(tester);
      expect(harness.pages, hasLength(1));
    });

    testWidgets('OCR Doc keeps the text read from each page to copy', (tester) async {
      await open(tester, overrides: [ocrEngineProvider.overrideWithValue(_FakeOcr(pageText: 'Invoice 42'))]);
      await mode(tester, 'OCR Doc');
      expect(find.text('OCR · IMAGE + SEARCHABLE TEXT'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Auto On'));
      await shoot(tester, 'Capture page for text recognition');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await harness.settle(tester);

      expect(harness.pages.single.text, 'Invoice 42');
      await tester.tap(find.bySemanticsLabel('Open preview of 1 captured photo'));
      await harness.settle(tester);
      expect(find.text('Copy text of 1 page'), findsOneWidget);
    });

    testWidgets('QR shows what a code holds after two agreeing reads, and opens nothing by itself', (tester) async {
      final reader = _FakeQr(
        inFrames: const QrResult(raw: 'https://example.com/menu', kind: QrKind.link),
      );
      await open(tester, overrides: [qrReaderProvider.overrideWithValue(reader)]);
      await mode(tester, 'QR');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 260)));
      camera.sendFrame(_frame());
      await tester.pump();
      await tester.pump();
      expect(reader.frames, 1);
      expect(find.text('QR code · Web link'), findsNothing, reason: 'one read is not enough');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 260)));
      camera.sendFrame(_frame());
      await tester.pump();
      await tester.pump();
      await harness.settle(tester);
      expect(reader.frames, 2);
      expect(find.text('QR code · Web link'), findsOneWidget);
      expect(find.text('https://example.com/menu'), findsOneWidget);
      await tester.tap(find.text('Open link'));
      await harness.settle(tester);
      expect(find.text('Open link?'), findsOneWidget, reason: 'asks before opening');
      await tester.tap(find.text('Cancel'));
      await harness.settle(tester);
      expect(harness.pages, isEmpty);
    });

    testWidgets('QR shutter reads the photo, and says when no code is found', (tester) async {
      await open(tester, overrides: [qrReaderProvider.overrideWithValue(_FakeQr())]);
      await mode(tester, 'QR');
      await shoot(tester, 'Scan QR code');
      expect(find.textContaining('No QR code found'), findsOneWidget);
      expect(harness.pages, isEmpty);
    });

    testWidgets('More capture settings changes the photo size the camera takes', (tester) async {
      await open(tester);
      expect(camera.resolution, CaptureResolution.high);
      await tester.tap(find.byTooltip('Camera settings'));
      await harness.settle(tester);
      await tester.tap(find.text('More capture settings'));
      await harness.settle(tester);
      expect(find.byType(CaptureSettingsScreen), findsOneWidget);

      await tester.tap(find.text('Maximum'));
      await tester.tap(find.text('Careful'));
      await tester.tap(find.text('Shutter sound'));
      await harness.settle(tester);
      final settings = harness.container.read(appSettingsProvider);
      expect(settings.captureResolution, CaptureResolution.maximum);
      expect(settings.autoCaptureSteadiness, AutoCaptureSteadiness.careful);
      expect(settings.shutterSound, isTrue);

      await tester.pageBack();
      await harness.settle(tester);
      expect(camera.resolution, CaptureResolution.maximum);
      expect(find.byType(BatchCaptureScreen), findsOneWidget);
    });
  });
}
