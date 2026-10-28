import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/scanner_service.dart';
import '../features/batch_capture/batch_capture_screen.dart';
import '../features/batch_capture/camera_mode.dart';
import '../features/capture/scan_tips.dart';
import '../features/home/home_screen.dart';
import '../features/pages/pages_screen.dart';
import '../features/pages/scan_actions.dart';
import '../features/pages/scan_controller.dart';
import '../features/tools/tools_screen.dart';
import 'theme.dart';
import '../ui/luma_icons.dart';

enum AppTab {
  docs('Docs', LumaIcons.docsTab, LumaIcons.documentSelected),
  tools('Tools', LumaIcons.tools, LumaIcons.toolsSelected);

  const AppTab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Main navigation, as in the UI/UX screenshots (Screens 1, 3 and 4): Docs
/// and Tools tabs with a green camera button between them. The camera
/// button starts a scan straight away; Settings opens from the avatar on
/// Docs, and every other way to start a document is in Create on Docs.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  AppTab _tab = AppTab.docs;

  void _select(AppTab tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    ref.listen(showHomeProvider, (_, _) => _select(AppTab.docs));
    final busy = ref.watch(scanControllerProvider.select((s) => s.busy));
    return Scaffold(
      body: IndexedStack(index: _tab.index, children: const [HomeScreen(), ToolsScreen()]),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: SizedBox.square(
        dimension: 64,
        child: FloatingActionButton(
          tooltip: 'Scan',
          backgroundColor: LumaColors.scan,
          foregroundColor: LumaColors.onScan,
          onPressed: busy ? null : () => scanThenReview(context, ref, ScanSource.camera),
          child: const Icon(LumaIcons.cameraFilled, size: 30),
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
/// [mode] is the capture mode the camera opens in.
Future<void> scanThenReview(
  BuildContext context,
  WidgetRef ref,
  ScanSource source, {
  CameraMode mode = CameraMode.docs,
}) async {
  if (source == ScanSource.camera && (!await showScanTipsOnce(context, ref) || !context.mounted)) return;
  await ref.read(scanControllerProvider.notifier).startNewDocument();
  if (!context.mounted) return;
  if (source == ScanSource.camera) return openBatchCapture(context, ref, mode: mode);
  await addShowingDraft(context, (onAdding) => runScan(context, ref, source, onAdding: onAdding));
}

/// Runs [add], which adds pages to the draft and calls its argument once the
/// pages being added are known, and opens the draft at that moment, so the
/// wait for a long import is spent looking at the pages arriving. Without
/// that call the draft opens when [add] finishes with pages added. Returns
/// whether pages were added.
Future<bool> addShowingDraft(BuildContext context, Future<bool> Function(VoidCallback onAdding) add) async {
  final navigator = Navigator.of(context);
  Route<void>? draft;
  final added = await add(() => draft = openDraft(context));
  if (draft == null) {
    if (added && context.mounted) openDraft(context);
  } else if (!added && draft!.isActive) {
    // Nothing could be added (every photo unreadable): do not leave an empty draft open.
    navigator.removeRoute(draft!);
  }
  return added;
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
        child: Row(children: [item(AppTab.docs), const SizedBox(width: 96), item(AppTab.tools)]),
      ),
    );
  }
}

/// One destination. Selection shows as a filled icon, bold label and the
/// screenshots' green together, so it never depends on colour alone.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.tab, required this.selected, required this.onTap});

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final color = selected ? c.success : c.muted;
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
