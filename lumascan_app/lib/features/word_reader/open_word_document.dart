import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/plan.dart';
import '../../ui/upgrade_dialog.dart';
// Deferred: the Word library is loaded only when it is first used. On
// Android this lets it ship as an on-demand download (Play Feature
// Delivery); on iOS and in debug builds it is part of the app and loads at once.
import 'word_viewer_screen.dart' deferred as viewer;

/// Tools > Open Word: Pro and Gold. Lets the user pick a .docx file and
/// reads it in the Word viewer. The existing Word to PDF tool is separate
/// and stays on every plan.
Future<void> openWordDocument(BuildContext context, WidgetRef ref) async {
  if (!await ensurePlan(context, ref, PlanFeature.wordReader, what: 'Open Word files')) return;
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final PlatformFile? picked;
  try {
    picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['docx']);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open the file picker ($e)')));
    return;
  }
  if (picked == null || !context.mounted) return;
  final chosen = picked;
  // Copied into app storage so it stays readable while the viewer is open.
  final String copy;
  try {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'word_reader'));
    await dir.create(recursive: true);
    copy = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}.docx');
    await chosen.xFile.saveTo(copy);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not read ${chosen.name} ($e)')));
    return;
  }
  if (!context.mounted) return;
  await openWordFile(context, copy, name: p.basenameWithoutExtension(chosen.name));
}

/// Opens a .docx file already on the device in the Word viewer, loading
/// the Word library first if it is not loaded yet.
Future<void> openWordFile(BuildContext context, String path, {required String name}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    await viewer.loadLibrary();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('The Word reader could not be downloaded. Check your connection and try again ($e)')));
    return;
  }
  await navigator.push(MaterialPageRoute<void>(builder: (_) => viewer.WordViewerScreen(path: path, name: name)));
}
