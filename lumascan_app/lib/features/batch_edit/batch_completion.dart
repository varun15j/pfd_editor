import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../pages/scan_controller.dart';

/// What the user chose when finishing Batch Review (BE-09).
enum BatchOutcome {
  camera('Return to camera', 'Scan more pages into this document', Icons.document_scanner_outlined),
  review('Review document', 'Go back to the document pages', Icons.description_outlined),
  export('Export PDF', 'Choose the PDF settings and save it', Icons.picture_as_pdf_outlined);

  const BatchOutcome(this.label, this.hint, this.icon);

  final String label;
  final String hint;
  final IconData icon;
}

/// Asks where to go after Batch Review. Returns null when dismissed.
Future<BatchOutcome?> showBatchCompletionSheet(BuildContext context) => showModalBottomSheet<BatchOutcome>(
  context: context,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 4), child: DraftSaveIndicator()),
        for (final o in BatchOutcome.values)
          ListTile(
            leading: Icon(o.icon),
            title: Text(o.label),
            subtitle: Text(o.hint),
            onTap: () => Navigator.pop(context, o),
          ),
      ],
    ),
  ),
);

/// Says whether the draft is safely on this device. "Saved on this device"
/// shows only once the draft file was written.
class DraftSaveIndicator extends ConsumerWidget {
  const DraftSaveIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = LumaColors.of(context);
    final (icon, color, label) = switch (ref.watch(draftSaveStatusProvider)) {
      DraftSaveStatus.saved => (Icons.check_circle_outline, colors.success, 'Saved on this device'),
      DraftSaveStatus.saving => (Icons.sync, colors.muted, 'Saving'),
      DraftSaveStatus.failed => (Icons.error_outline, colors.danger, 'Not saved yet'),
    };
    return Semantics(
      liveRegion: true,
      label: 'Draft: $label',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
