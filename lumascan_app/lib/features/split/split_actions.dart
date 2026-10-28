import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/app_info.dart';
import '../../domain/library.dart';
import '../../domain/plan.dart';
import '../../ui/upgrade_dialog.dart';
import '../merge/pdf_inspector.dart';
import '../merge/pdf_picker.dart';
import 'split_screen.dart';
import '../../ui/luma_icons.dart';

/// Library menu > Split or extract pages for a saved PDF.
Future<void> splitDocument(BuildContext context, WidgetRef ref, SavedDocument doc) async {
  if (!await _ensureSplitPlan(context, ref) || !context.mounted) return;
  if (!File(doc.pdfPath).existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${doc.name} is no longer on this device.')));
    return;
  }
  await _open(context, ref, name: doc.name, path: doc.pdfPath);
}

/// Tools > Split PDF: choose a PDF from the Library or the device, then
/// split it or extract pages from it.
Future<void> pickPdfToSplit(BuildContext context, WidgetRef ref) async {
  if (!await _ensureSplitPlan(context, ref) || !context.mounted) return;
  final fromLibrary = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(LumaIcons.folder),
            title: const Text('From Library'),
            subtitle: const Text('A PDF you saved in $appName'),
            onTap: () => Navigator.pop(sheet, true),
          ),
          ListTile(
            leading: const Icon(LumaIcons.device),
            title: const Text('From this device'),
            subtitle: const Text('Choose a PDF file'),
            onTap: () => Navigator.pop(sheet, false),
          ),
        ],
      ),
    ),
  );
  if (fromLibrary == null || !context.mounted) return;
  if (fromLibrary) {
    final doc = await Navigator.of(context)
        .push<SavedDocument>(MaterialPageRoute(builder: (_) => const SplitLibraryPickScreen()));
    if (doc != null && context.mounted) await _open(context, ref, name: doc.name, path: doc.pdfPath);
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final List<PickedPdf> picked;
  try {
    picked = await ref.read(pdfPickerProvider).pick();
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open the file picker ($e)')));
    return;
  }
  if (picked.isEmpty || !context.mounted) return;
  final pdf = picked.first;
  try {
    await _open(context, ref, name: p.basenameWithoutExtension(pdf.name), path: pdf.path);
  } finally {
    // The copy made for the picker is only needed while splitting.
    for (final f in picked) {
      try {
        File(f.path).deleteSync();
      } on Object {
        // Already gone.
      }
    }
  }
}

/// Counts the pages, turns away a locked or broken PDF, and opens the split
/// screen until the user leaves it.
Future<void> _open(BuildContext context, WidgetRef ref, {required String name, required String path}) async {
  final messenger = ScaffoldMessenger.of(context);
  final info = await ref.read(pdfInspectorProvider).inspect(path);
  final pageCount = info.pageCount;
  if (pageCount == null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          info.problem == PdfProblem.locked
              ? '$name is locked with a password. Unlock it first, then split it.'
              : '$name could not be read as a PDF.',
        ),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => SplitScreen(
        source: SplitSource(name: name, path: path, pageCount: pageCount),
      ),
    ),
  );
}

/// Split and extract are part of Pro and Gold. On Basic this shows the
/// upgrade pop-up and returns false.
Future<bool> _ensureSplitPlan(BuildContext context, WidgetRef ref) =>
    ensurePlan(context, ref, PlanFeature.splitPdf, what: 'Split PDF and extract pages');
