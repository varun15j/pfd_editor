import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../domain/photo_import.dart';

/// What Crop in Batch Review does to the selected pages.
enum CropChoice {
  /// Find the page in each photo and crop to it.
  auto('Auto crop', 'Find the page in each photo and crop to it', Icons.auto_awesome_outlined),

  /// Keep each whole photo, with no crop.
  full('Full photo', 'Keep each whole photo, with no crop', Icons.fullscreen),

  /// Open the crop editor for each page in turn.
  adjust('Adjust each page', 'Drag the corners on each page in turn', Icons.crop);

  const CropChoice(this.label, this.detail, this.icon);

  final String label, detail;
  final IconData icon;
}

/// Offers the [CropChoice]s for [count] selected pages.
class CropChoiceSheet extends StatelessWidget {
  const CropChoiceSheet({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'Crop $count selected page${count == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final choice in CropChoice.values)
          ListTile(
            leading: Icon(choice.icon),
            title: Text(choice.label),
            subtitle: Text(choice.detail),
            onTap: () => Navigator.pop(context, choice),
          ),
        const SizedBox(height: 8),
      ],
    ),
  );
}

/// Finds the page in each of [pages]' photos, showing progress. Returns the
/// crop found for each page that has one, or null when cancelled. Pages
/// whose photo shows no page are left out.
Future<Map<String, CropQuad>?> autoCropPages(BuildContext context, PhotoAnalyzer analyzer, List<ScanPage> pages) async {
  final done = ValueNotifier(0);
  var cancelled = false;
  final navigator = Navigator.of(context);
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Auto cropping'),
      content: ValueListenableBuilder(
        valueListenable: done,
        builder: (context, n, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: pages.isEmpty ? null : n / pages.length),
            const SizedBox(height: 12),
            Text('Page ${(n + 1).clamp(1, pages.length)} of ${pages.length}'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            cancelled = true;
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  final found = <String, CropQuad>{};
  for (final page in pages) {
    if (cancelled) break;
    try {
      final quad = await analyzer.analyze(page.originalPath);
      if (quad != null) found[page.id] = quad;
    } on Object catch (e) {
      debugPrint('Auto crop failed on ${page.id}: $e');
    }
    done.value++;
  }
  if (!cancelled) navigator.pop();
  await dialog;
  done.dispose();
  return cancelled ? null : found;
}
