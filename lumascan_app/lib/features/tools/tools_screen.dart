import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/plan.dart';
import '../../domain/scanner_service.dart';
import '../../ui/state_views.dart';
import '../batch_capture/camera_mode.dart';
import '../id_card/id_card_type_screen.dart';
import '../merge/merge_screen.dart';
import '../pdf_editor/open_pdf.dart';
import '../pdf_editor/pdf_editor_screen.dart';
import '../word/word_actions.dart';

/// Tools tab, laid out as Screens 3 and 4 of the UI/UX screenshots:
/// "Shortcuts" with Scan, Process Files and PDF Tools sections, three square
/// tiles to a row with the name under each. A tool that is not built yet is
/// left out, not shown greyed out.
class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void scan(CameraMode mode) => scanThenReview(context, ref, ScanSource.camera, mode: mode);
    final sections = <(String, List<_Tool>)>[
      (
        'Scan',
        [
          _Tool(Icons.badge_outlined, 'ID Card', () => openIdCardStudio(context)),
          _Tool(Icons.receipt_long_outlined, 'Scan Docs', () => scan(CameraMode.docs)),
          _Tool(Icons.menu_book_outlined, 'Book', () => scan(CameraMode.book)),
          _Tool(Icons.qr_code_scanner, 'QR Code', () => scan(CameraMode.qr)),
          _Tool(Icons.text_fields, 'To Text', () => scan(CameraMode.text)),
        ],
      ),
      (
        'Process Files',
        [
          _Tool(Icons.photo_library_outlined, 'Photos to PDF', () => scanThenReview(context, ref, ScanSource.gallery)),
          _Tool(
            Icons.description_outlined,
            'PDF to Word',
            () => pickPdfToWord(context, ref),
            badge: ref.watch(planIncludesProvider(PlanFeature.word)) ? null : 'Pro',
          ),
          _Tool(Icons.picture_as_pdf_outlined, 'Word to PDF', () => importWordFile(context, ref)),
          _Tool(
            Icons.library_add_outlined,
            'Merge PDFs',
            () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MergeScreen())),
          ),
        ],
      ),
      (
        'PDF Tools',
        [
          _Tool(Icons.draw_outlined, 'Sign', () => pickAndEditPdf(context, ref, entry: PdfEditorEntry.sign)),
          _Tool(Icons.edit_document, 'Edit a PDF', () => pickAndEditPdf(context, ref)),
          _Tool(
            Icons.view_agenda_outlined,
            'Reorder pages',
            () => pickAndEditPdf(context, ref, entry: PdfEditorEntry.organize),
          ),
        ],
      ),
    ];
    final text = Theme.of(context).textTheme;
    // Two to a row when text is large, so names are never cut off.
    final large = MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3;
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Shortcuts')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xxl * 2),
        children: [
          for (final (title, tools) in sections) ...[
            Padding(
              padding: const EdgeInsets.only(top: Space.lg, bottom: Space.md),
              child: Semantics(header: true, child: Text(title, style: text.headlineSmall)),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = large ? 2 : 3;
                final width = (constraints.maxWidth - Space.md * (columns - 1)) / columns;
                return Wrap(
                  spacing: Space.md,
                  runSpacing: Space.lg,
                  children: [for (final tool in tools) SizedBox(width: width, child: _ToolTile(tool))],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _Tool {
  const _Tool(this.icon, this.title, this.onTap, {this.badge});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  /// Shown on the tile when the tool needs a plan the user does not have.
  final String? badge;
}

/// A square picture of the tool with its name under it (Screen 3). The
/// picture is a light panel with the tool's icon in the green circle the
/// screenshots use.
class _ToolTile extends StatelessWidget {
  const _ToolTile(this.tool);

  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: tool.title,
      excludeSemantics: true,
      child: InkWell(
        onTap: tool.onTap,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 0.9,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  border: Border.all(color: c.line),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (tool.badge != null)
                      Positioned(
                        top: Space.sm,
                        right: Space.sm,
                        child: PremiumBadge(label: tool.badge!),
                      ),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: LumaColors.scan,
                        shape: BoxShape.circle,
                        border: Border.all(color: LumaColors.onScan, width: 2),
                      ),
                      child: Icon(tool.icon, color: LumaColors.onScan, size: 28),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            Text(
              tool.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
