import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Short answers to the questions people ask first. Plain text, works offline.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _topics = [
    (
      'Scanning a page',
      'Tap the + button and choose Scan document. Hold the phone over the page in good light; the edges are found for you. '
          'Add as many pages as you need, then check them before saving.',
    ),
    (
      'Using photos you already have',
      'Tap + and choose Import photos. Pick the photos, set their order and keep Auto-crop on to find each page in its photo.',
    ),
    (
      'Fixing a page',
      'Open a page and use Crop, Filters or Rotate. Markup adds pen, highlighter, text and a signature. '
          'Everything can be undone from the top of the screen.',
    ),
    (
      'Saving and sending',
      'Save PDF asks for a name, page size and quality, and shows the size. After saving, Send shares the PDF or a smaller copy. '
          'The PDF stays in your Library either way.',
    ),
    (
      'Editing a PDF you already have',
      'In Tools, choose Edit and sign a PDF. Your original is never changed; edits are saved as a new file.',
    ),
    (
      'Making room',
      'Settings shows what takes space. Clear cache is safe: it only removes previews and smaller copies that are made again when needed.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = LumaColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xxl),
        children: [
          for (final (title, body) in _topics) ...[
            Semantics(header: true, child: Text(title, style: text.titleMedium)),
            const SizedBox(height: Space.xs),
            Text(body, style: text.bodyMedium?.copyWith(color: c.muted)),
            const SizedBox(height: Space.xl),
          ],
        ],
      ),
    );
  }
}

/// What the app keeps and shares, in plain words.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = LumaColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xxl),
        children: [
          Text(
            'Your scans and PDFs stay on this device. LumaScan has no account and does not upload anything. '
            'A file leaves your device only when you share it.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: Space.lg),
          Text(
            'Camera access is used only while you scan. Photos are read only when you pick them.',
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
        ],
      ),
    );
  }
}
