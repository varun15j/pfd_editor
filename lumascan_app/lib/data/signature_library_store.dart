import 'dart:convert';

import '../domain/signature_library.dart';
import 'page_store.dart';

/// Stores the signature library (`settings/signatures.json`) on the device
/// only. Nothing here is uploaded.
class SignatureLibraryStore {
  SignatureLibraryStore(this._files);

  final PageStore _files;

  static const libraryFile = 'settings/signatures.json';

  /// Returns the saved library, or an empty one when there is none or the
  /// file cannot be read.
  Future<SignatureLibrary> load() async {
    try {
      final text = await _files.readText(libraryFile);
      return text == null ? const SignatureLibrary() : SignatureLibrary.fromJson((jsonDecode(text) as Map).cast());
    } catch (_) {
      return const SignatureLibrary();
    }
  }

  Future<void> save(SignatureLibrary library) =>
      _files.writeFileAtomically(libraryFile, utf8.encode(jsonEncode(library.toJson())));
}
