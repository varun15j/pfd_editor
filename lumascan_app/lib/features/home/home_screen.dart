import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/scanner_service.dart';
import '../library/document_tile.dart';
import '../library/library_actions.dart';
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
    final recent = ref.watch(visibleDocumentsProvider).take(10).toList();
    final dismissed = ref.watch(uiPrefsProvider.select((p) => p.dismissedCards));
    final discovery = [
      for (final card in _DiscoveryCard.all)
        if (!dismissed.contains(card.id)) card,
    ];

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
          for (final card in discovery) ...[
            const SizedBox(height: Space.lg),
            _DiscoveryCardView(
              card: card,
              onTap: busy ? null : () => card.run(context, ref),
              onDismiss: () => ref.read(uiPrefsProvider.notifier).dismissCard(card.id),
            ),
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
          if (state.pages.isNotEmpty) ...[
            _DraftCard(pageCount: state.pages.length, onTap: () => openDraft(context)),
            const SizedBox(height: Space.sm),
          ],
          if (recent.isNotEmpty)
            SizedBox(
              height:
                  RecentDocumentCard.width * 1.1 + MediaQuery.textScalerOf(context).scale(44) + Space.lg + Space.xs,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: recent.length,
                separatorBuilder: (_, _) => const SizedBox(width: Space.md),
                itemBuilder: (_, i) =>
                    RecentDocumentCard(document: recent[i], onTap: () => openDocument(context, ref, recent[i])),
              ),
            ),
          if (state.pages.isEmpty && recent.isEmpty)
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

/// A dismissible tip on Home that points to a feature (B1 discovery cards).
/// A card for Merge PDFs joins this list once that tool exists (G1); tools
/// that are not built yet are never advertised.
class _DiscoveryCard {
  const _DiscoveryCard({
    required this.id,
    required this.icon,
    required this.title,
    required this.message,
    required this.run,
  });

  final String id;
  final IconData icon;
  final String title;
  final String message;
  final void Function(BuildContext context, WidgetRef ref) run;

  static final all = [
    _DiscoveryCard(
      id: 'photos_to_pdf',
      icon: Icons.photo_library_outlined,
      title: 'Turn photos into a PDF',
      message: 'Pick photos of documents you already took.',
      run: (context, ref) => scanThenReview(context, ref, ScanSource.gallery),
    ),
  ];
}

class _DiscoveryCardView extends StatelessWidget {
  const _DiscoveryCardView({required this.card, required this.onTap, required this.onDismiss});

  final _DiscoveryCard card;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    return Card(
      color: c.accentSoft,
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: '${card.title}. ${card.message}',
              excludeSemantics: true,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, 0, Space.lg),
                  child: Row(
                    children: [
                      Icon(card.icon, color: c.accent, size: 28),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(card.title, style: text.titleMedium),
                            const SizedBox(height: 2),
                            Text(card.message, style: text.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(tooltip: 'Dismiss ${card.title}', icon: const Icon(Icons.close), onPressed: onDismiss),
        ],
      ),
    );
  }
}
