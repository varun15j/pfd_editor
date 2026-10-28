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
import '../split/split_actions.dart';
import '../table/table_to_excel.dart';
import '../word/word_actions.dart';
import '../../ui/luma_icons.dart';

/// Tools tab, laid out as Screens 3 and 4 of the UI/UX screenshots:
/// "Shortcuts" with Scan, Process Files and PDF Tools sections, three square
/// tiles to a row with the name under each, drawn as tinted icon squares. A tool that is not built yet is
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
          _Tool(LumaIcons.toolIdCard, 'ID Card', () => openIdCardStudio(context)),
          _Tool(LumaIcons.toolScanDocs, 'Scan Docs', () => scan(CameraMode.docs)),
          _Tool(LumaIcons.toolBook, 'Book', () => scan(CameraMode.book)),
          _Tool(LumaIcons.toolQr, 'QR Code', () => scan(CameraMode.qr)),
          _Tool(LumaIcons.toolText, 'To Text', () => scan(CameraMode.text)),
          _Tool(
            LumaIcons.toolTable,
            'Table to Excel',
            () => scanTableToExcel(context, ref),
            badge: ref.watch(planIncludesProvider(PlanFeature.tableToExcel)) ? null : 'Gold',
          ),
        ],
      ),
      (
        'Process Files',
        [
          _Tool(LumaIcons.toolPhotos, 'Photos to PDF', () => scanThenReview(context, ref, ScanSource.gallery)),
          _Tool(
            LumaIcons.toolPdfToWord,
            'PDF to Word',
            () => pickPdfToWord(context, ref),
            badge: ref.watch(planIncludesProvider(PlanFeature.word)) ? null : 'Pro',
          ),
          _Tool(LumaIcons.toolWordToPdf, 'Word to PDF', () => importWordFile(context, ref)),
          _Tool(
            LumaIcons.toolMerge,
            'Merge PDFs',
            () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MergeScreen())),
          ),
          _Tool(
            LumaIcons.toolSplit,
            'Split PDF',
            () => pickPdfToSplit(context, ref),
            badge: ref.watch(planIncludesProvider(PlanFeature.splitPdf)) ? null : 'Pro',
          ),
        ],
      ),
      (
        'PDF Tools',
        [
          _Tool(LumaIcons.toolSign, 'Sign', () => pickAndEditPdf(context, ref, entry: PdfEditorEntry.sign)),
          _Tool(LumaIcons.toolEditPdf, 'Edit a PDF', () => pickAndEditPdf(context, ref)),
          _Tool(
            LumaIcons.toolReorder,
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
          for (final (index, (title, tools)) in sections.indexed) ...[
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
                  children: [
                    for (final tool in tools)
                      SizedBox(
                        width: width,
                        child: _ToolTile(tool, tint: _ToolTint.forSection(index)),
                      ),
                  ],
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

  final LumaDuotone icon;
  final String title;
  final VoidCallback onTap;

  /// Shown on the tile when the tool needs a plan the user does not have.
  final String? badge;
}

/// Tint of a tool tile: one colour per section, the way CamScanner-style
/// tool grids group their tools.
class _ToolTint {
  const _ToolTint(this.dark, this.light);

  /// Background and icon colour on the dark theme, then on the light one.
  final (Color, Color) dark;
  final (Color, Color) light;

  static const _tints = [
    _ToolTint((Color(0xFF173456), Color(0xFF8CC2FF)), (Color(0xFFE2EDFC), Color(0xFF1C5BB8))), // Scan: blue
    _ToolTint((Color(0xFF163D2A), Color(0xFF7FE0A6)), (Color(0xFFDDF4E6), Color(0xFF167A3F))), // Process Files: green
    _ToolTint((Color(0xFF45330F), Color(0xFFFFD27A)), (Color(0xFFFCEFD4), Color(0xFF8A5A00))), // PDF Tools: amber
  ];

  static _ToolTint forSection(int index) => _tints[index % _tints.length];
}

/// The tool's two-tone icon on a tinted rounded square with its name under
/// it, in the CamScanner-style tools grid.
class _ToolTile extends StatelessWidget {
  const _ToolTile(this.tool, {required this.tint});

  final _Tool tool;
  final _ToolTint tint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (background, foreground) = Theme.of(context).brightness == Brightness.dark ? tint.dark : tint.light;
    return Semantics(
      button: true,
      label: tool.title,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: tool.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(18)),
                    child: DuotoneIcon(tool.icon, color: foreground, size: 32),
                  ),
                  if (tool.badge != null)
                    Positioned(
                      top: -Space.sm,
                      right: -Space.lg,
                      child: PremiumBadge(label: tool.badge!),
                    ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(
                tool.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
