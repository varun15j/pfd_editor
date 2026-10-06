import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'image_profiler.dart';
import 'profile_sample.dart';
import 'profiling_report_screen.dart';

/// The app's navigator, so the debug panel (which sits above every route) can
/// open the profiling report.
final debugNavigatorKey = GlobalKey<NavigatorState>();

/// Debug builds only: wraps the whole app and opens a debug panel when the
/// user swipes in from the left edge, on any screen.
class DebugPanelHost extends ConsumerStatefulWidget {
  const DebugPanelHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DebugPanelHost> createState() => _DebugPanelHostState();
}

class _DebugPanelHostState extends ConsumerState<DebugPanelHost> {
  static const _panelWidth = 300.0;
  static const _edgeWidth = 16.0;

  /// 0 closed, 1 fully open; follows the finger while dragging.
  double _open = 0;
  bool _dragging = false;

  void _drag(double dx) => setState(() => _open = (_open + dx / _panelWidth).clamp(0.0, 1.0));

  void _settle(double velocity) => setState(() {
    _dragging = false;
    _open = velocity > 300 || (velocity > -300 && _open > 0.4) ? 1 : 0;
  });

  void _close() => setState(() => _open = 0);

  late final _panelEntry = OverlayEntry(
    builder: (context) => DebugPanel(profiler: ref.read(imageProfilerProvider), onClose: _close),
  );

  @override
  Widget build(BuildContext context) {
    final profiler = ref.watch(imageProfilerProvider);
    if (!profiler.available) return widget.child;
    final panelLeft = -_panelWidth * (1 - _open);
    return Stack(
      children: [
        widget.child,
        if (_open > 0)
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              onHorizontalDragStart: (_) => _dragging = true,
              onHorizontalDragUpdate: (d) => _drag(d.delta.dx),
              onHorizontalDragEnd: (d) => _settle(d.primaryVelocity ?? 0),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.35 * _open)),
            ),
          ),
        // Swipe from the left edge, left to right, to open.
        if (_open == 0)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _edgeWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => setState(() => _dragging = true),
              onHorizontalDragUpdate: (d) => _drag(d.delta.dx),
              onHorizontalDragEnd: (d) => _settle(d.primaryVelocity ?? 0),
            ),
          ),
        AnimatedPositioned(
          duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          left: panelLeft,
          top: 0,
          bottom: 0,
          width: _panelWidth,
          child: GestureDetector(
            onHorizontalDragStart: (_) => _dragging = true,
            onHorizontalDragUpdate: (d) => _drag(d.delta.dx),
            onHorizontalDragEnd: (d) => _settle(d.primaryVelocity ?? 0),
            // Its own overlay, because the panel sits above the app's
            // navigator and tooltips and menus need one.
            child: Offstage(
              offstage: _open == 0 && !_dragging,
              child: Overlay(initialEntries: [_panelEntry]),
            ),
          ),
        ),
      ],
    );
  }
}

/// The panel's contents: the profiling switches and live figures.
class DebugPanel extends StatelessWidget {
  const DebugPanel({super.key, required this.profiler, required this.onClose});

  final ImageProfiler profiler;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 16,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: profiler,
          builder: (context, _) {
            final averages = profiler.liveAverages;
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ListTile(
                  title: Text('Debug', style: Theme.of(context).textTheme.titleLarge),
                  subtitle: const Text('Debug builds only'),
                  trailing: IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: onClose),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Profile image loading'),
                  subtitle: const Text('Times every thumbnail, preview and effect, and saves it for the report.'),
                  value: profiler.enabled,
                  onChanged: (v) => profiler.enabled = v,
                ),
                SwitchListTile(
                  title: const Text('Show times on pictures'),
                  subtitle: const Text('Red label: R rendered now, D read from disk, M already in memory.'),
                  value: profiler.showLabels,
                  onChanged: profiler.enabled ? (v) => profiler.showLabels = v : null,
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Last ${profiler.recentSamples.length} measurements',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (averages.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text('Nothing measured yet. Turn profiling on and open some pages.'),
                  ),
                for (final kind in ProfileKind.values)
                  if (averages[kind] case (final n, final avg))
                    ListTile(
                      dense: true,
                      title: Text(kind.label),
                      subtitle: Text('$n measured'),
                      trailing: Text(
                        'avg ${formatProfileMs(avg)}',
                        style: const TextStyle(color: Color(0xFFD50000), fontWeight: FontWeight.w700),
                      ),
                    ),
                const Divider(),
                if (profiler.location != null)
                  ListTile(
                    leading: Icon(profiler.keptAfterUninstall ? Icons.folder_shared_outlined : Icons.folder_outlined),
                    title: Text(
                      profiler.keptAfterUninstall ? 'Data is kept after uninstall' : 'Keep data after uninstall',
                    ),
                    subtitle: Text(
                      profiler.keptAfterUninstall
                          ? 'Saved in ${profiler.databasePath}'
                          : 'Moves the database to Documents/LumaScan/debug. Android asks for "All files access".',
                    ),
                    onTap: profiler.keptAfterUninstall
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.maybeOf(context);
                            final kept = await profiler.keepAfterUninstall();
                            if (!kept) {
                              messenger?.showSnackBar(
                                const SnackBar(content: Text('Not allowed, so the data stays inside the app.')),
                              );
                            }
                          },
                  ),
                ListTile(
                  leading: const Icon(Icons.analytics_outlined),
                  title: const Text('Open profiling report'),
                  onTap: () {
                    onClose();
                    debugNavigatorKey.currentState?.push(
                      MaterialPageRoute<void>(builder: (_) => const ProfilingReportScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Clear profiling data'),
                  onTap: profiler.clear,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
