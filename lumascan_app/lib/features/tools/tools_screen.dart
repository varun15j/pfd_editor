import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/scanner_service.dart';
import '../pdf_editor/open_pdf.dart';

/// Tools tab. Lists only tools that work today; merge, compress and the rest
/// join as they are built (G1 in the UI/UX plan).
class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xxl),
        children: [
          _ToolTile(
            icon: Icons.edit_document,
            title: 'Edit and sign a PDF',
            subtitle: 'Add text, drawings and a signature; reorder or delete pages',
            onTap: () => pickAndEditPdf(context, ref),
          ),
          const SizedBox(height: Space.md),
          _ToolTile(
            icon: Icons.photo_library_outlined,
            title: 'Photos to PDF',
            subtitle: 'Turn photos of pages into one PDF',
            onTap: () => scanThenReview(context, ref, ScanSource.gallery),
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minVerticalPadding: Space.md,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xs),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.md)),
          child: Icon(icon, color: c.accent),
        ),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right, color: c.muted),
        onTap: onTap,
      ),
    );
  }
}
