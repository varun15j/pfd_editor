import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../ui/luma_icons.dart';
import 'id_card_capture_screen.dart';
import 'id_card_session.dart';

/// Retake of a page of an ID copy, from any page options (the saved grid,
/// the page preview, Batch Review). A side opens the ID card camera for
/// that side; the copy page asks which side first, when there are two. The
/// camera takes one photo in place of the side and closes, and the copy
/// page is made again from it.
///
/// Returns false when [page] is not part of an ID copy, so the caller
/// retakes it as an ordinary page.
Future<bool> retakeIdCopyPage(BuildContext context, WidgetRef ref, ScanPage page) async {
  final draft = ref.read(idCopyDraftProvider);
  if (draft == null) return false;
  int? side = draft.sideIds.indexOf(page.id);
  if (side < 0) {
    if (page.id != draft.compositeId) return false;
    side = draft.type.sides == 1
        ? 0
        : await _pickSide(context, [for (var i = 0; i < draft.type.sides; i++) draft.type.sideName(i)]);
    if (side == null) return true;
  }
  if (!context.mounted) return true;
  await retakeIdSide(context, side);
  return true;
}

/// Opens the ID card camera to take side [side] again.
Future<void> retakeIdSide(BuildContext context, int side) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => IdCardCaptureScreen(retakeSide: side)));

Future<int?> _pickSide(BuildContext context, List<String> names) => showModalBottomSheet<int>(
  context: context,
  showDragHandle: true,
  builder: (sheet) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('Retake which side?', style: Theme.of(sheet).textTheme.titleLarge),
        ),
        for (var i = 0; i < names.length; i++)
          ListTile(leading: const Icon(LumaIcons.retake), title: Text(names[i]), onTap: () => Navigator.pop(sheet, i)),
      ],
    ),
  ),
);
