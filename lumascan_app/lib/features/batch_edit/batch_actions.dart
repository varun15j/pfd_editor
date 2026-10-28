import 'package:flutter/material.dart';

import 'batch_selection.dart';
import '../../ui/luma_icons.dart';

/// Actions in Batch Review (BE-03). The first group sits in the action bar;
/// the rest are under More.
enum BatchAction {
  enhance('Enhance', LumaIcons.enhance, 'enhance'),
  rotate('Rotate', LumaIcons.rotateRight, 'rotate'),
  crop('Crop', LumaIcons.crop, 'crop'),
  ocr('OCR', LumaIcons.textResult, 'read text from'),
  delete('Delete', LumaIcons.delete, 'delete'),
  retake('Retake', LumaIcons.retake, 'retake', singlePage: true),
  markup('Markup', LumaIcons.sign, 'mark up', singlePage: true),
  duplicate('Duplicate', LumaIcons.duplicate, 'duplicate', singlePage: true),
  reorder('Reorder', LumaIcons.reorder, 'reorder', needsSelection: false);

  const BatchAction(this.label, this.icon, this.verb, {this.singlePage = false, this.needsSelection = true});

  final String label;
  final IconData icon;

  /// Lower-case verb for helper text, as in "Select one page to retake".
  final String verb;

  /// Needs exactly one selected page (US-03.5 AC 6).
  final bool singlePage;

  /// Works on the whole document rather than the selection.
  final bool needsSelection;

  /// Shown in the action bar; the others are under More.
  static const bar = [enhance, rotate, crop, ocr, delete];
  static const more = [retake, markup, duplicate, reorder];
}

/// Whether an action can run on the current selection, and if not, what the
/// user can do to enable it. Disabled actions stay visible with this reason.
@immutable
class ActionAvailability {
  const ActionAvailability.enabled() : reason = null;
  const ActionAvailability.disabled(String this.reason);

  final String? reason;

  bool get enabled => reason == null;
}

/// [pageCount] is the number of pages in the document.
ActionAvailability availabilityOf(BatchAction action, BatchSelection selection, {required int pageCount}) {
  if (!action.needsSelection) {
    return pageCount < 2
        ? const ActionAvailability.disabled('Add another page to reorder')
        : const ActionAvailability.enabled();
  }
  if (selection.isEmpty) {
    return ActionAvailability.disabled(
      action.singlePage ? 'Select one page to ${action.verb}' : 'Select pages to ${action.verb}',
    );
  }
  if (action.singlePage && !selection.isSingle) {
    return ActionAvailability.disabled('Select one page to ${action.verb}');
  }
  return const ActionAvailability.enabled();
}

/// Names what an action will touch, for example "Rotate 4 selected pages".
String scopeLabel(BatchAction action, int count) => '${action.label} $count selected page${count == 1 ? '' : 's'}';
