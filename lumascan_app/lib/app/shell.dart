import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/scanner_service.dart';
import '../features/batch_capture/batch_capture_screen.dart';
import '../features/capture/create_sheet.dart';
import '../features/capture/scan_tips.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/pages/pages_screen.dart';
import '../features/pages/scan_actions.dart';
import '../features/pages/scan_controller.dart';
import '../features/settings/settings_screen.dart';
import '../features/tools/tools_screen.dart';
import 'theme.dart';

enum AppTab {
  home('Home', Icons.home_outlined, Icons.home),
  library('Library', Icons.folder_outlined, Icons.folder),
  tools('Tools', Icons.handyman_outlined, Icons.handyman),
  settings('Settings', Icons.settings_outlined, Icons.settings);

  const AppTab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Main navigation: Home, Library, Tools and Settings, with Create as a raised
/// centre button rather than a tab (LumaScan_features.md, "V2 information
/// architecture": capture is a task, not a destination).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  AppTab _tab = AppTab.home;

  void _select(AppTab tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    ref.listen(showHomeProvider, (_, _) => _select(AppTab.home));
    final busy = ref.watch(scanControllerProvider.select((s) => s.busy));
    return Scaffold(
      body: IndexedStack(
        index: _tab.index,
        children: [
          HomeScreen(onOpenLibrary: () => _select(AppTab.library)),
          const LibraryScreen(),
          const ToolsScreen(),
          const SettingsScreen(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: SizedBox.square(
        dimension: 56,
        child: FloatingActionButton(
          tooltip: 'Create',
          onPressed: busy ? null : () => showCreateSheet(context, ref),
          child: const Icon(Icons.add, size: 26),
        ),
      ),
      bottomNavigationBar: _BottomBar(selected: _tab, onSelect: _select),
    );
  }
}

/// Starts a new document, scans or imports into it, then opens it so the new
/// pages can be checked straight away. The document on screen before, if
/// any, is kept on Home to open again. The first camera scan shows the scan
/// tips. The camera stays open between shots and opens the document when it
/// closes.
Future<void> scanThenReview(BuildContext context, WidgetRef ref, ScanSource source) async {
  if (source == ScanSource.camera && (!await showScanTipsOnce(context, ref) || !context.mounted)) return;
  await ref.read(scanControllerProvider.notifier).startNewDocument();
  if (!context.mounted) return;
  if (source == ScanSource.camera) return openBatchCapture(context, ref);
  // Open the draft as soon as the pages are known, so the wait for a long
  // import is spent looking at the pages arriving.
  final navigator = Navigator.of(context);
  Route<void>? draft;
  final added = await runScan(context, ref, source, onAdding: () => draft = openDraft(context));
  if (draft == null) {
    if (added && context.mounted) openDraft(context);
  } else if (!added && draft!.isActive) {
    // Nothing could be added (every photo unreadable): do not leave an empty draft open.
    navigator.removeRoute(draft!);
  }
}

/// Asks the shell to show the Home tab; each request bumps the count.
final showHomeProvider = NotifierProvider<ShowHomeRequests, int>(ShowHomeRequests.new);

class ShowHomeRequests extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

/// Save and go home: waits for the document to be written, then closes every
/// screen over the shell and shows Home, where the next scan starts a new
/// document. The scan stays on Home to open again.
Future<void> saveAndGoHome(BuildContext context, WidgetRef ref) async {
  await ref.read(scanControllerProvider.notifier).draftSaved;
  if (!context.mounted) return;
  ref.read(showHomeProvider.notifier).request();
  Navigator.of(context).popUntil((route) => route.isFirst);
}

Route<void> openDraft(BuildContext context) {
  final route = MaterialPageRoute<void>(builder: (_) => const PagesScreen());
  Navigator.of(context).push(route);
  return route;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.selected, required this.onSelect});

  final AppTab selected;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    Widget item(AppTab tab) => Expanded(
      child: _NavItem(tab: tab, selected: tab == selected, onTap: () => onSelect(tab)),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 5,
        height: 64,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            item(AppTab.home),
            item(AppTab.library),
            const SizedBox(width: 68),
            item(AppTab.tools),
            item(AppTab.settings),
          ],
        ),
      ),
    );
  }
}

/// One destination. Selection shows as a filled icon, bold label and accent
/// colour together, so it never depends on colour alone.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.tab, required this.selected, required this.onTap});

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final color = selected ? c.accent : c.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minTapTarget),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? tab.selectedIcon : tab.icon, color: color, size: ControlMetrics.icon),
              const SizedBox(height: 2),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
