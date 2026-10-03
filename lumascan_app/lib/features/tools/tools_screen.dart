import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/scanner_service.dart';
import '../merge/merge_screen.dart';
import '../pdf_editor/open_pdf.dart';
import '../pdf_editor/pdf_editor_screen.dart';

/// Tools tab: a grid of the tools that work today. A tool that is not built
/// yet is left out, not shown greyed out; compress, split and the rest join
/// as they arrive.
class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = <_Tool>[
      _Tool(Icons.draw_outlined, 'Sign', 'Sign a PDF', () => pickAndEditPdf(context, ref, entry: PdfEditorEntry.sign)),
      _Tool(
        Icons.view_agenda_outlined,
        'Reorder pages',
        'Move or delete pages',
        () => pickAndEditPdf(context, ref, entry: PdfEditorEntry.organize),
      ),
      _Tool(
        Icons.library_add_outlined,
        'Merge PDFs',
        'Combine several PDFs',
        () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MergeScreen())),
      ),
      _Tool(Icons.edit_document, 'Edit a PDF', 'Text, drawings and signature', () => pickAndEditPdf(context, ref)),
      _Tool(
        Icons.photo_library_outlined,
        'Photos to PDF',
        'Turn photos into pages',
        () => scanThenReview(context, ref, ScanSource.gallery),
      ),
    ];
    // One column when text is large, so titles and hints are never cut off.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final large = scale > 1.3;
    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      body: GridView(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xxl),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: large ? 1 : 2,
          mainAxisSpacing: Space.md,
          crossAxisSpacing: Space.md,
          // Padding, icon and gaps, plus room for a two-line title and hint
          // that grows with the text size.
          mainAxisExtent: 104 + 80 * scale,
        ),
        children: [for (final tool in tools) _ToolCard(tool)],
      ),
    );
  }
}

class _Tool {
  const _Tool(this.icon, this.title, this.hint, this.onTap);

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;
}

class _ToolCard extends StatelessWidget {
  const _ToolCard(this.tool);

  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tool.onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.md)),
                child: Icon(tool.icon, color: c.accent),
              ),
              const SizedBox(height: Space.md),
              Text(tool.title, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: Space.xs),
              Text(
                tool.hint,
                style: text.bodySmall?.copyWith(color: c.muted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
