import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:luma_docx/luma_docx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/motion.dart';
import '../../ui/luma_icons.dart';

/// Opens and reads a Word (.docx) file with the luma_docx library: pages as
/// in Word or text that fits the screen, headings to jump to, comments,
/// tracked changes and document details. Pro and Gold.
///
/// This file is loaded with a deferred import (see open_word_document.dart),
/// so on Android it can be delivered as an on-demand download.
class WordViewerScreen extends StatefulWidget {
  const WordViewerScreen({super.key, required this.path, required this.name});

  /// The .docx file on this device.
  final String path;
  final String name;

  @override
  State<WordViewerScreen> createState() => _WordViewerScreenState();
}

class _WordViewerScreenState extends State<WordViewerScreen> {
  final _controller = WordViewController();
  late final Future<WordDocument> _document = _read();
  var _options = const WordViewOptions();

  Future<WordDocument> _read() async {
    final path = widget.path;
    // Reading a long file takes a moment; keep the screen responsive.
    return Isolate.run(() => WordReader.read(File(path).readAsBytesSync()));
  }

  void _set(WordViewOptions o) => setState(() => _options = o);

  Future<void> _openLink(WordLink link) async {
    final url = link.url;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final open = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Open this link?', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (link.tooltip != null) Text(link.tooltip!, style: Theme.of(context).textTheme.bodyMedium),
              SelectableText(url, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(LumaIcons.openExternal),
                label: const Text('Open'),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (open == true) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showText(String title, String body, {String? subtitle}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              SelectableText(body),
            ],
          ),
        ),
      ),
    );
  }

  String _date(DateTime? d) => d == null ? '' : '${d.day}/${d.month}/${d.year}';

  void _showComment(WordDocument doc, WordComment c) {
    final replies = doc.comments.where((r) => r.parentId == c.id).toList();
    final body = StringBuffer(c.text);
    for (final r in replies) {
      body.write('\n\n${r.author ?? 'Reply'}: ${r.text}');
    }
    _showText(
      c.author ?? 'Comment',
      body.toString(),
      subtitle: [_date(c.date), if (c.resolved) 'Resolved'].where((s) => s.isNotEmpty).join(' · '),
    );
  }

  void _showOutline(WordDocument doc) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => ListView(
          controller: scroll,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Headings', style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final h in doc.headings)
              ListTile(
                dense: true,
                contentPadding: EdgeInsetsDirectional.only(start: 20.0 + 16 * (h.level > 0 ? h.level - 1 : 0), end: 20),
                title: Text(h.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(sheet);
                  _controller.jumpToParagraph(h.paragraphIndex);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showComments(WordDocument doc) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        builder: (context, scroll) => ListView(
          controller: scroll,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Comments', style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final c in doc.comments)
              ListTile(
                contentPadding: EdgeInsetsDirectional.only(start: c.parentId == null ? 20 : 44, end: 20),
                title: Text(c.text),
                subtitle: Text(
                  [c.author ?? '', _date(c.date), if (c.resolved) 'Resolved'].where((s) => s.isNotEmpty).join(' · '),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showInfo(WordDocument doc) {
    final p = doc.properties;
    final rows = <(String, String?)>[
      ('Title', p.title),
      ('Subject', p.subject),
      ('Author', p.author),
      ('Keywords', p.keywords),
      ('Category', p.category),
      ('Description', p.description),
      ('Last saved by', p.lastModifiedBy),
      ('Created', _date(p.created)),
      ('Modified', _date(p.modified)),
      ('Pages (as saved by Word)', p.pages?.toString()),
      ('Words', p.words?.toString()),
      ('Made with', p.application),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Document details', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final (label, value) in rows)
                if (value != null && value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 120, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
                        Expanded(child: Text(value)),
                      ],
                    ),
                  ),
              if (doc.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Some parts could not be shown', style: Theme.of(context).textTheme.titleSmall),
                for (final w in doc.warnings) Text(w, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    return FutureBuilder<WordDocument>(
      future: _document,
      builder: (context, snap) {
        final doc = snap.data;
        final pages = _options.layout == WordLayout.pages;
        return Scaffold(
          appBar: AppBar(
            title: Text(doc?.properties.title?.isNotEmpty == true ? doc!.properties.title! : widget.name, overflow: TextOverflow.ellipsis),
            actions: doc == null
                ? null
                : [
                    IconButton(
                      tooltip: pages ? 'Fit text to screen' : 'Show pages',
                      icon: Icon(pages ? LumaIcons.text : LumaIcons.pageView),
                      onPressed: () => _set(_options.copyWith(layout: pages ? WordLayout.reflow : WordLayout.pages)),
                    ),
                    if (doc.headings.isNotEmpty)
                      IconButton(tooltip: 'Headings', icon: const Icon(LumaIcons.listView), onPressed: () => _showOutline(doc)),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      icon: const Icon(LumaIcons.more),
                      onSelected: (v) {
                        switch (v) {
                          case 'markup':
                            _set(_options.copyWith(showMarkup: !_options.showMarkup));
                          case 'hidden':
                            _set(_options.copyWith(showHidden: !_options.showHidden));
                          case 'bigger':
                            _set(_options.copyWith(textScale: (_options.textScale + 0.15).clamp(0.7, 2.5)));
                          case 'smaller':
                            _set(_options.copyWith(textScale: (_options.textScale - 0.15).clamp(0.7, 2.5)));
                          case 'comments':
                            _showComments(doc);
                          case 'info':
                            _showInfo(doc);
                        }
                      },
                      itemBuilder: (context) => [
                        CheckedPopupMenuItem(value: 'markup', checked: _options.showMarkup, child: const Text('Show tracked changes')),
                        CheckedPopupMenuItem(value: 'hidden', checked: _options.showHidden, child: const Text('Show hidden text')),
                        if (!pages) const PopupMenuItem(value: 'bigger', child: Text('Bigger text')),
                        if (!pages) const PopupMenuItem(value: 'smaller', child: Text('Smaller text')),
                        if (doc.comments.isNotEmpty) PopupMenuItem(value: 'comments', child: Text('Comments (${doc.comments.length})')),
                        const PopupMenuItem(value: 'info', child: Text('Document details')),
                      ],
                    ),
                  ],
          ),
          body: switch (snap) {
            AsyncSnapshot(hasError: true) => _ReadError(name: widget.name, error: snap.error),
            AsyncSnapshot(hasData: true) => AnimatedSwitcher(
              duration: motion.duration(const Duration(milliseconds: 200)),
              child: WordDocumentView(
                key: ValueKey(_options.layout),
                document: doc!,
                options: _options,
                controller: _controller,
                jumpDuration: motion.duration(const Duration(milliseconds: 300)),
                onLinkTap: _openLink,
                onNoteTap: (n) => _showText(
                  n.kind == WordNoteKind.footnote ? 'Footnote ${n.label}' : 'Endnote ${n.label}',
                  n.blocks.map((b) {
                    final out = StringBuffer();
                    b.writePlainText(out);
                    return out.toString().trim();
                  }).join('\n'),
                ),
                onCommentTap: (c) => _showComment(doc, c),
              ),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        );
      },
    );
  }
}

class _ReadError extends StatelessWidget {
  const _ReadError({required this.name, this.error});

  final String name;
  final Object? error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LumaIcons.error, size: 40),
          const SizedBox(height: 12),
          Text('$name could not be opened', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            error is FormatException ? (error! as FormatException).message : 'The file may be damaged or not a .docx Word file.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
