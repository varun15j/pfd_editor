import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/library.dart';
import '../pdf_editor/open_pdf.dart';
import 'library_controller.dart';

/// Ids hidden from the UI while their delete can still be undone. Nothing
/// is removed from disk until the undo window closes, so if the app is
/// killed meanwhile the documents simply come back.
final pendingDeletionProvider = NotifierProvider<PendingDeletion, Set<String>>(PendingDeletion.new);

class PendingDeletion extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void hide(Iterable<String> ids) => state = {...state, ...ids};

  void undo(Iterable<String> ids) => state = state.difference(ids.toSet());

  Future<void> commit(Iterable<String> ids) async {
    final library = ref.read(libraryProvider.notifier);
    try {
      for (final id in ids) {
        await library.delete(id);
      }
    } finally {
      if (ref.mounted) state = state.difference(ids.toSet());
    }
  }
}

/// Saved documents as the UI shows them: newest first, without the ones
/// waiting to be deleted.
final visibleDocumentsProvider = Provider<List<SavedDocument>>((ref) {
  final hidden = ref.watch(pendingDeletionProvider);
  final docs = ref.watch(savedDocumentsProvider);
  return hidden.isEmpty
      ? docs
      : [
          for (final d in docs)
            if (!hidden.contains(d.id)) d,
        ];
});

/// Opens a saved document in the PDF editor. Edits are saved as a new file.
Future<void> openDocument(BuildContext context, WidgetRef ref, SavedDocument doc) async {
  if (!File(doc.pdfPath).existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${doc.name} is no longer on this device.')));
    return;
  }
  await openPdfInEditor(context, ref, path: doc.pdfPath, name: '${doc.name}.pdf');
}

Future<void> shareDocuments(BuildContext context, List<SavedDocument> docs) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      files: [for (final d in docs) XFile(d.pdfPath, mimeType: 'application/pdf')],
      // Required on iPad, where the share sheet is a popover.
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

/// Hides the documents at once and deletes them when the Undo snackbar
/// closes without being tapped.
Future<void> deleteWithUndo(BuildContext context, WidgetRef ref, List<SavedDocument> docs) async {
  if (docs.isEmpty) return;
  final ids = [for (final d in docs) d.id];
  final pending = ref.read(pendingDeletionProvider.notifier)..hide(ids);
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  final label = docs.length == 1 ? '${docs.single.name} deleted' : '${docs.length} documents deleted';
  final reason = await messenger
      .showSnackBar(
        SnackBar(
          content: Text(label),
          action: SnackBarAction(label: 'Undo', onPressed: () {}),
          persist: false,
        ),
      )
      .closed;
  if (reason == SnackBarClosedReason.action) {
    pending.undo(ids);
  } else {
    try {
      await pending.commit(ids);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete everything ($e)')));
    }
  }
}

/// Asks for a new name and renames the document and its file.
Future<void> renameDocument(BuildContext context, WidgetRef ref, SavedDocument doc) async {
  final messenger = ScaffoldMessenger.of(context);
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(initial: doc.name),
  );
  if (name == null || name == doc.name) return;
  try {
    await ref.read(libraryProvider.notifier).rename(doc.id, name);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not rename ($e)')));
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _text.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: _text,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: 'Name', errorText: _error),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
