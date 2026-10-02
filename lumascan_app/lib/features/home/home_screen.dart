import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/scanner_service.dart';
import '../pages/scan_controller.dart';
import '../pdf_editor/open_pdf.dart';

/// Home: start something new or pick up the draft (LumaScan v2 screen 1).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.onOpenLibrary});

  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanControllerProvider);
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    final busy = state.busy;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.xl, Space.page, Space.xxl),
        children: [
          Semantics(header: true, child: Text('LumaScan', style: text.headlineMedium)),
          const SizedBox(height: Space.xs),
          Text('Scan something new', style: text.bodyLarge?.copyWith(color: c.muted)),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.document_scanner_outlined,
                  label: 'Scan',
                  primary: true,
                  onTap: busy ? null : () => scanThenReview(context, ref, ScanSource.camera),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: _QuickAction(
                  icon: Icons.photo_library_outlined,
                  label: 'Import',
                  onTap: busy ? null : () => scanThenReview(context, ref, ScanSource.gallery),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: _QuickAction(
                  icon: Icons.edit_document,
                  label: 'Edit PDF',
                  onTap: busy ? null : () => pickAndEditPdf(context, ref),
                ),
              ),
            ],
          ),
          if (busy) ...[
            const SizedBox(height: Space.lg),
            const LinearProgressIndicator(semanticsLabel: 'Adding pages'),
          ],
          const SizedBox(height: Space.xxl),
          Row(
            children: [
              Expanded(
                child: Semantics(header: true, child: Text('Recent', style: text.titleMedium)),
              ),
              TextButton(onPressed: onOpenLibrary, child: const Text('See all')),
            ],
          ),
          const SizedBox(height: Space.sm),
          if (state.pages.isNotEmpty)
            _DraftCard(pageCount: state.pages.length, onTap: () => openDraft(context))
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Row(
                  children: [
                    Icon(Icons.history, color: c.muted),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text('Your scans will show up here.', style: text.bodyMedium?.copyWith(color: c.muted)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap, this.primary = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final fg = primary ? c.onAccent : c.ink;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: primary ? c.accent : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: primary ? BorderSide.none : BorderSide(color: c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.lg, horizontal: Space.sm),
            child: Column(
              children: [
                Icon(icon, size: 28, color: primary ? fg : c.accent),
                const SizedBox(height: Space.sm),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({required this.pageCount, required this.onTap});

  final int pageCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    return Card(
      color: c.surfaceRaised,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Row(
            children: [
              Icon(Icons.layers_outlined, color: c.accent, size: 32),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Continue draft', style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text('$pageCount page${pageCount == 1 ? '' : 's'} not saved yet', style: text.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}
