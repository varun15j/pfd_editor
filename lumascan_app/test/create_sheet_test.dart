import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/domain/scanner_service.dart';
import 'package:lumascan/domain/ui_prefs.dart';
import 'package:lumascan/features/batch_capture/batch_capture_screen.dart';
import 'package:lumascan/features/capture/scan_tips.dart';

import 'support/fake_batch_camera.dart';
import 'support/fake_photos.dart';
import 'support/memory_stores.dart';
import 'support/pump_app.dart';

/// Records each scan request; returns no pages (as if cancelled), or throws
/// a permission error for the camera when [blocked].
class _Scanner implements ScannerService {
  _Scanner({this.blocked = false});

  final bool blocked;
  final sources = <ScanSource>[];

  @override
  Future<List<String>> scan({required ScanSource source, int maxPages = 100}) async {
    sources.add(source);
    if (blocked && source == ScanSource.camera) throw const ScannerPermissionDenied(permanently: true);
    return const [];
  }

  @override
  Future<void> cleanUp() async {}
}

MemoryUiPrefsStore tipsSeen() => MemoryUiPrefsStore(const UiPrefs(dismissedCards: {scanTipsId}));

void main() {
  testWidgets('Create sheet offers scan, import and PDF editing', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Scan document'), findsOneWidget);
    expect(find.text('Batch scan'), findsOneWidget);
    expect(find.text('Import photos'), findsOneWidget);
    expect(find.text('Edit a PDF'), findsOneWidget);
  });

  testWidgets('Batch scan from the sheet opens the batch camera', (tester) async {
    final shots = Directory.systemTemp.createTempSync('lumascan_shots');
    addTearDown(() => shots.deleteSync(recursive: true));
    await pumpApp(tester, overrides: [batchCameraProvider.overrideWithValue(() => FakeBatchCamera(shots))]);
    await tester.tap(find.byTooltip('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batch scan'));
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
    final scanner = _Scanner();
    final prefs = MemoryUiPrefsStore();
    await pumpApp(tester, prefs: prefs, overrides: [scannerServiceProvider.overrideWithValue(scanner)]);
    await tester.tap(find.bySemanticsLabel('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Tips for a clean scan'), findsOneWidget);
    expect(find.text('Use a dark background'), findsOneWidget);
    expect(scanner.sources, isEmpty);
    await tester.tap(find.text('Start scanning'));
    await tester.pumpAndSettle();
    expect(scanner.sources, [ScanSource.camera]);
    expect(prefs.prefs.dismissedCards, contains(scanTipsId));

    await tester.tap(find.bySemanticsLabel('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Tips for a clean scan'), findsNothing);
    expect(scanner.sources, [ScanSource.camera, ScanSource.camera]);
  });

  testWidgets('closing the tips skips the scan and does not show them again', (tester) async {
    final scanner = _Scanner();
    await pumpApp(tester, overrides: [scannerServiceProvider.overrideWithValue(scanner)]);
    await tester.tap(find.bySemanticsLabel('Scan'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(scanner.sources, isEmpty);
    await tester.tap(find.bySemanticsLabel('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Tips for a clean scan'), findsNothing);
    expect(scanner.sources, [ScanSource.camera]);
  });

  testWidgets('blocked camera explains why and offers photo import instead', (tester) async {
    final scanner = _Scanner(blocked: true);
    final picker = FakePhotoPicker();
    await pumpApp(
      tester,
      prefs: tipsSeen(),
      overrides: [scannerServiceProvider.overrideWithValue(scanner), photoPickerProvider.overrideWithValue(picker)],
    );
    await tester.tap(find.bySemanticsLabel('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Camera access needed'), findsOneWidget);
    expect(find.textContaining('stay on this device'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Import photos'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(scanner.sources, [ScanSource.camera]);
    expect(picker.picks, 1);
  });

  testWidgets('Create sheet, tips and camera guide fit at 200% text', (tester) async {
    await pumpApp(tester, textScale: 2, overrides: [scannerServiceProvider.overrideWithValue(_Scanner(blocked: true))]);
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
}
