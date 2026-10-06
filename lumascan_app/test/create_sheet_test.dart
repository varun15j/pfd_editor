import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/ui_prefs.dart';
import 'package:lumascan/features/batch_capture/batch_capture_screen.dart';
import 'package:lumascan/features/capture/scan_tips.dart';

import 'support/fake_batch_camera.dart';
import 'support/fake_photos.dart';
import 'support/memory_stores.dart';
import 'support/pump_app.dart';

/// A camera in a fresh temp folder, removed after the test.
FakeBatchCamera tempCamera({bool deny = false}) {
  final shots = Directory.systemTemp.createTempSync('lumascan_shots');
  addTearDown(() => shots.deleteSync(recursive: true));
  return FakeBatchCamera(shots, deny: deny);
}

MemoryUiPrefsStore tipsSeen() => MemoryUiPrefsStore(const UiPrefs(dismissedCards: {scanTipsId}));

void main() {
  testWidgets('Create sheet offers scan, import and PDF editing', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Scan document'), findsOneWidget);
    expect(find.text('Batch scan'), findsNothing, reason: 'every camera scan is a batch scan');
    expect(find.text('Import photos'), findsOneWidget);
    expect(find.text('Edit a PDF'), findsOneWidget);
  });

  testWidgets('Scan document opens the camera that stays open between shots', (tester) async {
    final camera = tempCamera();
    await pumpApp(tester, prefs: tipsSeen(), overrides: [batchCameraProvider.overrideWithValue(() => camera)]);
    await tester.tap(find.byTooltip('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan document'));
    await tester.pumpAndSettle();
    expect(find.byType(BatchCaptureScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Take photo'), findsOneWidget);
  });

  testWidgets('Import photos from the sheet opens the photo picker', (tester) async {
    final picker = FakePhotoPicker();
    await pumpApp(tester, overrides: [photoPickerProvider.overrideWithValue(picker)]);
    await tester.tap(find.byTooltip('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import photos'));
    await tester.pumpAndSettle();
    expect(picker.picks, 1);
    expect(find.text('Scan document'), findsNothing);
  });

  testWidgets('scan tips show before the first scan only', (tester) async {
    final camera = tempCamera();
    final prefs = MemoryUiPrefsStore();
    await pumpApp(tester, prefs: prefs, overrides: [batchCameraProvider.overrideWithValue(() => camera)]);
    await tester.tap(find.bySemanticsLabel('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Tips for a clean scan'), findsOneWidget);
    expect(find.text('Use a dark background'), findsOneWidget);
    expect(camera.opens, 0);
    await tester.tap(find.text('Start scanning'));
    await tester.pumpAndSettle();
    expect(camera.opens, 1);
    expect(prefs.prefs.dismissedCards, contains(scanTipsId));

    await tester.tap(find.bySemanticsLabel('Discard all captured photos and changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Tips for a clean scan'), findsNothing);
    expect(camera.opens, 2);
  });

  testWidgets('closing the tips skips the scan and does not show them again', (tester) async {
    final camera = tempCamera();
    await pumpApp(tester, overrides: [batchCameraProvider.overrideWithValue(() => camera)]);
    await tester.tap(find.bySemanticsLabel('Scan'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(camera.opens, 0);
    await tester.tap(find.bySemanticsLabel('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Tips for a clean scan'), findsNothing);
    expect(camera.opens, 1);
  });

  testWidgets('blocked camera explains why and offers photo import instead', (tester) async {
    final picker = FakePhotoPicker();
    await pumpApp(
      tester,
      prefs: tipsSeen(),
      overrides: [
        batchCameraProvider.overrideWithValue(() => tempCamera(deny: true)),
        photoPickerProvider.overrideWithValue(picker),
      ],
    );
    await tester.tap(find.bySemanticsLabel('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Camera access needed'), findsOneWidget);
    expect(find.textContaining('stay on this device'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Import photos'));
    await tester.pumpAndSettle();
    expect(find.byType(BatchCaptureScreen), findsNothing);
    expect(picker.picks, 1);
  });

  testWidgets('Create sheet, tips and camera guide fit at 200% text', (tester) async {
    await pumpApp(
      tester,
      textScale: 2,
      overrides: [batchCameraProvider.overrideWithValue(() => tempCamera(deny: true))],
    );
    await tester.tap(find.byTooltip('Create'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Scan document'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Start scanning'));
    await tester.tap(find.text('Start scanning'));
    await tester.pumpAndSettle();
    expect(find.text('Camera access needed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the camera, its sheets and the discard question fit at 200% text', (tester) async {
    final camera = tempCamera();
    final root = Directory.systemTemp.createTempSync('lumascan_root');
    addTearDown(() => root.deleteSync(recursive: true));
    await pumpApp(
      tester,
      textScale: 2,
      prefs: tipsSeen(),
      overrides: [
        batchCameraProvider.overrideWithValue(() => camera),
        pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => root)),
        photoAnalyzerProvider.overrideWithValue(FakePhotoAnalyzer()),
      ],
    );
    await tester.tap(find.bySemanticsLabel('Scan'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.bySemanticsLabel('Take photo'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Open preview of 1 captured photo'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Camera settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel(RegExp(r'^Open preview of')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Continue scanning'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Discard all captured photos and changes'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
