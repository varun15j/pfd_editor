import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../app/providers.dart';
import '../../domain/document_text.dart';
import '../../domain/library.dart';
import '../../domain/plan.dart';
import 'library_controller.dart';

/// The text of saved documents, for searching inside them (Pro). Started
/// by the Library; on Pro and Gold it reads every document that has no
/// text yet, or changed since it was read, one at a time in the background.
final documentTextProvider = NotifierProvider<DocumentTextController, DocumentTextState>(DocumentTextController.new);

@immutable
class DocumentTextState {
  const DocumentTextState({this.texts = const {}, this.left = 0});

  /// Text by document id.
  final Map<String, DocumentText> texts;

  /// Documents still waiting to be read, including the one being read.
  final int left;

  DocumentTextState copyWith({Map<String, DocumentText>? texts, int? left}) =>
      DocumentTextState(texts: texts ?? this.texts, left: left ?? this.left);
}

class DocumentTextController extends Notifier<DocumentTextState> {
  bool _loaded = false;
  bool _running = false;

  @override
  DocumentTextState build() {
    ref.listen(savedDocumentsProvider, (_, _) => _schedule());
    ref.listen(planIncludesProvider(PlanFeature.searchText), (_, _) => _schedule());
    _load();
    return const DocumentTextState();
  }

  Future<void> _load() async {
    final texts = await ref.read(documentTextStoreProvider).load();
    if (!ref.mounted) return;
    state = state.copyWith(texts: {...texts, ...state.texts});
    _loaded = true;
    _schedule();
  }

  void _schedule() {
    if (_loaded && !_running) _run();
  }

  bool _stale(SavedDocument d) {
    final t = state.texts[d.id];
    return t == null || t.readAt.isBefore(d.modifiedAt);
  }

  Future<void> _run() async {
    _running = true;
    // Each document is tried once per run, so one whose date is in the
    // future cannot be read over and over.
    final tried = <String>{};
    try {
      while (ref.mounted && ref.read(planIncludesProvider(PlanFeature.searchText))) {
        final docs = ref.read(savedDocumentsProvider);
        _forgetDeleted(docs);
        final waiting = [
          for (final d in docs)
            if (!tried.contains(d.id) && _stale(d)) d,
        ];
        if (waiting.isEmpty) break;
        final doc = waiting.first;
        tried.add(doc.id);
        state = state.copyWith(left: waiting.length);
        String text;
        try {
          text = await ref
              .read(documentTextReaderProvider)
              .read(doc.pdfPath, pageCount: doc.pageCount, languageCode: ref.read(ocrLanguageProvider));
        } on Object {
          // Kept as read, with no text, so it is not tried again until the
          // document changes.
          text = '';
        }
        if (!ref.mounted) return;
        state = state.copyWith(texts: {...state.texts, doc.id: DocumentText(text, DateTime.now())});
        await _save();
      }
    } finally {
      _running = false;
      if (ref.mounted) state = state.copyWith(left: 0);
    }
  }

  void _forgetDeleted(List<SavedDocument> docs) {
    final ids = {for (final d in docs) d.id};
    if (state.texts.keys.every(ids.contains)) return;
    state = state.copyWith(texts: {for (final e in state.texts.entries) if (ids.contains(e.key)) e.key: e.value});
  }

  Future<void> _save() async {
    try {
      await ref.read(documentTextStoreProvider).save(state.texts);
    } on Object {
      // The text is kept in memory; it is read again next start if lost.
    }
  }
}
