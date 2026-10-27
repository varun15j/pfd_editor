import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/signature_library_store.dart';
import '../../domain/signature_library.dart';

final signatureLibraryStoreProvider = Provider<SignatureLibraryStore>(
  (ref) => SignatureLibraryStore(ref.watch(pageStoreProvider)),
);

/// The saved signatures, initials and stamp name. Starts empty and switches
/// to the saved library once it is read.
final signatureLibraryProvider = NotifierProvider<SignatureLibraryController, SignatureLibrary>(
  SignatureLibraryController.new,
);

class SignatureLibraryController extends Notifier<SignatureLibrary> {
  Future<void> _io = Future.value();
  bool _changed = false;

  /// Completes once the saved library is loaded and every change is written.
  Future<void> get settled => _io;

  @override
  SignatureLibrary build() {
    _io = _load().catchError((Object _) {});
    return const SignatureLibrary();
  }

  Future<void> _load() async {
    final saved = await ref.read(signatureLibraryStoreProvider).load();
    // A change made while loading wins over the stored library.
    if (ref.mounted && !_changed) state = saved;
  }

  void save(SavedSignature signature) => _set(state.withSaved(signature));

  void remove(String id) => _set(state.without(id));

  void setStampName(String name) => _set(state.copyWith(stampName: name.trim()));

  void _set(SignatureLibrary library) {
    _changed = true;
    state = library;
    final store = ref.read(signatureLibraryStoreProvider);
    _io = _io.then((_) => store.save(library)).catchError((Object _) {});
  }
}
