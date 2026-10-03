import 'dart:convert';

import '../domain/app_settings.dart';
import 'page_store.dart';

/// Stores the Settings choices (`settings/app.json`) so they survive a restart.
class AppSettingsStore {
  AppSettingsStore(this._files);

  final PageStore _files;

  static const settingsFile = 'settings/app.json';

  /// Returns the saved choices, or the defaults when there are none or the
  /// file cannot be read.
  Future<AppSettings> load() async {
    try {
      final text = await _files.readText(settingsFile);
      return text == null ? const AppSettings() : AppSettings.fromJson((jsonDecode(text) as Map).cast());
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) =>
      _files.writeFileAtomically(settingsFile, utf8.encode(jsonEncode(settings.toJson())));
}
