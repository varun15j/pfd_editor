import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../app/theme.dart';
import '../../domain/app_settings.dart';
import '../../domain/models.dart';
import 'about_section.dart';
import 'storage_section.dart';

/// Settings tab: preferences for new scans and saves, appearance, storage,
/// help and about. Every preference says whether it changes files that
/// already exist.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final text = Theme.of(context).textTheme;
    final c = LumaColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xxl),
        children: [
          const _Header('Scanning'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Default filter'),
            subtitle: Text('${settings.defaultFilter.label}. New scans only; pages already scanned keep their filter.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _chooseFilter(context, settings.defaultFilter, controller.setDefaultFilter),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-crop imported photos'),
            subtitle: const Text(
              'Photos start cropped to the page found in them. Applies to future imports; you can still turn it off for each import and re-crop any page.',
            ),
            value: settings.autoCropOnImport,
            onChanged: controller.setAutoCropOnImport,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep page images after saving'),
            subtitle: Text(
              settings.keepOriginals
                  ? 'Pages stay on this device until you discard them. Saved PDFs are never affected.'
                  : 'Page images are deleted as soon as the PDF is saved, from your next save on. Saved PDFs are never affected.',
            ),
            value: settings.keepOriginals,
            onChanged: controller.setKeepOriginals,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('File name'),
            subtitle: Text(
              '${settings.fileNamePattern.label}, like ${settings.fileNamePattern.example}. '
              'Offered for the next PDF; saved files keep their names.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _choosePattern(context, settings.fileNamePattern, controller.setFileNamePattern),
          ),
          const SizedBox(height: Space.xl),
          const _Header('Appearance'),
          const SizedBox(height: Space.sm),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
              ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (s) => controller.setThemeMode(s.single),
          ),
          const SizedBox(height: Space.sm),
          Text('Changes how the app looks. No files are affected.', style: text.bodySmall?.copyWith(color: c.muted)),
          const SizedBox(height: Space.xl),
          const StorageSection(),
          const SizedBox(height: Space.xl),
          const AboutSection(),
        ],
      ),
    );
  }

  Future<void> _chooseFilter(BuildContext context, DocumentFilter current, ValueChanged<DocumentFilter> onPick) =>
      _pick<DocumentFilter>(
        context,
        title: 'Default filter',
        note: 'Used for new scans and imports. Pages already in a document are not changed.',
        values: DocumentFilter.values,
        current: current,
        label: (f) => f.label,
        onPick: onPick,
      );

  Future<void> _choosePattern(BuildContext context, FileNamePattern current, ValueChanged<FileNamePattern> onPick) =>
      _pick<FileNamePattern>(
        context,
        title: 'File name',
        note: 'Offered when you save the next PDF. You can still edit the name, and saved files are not renamed.',
        values: FileNamePattern.values,
        current: current,
        label: (p) => p.label,
        subtitle: (p) => p.example,
        onPick: onPick,
      );

  Future<void> _pick<T>(
    BuildContext context, {
    required String title,
    required String note,
    required List<T> values,
    required T current,
    required String Function(T) label,
    String Function(T)? subtitle,
    required ValueChanged<T> onPick,
  }) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(title, style: Theme.of(sheetContext).textTheme.headlineSmall),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
              child: Text(note, style: Theme.of(sheetContext).textTheme.bodySmall),
            ),
            RadioGroup<T>(
              groupValue: current,
              onChanged: (v) {
                if (v == null) return;
                onPick(v);
                Navigator.pop(sheetContext);
              },
              child: Column(
                children: [
                  for (final v in values)
                    RadioListTile<T>(
                      value: v,
                      title: Text(label(v)),
                      subtitle: subtitle == null ? null : Text(subtitle(v)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) =>
      Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium));
}
