import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Scanner-style icon-and-label action with compact visual chrome and a full
/// 48 dp hit target. Use this in persistent toolbars and action rows where a
/// normal text button would consume too much document-preview space.
class CompactActionButton extends StatelessWidget {
  const CompactActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.enabled = true,
    this.semanticsLabel,
    this.hint,
    this.minWidth = 56,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  /// Controls appearance and semantics separately from [onPressed]. A
  /// disabled action may still handle a tap to explain how to enable it.
  final bool enabled;
  final String? semanticsLabel;
  final String? hint;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    final available = enabled && onPressed != null;
    final foreground = available
        ? (selected ? colors.accent : colors.ink)
        : colors.muted;
    final background = selected ? colors.accentSoft : Colors.transparent;

    return Semantics(
      button: true,
      enabled: available,
      selected: selected,
      label: semanticsLabel ?? label,
      hint: hint,
      excludeSemantics: true,
      child: Tooltip(
        message: hint == null ? label : '$label. $hint',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(ControlMetrics.radius),
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: minWidth,
                minHeight: minTapTarget,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.xs,
                  vertical: Space.xs,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(ControlMetrics.radius),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: ControlMetrics.toolbarIcon, color: foreground),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
