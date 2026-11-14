import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../domain/models.dart';
import '../../domain/ocr.dart';
import '../../domain/plan.dart';
import '../../domain/scan_document.dart';
import '../../imaging/page_jobs.dart';
import '../../imaging/page_renderer.dart';
import '../../pdf_edit/pdf_saver.dart';
import '../../ui/luma_icons.dart';
import '../../ui/upgrade_dialog.dart';
import '../../ui/work_progress.dart';
import '../export/export_delivery.dart';
import '../share/docx_sharer.dart';
import '../word_reader/open_word_document.dart';
import 'ocr_word_figure.dart';
// Deferred, like the Word reader: the Word library loads only when used
// (an on-demand download on Android, built in on iOS).
import 'ocr_word_builder.dart' deferred as builder;

/// One recognised page: the page, its text and where the text sat.
typedef OcrWordInput = ({ScanPage page, String text, OcrLayout? layout});

/// Create Word file after Recognize text (Pro and Gold): builds an editable
/// .docx from the recognised pages with the luma_docx library, then asks
/// where it goes: saved where the user picks, or shared. It can also be
/// opened. The app keeps no copy. Separate from the Basic Word export, which
/// is unchanged.
Future<void> createOcrWordFile(
  BuildContext context,
  WidgetRef ref,
  List<OcrWordInput> pages, {
  ScanDocInfo? info,
}) async {
  if (pages.isEmpty) return;
  if (!await ensurePlan(context, ref, PlanFeature.ocrToWord, what: 'Word file from text') || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final store = ref.read(pageStoreProvider);
  final name = info?.name ?? 'Scan';
  final fileName = ocrWordFileName(name);
  final String path;
  try {
    // The parts of each page that were not read (pictures, drawings) are
    // cut out of the scan, a few pages at a time off the UI thread, with
    // the page count showing and a Cancel button.
    // They are cut from the page image text recognition read, which is
    // already on disk, so no page is drawn again from the full photo.
    final pageImage = ref.read(ocrPageImageProvider);
    final figures = await runWithProgress(
      context,
      title: 'Creating Word file',
      task: (progress) async {
        final images = <RenderedImage?>[];
        for (final p in pages) {
          if (progress.cancelled) throw const PageJobsCancelled();
          images.add(await pageImage(p.page).then<RenderedImage?>((r) => r, onError: (Object _) => null));
        }
        // ocrWordFiguresOf is top-level: the isolates get the pages and
        // nothing of this screen.
        return runPageJobs(
          [for (final (i, p) in pages.indexed) (page: p.page, text: p.text, layout: p.layout, image: images[i])],
          ocrWordFiguresOf,
          onProgress: progress.report,
          isCancelled: () => progress.cancelled,
        );
      },
    );
    if (figures == null) return;
    await builder.loadLibrary();
    final bytes = builder.buildOcrWordFile([
      for (final (i, page) in pages.indexed)
        builder.OcrWordPage(text: page.text, layout: page.layout, figures: figures[i]),
    ], title: name);
    // Made in the Outbox, which keeps it only until it is saved or shared.
    await store.clearOutbox();
    final file = await store.writeExportAtomically(await store.outboxName(fileName), bytes);
    path = file.path;
  } on Object catch (e) {
    debugPrint('OCR to Word failed: $e');
    messenger.showSnackBar(const SnackBar(content: Text('Could not create the Word file. Try again.')));
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Word file ready', style: Theme.of(sheet).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('${p.basename(path)} · ${pages.length} page${pages.length == 1 ? '' : 's'}'),
            const SizedBox(height: 4),
            Text(exportNotKeptNote, style: Theme.of(sheet).textTheme.bodySmall),
            const SizedBox(height: 16),
            ExportDeliveryButtons(
              paths: [path],
              onShare: (button) async {
                try {
                  await ref.read(docxSharerProvider).send(path, origin: shareOriginOf(button));
                } on Object catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('Could not open the share sheet. $e')));
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LumaIcons.article),
              title: const Text('Open'),
              onTap: () {
                Navigator.of(sheet).pop();
                openWordFile(context, path, name: p.basenameWithoutExtension(path));
              },
            ),
            TextButton(onPressed: () => Navigator.of(sheet).pop(), child: const Text('Done')),
          ],
        ),
      ),
    ),
  );
}

/// "Lease text.docx" for a scan called Lease: told apart from the Basic
/// Word export ("Lease.docx").
String ocrWordFileName(String name) {
  final pdf = PdfEditSaver.safeFileName(name);
  return '${pdf.substring(0, pdf.length - '.pdf'.length)} text.docx';
}
