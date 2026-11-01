import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../app/preferences.dart';
import '../../app/theme.dart';
import '../../domain/eula.dart';

/// The End User Licence Agreement. At start ([EulaScreen.gate]) it stands
/// before the rest of the app until it is accepted, on first run and again
/// whenever [eulaVersion] is raised. From Settings it opens to be read only.
class EulaScreen extends ConsumerWidget {
  /// Read only, with a back button.
  const EulaScreen({super.key}) : gate = false, updated = false;

  /// Asks for acceptance. [updated] says an older version was accepted
  /// before, so the screen explains the agreement has changed.
  const EulaScreen.gate({super.key, this.updated = false}) : gate = true;

  /// Whether acceptance is asked for, rather than read only.
  final bool gate;

  /// Whether an older version was accepted before.
  final bool updated;

  Future<void> _decline(BuildContext context) async {
    // Only Android lets an app close itself; elsewhere the person leaves it.
    final canClose = defaultTargetPlatform == TargetPlatform.android;
    final close = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agreement needed'),
        content: Text(
          'You need to accept the End User Licence Agreement to use $appName.'
          '${canClose ? '' : ' If you do not agree, you can close the app and uninstall it.'}',
        ),
        actions: [
          if (canClose) TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Close app')),
          FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Read again')),
        ],
      ),
    );
    if (close ?? false) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    final heading = updated ? 'We have updated our terms' : 'Before you start';
    final lead = updated
        ? 'Please read and accept the new End User Licence Agreement to keep using $appName.'
        : 'Please read and accept the End User Licence Agreement to use $appName.';
    return Scaffold(
      appBar: gate ? null : AppBar(title: const Text('Terms of use')),
      body: SafeArea(
        top: gate,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.page, Space.xl, Space.page, Space.xl),
                children: [
                  if (gate) ...[
                    Semantics(header: true, child: Text(heading, style: text.headlineMedium)),
                    const SizedBox(height: Space.sm),
                    Text(lead, style: text.bodyLarge?.copyWith(color: c.muted)),
                    const SizedBox(height: Space.xl),
                  ],
                  Semantics(header: true, child: Text('End User Licence Agreement', style: text.titleLarge)),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Version $eulaVersion, effective $eulaEffectiveDate',
                    style: text.bodySmall?.copyWith(color: c.muted),
                  ),
                  const SizedBox(height: Space.lg),
                  ..._paragraphs(eulaIntro, text.bodyMedium),
                  for (final (i, section) in eulaSections.indexed) ...[
                    const SizedBox(height: Space.md),
                    Semantics(header: true, child: Text('${i + 1}. ${section.heading}', style: text.titleMedium)),
                    const SizedBox(height: Space.sm),
                    ..._paragraphs(section.body, text.bodyMedium),
                  ],
                ],
              ),
            ),
            if (gate)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.line)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.page, Space.md, Space.page, Space.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        onPressed: () => ref.read(appSettingsProvider.notifier).acceptEula(),
                        child: const Text('Agree and continue'),
                      ),
                      const SizedBox(height: Space.sm),
                      TextButton(onPressed: () => _decline(context), child: const Text('Decline')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static List<Widget> _paragraphs(String body, TextStyle? style) => [
    for (final paragraph in body.split('\n\n'))
      Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in paragraph.split('\n'))
              line.startsWith('• ')
                  ? Padding(
                      padding: const EdgeInsets.only(left: Space.sm, top: Space.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('•  ', style: style),
                          Expanded(child: Text(line.substring(2), style: style)),
                        ],
                      ),
                    )
                  : Text(line, style: style),
          ],
        ),
      ),
  ];
}
