import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'batch_actions.dart';
import 'batch_selection.dart';

/// Persistent action bar under the Batch Review grid (BE-03). Unavailable
/// actions stay visible; tapping one explains how to enable it.
class BatchActionBar extends StatelessWidget {
  const BatchActionBar({super.key, required this.selection, required this.pageCount, required this.onAction});

  final BatchSelection selection;
  final int pageCount;
  final ValueChanged<BatchAction> onAction;

  void _tap(BuildContext context, BatchAction action) {
    final availability = availabilityOf(action, selection, pageCount: pageCount);
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
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              for (final action in BatchAction.bar)
                Expanded(
                  child: _BarButton(
                    label: action.label,
                    icon: action.icon,
                    semanticsLabel: selection.isEmpty ? action.label : scopeLabel(action, selection.count),
                    availability: availabilityOf(action, selection, pageCount: pageCount),
                    onTap: () => _tap(context, action),
                  ),
                ),
              Expanded(
                child: _BarButton(
                  label: 'More',
                  icon: Icons.more_horiz,
                  semanticsLabel: 'More actions',
                  availability: const ActionAvailability.enabled(),
                  onTap: () => _showMore(context),
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
                  final availability = availabilityOf(a, selection, pageCount: pageCount);
                  return ListTile(
                    leading: Icon(a.icon),
                    title: Text(a.label),
                    subtitle: availability.enabled ? null : Text(availability.reason!),
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

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.icon,
    required this.semanticsLabel,
    required this.availability,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String semanticsLabel;
  final ActionAvailability availability;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    final color = availability.enabled ? colors.ink : colors.muted;
    return Semantics(
      button: true,
      enabled: availability.enabled,
      label: semanticsLabel,
      hint: availability.reason,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
