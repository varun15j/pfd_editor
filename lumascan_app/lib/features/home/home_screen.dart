import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../app/preferences.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/library_query.dart';
import '../../domain/scanner_service.dart';
import '../../domain/ui_prefs.dart';
import '../capture/create_sheet.dart';
import '../export/saved_exports.dart';
import '../library/library_actions.dart';
import '../library/library_query_controller.dart';
import '../library/library_query_sheets.dart';
import '../library/library_screen.dart';
import '../settings/settings_screen.dart';
import '../pages/scan_controller.dart';
import 'home_documents.dart';
import '../../ui/luma_icons.dart';

/// Docs tab, laid out as Screen 1 of the UI/UX screenshots: the avatar
/// (Settings), the app name and Search at the top, then "Docs(N)" with
/// Create, Sort, Grid and Select, the Docs / Saved / All chips, then the
/// documents. Docs (the default) are the scans and the PDFs worked on;
/// Saved holds the PDF and Word files exported from scans. Search, the
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
    final scope = ref.watch(libraryQueryProvider.select((q) => q.scope));
    final pdfs = ref.watch(visibleDocumentsProvider);
    final words = ref.watch(savedWordFilesProvider);
    int count(DocScope s) => homeDocuments(state, pdfs, scope: s, words: words).length;
    final docs = homeDocuments(state, pdfs, scope: scope, words: words);
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
                  label: '${scope.label}, ${docs.length}. Open folders',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => _openLibrary(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${scope.label}(${docs.length})',
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
          _ScopeChips(
            scope: scope,
            count: count,
            onSelected: (s) => ref.read(libraryQueryProvider.notifier).showScope(s),
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
          else if (scope == DocScope.saved)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxl),
              child: Column(
                children: [
                  Icon(LumaIcons.save, size: 48, color: c.muted),
                  const SizedBox(height: Space.md),
                  Text('Nothing saved yet.', style: text.bodyLarge?.copyWith(color: c.muted)),
                  const SizedBox(height: Space.xs),
                  Text(
                    'PDF and Word files you export from a scan are kept here.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: c.muted),
                  ),
                ],
              ),
            )
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

/// Docs, Saved and All, each with its count. Docs is picked at start.
class _ScopeChips extends StatelessWidget {
  const _ScopeChips({required this.scope, required this.count, required this.onSelected});

  final DocScope scope;
  final int Function(DocScope) count;
  final ValueChanged<DocScope> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final s in DocScope.values) ...[
          if (s != DocScope.docs) const SizedBox(width: Space.sm),
          ChoiceChip(
            avatar: s == DocScope.saved ? const Icon(LumaIcons.save, size: 18) : null,
            label: Text('${s.label} (${count(s)})'),
            selected: s == scope,
            onSelected: (_) => onSelected(s),
          ),
        ],
      ],
    ),
  );
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
