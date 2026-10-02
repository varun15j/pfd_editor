import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/app.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/domain/scanner_service.dart';

class _BlockedScanner implements ScannerService {
  @override
  Future<List<String>> scan({required ScanSource source, int maxPages = 100}) async =>
      throw const ScannerPermissionDenied(permanently: true);

  @override
  Future<void> cleanUp() async {}
}

void main() {
  testWidgets('empty draft offers camera scan and photo import', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LumaScanApp()));
    expect(find.text('Scan with camera'), findsOneWidget);
    expect(find.text('Import from photos'), findsOneWidget);
  });

  testWidgets('blocked camera explains and links to Settings', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [scannerServiceProvider.overrideWithValue(_BlockedScanner())],
      child: const LumaScanApp(),
    ));
    await tester.tap(find.text('Scan with camera'));
    await tester.pumpAndSettle();
    expect(find.text('Camera access needed'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
