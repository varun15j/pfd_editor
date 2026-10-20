import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../library/library_controller.dart';
import 'merge_controller.dart';

/// Pick saved documents to add to a merge. Returns the chosen ones, in the
/// order they were ticked.
class LibraryPickScreen extends ConsumerStatefulWidget {
  const LibraryPickScreen({super.key});

  @override
  ConsumerState<LibraryPickScreen> createState() => _LibraryPickScreenState();
}

class _LibraryPickScreenState extends ConsumerState<LibraryPickScreen> {
  final _chosen = <String>[];

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    final c = LumaColors.of(context);
    final docs = library.value?.documents ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Choose from Library')),
      body: library.isLoading
          ? const Center(child: CircularProgressIndicator())
          : docs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Text(
                  'Your Library has no documents yet. Save a scan or a PDF first, or choose files from this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: Space.xxl),
              children: [
                for (final doc in docs)
                  CheckboxListTile(
                    value: _chosen.contains(doc.id),
                    onChanged: (v) => setState(() => v == true ? _chosen.add(doc.id) : _chosen.remove(doc.id)),
                    secondary: const Icon(Icons.picture_as_pdf_outlined),
                    title: Text(doc.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}'),
                    controlAffinity: ListTileControlAffinity.trailing,
                  ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: FilledButton(
            onPressed: _chosen.isEmpty
                ? null
                : () => Navigator.of(context).pop([
                    for (final id in _chosen)
                      if (docs.where((d) => d.id == id).firstOrNull case final doc?)
                        NewMergeSource(name: '${doc.name}.pdf', path: doc.pdfPath, knownPages: doc.pageCount),
                  ]),
            child: Text(_chosen.isEmpty ? 'Add' : 'Add ${_chosen.length}'),
          ),
        ),
      ),
    );
  }
}
