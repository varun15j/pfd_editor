import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/plan.dart';
import '../../domain/scanner_service.dart';
import '../../ui/state_views.dart';
import '../merge/merge_screen.dart';
import '../pdf_editor/open_pdf.dart';
import '../pdf_editor/pdf_editor_screen.dart';
import '../word/word_actions.dart';

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
        Icons.description_outlined,
        'PDF to Word',
        'Make an editable .docx',
        () => pickPdfToWord(context, ref),
        // Shown to everyone; on Basic it opens the upgrade pop-up.
        badge: ref.watch(planIncludesProvider(PlanFeature.word)) ? null : 'Pro',
      ),
      _Tool(Icons.picture_as_pdf_outlined, 'Word to PDF', 'Open a .docx as a PDF', () => importWordFile(context, ref)),
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
          mainAxisExtent: 88 + 72 * scale,
        ),
        children: [for (final tool in tools) _ToolCard(tool)],
      ),
    );
  }
}

class _Tool {
  const _Tool(this.icon, this.title, this.hint, this.onTap, {this.badge});

  final IconData icon;

  /// The plan a locked tool needs, shown next to its icon.
  final String? badge;
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
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      borderRadius: BorderRadius.circular(ControlMetrics.radius),
                    ),
                    child: Icon(tool.icon, color: c.accent, size: ControlMetrics.icon),
                  ),
                  if (tool.badge != null) ...[const Spacer(), PremiumBadge(label: tool.badge!)],
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(tool.title, style: text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
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
