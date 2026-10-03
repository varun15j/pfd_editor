import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../app/theme.dart';

/// Kept with the dismissed Home cards so it shows only once.
const scanTipsId = 'scan_tips';

/// Shows the scan tips before the first camera scan. Returns false when the
/// user closes them without choosing to scan. Either way they don't show again.
Future<bool> showScanTipsOnce(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(uiPrefsProvider.notifier);
  await prefs.settled;
  if (!context.mounted) return false;
  if (ref.read(uiPrefsProvider).dismissedCards.contains(scanTipsId)) return true;
  final go = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const ScanTipsSheet(),
  );
  prefs.dismissCard(scanTipsId);
  return go ?? false;
}

class ScanTipsSheet extends StatelessWidget {
  const ScanTipsSheet({super.key});

  static const tips = [
    (Icons.light_mode_outlined, 'Use good light', 'Daylight or a bright room, without shadows on the page.'),
    (Icons.crop_free, 'Keep the page flat', 'Smooth out folds and fit all four corners in view.'),
    (Icons.contrast, 'Use a dark background', 'A dark table helps LumaScan find the page edges.'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('Tips for a clean scan', style: text.titleLarge)),
            const SizedBox(height: Space.md),
            for (final (icon, title, body) in tips)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon, color: c.accent),
                title: Text(title),
                subtitle: Text(body),
              ),
            const SizedBox(height: Space.lg),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start scanning')),
          ],
        ),
      ),
    );
  }
}
