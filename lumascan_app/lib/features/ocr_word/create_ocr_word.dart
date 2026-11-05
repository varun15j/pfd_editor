import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../domain/ocr.dart';
import '../../domain/plan.dart';
import '../../ui/luma_icons.dart';
import '../../ui/upgrade_dialog.dart';
import '../word_reader/open_word_document.dart';
// Deferred, like the Word reader: the Word library loads only when used
// (an on-demand download on Android, built in on iOS).
import 'ocr_word_builder.dart' deferred as builder;

/// The text and layout of one recognised page, in document order.
typedef OcrWordInput = ({String text, OcrLayout? layout});

/// Create Word file after Recognize text (Pro and Gold): builds an editable
/// .docx from the recognised pages with the luma_docx library, saves it in
/// the exports folder and offers Open and Share. Separate from the Basic
/// Word export, which is unchanged.
Future<void> createOcrWordFile(BuildContext context, WidgetRef ref, List<OcrWordInput> pages) async {
  if (pages.isEmpty) return;
  if (!await ensurePlan(context, ref, PlanFeature.ocrToWord, what: 'Word file from text') || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final store = ref.read(pageStoreProvider);
  final String path;
  try {
    await builder.loadLibrary();
    final bytes = builder.buildOcrWordFile([
      for (final page in pages) builder.OcrWordPage(text: page.text, layout: page.layout),
    ]);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'Text_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.docx';
    path = (await store.writeExportAtomically(await store.freeExportName(name), bytes)).path;
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not create the Word file. Try again. ($e)')));
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('Word file ready', style: Theme.of(sheet).textTheme.titleMedium),
            subtitle: Text('${p.basename(path)} · ${pages.length} page${pages.length == 1 ? '' : 's'}'),
          ),
          ListTile(
            leading: const Icon(LumaIcons.article),
            title: const Text('Open'),
            onTap: () {
              Navigator.of(sheet).pop();
              openWordFile(context, path, name: p.basenameWithoutExtension(path));
            },
          ),
          ListTile(
            leading: const Icon(LumaIcons.share),
            title: const Text('Share'),
            onTap: () async {
              Navigator.of(sheet).pop();
              await SharePlus.instance.share(
                ShareParams(
                  files: [
                    XFile(path, mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}
