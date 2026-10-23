import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../domain/ocr_languages.dart';
import '../../domain/plan.dart';
import '../../ui/state_views.dart';
import '../../ui/upgrade_dialog.dart';

/// Settings > Text recognition language. Indian languages, with neat
/// handwriting in English, Hindi and Marathi, are part of Pro and Gold; they
/// are listed on every plan and offer the upgrade when tapped.
class OcrLanguageScreen extends ConsumerWidget {
  const OcrLanguageScreen({super.key});

  /// Shown under each language: how well it is read, and whether a model is
  /// downloaded the first time.
  static String hint(OcrLanguage language) => switch (language.script) {
    OcrScript.latin => 'Print and neat handwriting. Built in',
    OcrScript.devanagari => 'Print and neat handwriting. Built in',
    _ => 'Printed text; handwriting only in part. One-time download, then offline',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(ocrLanguageProvider);
    final indian = ref.watch(planIncludesProvider(PlanFeature.indianOcr));
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Text recognition language')),
      body: RadioGroup<String>(
        groupValue: current,
        onChanged: (code) async {
          if (code == null) return;
          final language = OcrLanguage.of(code);
          if (language.script != OcrScript.latin &&
              !await ensurePlan(context, ref, PlanFeature.indianOcr, what: 'Reading ${language.name}')) {
            return;
          }
          ref.read(appSettingsProvider.notifier).setOcrLanguage(code);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Text is read on this phone; pages never leave it. Pick the language the pages are written in. '
                'English words on the page are read too.',
                style: text.bodySmall,
              ),
            ),
            for (final language in OcrLanguage.all)
              RadioListTile<String>(
                value: language.code,
                title: Text(language.label),
                subtitle: Text(hint(language)),
                secondary: language.script == OcrScript.latin || indian ? null : const PremiumBadge(label: 'Pro'),
              ),
          ],
        ),
      ),
    );
  }
}
