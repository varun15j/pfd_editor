import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/scanner_service.dart';
import '../pdf_editor/open_pdf.dart';

/// The centre Create button's sheet: every way to start a document in one
/// place (US-03.1). Each option closes the sheet before it starts.
Future<void> showCreateSheet(BuildContext context, WidgetRef ref) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) => CreateSheet(
    onPick: (run) {
      Navigator.pop(sheet);
      run(context, ref);
    },
  ),
);

typedef CreateAction = Future<void> Function(BuildContext context, WidgetRef ref);

class CreateSheet extends StatelessWidget {
  const CreateSheet({super.key, required this.onPick});

  final void Function(CreateAction run) onPick;

  static final options = <(IconData, String, String, CreateAction)>[
    (
      Icons.document_scanner_outlined,
      'Scan document',
      'Use the camera; edges are found for you',
      (context, ref) => scanThenReview(context, ref, ScanSource.camera),
    ),
    (
      Icons.photo_library_outlined,
      'Import photos',
      'Turn photos of pages into a PDF',
      (context, ref) => scanThenReview(context, ref, ScanSource.gallery),
    ),
    (Icons.edit_document, 'Edit a PDF', 'Add text, drawings or a signature', pickAndEditPdf),
  ];

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
              child: Semantics(header: true, child: Text('Create', style: text.titleLarge)),
            ),
            for (final (icon, title, subtitle, run) in options)
              ListTile(
                minVerticalPadding: Space.md,
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.md)),
                  child: Icon(icon, color: c.accent),
                ),
                title: Text(title),
                subtitle: Text(subtitle),
                onTap: () => onPick(run),
              ),
          ],
        ),
      ),
    );
  }
}
