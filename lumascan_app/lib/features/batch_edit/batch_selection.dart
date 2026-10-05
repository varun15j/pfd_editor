import 'package:flutter/foundation.dart';

import '../../domain/models.dart';

/// Pages picked in Batch Review, kept by page ID so the selection follows
/// pages when they are reordered. It lives only as long as the screen; the
/// pages and their edits are saved with the draft as usual.
@immutable
class BatchSelection {
  const BatchSelection([this.ids = const {}]);

  /// Every page selected, which is how Batch Review opens.
  BatchSelection.all(List<ScanPage> pages) : ids = {for (final p in pages) p.id};

  final Set<String> ids;

  int get count => ids.length;
  bool get isEmpty => ids.isEmpty;
  bool get isSingle => ids.length == 1;

  bool contains(String id) => ids.contains(id);

  bool coversAll(List<ScanPage> pages) => pages.isNotEmpty && pages.every((p) => ids.contains(p.id));

  BatchSelection toggle(String id) => BatchSelection(ids.contains(id) ? ({...ids}..remove(id)) : {...ids, id});

  /// Drops IDs of pages that are no longer in the draft, such as deleted ones.
  BatchSelection retain(List<ScanPage> pages) {
    final kept = {
      for (final p in pages)
        if (ids.contains(p.id)) p.id,
    };
    return kept.length == ids.length ? this : BatchSelection(kept);
  }

  /// The selected pages in document order.
  List<ScanPage> pagesIn(List<ScanPage> pages) => [
    for (final p in pages)
      if (ids.contains(p.id)) p,
  ];

  @override
  bool operator ==(Object other) => other is BatchSelection && setEquals(other.ids, ids);

  @override
  int get hashCode => Object.hashAllUnordered(ids);
}
