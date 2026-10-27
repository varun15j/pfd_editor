import 'dart:convert';

import '../domain/document_text.dart';
import 'page_store.dart';

/// Keeps the text read from saved documents in `library/text-index.json`,
/// apart from the library index so that file stays small. Written whole and
/// atomically, like the index.
class DocumentTextStore {
  DocumentTextStore(this._files);

  final PageStore _files;

  static const file = 'library/text-index.json';

  Future<Map<String, DocumentText>> load() async {
    try {
      final raw = await _files.readText(file);
      if (raw == null) return {};
      final json = (jsonDecode(raw) as Map).cast<String, Object?>();
      return {for (final e in json.entries) e.key: ?DocumentText.fromJson(e.value)};
    } on Object {
      // Damaged or unreadable: the text is read again, nothing is lost.
      return {};
    }
  }

  Future<void> save(Map<String, DocumentText> texts) =>
      _files.writeFileAtomically(file, utf8.encode(jsonEncode({for (final e in texts.entries) e.key: e.value.toJson()})));
}
