import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings_store.dart';
import '../data/ui_prefs_store.dart';
import '../domain/app_settings.dart';
import '../domain/models.dart';
import '../domain/ui_prefs.dart';
import 'providers.dart';

final appSettingsStoreProvider = Provider<AppSettingsStore>((ref) => AppSettingsStore(ref.watch(pageStoreProvider)));

/// The Settings choices. Starts with the defaults and switches to the saved
/// choices once they are read.
final appSettingsProvider = NotifierProvider<AppSettingsController, AppSettings>(AppSettingsController.new);

class AppSettingsController extends Notifier<AppSettings> {
  Future<void> _io = Future.value();
  Future<void> _loaded = Future.value();
  bool _changed = false;

  /// Completes once the saved choices are loaded and every change is written.
  Future<void> get settled => _io;

  /// Completes once the saved choices are read, whatever is saved afterwards.
  Future<void> get loaded => _loaded;

  @override
  AppSettings build() {
    _loaded = _load().catchError((Object _) {});
    _io = _loaded;
    return const AppSettings();
  }

  Future<void> _load() async {
    final saved = await ref.read(appSettingsStoreProvider).load();
    // A choice made while loading wins over the stored one.
    if (ref.mounted && !_changed) state = saved;
  }

  void setThemeMode(ThemeMode mode) => _set(state.copyWith(themeMode: mode));

  void setDefaultFilter(DocumentFilter filter) => _set(state.copyWith(defaultFilter: filter));

  void setAutoCropOnImport(bool value) => _set(state.copyWith(autoCropOnImport: value));

  void setKeepOriginals(bool value) => _set(state.copyWith(keepOriginals: value));

  void setFileNamePattern(FileNamePattern pattern) => _set(state.copyWith(fileNamePattern: pattern));

  /// Remembers that the intro was shown, with the answer to the usage-data
  /// question when one was given.
  void completeOnboarding({bool? analytics}) =>
      _set(state.copyWith(onboardingSeen: true, analytics: analytics ?? state.analytics));

  void setAnalytics(bool value) => _set(state.copyWith(analytics: value));

  void setCaptureResolution(CaptureResolution value) => _set(state.copyWith(captureResolution: value));

  void setShutterSound(bool value) => _set(state.copyWith(shutterSound: value));

  void setCaptureHaptics(bool value) => _set(state.copyWith(captureHaptics: value));

  void setAutoCaptureSteadiness(AutoCaptureSteadiness value) => _set(state.copyWith(autoCaptureSteadiness: value));

  void _set(AppSettings settings) {
    _changed = true;
    state = settings;
    final store = ref.read(appSettingsStoreProvider);
    _io = _io.then((_) => store.save(settings)).catchError((Object _) {});
  }
}

/// Completes once the saved Settings choices are read, so the first screen
/// is not picked from the defaults.
final appSettingsReadyProvider = FutureProvider<void>((ref) => ref.read(appSettingsProvider.notifier).loaded);

/// Light, dark or follow the system.
final themeModeProvider = Provider<ThemeMode>((ref) => ref.watch(appSettingsProvider.select((s) => s.themeMode)));

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
