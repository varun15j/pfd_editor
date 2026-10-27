import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/library.dart';
import '../../export/pdf_splitter.dart';
import '../../pdf_edit/pdf_edit_controller.dart';
import '../../ui/file_size.dart';
import '../library/library_controller.dart';
import '../share/send_pdf_sheet.dart';

final pdfSplitterProvider = Provider<PdfSplitter>(
  (ref) => PdfSplitter(ref.watch(pageStoreProvider), ref.watch(pdfRasterizerProvider)),
);

/// The PDF to split: its name without .pdf, its file and its page count.
class SplitSource {
  const SplitSource({required this.name, required this.path, required this.pageCount});

  final String name;
  final String path;
  final int pageCount;
}

enum SplitMode { split, extract }

enum SplitBy { every, ranges }

/// Split a PDF into several files (every few pages, or by typed ranges), or
/// extract the ticked pages into one new file. New files go to the Library;
/// the source PDF is not changed.
class SplitScreen extends ConsumerStatefulWidget {
  const SplitScreen({super.key, required this.source});

  final SplitSource source;

  @override
  ConsumerState<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends ConsumerState<SplitScreen> {
  late SplitMode _mode = widget.source.pageCount > 1 ? SplitMode.split : SplitMode.extract;
  SplitBy _by = SplitBy.every;
  late int _every = widget.source.pageCount > 2 ? 2 : 1;
  final _ranges = TextEditingController();
  final _picked = <int>{};
  double? _progress;
  String? _error;
  List<(File, int)>? _saved;

  int get _pageCount => widget.source.pageCount;
  bool get _busy => _progress != null;

  @override
  void initState() {
    super.initState();
    _ranges.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ranges.dispose();
    super.dispose();
  }

  /// The files the current choices make, or a reason they cannot be made.
  (List<SplitPart>, String?) _plan() {
    final name = widget.source.name;
    if (_mode == SplitMode.extract) {
      if (_picked.isEmpty) return (const [], 'Tick the pages to extract.');
      final pages = _picked.toList()..sort();
      final label = describePages(pages).replaceAll(', ', ',');
      return ([SplitPart(pages: pages, name: '$name pages $label')], null);
    }
    final List<List<int>> groups;
    if (_by == SplitBy.every) {
      groups = pagesInChunks(_pageCount, _every);
    } else {
      if (_ranges.text.trim().isEmpty) return (const [], 'Type the pages for each file, such as 1-3, 4-6.');
      try {
        groups = parsePageRanges(_ranges.text, _pageCount);
      } on PageRangeException catch (e) {
        return (const [], e.message);
      }
    }
    if (groups.length == 1 && groups.single.length == _pageCount) {
      return (const [], 'That keeps every page in one file. Choose fewer pages per file.');
    }
    return ([for (final (i, pages) in groups.indexed) SplitPart(pages: pages, name: '$name part ${i + 1}')], null);
  }

  Future<void> _run(List<SplitPart> parts) async {
    final splitter = ref.read(pdfSplitterProvider);
    final library = ref.read(libraryProvider.notifier);
    setState(() {
      _progress = 0;
      _error = null;
    });
    final List<File> files;
    try {
      files = await splitter.split(
        widget.source.path,
        parts,
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = done / total);
        },
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = 'Could not make the new PDFs. Your PDF is unchanged. ($e)';
        });
      }
      return;
    }
    final saved = [for (final (i, f) in files.indexed) (f, parts[i].pages.length)];
    if (mounted) {
      setState(() {
        _progress = null;
        _saved = saved;
      });
    }
    try {
      for (final (file, pages) in saved) {
        await library.addPdf(file, pageCount: pages);
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Saved, but not every file could be added to your Library. ($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(_mode == SplitMode.split ? 'Split PDF' : 'Extract pages')),
        body: saved != null ? _result(context, saved) : _choices(context),
      ),
    );
  }

  Widget _choices(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    final (parts, problem) = _plan();
    final action = _mode == SplitMode.split
        ? 'Split into ${parts.length} PDFs'
        : 'Extract ${_picked.length} page${_picked.length == 1 ? '' : 's'}';
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.lg),
            children: [
              Text(widget.source.name, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text('$_pageCount page${_pageCount == 1 ? '' : 's'}', style: text.bodySmall?.copyWith(color: c.muted)),
              const SizedBox(height: Space.lg),
              SegmentedButton<SplitMode>(
                segments: [
                  ButtonSegment(
                    value: SplitMode.split,
                    label: const Text('Split'),
                    icon: const Icon(Icons.call_split),
                    enabled: _pageCount > 1,
                  ),
                  const ButtonSegment(
                    value: SplitMode.extract,
                    label: Text('Extract'),
                    icon: Icon(Icons.file_copy_outlined),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: _busy ? null : (s) => setState(() => _mode = s.single),
              ),
              const SizedBox(height: Space.lg),
              if (_mode == SplitMode.split) ..._splitOptions(context, parts) else ..._extractOptions(context),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy) ...[LinearProgressIndicator(value: _progress), const SizedBox(height: Space.sm)],
                Text(
                  _error ??
                      problem ??
                      'Pages are copied as images, so their text cannot be selected. Your PDF is not changed.',
                  style: text.bodySmall?.copyWith(color: _error != null || problem != null ? c.danger : c.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.sm),
                FilledButton(
                  onPressed: _busy || problem != null ? null : () => _run(parts),
                  child: Text(_busy ? (_mode == SplitMode.split ? 'Splitting…' : 'Extracting…') : action),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _splitOptions(BuildContext context, List<SplitPart> parts) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    return [
      RadioGroup<SplitBy>(
        groupValue: _by,
        onChanged: (v) {
          if (!_busy && v != null) setState(() => _by = v);
        },
        child: Column(
          children: [
            RadioListTile<SplitBy>(
              value: SplitBy.every,
              contentPadding: EdgeInsets.zero,
              title: const Text('Every few pages'),
              subtitle: const Text('Files of the same length'),
            ),
            if (_by == SplitBy.every)
              Row(
                children: [
                  const SizedBox(width: Space.xl),
                  IconButton.outlined(
                    tooltip: 'Fewer pages per file',
                    onPressed: _busy || _every <= 1 ? null : () => setState(() => _every--),
                    icon: const Icon(Icons.remove),
                  ),
                  Expanded(
                    child: Text(
                      '$_every page${_every == 1 ? '' : 's'} per file',
                      textAlign: TextAlign.center,
                      style: text.titleMedium,
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'More pages per file',
                    onPressed: _busy || _every >= _pageCount - 1 ? null : () => setState(() => _every++),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            RadioListTile<SplitBy>(
              value: SplitBy.ranges,
              contentPadding: EdgeInsets.zero,
              title: const Text('By page ranges'),
              subtitle: const Text('One file for each range you type'),
            ),
          ],
        ),
      ),
      if (_by == SplitBy.ranges)
        Padding(
          padding: const EdgeInsets.only(left: Space.xl),
          child: TextField(
            controller: _ranges,
            enabled: !_busy,
            keyboardType: TextInputType.visiblePassword,
            decoration: const InputDecoration(
              labelText: 'Page ranges',
              hintText: 'For example 1-3, 4, 5-',
              border: OutlineInputBorder(),
            ),
          ),
        ),
      if (parts.isNotEmpty) ...[
        const SizedBox(height: Space.lg),
        Text('New files', style: text.titleSmall),
        for (final part in parts)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text('${part.name}.pdf', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              'Page${part.pages.length == 1 ? '' : 's'} ${describePages(part.pages)}',
              style: TextStyle(color: c.muted),
            ),
          ),
      ],
    ];
  }

  List<Widget> _extractOptions(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    final all = _picked.length == _pageCount;
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              _picked.isEmpty
                  ? 'Tick the pages to copy into a new PDF.'
                  : 'Pages ${describePages(_picked)} go into a new PDF.',
              style: text.bodyMedium?.copyWith(color: c.muted),
            ),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    if (all) {
                      _picked.clear();
                    } else {
                      _picked.addAll([for (var n = 1; n <= _pageCount; n++) n]);
                    }
                  }),
            child: Text(all ? 'Clear' : 'Select all'),
          ),
        ],
      ),
      const SizedBox(height: Space.sm),
      Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (var n = 1; n <= _pageCount; n++)
            FilterChip(
              label: Text('$n'),
              tooltip: 'Page $n',
              selected: _picked.contains(n),
              onSelected: _busy ? null : (v) => setState(() => v ? _picked.add(n) : _picked.remove(n)),
            ),
        ],
      ),
    ];
  }

  Widget _result(BuildContext context, List<(File, int)> saved) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    final count = saved.length;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Space.page),
        children: [
          Text(count == 1 ? 'Saved 1 new PDF' : 'Saved $count new PDFs', style: text.headlineSmall),
          const SizedBox(height: Space.xs),
          Text('They are in your Library. ${widget.source.name} is unchanged.', style: text.bodySmall),
          if (_error != null) ...[const SizedBox(height: Space.sm), Text(_error!, style: TextStyle(color: c.danger))],
          const SizedBox(height: Space.md),
          for (final (file, pages) in saved)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(p.basename(file.path), maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '$pages page${pages == 1 ? '' : 's'}'
                '${file.existsSync() ? ' · ${formatFileSize(file.lengthSync())}' : ''}',
              ),
              trailing: IconButton(
                tooltip: 'Send ${p.basename(file.path)}',
                icon: const Icon(Icons.ios_share),
                onPressed: () =>
                    showSendPdfSheet(context, pdfPath: file.path, name: p.basename(file.path), pageCount: pages),
              ),
            ),
          const SizedBox(height: Space.lg),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }
}

/// Choose one saved document to split.
class SplitLibraryPickScreen extends ConsumerWidget {
  const SplitLibraryPickScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final c = LumaColors.of(context);
    final List<SavedDocument> docs = library.value?.documents ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a PDF')),
      body: library.isLoading
          ? const Center(child: CircularProgressIndicator())
          : docs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Text(
                  'Your Library has no documents yet. Save a scan or a PDF first, or choose a file from this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: Space.xxl),
              children: [
                for (final doc in docs)
                  ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: Text(doc.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}'),
                    onTap: () => Navigator.of(context).pop(doc),
                  ),
              ],
            ),
    );
  }
}
