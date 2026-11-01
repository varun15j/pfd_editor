import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../app/preferences.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/scanner_service.dart';
import '../../domain/ui_prefs.dart';
import '../capture/create_sheet.dart';
import '../library/library_actions.dart';
import '../library/library_query_sheets.dart';
import '../library/library_screen.dart';
import '../settings/settings_screen.dart';
import '../pages/scan_controller.dart';
import 'home_documents.dart';
import '../../ui/luma_icons.dart';

/// Docs tab, laid out as Screen 1 of the UI/UX screenshots: the avatar
/// (Settings), the app name and Search at the top, then "All docs(N)" with
/// Create, Sort, Grid and Select, then every scan and PDF. Search, the
/// folder picker and Select open the Library, where those tools live.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _openLibrary(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LibraryScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanControllerProvider);
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    final busy = state.busy;
    // Every scan is kept as page images, so it is listed with the saved PDFs.
    final docs = homeDocuments(state, ref.watch(visibleDocumentsProvider));
    final grid = ref.watch(uiPrefsProvider.select((p) => p.homeView)) == LibraryView.grid;
    final dismissed = ref.watch(uiPrefsProvider.select((p) => p.dismissedCards));
    final discovery = [
      for (final card in _DiscoveryCard.all)
        if (!dismissed.contains(card.id)) card,
    ];

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: Space.md),
          child: IconButton(
            tooltip: 'Settings',
            padding: EdgeInsets.zero,
            icon: CircleAvatar(
              radius: 18,
              backgroundColor: c.surfaceRaised,
              child: Icon(LumaIcons.profile, color: c.ink),
            ),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
          ),
        ),
        title: Text(
          appName,
          style: text.titleLarge?.copyWith(color: c.success, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(tooltip: 'Search', icon: const Icon(LumaIcons.search), onPressed: () => _openLibrary(context)),
          const SizedBox(width: Space.xs),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xxl * 2),
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  button: true,
                  label: 'All docs, ${docs.length}. Open folders',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => _openLibrary(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              'All docs(${docs.length})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Icon(LumaIcons.dropDown, color: c.success),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Create',
                icon: const Icon(LumaIcons.create),
                onPressed: busy ? null : () => showCreateSheet(context, ref),
              ),
              IconButton(
                tooltip: 'Sort',
                icon: const Icon(LumaIcons.sort),
                onPressed: () async {
                  await showSortSheet(context);
                  if (context.mounted) _openLibrary(context);
                },
              ),
              IconButton(
                tooltip: grid ? 'Show as list' : 'Show as gallery',
                icon: Icon(grid ? LumaIcons.listView : LumaIcons.gridView),
                onPressed: docs.isEmpty
                    ? null
                    : () => ref.read(uiPrefsProvider.notifier).setHomeView(grid ? LibraryView.list : LibraryView.grid),
              ),
              IconButton(
                tooltip: 'Select',
                icon: const Icon(LumaIcons.select),
                onPressed: docs.isEmpty ? null : () => _openLibrary(context),
              ),
            ],
          ),
          if (busy) ...[
            const SizedBox(height: Space.md),
            const LinearProgressIndicator(semanticsLabel: 'Adding pages'),
          ],
          for (final card in discovery) ...[
            const SizedBox(height: Space.md),
            _DiscoveryCardView(
              card: card,
              onTap: busy ? null : () => card.run(context, ref),
              onDismiss: () => ref.read(uiPrefsProvider.notifier).dismissCard(card.id),
            ),
          ],
          const SizedBox(height: Space.lg),
          if (docs.isNotEmpty)
            HomeDocumentsView(docs: docs, grid: grid)
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxl),
              child: Column(
                children: [
                  Icon(LumaIcons.document, size: 48, color: c.muted),
                  const SizedBox(height: Space.md),
                  Text('Your scans will show up here.', style: text.bodyLarge?.copyWith(color: c.muted)),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Tap the camera button to scan a document.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
        ],
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
      icon: LumaIcons.gallery,
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
          IconButton(tooltip: 'Dismiss ${card.title}', icon: const Icon(LumaIcons.close), onPressed: onDismiss),
        ],
      ),
    );
  }
}
