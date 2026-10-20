import 'package:flutter/material.dart';

import '../crop/crop_screen.dart';

/// What a guided crop queue did, for the message afterwards.
@immutable
class CropQueueSummary {
  const CropQueueSummary({required this.applied, required this.remaining});

  /// Pages whose crop was applied in the queue.
  final int applied;

  /// Pages not reached because the user left early.
  final int remaining;

  String get message {
    final done = applied == 0 ? 'No pages cropped' : 'Cropped $applied page${applied == 1 ? '' : 's'}';
    if (remaining == 0) return done;
    return '$done. $remaining page${remaining == 1 ? '' : 's'} left to crop';
  }
}

/// Guided Crop Queue (BE-05): opens the crop editor for each page in
/// [pageIds], one after another. Every page is edited and re-detected on its
/// own original, so one page's crop never reaches another. Each applied crop
/// is saved straight away (its own undo step), so leaving early keeps them.
Future<CropQueueSummary> runCropQueue(NavigatorState navigator, List<String> pageIds) async {
  final applied = <String>{};
  var i = 0;
  while (i < pageIds.length) {
    final result = await navigator.push<CropStepResult>(
      MaterialPageRoute(
        builder: (_) => CropScreen(
          pageId: pageIds[i],
          step: CropQueueStep(index: i, total: pageIds.length),
        ),
      ),
    );
    switch (result) {
      case CropStepResult.applied:
        applied.add(pageIds[i]);
        i++;
      case CropStepResult.skipped:
        i++;
      case CropStepResult.back:
        if (i > 0) i--;
      case CropStepResult.finish:
      case null:
        return CropQueueSummary(applied: applied.length, remaining: pageIds.length - i);
    }
  }
  return CropQueueSummary(applied: applied.length, remaining: 0);
}
