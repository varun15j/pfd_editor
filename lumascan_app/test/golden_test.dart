@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/app_settings.dart';
import 'package:lumascan/features/crop/crop_screen.dart';
import 'package:lumascan/features/export/export_sheet.dart';
import 'package:lumascan/features/filters/filter_screen.dart';
import 'package:lumascan/features/pages/pages_screen.dart';

import 'library_browse_test.dart' show threeDocs;
import 'support/memory_stores.dart';
import 'support/pump_app.dart';
import 'support/screen_harness.dart';

/// Pictures of the main screens, to catch a layout or colour change nobody
/// meant. The test font draws every letter as a block, so these compare
/// layout, spacing and colour, not type. Pixels differ slightly between
/// platforms, so they only run on Linux, where CI runs. After a deliberate
/// change, regenerate with `flutter test --update-goldens test/golden_test.dart`.
void main() {
  final skip = !Platform.isLinux;
  final harness = ScreenHarness();

  Finder app() => find.byType(MaterialApp);

  group('app tabs', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final tab in ['Home', 'Library', 'Settings']) {
        testWidgets('$tab in ${mode.name}', (tester) async {
          await pumpApp(
            tester,
            library: MemoryLibraryStore(threeDocs()),
            settings: MemoryAppSettingsStore(AppSettings(onboardingSeen: true, themeMode: mode)),
          );
          if (tab != 'Home') {
            await tester.tap(find.bySemanticsLabel(tab).first);
            await tester.pumpAndSettle();
          }
          await expectLater(app(), matchesGoldenFile('goldens/${tab.toLowerCase()}_${mode.name}.png'));
        }, skip: skip);
      }
    }
  });

  group('scanning flow', () {
    final screens = <String, Future<void> Function(WidgetTester, Brightness)>{
      'review': (t, b) => harness.pump(t, const PagesScreen(), brightness: b),
      'crop': (t, b) => harness.pumpRoute(t, (_) => CropScreen(pageId: harness.pages.first.id), brightness: b),
      'enhance': (t, b) => harness.pumpRoute(t, (_) => FilterScreen(pageId: harness.pages.first.id), brightness: b),
      'save': (t, b) async {
        await harness.pump(
          t,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () => showExportSheet(context), child: const Text('open')),
            ),
          ),
          brightness: b,
        );
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
      },
    };
    for (final brightness in Brightness.values) {
      for (final entry in screens.entries) {
        testWidgets('${entry.key} in ${brightness.name}', (tester) async {
          await tester.runAsync(harness.setUp);
          addTearDown(harness.dispose);
          await entry.value(tester, brightness);
          await expectLater(app(), matchesGoldenFile('goldens/${entry.key}_${brightness.name}.png'));
        }, skip: skip);
      }
    }
  });
}
