import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../domain/models.dart';
import '../../domain/ocr.dart';
import '../../domain/plan.dart';
import '../../domain/saved_export.dart';
import '../../domain/scan_document.dart';
import '../../imaging/page_jobs.dart';
import '../../imaging/page_renderer.dart';
import '../../pdf_edit/pdf_saver.dart';
import '../../ui/luma_icons.dart';
import '../../ui/upgrade_dialog.dart';
import '../../ui/work_progress.dart';
import '../export/saved_exports.dart';
import '../share/docx_sharer.dart';
import '../word_reader/open_word_document.dart';
import 'ocr_word_figure.dart';
// Deferred, like the Word reader: the Word library loads only when used
// (an on-demand download on Android, built in on iOS).
import 'ocr_word_builder.dart' deferred as builder;

/// One recognised page: the page, its text and where the text sat.
typedef OcrWordInput = ({ScanPage page, String text, OcrLayout? layout});

/// Create Word file after Recognize text (Pro and Gold): builds an editable
/// .docx from the recognised pages with the luma_docx library and keeps it
/// in the Saved folder (Library > Saved, with the other Word files), one
/// per scan: making it again replaces it, and an unchanged scan reuses it.
/// Then offers Open and Share. Separate from the Basic Word export, which
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
  final savedExports = ref.read(savedExportsProvider.notifier);
  final name = info?.name ?? 'Scan';
  final fileName = ocrWordFileName(name);
  final docKey = info == null ? null : scanDocKey(info);
  final fingerprint = exportFingerprint(
    [for (final page in pages) page.page],
    fileName: fileName,
    options: {
      'kind': 'ocrWord',
      'text': [for (final page in pages) page.text],
      // Files made before pictures were added are made again.
      'pictures': 1,
    },
  );
  final String path;
  try {
    final plan = docKey == null
        ? null
        : await savedExports.plan(
            docKey: docKey,
            format: ExportFormat.ocrWord,
            fingerprint: fingerprint,
            fileName: fileName,
          );
    if (plan is ExportReuse) {
      path = plan.saved.path;
    } else {
      // The parts of each page that were not read (pictures, drawings) are
      // cut out of the scan, a few pages at a time off the UI thread, with
      // the page count showing and a Cancel button.
      // They are cut from the page image text recognition read, which is
      // already on disk, so no page is drawn again from the full photo.
      if (!context.mounted) return;
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
          return runPageJobs(
            [for (final (i, p) in pages.indexed) (p, images[i])],
            ((OcrWordInput, RenderedImage?) job) =>
                ocrWordFigures(job.$1.page, text: job.$1.text, layout: job.$1.layout, image: job.$2),
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
      final target = plan is ExportNew ? plan.fileName : await store.freeExportName(fileName);
      if (plan is ExportNew) await store.savedDir;
      final file = await store.writeExportAtomically(target, bytes);
      path = file.path;
      if (docKey != null) {
        await savedExports.record(
          SavedExport(
            docKey: docKey,
            format: ExportFormat.ocrWord,
            path: path,
            fingerprint: fingerprint,
            name: name,
            pageCount: pages.length,
            sizeBytes: File(path).lengthSync(),
            exportedAt: DateTime.now(),
          ),
          previous: plan is ExportNew ? plan.previous : null,
        );
      }
    }
  } on Object catch (e) {
    debugPrint('OCR to Word failed: $e');
    messenger.showSnackBar(const SnackBar(content: Text('Could not create the Word file. Try again.')));
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
            subtitle: Text(
              '${p.basename(path)} · ${pages.length} page${pages.length == 1 ? '' : 's'}\n'
              'Kept in Library > Saved',
            ),
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
              try {
                await ref.read(docxSharerProvider).send(path);
              } on Object catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('Could not open the share sheet. $e')));
              }
            },
          ),
        ],
      ),
    ),
  );
}

/// "Lease text.docx" for a scan called Lease: told apart from the Basic
/// Word export ("Lease.docx") in the Saved folder.
String ocrWordFileName(String name) {
  final pdf = PdfEditSaver.safeFileName(name);
  return '${pdf.substring(0, pdf.length - '.pdf'.length)} text.docx';
}
