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

/// A page signature with bright cells at [spot] on an even page, so
/// different spots are clearly different pages.
Float32List _signature(int spot) {
  final s = Float32List(signatureColumns * signatureRows)..fillRange(0, signatureColumns * signatureRows, -0.1);
  for (var i = 0; i < 8; i++) {
    s[(spot * 11 + i) % s.length] = 4;
  }
  return s;
}

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

      // A new sheet is put down elsewhere: the outline jumps and stays.
      const next = CropQuad(NormPoint(0.05, 0.3), NormPoint(0.6, 0.25), NormPoint(0.65, 0.95), NormPoint(0.1, 0.95));
      expect([tracker.add(next), tracker.add(next)], [false, false]);
      expect(tracker.state, AutoCaptureState.steadying);
      expect(tracker.add(next), isTrue);
    });

    test('the outline flickering out does not take the same page again', () {
      final tracker = AutoCaptureTracker(stableFrames: 3);
      final page = _signature(1);
      for (var i = 0; i < 3; i++) {
        tracker.add(_page, page);
      }
      tracker.captured();
      for (var round = 0; round < 4; round++) {
        expect(tracker.add(null), isFalse, reason: 'one lost or dark frame');
        for (var i = 0; i < 5; i++) {
          expect(tracker.add(_page, page), isFalse, reason: 'same page, round $round');
        }
      }
      expect(tracker.state, AutoCaptureState.waitingForNext);
      expect(tracker.progress, 0);
    });

    test('a page turned under a still outline is taken once it settles', () {
      final tracker = AutoCaptureTracker(stableFrames: 3);
      final first = _signature(1), turning = _signature(2), second = _signature(3);
      for (var i = 0; i < 3; i++) {
        tracker.add(_page, first);
      }
      tracker.captured();

      // The page sweeps over the view; the book's outline stays put.
      expect([tracker.add(_page, turning), tracker.add(_page, second)], [false, false]);
      expect(tracker.state, AutoCaptureState.steadying);
      expect([tracker.add(_page, second), tracker.add(_page, second)], [false, true]);
    });

    test('with the whole view unchanged, a jumping outline never takes the page again', () {
      final tracker = AutoCaptureTracker(stableFrames: 3);
      final view = _signature(5);
      const other = CropQuad(NormPoint(0.05, 0.3), NormPoint(0.6, 0.25), NormPoint(0.65, 0.95), NormPoint(0.1, 0.95));
      for (var i = 0; i < 3; i++) {
        tracker.add(_page, _signature(1), view);
      }
      tracker.captured();
      // The detector flips between two guesses, or loses the page, while
      // nothing in front of the camera moves.
      for (var i = 0; i < 30; i++) {
        final quad = [_page, other, other, null][i % 4];
        expect(tracker.add(quad, quad == null ? null : _signature(1), view), isFalse, reason: 'frame $i');
      }
      expect(tracker.state, AutoCaptureState.waitingForNext);

      // A page is turned: the view changes, then settles on the next page.
      expect(tracker.add(_page, _signature(2), _signature(6)), isFalse);
      expect([for (var i = 0; i < 3; i++) tracker.add(_page, _signature(3), _signature(7))], [false, false, true]);
    });

    test('a page taken away and put back counts as a new page', () {
      final tracker = AutoCaptureTracker(stableFrames: 3);
      for (var i = 0; i < 3; i++) {
        tracker.add(_page);
      }
      tracker.captured();
      tracker.add(null);
      tracker.add(null);
      expect(tracker.state, AutoCaptureState.searching);
      expect([for (var i = 0; i < 3; i++) tracker.add(_page)], [false, false, true]);
    });

    test('movement restarts the count', () {
      final tracker = AutoCaptureTracker(stableFrames: 3);
      tracker.add(_page);
      tracker.add(_page);
      const moved = CropQuad(NormPoint(0.3, 0.15), NormPoint(0.9, 0.15), NormPoint(0.9, 0.85), NormPoint(0.3, 0.85));
      expect(tracker.add(moved), isFalse);
      expect(tracker.progress, closeTo(1 / 3, 1e-9));
    });

    test('a page caught mid-turn is not steady', () {
      final tracker = AutoCaptureTracker(stableFrames: 3);
      tracker.add(_page, _signature(1));
      tracker.add(_page, _signature(1));
      expect(tracker.add(_page, _signature(2)), isFalse);
      expect(tracker.progress, closeTo(1 / 3, 1e-9));
    });
  });

  group('page signature', () {
    // A grey desk with a white page on it; the page carries a dark block
    // whose place makes the content.
    RgbImage photo({double dx = 0, double gain = 1, (double, double)? block = (0.2, 0.2)}) {
      final image = RgbImage(150, 200);
      for (var y = 0; y < 200; y++) {
        for (var x = 0; x < 150; x++) {
          final u = (x / 150 - 0.2 - dx) / 0.6, v = (y / 200 - 0.15) / 0.7;
          var value = 70.0;
          if (u >= 0 && u <= 1 && v >= 0 && v <= 1) {
            value = 230;
            if (block != null && (u - block.$1).abs() < 0.15 && (v - block.$2).abs() < 0.15) value = 40;
          }
          final g = (value * gain).round().clamp(0, 255);
          final o = (y * 150 + x) * 3;
          image.data
            ..[o] = g
            ..[o + 1] = g
            ..[o + 2] = g;
        }
      }
      return image;
    }

    CropQuad shifted(double dx) => CropQuad(
      NormPoint(_page.tl.x + dx, _page.tl.y),
      NormPoint(_page.tr.x + dx, _page.tr.y),
      NormPoint(_page.br.x + dx, _page.br.y),
      NormPoint(_page.bl.x + dx, _page.bl.y),
    );

    test('stays the same when the camera moves or the exposure changes', () {
      final still = pageSignature(photo(), _page);
      final moved = pageSignature(photo(dx: 0.05, gain: 0.8), shifted(0.05));
      expect(signatureDiff(still, moved), lessThan(0.3));
    });

    test('changes when different content is on the page', () {
      final first = pageSignature(photo(), _page);
      final other = pageSignature(photo(block: (0.75, 0.7)), _page);
      expect(signatureDiff(first, other), greaterThan(0.7));
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

    Future<void> open(WidgetTester tester, {List overrides = const [], FrameAnalyzer? analyzer}) async {
      shots = Directory.systemTemp.createTempSync('lumascan_shots');
      camera = FakeBatchCamera(shots);
      await tester.runAsync(
        () => harness.setUp(
          pageCount: 0,
          overrides: [
            batchCameraProvider.overrideWithValue(() => camera),
            photoAnalyzerProvider.overrideWithValue(FakePhotoAnalyzer()),
            frameAnalyzerProvider.overrideWithValue(analyzer ?? (frame) async => const FrameAnalysis(quad: _page)),
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

    testWidgets('a flickering outline does not retake the page; a turned page is taken', (tester) async {
      // What the preview shows, frame by frame.
      final seen = [
        for (var i = 0; i < 6; i++) FrameAnalysis(quad: _page, signature: _signature(1)),
        const FrameAnalysis(),
        for (var i = 0; i < 6; i++) FrameAnalysis(quad: _page, signature: _signature(1)),
        const FrameAnalysis(quad: _page, brightness: 10),
        for (var i = 0; i < 6; i++) FrameAnalysis(quad: _page, signature: _signature(1)),
        FrameAnalysis(quad: _page, signature: _signature(2)),
        for (var i = 0; i < 7; i++) FrameAnalysis(quad: _page, signature: _signature(3)),
      ];
      var next = 0;
      await open(tester, analyzer: (frame) async => seen[next < seen.length ? next++ : seen.length - 1]);

      await frames(tester, 20);
      expect(camera.shots, 1, reason: 'one lost frame and one dark frame are still the same page');
      expect(find.text('Turn to the next page'), findsOneWidget);

      await frames(tester, 8);
      expect(camera.shots, 2, reason: 'the turned page settles and is taken');
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

    testWidgets('Book held over one page makes just that page', (tester) async {
      // The left page alone: the right one is cut off, so the outline was
      // trimmed to the left page and does not reach across the middle.
      const onePage = CropQuad(NormPoint(0.05, 0.1), NormPoint(0.55, 0.1), NormPoint(0.55, 0.9), NormPoint(0.05, 0.9));
      await open(tester, analyzer: (frame) async => const FrameAnalysis(quad: onePage));
      await tester.tap(find.bySemanticsLabel('Auto On'));
      await tester.pump();
      await mode(tester, 'Book');
      await frames(tester, 2);
      expect(find.text('LEFT PAGE'), findsNothing);

      await shoot(tester, 'Capture left and right book pages');
      expect(harness.pages, hasLength(1));
      expect(find.text('Page 1 captured'), findsOneWidget);
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
