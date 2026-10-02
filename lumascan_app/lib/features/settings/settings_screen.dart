import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../app/theme.dart';

/// Settings tab. Appearance only for now; capture defaults, storage, help and
/// legal arrive with F1 in the UI/UX plan.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final text = Theme.of(context).textTheme;
    final c = LumaColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xxl),
        children: [
          Semantics(header: true, child: Text('Appearance', style: text.titleMedium)),
          const SizedBox(height: Space.md),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
              ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
            ],
            selected: {mode},
            onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.single),
          ),
          const SizedBox(height: Space.xxl),
          Semantics(header: true, child: Text('Privacy', style: text.titleMedium)),
          const SizedBox(height: Space.sm),
          Text(
            'Scans and PDFs stay on this device unless you share them.',
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
        ],
      ),
    );
  }
}
