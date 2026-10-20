import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'scan_controller.dart';

/// "Adding 7 of 20 pages" with a progress bar, shown at the top of the Pages
/// screen while a scan or import is being saved.
class AddingBanner extends StatelessWidget {
  const AddingBanner({super.key, required this.progress});

  final AddProgress progress;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    final label = progress.total == 1
        ? 'Adding 1 page'
        : 'Adding ${math.min(progress.done + 1, progress.total)} of ${progress.total} pages';
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: text.labelLarge?.copyWith(color: c.muted)),
              const SizedBox(height: Space.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  color: c.accent,
                  backgroundColor: c.accentSoft,
                  value: progress.total == 0 ? null : progress.done / progress.total,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stands in for a page that is still being added. Pages that are ready show
/// a tick, the next one a spinner, and the rest stay quiet.
class PagePlaceholder extends StatelessWidget {
  const PagePlaceholder({super.key, required this.number, required this.state});

  /// 1-based position the page will have in the draft.
  final int number;
  final PlaceholderState state;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    return Semantics(
      label: 'Page $number, ${state == PlaceholderState.ready ? 'ready' : 'being added'}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.line),
        ),
        child: Center(
          child: switch (state) {
            PlaceholderState.ready => Icon(Icons.check_circle, color: c.success),
            PlaceholderState.working => const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            PlaceholderState.waiting => Icon(Icons.description_outlined, color: c.muted),
          },
        ),
      ),
    );
  }
}

enum PlaceholderState { ready, working, waiting }

/// How a placeholder looks, by its place among the pages still to come.
extension AddProgressPlaceholders on AddProgress {
  PlaceholderState stateOf(int index) => index < done
      ? PlaceholderState.ready
      : index == done
      ? PlaceholderState.working
      : PlaceholderState.waiting;
}

/// Watches the add progress of the draft; null when nothing is being added.
final addProgressProvider = Provider<AddProgress?>((ref) => ref.watch(scanControllerProvider.select((s) => s.adding)));
