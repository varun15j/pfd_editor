import 'dart:convert';

import '../domain/ui_prefs.dart';
import 'page_store.dart';

/// Stores small UI choices (`settings/ui.json`), such as the Library view and
/// dismissed Home cards, so they survive a restart (US-02.1: list/grid
/// preference persists).
class UiPrefsStore {
  UiPrefsStore(this._files);

  final PageStore _files;

  static const prefsFile = 'settings/ui.json';

  /// Returns the saved choices, or the defaults when there are none or the
  /// file cannot be read.
  Future<UiPrefs> load() async {
    try {
      final text = await _files.readText(prefsFile);
      return text == null ? const UiPrefs() : UiPrefs.fromJson((jsonDecode(text) as Map).cast());
    } catch (_) {
      return const UiPrefs();
    }
  }

  Future<void> save(UiPrefs prefs) => _files.writeFileAtomically(prefsFile, utf8.encode(jsonEncode(prefs.toJson())));
}
