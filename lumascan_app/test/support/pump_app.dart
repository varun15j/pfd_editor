import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/app.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/library_store.dart';
import 'package:lumascan/data/ui_prefs_store.dart';

import 'memory_stores.dart';

/// Pumps the whole app on a phone-sized screen with in-memory stores.
Future<void> pumpApp(
  WidgetTester tester, {
  List overrides = const [],
  double textScale = 1,
  LibraryStore? library,
  DraftStore? draft,
  UiPrefsStore? prefs,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.6;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryStoreProvider.overrideWithValue(library ?? MemoryLibraryStore()),
        draftStoreProvider.overrideWithValue(draft ?? MemoryDraftStore()),
        uiPrefsStoreProvider.overrideWithValue(prefs ?? MemoryUiPrefsStore()),
        ...overrides,
      ],
      child: const LumaScanApp(),
    ),
  );
  await tester.pumpAndSettle();
}
