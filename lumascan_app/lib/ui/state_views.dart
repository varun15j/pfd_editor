import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Shared empty, loading, error and premium widgets, so every screen states
/// these the same way (spec US-02.1: empty, loading, offline and error states
/// carry a useful action).

/// Nothing to show yet, with one action that fixes it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Space.xxl, vertical: Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.lg)),
              child: Icon(icon, size: 32, color: c.accent),
            ),
            const SizedBox(height: Space.lg),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: Space.sm),
            Text(
              message,
              style: text.bodyMedium?.copyWith(color: c.muted),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Space.xl),
              FilledButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon ?? Icons.arrow_forward),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Placeholder rows shown while a list loads. Announced once to screen
/// readers instead of reading every grey bar.
class LoadingList extends StatelessWidget {
  const LoadingList({super.key, this.rows = 4, this.label = 'Loading'});

  final int rows;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: c.surfaceRaised, borderRadius: BorderRadius.circular(Radii.sm / 2)),
    );
    return Semantics(
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView.separated(
          padding: const EdgeInsets.all(Space.page),
          itemCount: rows,
          physics: const NeverScrollableScrollPhysics(),
          separatorBuilder: (_, _) => const SizedBox(height: Space.md),
          itemBuilder: (_, _) => Row(
            children: [
              bar(48, 64),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(160, 14),
                    const SizedBox(height: Space.sm),
                    bar(100, 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Something failed; says what and offers a retry.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry, this.title = 'Something went wrong'});

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Space.xxl, vertical: Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: c.danger),
            const SizedBox(height: Space.md),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: Space.sm),
            Text(
              message,
              style: text.bodyMedium?.copyWith(color: c.muted),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: Space.xl),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Marks a premium feature with an icon and the word, never colour alone
/// (spec section 6, US-10.1).
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key, this.label = 'Premium'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
      decoration: BoxDecoration(color: c.premium, borderRadius: BorderRadius.circular(Radii.sm)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_outlined, size: 14, color: c.onPremium),
          const SizedBox(width: Space.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.onPremium, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
