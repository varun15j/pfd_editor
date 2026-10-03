import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/library.dart';
import 'library_controller.dart';

/// Folders and tags (US-02.3): naming dialogs with inline checks, the move
/// and tag sheets used from a row or a selection, and delete confirmations
/// that never remove documents.

LibraryIndex _index(WidgetRef ref) => ref.read(libraryProvider).value ?? const LibraryIndex();

/// Asks for a folder or tag name, checking it as the user types.
Future<String?> askLabelName(
  BuildContext context, {
  required String title,
  required String action,
  required Iterable<String> existing,
  String? current,
}) => showDialog<String>(
  context: context,
  builder: (_) => _NameDialog(title: title, action: action, existing: existing.toList(), current: current),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.action, required this.existing, this.current});

  final String title;
  final String action;
  final List<String> existing;
  final String? current;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _text = TextEditingController(text: widget.current ?? '');
  bool _touched = false;

  String? get _error => validateLabelName(_text.text, widget.existing, current: widget.current);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (_error != null) {
      setState(() => _touched = true);
      return;
    }
    Navigator.pop(context, _text.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: 'Name', errorText: _touched ? _error : null),
        onChanged: (_) => setState(() => _touched = true),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}

Future<LibraryFolder?> createFolderFlow(BuildContext context, WidgetRef ref) async {
  final name = await askLabelName(
    context,
    title: 'New folder',
    action: 'Create',
    existing: _index(ref).folders.map((f) => f.name),
  );
  if (name == null) return null;
  return ref.read(libraryProvider.notifier).createFolder(name);
}

Future<String?> createTagFlow(BuildContext context, WidgetRef ref) async {
  final name = await askLabelName(context, title: 'New tag', action: 'Create', existing: _index(ref).allTags);
  if (name == null) return null;
  await ref.read(libraryProvider.notifier).createTag(name);
  return name;
}

Future<void> renameFolderFlow(BuildContext context, WidgetRef ref, LibraryFolder folder) async {
  final name = await askLabelName(
    context,
    title: 'Rename folder',
    action: 'Save',
    existing: _index(ref).folders.where((f) => f.id != folder.id).map((f) => f.name),
    current: folder.name,
  );
  if (name != null && name != folder.name) await ref.read(libraryProvider.notifier).renameFolder(folder.id, name);
}

Future<void> renameTagFlow(BuildContext context, WidgetRef ref, String tag) async {
  final name = await askLabelName(
    context,
    title: 'Rename tag',
    action: 'Save',
    existing: _index(ref).allTags.where((t) => t != tag),
    current: tag,
  );
  if (name != null && name != tag) await ref.read(libraryProvider.notifier).renameTag(tag, name);
}

/// Asks first; the folder's documents move to All documents.
Future<void> deleteFolderFlow(BuildContext context, WidgetRef ref, LibraryFolder folder) async {
  final count = _index(ref).documents.where((d) => d.folderId == folder.id).length;
  final ok = await _confirm(
    context,
    title: 'Delete folder "${folder.name}"?',
    message: count == 0
        ? 'The folder is empty.'
        : 'Its $count document${count == 1 ? '' : 's'} stay in your Library, outside any folder. '
              'No documents are deleted.',
  );
  if (ok) await ref.read(libraryProvider.notifier).deleteFolder(folder.id);
}

/// Asks first; the tag is removed from documents, which stay.
Future<void> deleteTagFlow(BuildContext context, WidgetRef ref, String tag) async {
  final lower = tag.toLowerCase();
  final count = _index(ref).documents.where((d) => d.tags.any((t) => t.toLowerCase() == lower)).length;
  final ok = await _confirm(
    context,
    title: 'Delete tag "$tag"?',
    message: count == 0
        ? 'No documents use this tag.'
        : 'It is removed from $count document${count == 1 ? '' : 's'}. No documents are deleted.',
  );
  if (ok) await ref.read(libraryProvider.notifier).deleteTag(tag);
}

Future<bool> _confirm(BuildContext context, {required String title, required String message}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    ) ??
    false;

/// Picks one folder (or none) for [docs] and moves them straight away.
Future<void> moveToFolderSheet(BuildContext context, WidgetRef ref, List<SavedDocument> docs) async {
  if (docs.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final current = docs.map((d) => d.folderId).toSet();
  const none = '';
  final picked = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final folders = ref.watch(libraryProvider).value?.folders ?? const [];
        final selected = current.length == 1 ? (current.single ?? none) : null;
        return SafeArea(
          child: SingleChildScrollView(
            child: RadioGroup<String>(
              groupValue: selected,
              onChanged: (v) => Navigator.pop(sheetContext, v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
                    child: Semantics(
                      header: true,
                      child: Text(
                        docs.length == 1 ? 'Move to folder' : 'Move ${docs.length} documents',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  const RadioListTile<String>(value: none, title: Text('No folder')),
                  for (final f in folders) RadioListTile<String>(value: f.id, title: Text(f.name)),
                  ListTile(
                    leading: const Icon(Icons.create_new_folder_outlined),
                    title: const Text('New folder'),
                    onTap: () async {
                      final folder = await createFolderFlow(context, ref);
                      if (folder != null && sheetContext.mounted) Navigator.pop(sheetContext, folder.id);
                    },
                  ),
                  const SizedBox(height: Space.sm),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  if (picked == null) return;
  final folderId = picked == none ? null : picked;
  await ref.read(libraryProvider.notifier).moveManyToFolder(docs.map((d) => d.id), folderId);
  final name = _index(ref).folderById(folderId)?.name;
  messenger.showSnackBar(SnackBar(content: Text(name == null ? 'Moved out of folders' : 'Moved to $name')));
}

/// Adds or removes tags on [docs]. A tag only some of them carry starts as
/// "mixed" and is left alone unless tapped.
Future<void> editTagsSheet(BuildContext context, WidgetRef ref, List<SavedDocument> docs) async {
  if (docs.isEmpty) return;
  final result = await showModalBottomSheet<Map<String, bool?>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _TagsSheet(docs: docs),
  );
  if (result == null) return;
  await ref
      .read(libraryProvider.notifier)
      .updateTags(
        docs.map((d) => d.id),
        add: {
          for (final e in result.entries)
            if (e.value == true) e.key,
        },
        remove: {
          for (final e in result.entries)
            if (e.value == false) e.key,
        },
      );
}

class _TagsSheet extends ConsumerStatefulWidget {
  const _TagsSheet({required this.docs});
  final List<SavedDocument> docs;

  @override
  ConsumerState<_TagsSheet> createState() => _TagsSheetState();
}

class _TagsSheetState extends ConsumerState<_TagsSheet> {
  /// true = on every document, false = on none, null = on some.
  final _state = <String, bool?>{};
  final _initial = <String, bool?>{};

  bool? _stateFor(String tag) {
    final lower = tag.toLowerCase();
    final n = widget.docs.where((d) => d.tags.any((t) => t.toLowerCase() == lower)).length;
    return n == 0 ? false : (n == widget.docs.length ? true : null);
  }

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(libraryProvider).value?.allTags ?? const <String>[];
    for (final t in tags) {
      _initial.putIfAbsent(t, () => _stateFor(t));
      _state.putIfAbsent(t, () => _initial[t]);
    }
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
              child: Semantics(header: true, child: Text('Tags', style: text.titleLarge)),
            ),
            if (tags.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.sm),
                child: Text('No tags yet. Create one to group documents by subject.', style: text.bodyMedium),
              ),
            for (final t in tags)
              CheckboxListTile(
                value: _state[t],
                tristate: _initial[t] == null,
                title: Text(t),
                subtitle: _state[t] == null ? const Text('On some selected documents') : null,
                onChanged: (_) => setState(() {
                  // Cycle on -> off -> (mixed, only if it started mixed) -> on.
                  final now = _state[t];
                  _state[t] = now == true ? false : (now == false && _initial[t] == null ? null : true);
                }),
              ),
            ListTile(
              leading: const Icon(Icons.new_label_outlined),
              title: const Text('New tag'),
              onTap: () async {
                final name = await createTagFlow(context, ref);
                if (name != null) {
                  setState(() {
                    _initial[name] = false;
                    _state[name] = true;
                  });
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, Space.lg),
              child: FilledButton(
                onPressed: () => Navigator.pop(context, {
                  for (final e in _state.entries)
                    if (e.value != _initial[e.key]) e.key: e.value,
                }),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lists every folder and tag with how many documents use it, to create,
/// rename or delete them.
class ManageLabelsScreen extends ConsumerWidget {
  const ManageLabelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(libraryProvider).value ?? const LibraryIndex();
    final text = Theme.of(context).textTheme;
    final c = LumaColors.of(context);
    String count(int n) => '$n document${n == 1 ? '' : 's'}';

    Widget header(String title, String action, VoidCallback onAdd) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.page, Space.lg, Space.sm, Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Semantics(header: true, child: Text(title, style: text.titleMedium)),
          ),
          TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(action)),
        ],
      ),
    );

    Widget menu(String name, VoidCallback onRename, VoidCallback onDelete) => PopupMenuButton<int>(
      tooltip: 'More for $name',
      onSelected: (v) => v == 0 ? onRename() : onDelete(),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 0,
          child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Rename')),
        ),
        PopupMenuItem(
          value: 1,
          child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')),
        ),
      ],
    );

    Widget empty(String message) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.page, vertical: Space.sm),
      child: Text(message, style: text.bodyMedium?.copyWith(color: c.muted)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Folders and tags')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxl),
        children: [
          header('Folders', 'New folder', () => createFolderFlow(context, ref)),
          if (index.folders.isEmpty) empty('A document can live in one folder.'),
          for (final f in index.folders)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(f.name),
              subtitle: Text(count(index.documents.where((d) => d.folderId == f.id).length)),
              trailing: menu(f.name, () => renameFolderFlow(context, ref, f), () => deleteFolderFlow(context, ref, f)),
            ),
          const Divider(height: Space.xl),
          header('Tags', 'New tag', () => createTagFlow(context, ref)),
          if (index.allTags.isEmpty) empty('A document can have any number of tags.'),
          for (final t in index.allTags)
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(t),
              subtitle: Text(
                count(index.documents.where((d) => d.tags.any((x) => x.toLowerCase() == t.toLowerCase())).length),
              ),
              trailing: menu(t, () => renameTagFlow(context, ref, t), () => deleteTagFlow(context, ref, t)),
            ),
        ],
      ),
    );
  }
}
