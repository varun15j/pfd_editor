import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../ui/compact_action_button.dart';
import 'batch_actions.dart';
import 'batch_selection.dart';

/// Persistent action bar under the Batch Review grid (BE-03). Unavailable
/// actions stay visible; tapping one explains how to enable it.
class BatchActionBar extends StatelessWidget {
  const BatchActionBar({
    super.key,
    required this.selection,
    required this.pageCount,
    required this.onAction,
  });

  final BatchSelection selection;
  final int pageCount;
  final ValueChanged<BatchAction> onAction;

  void _tap(BuildContext context, BatchAction action) {
    final availability = availabilityOf(
      action,
      selection,
      pageCount: pageCount,
    );
    if (availability.enabled) {
      onAction(action);
    } else {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(availability.reason!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.xs,
            vertical: 2,
          ),
          child: Row(
            children: [
              for (final action in BatchAction.bar)
                Expanded(
                  child: CompactActionButton(
                    label: action.label,
                    icon: action.icon,
                    semanticsLabel: selection.isEmpty
                        ? action.label
                        : scopeLabel(action, selection.count),
                    enabled: availabilityOf(
                      action,
                      selection,
                      pageCount: pageCount,
                    ).enabled,
                    hint: availabilityOf(
                      action,
                      selection,
                      pageCount: pageCount,
                    ).reason,
                    onPressed: () => _tap(context, action),
                  ),
                ),
              Expanded(
                child: CompactActionButton(
                  label: 'More',
                  icon: Icons.more_horiz,
                  semanticsLabel: 'More actions',
                  onPressed: () => _showMore(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMore(BuildContext context) async {
    final action = await showModalBottomSheet<BatchAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in BatchAction.more)
              Builder(
                builder: (context) {
                  final availability = availabilityOf(
                    a,
                    selection,
                    pageCount: pageCount,
                  );
                  return ListTile(
                    leading: Icon(a.icon),
                    title: Text(a.label),
                    subtitle: availability.enabled
                        ? null
                        : Text(availability.reason!),
                    enabled: availability.enabled,
                    onTap: () => Navigator.pop(context, a),
                  );
                },
              ),
          ],
        ),
      ),
    );
    if (action != null) onAction(action);
  }
}
