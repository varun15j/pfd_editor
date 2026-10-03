import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../export/pdf_merger.dart';
import '../../pdf_edit/pdf_edit_controller.dart';
import 'pdf_inspector.dart';

final pdfMergerProvider = Provider<PdfMerger>(
  (ref) => PdfMerger(ref.watch(pageStoreProvider), ref.watch(pdfRasterizerProvider)),
);

/// One PDF in the merge list. [info] is null while the file is being checked.
@immutable
class MergeSource {
  const MergeSource({required this.key, required this.name, required this.path, this.knownPages, this.info});

  /// Unique in the list, so the same PDF can be added twice.
  final int key;

  /// File name with .pdf, as shown in the list.
  final String name;
  final String path;

  /// Page count already known (from the Library) to show while checking.
  final int? knownPages;
  final PdfInfo? info;

  bool get checking => info == null;
  PdfProblem? get problem => info?.problem;
  bool get usable => info?.problem == null && info != null;
  int? get pages => info?.pageCount ?? knownPages;

  int? get sizeBytes {
    final f = File(path);
    return f.existsSync() ? f.lengthSync() : null;
  }

  MergeSource withInfo(PdfInfo info) =>
      MergeSource(key: key, name: name, path: path, knownPages: knownPages, info: info);
}

/// A PDF waiting to be added to the list.
class NewMergeSource {
  const NewMergeSource({required this.name, required this.path, this.knownPages});

  final String name;
  final String path;
  final int? knownPages;
}

@immutable
class MergeState {
  const MergeState([this.sources = const []]);

  final List<MergeSource> sources;

  bool get checking => sources.any((s) => s.checking);
  List<MergeSource> get flagged => [
    for (final s in sources)
      if (s.problem != null) s,
  ];

  /// Every file checked and readable, and at least two of them.
  bool get canMerge => sources.length >= 2 && !checking && flagged.isEmpty;

  int get totalPages => sources.fold(0, (sum, s) => sum + (s.pages ?? 0));
}

final mergeControllerProvider = NotifierProvider.autoDispose<MergeController, MergeState>(MergeController.new);

/// The ordered list of PDFs to merge. Each added file is opened once to count
/// its pages and flag it when it is locked or cannot be read.
class MergeController extends Notifier<MergeState> {
  int _nextKey = 0;

  @override
  MergeState build() => const MergeState();

  void add(Iterable<NewMergeSource> added) {
    final fresh = [
      for (final a in added) MergeSource(key: _nextKey++, name: a.name, path: a.path, knownPages: a.knownPages),
    ];
    if (fresh.isEmpty) return;
    state = MergeState([...state.sources, ...fresh]);
    for (final source in fresh) {
      _check(source);
    }
  }

  Future<void> _check(MergeSource source) async {
    final PdfInfo info;
    try {
      info = await ref.read(pdfInspectorProvider).inspect(source.path);
    } on Object {
      _setInfo(source.key, const PdfInfo.problem(PdfProblem.unreadable));
      return;
    }
    _setInfo(source.key, info);
  }

  void _setInfo(int key, PdfInfo info) {
    if (!ref.mounted) return;
    state = MergeState([for (final s in state.sources) s.key == key ? s.withInfo(info) : s]);
  }

  void remove(int key) => state = MergeState([
    for (final s in state.sources)
      if (s.key != key) s,
  ]);

  /// [newIndex] is the item's final position, as ReorderableListView's
  /// onReorderItem reports it.
  void reorder(int oldIndex, int newIndex) {
    final list = [...state.sources];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    newIndex = newIndex.clamp(0, list.length - 1);
    list.insert(newIndex, list.removeAt(oldIndex));
    state = MergeState(list);
  }
}
