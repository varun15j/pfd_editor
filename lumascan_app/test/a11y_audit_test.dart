import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/domain/app_settings.dart';
import 'package:lumascan/domain/ui_prefs.dart';

import 'library_browse_test.dart' show threeDocs;
import 'support/memory_stores.dart';
import 'support/pump_app.dart';

void main() {
  Future<void> expectAccessible(WidgetTester tester) async {
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final tab in ['Home', 'Library', 'Tools', 'Settings']) {
      testWidgets('$tab in ${mode.name}: guidelines', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpApp(
          tester,
          library: MemoryLibraryStore(threeDocs()),
          settings: MemoryAppSettingsStore(AppSettings(onboardingSeen: true, themeMode: mode)),
        );
        if (tab != 'Home') {
          await tester.tap(find.bySemanticsLabel(tab).first);
          await tester.pumpAndSettle();
        }
        await expectAccessible(tester);
        handle.dispose();
      });
    }

    testWidgets('Library grid in ${mode.name}: guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        library: MemoryLibraryStore(threeDocs()),
        prefs: MemoryUiPrefsStore(const UiPrefs(libraryView: LibraryView.grid)),
        settings: MemoryAppSettingsStore(AppSettings(onboardingSeen: true, themeMode: mode)),
      );
      await tester.tap(find.bySemanticsLabel('Library').first);
      await tester.pumpAndSettle();
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('Library selecting in ${mode.name}: guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        library: MemoryLibraryStore(threeDocs()),
        settings: MemoryAppSettingsStore(AppSettings(onboardingSeen: true, themeMode: mode)),
      );
      await tester.tap(find.bySemanticsLabel('Library').first);
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Lease').last);
      await tester.pumpAndSettle();
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('Intro and usage question in ${mode.name}: guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, settings: MemoryAppSettingsStore(AppSettings(themeMode: mode)));
      await expectAccessible(tester);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await expectAccessible(tester);
      handle.dispose();
    });
  }

  for (final tab in ['Home', 'Library', 'Tools', 'Settings']) {
    testWidgets('$tab fits at 200% text size', (tester) async {
      await pumpApp(tester, library: MemoryLibraryStore(threeDocs()), textScale: 2);
      if (tab != 'Home') {
        await tester.tap(find.bySemanticsLabel(tab).first);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Library grid and selecting fit at 200% text size', (tester) async {
    await pumpApp(
      tester,
      library: MemoryLibraryStore(threeDocs()),
      prefs: MemoryUiPrefsStore(const UiPrefs(libraryView: LibraryView.grid)),
      textScale: 2,
    );
    await tester.tap(find.bySemanticsLabel('Library').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.longPress(find.text('Lease').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
