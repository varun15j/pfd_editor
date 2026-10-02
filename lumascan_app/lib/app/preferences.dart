import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ui_prefs_store.dart';
import '../domain/ui_prefs.dart';
import 'providers.dart';

/// Light, dark or follow the system. Kept in memory for now; the Settings PR
/// (F1 in the UI/UX plan) stores it on the device.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void set(ThemeMode mode) => state = mode;
}

final uiPrefsStoreProvider = Provider<UiPrefsStore>((ref) => UiPrefsStore(ref.watch(pageStoreProvider)));

/// Library view and dismissed Home cards. Starts with the defaults and
/// switches to the saved choices once they are read.
final uiPrefsProvider = NotifierProvider<UiPrefsController, UiPrefs>(UiPrefsController.new);

class UiPrefsController extends Notifier<UiPrefs> {
  Future<void> _io = Future.value();
  bool _changed = false;

  /// Completes once the saved choices are loaded and every change is written.
  Future<void> get settled => _io;

  @override
  UiPrefs build() {
    _io = _load().catchError((Object _) {});
    return const UiPrefs();
  }

  Future<void> _load() async {
    final saved = await ref.read(uiPrefsStoreProvider).load();
    // A choice made while loading wins over the stored one.
    if (ref.mounted && !_changed) state = saved;
  }

  void setLibraryView(LibraryView view) => _set(state.copyWith(libraryView: view));

  void dismissCard(String id) => _set(state.copyWith(dismissedCards: {...state.dismissedCards, id}));

  void _set(UiPrefs prefs) {
    _changed = true;
    state = prefs;
    final store = ref.read(uiPrefsStoreProvider);
    _io = _io.then((_) => store.save(prefs)).catchError((Object _) {});
  }
}
