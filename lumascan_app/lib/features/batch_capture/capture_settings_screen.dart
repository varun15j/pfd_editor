import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../app/theme.dart';
import '../../domain/app_settings.dart';

/// More capture settings, opened from Camera settings (prototype: "More
/// capture settings · Resolution, shutter sound, save original"). Choices
/// are kept on the device and apply to the next photo.
class CaptureSettingsScreen extends ConsumerWidget {
  const CaptureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final colors = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    Widget header(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.xs),
      child: Semantics(
        header: true,
        child: Text(title.toUpperCase(), style: text.labelMedium?.copyWith(color: colors.muted, letterSpacing: 1)),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('More capture settings')),
      body: ListView(
        children: [
          header('Photo size'),
          RadioGroup<CaptureResolution>(
            groupValue: settings.captureResolution,
            onChanged: (value) {
              if (value != null) controller.setCaptureResolution(value);
            },
            child: Column(
              children: [
                for (final r in CaptureResolution.values)
                  RadioListTile<CaptureResolution>(value: r, title: Text(r.label), subtitle: Text(r.hint)),
              ],
            ),
          ),
          header('Auto capture'),
          ListTile(
            title: const Text('Wait for the page to be still'),
            subtitle: const Text('Longer waits take fewer blurry photos'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xl),
            child: SegmentedButton<AutoCaptureSteadiness>(
              segments: [for (final s in AutoCaptureSteadiness.values) ButtonSegment(value: s, label: Text(s.label))],
              selected: {settings.autoCaptureSteadiness},
              onSelectionChanged: (value) => controller.setAutoCaptureSteadiness(value.single),
            ),
          ),
          header('When a photo is taken'),
          SwitchListTile(
            value: settings.shutterSound,
            onChanged: controller.setShutterSound,
            title: const Text('Shutter sound'),
            subtitle: const Text('Some phones always play their own sound'),
          ),
          SwitchListTile(
            value: settings.captureHaptics,
            onChanged: controller.setCaptureHaptics,
            title: const Text('Vibrate'),
            subtitle: const Text('A short tap you can feel for each photo'),
          ),
          header('Originals'),
          SwitchListTile(
            value: settings.keepOriginals,
            onChanged: controller.setKeepOriginals,
            title: const Text('Save original photos'),
            subtitle: const Text(
              'Keep each uncropped photo after the PDF is saved, so pages can be re-cropped later. '
              'Same as Keep originals in Settings.',
            ),
          ),
          const SizedBox(height: Space.xl),
        ],
      ),
    );
  }
}
