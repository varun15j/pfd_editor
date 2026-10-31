import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'models.dart';

/// What is being copied in ID card mode (design/UI_UX_screen/ID-card-scan,
/// screens ID-02 to ID-04). Sizes are the printed size, in millimetres, of
/// the standard ISO/IEC 7810 formats: ID-1 for cards (Aadhaar, PAN, driving
/// licence, bank cards) and an open ID-3 passport for the photo page.
enum IdCopyType {
  singleSide('single_side', 'Single Side', sides: 1, widthMm: 85.6, heightMm: 53.98),
  idCard('id_card', 'ID Card', sides: 2, widthMm: 85.6, heightMm: 53.98),
  passport('passport', 'Passport', sides: 1, widthMm: 125, heightMm: 176);

  const IdCopyType(this.id, this.label, {required this.sides, required this.widthMm, required this.heightMm});

  final String id;
  final String label;

  /// How many photos the copy is made of: front and back for an ID card.
  final int sides;
  final double widthMm;
  final double heightMm;

  /// Width over height of the document.
  double get aspect => widthMm / heightMm;

  /// Shown over the camera and on the review page for side [index].
  String sideName(int index) => switch (this) {
    passport => 'Passport page',
    _ => index == 0 ? 'Front page' : 'Back page',
  };

  /// One line under the A4 example on the type picker.
  String get description => switch (this) {
    idCard => 'Both sides of a card on one A4 page, at their real size. Ready to print or share.',
    singleSide => 'One side of a card on an A4 page, at its real size.',
    passport => 'The open photo page of a passport on an A4 page, at its real size.',
  };
}

/// How big the document is printed: its real size, or half as big again
/// for small print that is hard to read.
enum IdCopyScale {
  actual('Actual size', 1),
  large('Large', 1.5);

  const IdCopyScale(this.label, this.factor);

  final String label;
  final double factor;
}

/// Paper sizes in millimetres. Only A4 and Letter make sense for a copy.
Size paperSizeMm(PdfPageSize paper) => switch (paper) {
  PdfPageSize.letter => const Size(215.9, 279.4),
  _ => const Size(210, 297),
};

/// The blank border every printer can reach, in millimetres.
const _marginMm = 15.0;

/// Space between the front and the back.
const _gapMm = 15.0;

/// Where each side goes on the page, normalized to the paper (0..1 on both
/// axes), in side order. The sides keep their real size, times [scale],
/// unless that would not fit inside the margins, when they shrink just
/// enough to fit. The block of sides is centred on the page.
List<Rect> idCopySlots(IdCopyType type, {PdfPageSize paper = PdfPageSize.a4, IdCopyScale scale = IdCopyScale.actual}) {
  final page = paperSizeMm(paper);
  final n = type.sides;
  var w = type.widthMm * scale.factor, h = type.heightMm * scale.factor;
  final gap = _gapMm * (n - 1);
  final fit = math.min(1.0, math.min((page.width - 2 * _marginMm) / w, (page.height - 2 * _marginMm - gap) / (h * n)));
  w *= fit;
  h *= fit;
  final left = (page.width - w) / 2;
  var top = (page.height - (h * n + gap)) / 2;
  final slots = <Rect>[];
  for (var i = 0; i < n; i++) {
    slots.add(Rect.fromLTWH(left / page.width, top / page.height, w / page.width, h / page.height));
    top += h + _gapMm;
  }
  return slots;
}

/// Where each of [count] pictures goes in a collage page (1 to 4): one or
/// two stacked, three or four in a grid of two columns. Each cell keeps the
/// page's margins and a gap to its neighbours; pictures are fitted inside.
List<Rect> collageSlots(int count, {PdfPageSize paper = PdfPageSize.a4}) {
  assert(count >= 1 && count <= maxCollagePictures);
  final page = paperSizeMm(paper);
  final columns = count <= 2 ? 1 : 2;
  final rows = (count / columns).ceil();
  final cellW = (page.width - 2 * _marginMm - (columns - 1) * _gapMm) / columns;
  final cellH = (page.height - 2 * _marginMm - (rows - 1) * _gapMm) / rows;
  return [
    for (var i = 0; i < count; i++)
      Rect.fromLTWH(
        (_marginMm + (i % columns) * (cellW + _gapMm)) / page.width,
        (_marginMm + (i ~/ columns) * (cellH + _gapMm)) / page.height,
        cellW / page.width,
        cellH / page.height,
      ),
  ];
}

const maxCollagePictures = 4;

/// The longest watermark, so it still fits across a card (US-ID-01.7).
const maxWatermarkLength = 60;

/// Checks a watermark typed in Add Watermark. Returns the message to show,
/// or null when [text] can be used.
String? validateWatermark(String text) {
  final t = text.trim();
  if (t.isEmpty) return 'Add a purpose or remove the watermark.';
  if (t.length > maxWatermarkLength) return 'Use $maxWatermarkLength characters or fewer.';
  return null;
}

/// The ID copy being made: its type, the draft pages holding each side, the
/// watermark and the layout. Only page ids are kept, because the pages
/// themselves live in the scan draft, where crop, filter and masks edit them.
@immutable
class IdCopyDraft {
  const IdCopyDraft({
    required this.type,
    this.sideIds = const [],
    this.watermark,
    this.paper = PdfPageSize.a4,
    this.scale = IdCopyScale.actual,
    this.compositeId,
  });

  final IdCopyType type;

  /// Draft page id of each side taken so far, in side order.
  final List<String> sideIds;

  /// Text printed across each side, or null for none.
  final String? watermark;
  final PdfPageSize paper;
  final IdCopyScale scale;

  /// The draft page holding the finished copy, once made.
  final String? compositeId;

  bool get complete => sideIds.length >= type.sides;

  /// The side to take next.
  int get nextSide => math.min(sideIds.length, type.sides - 1);

  IdCopyDraft withSide(int index, String pageId) {
    final ids = [...sideIds];
    if (index < ids.length) {
      ids[index] = pageId;
    } else {
      ids.add(pageId);
    }
    return _copy(sideIds: List.unmodifiable(ids));
  }

  /// Front becomes back and back becomes front. The pictures are not
  /// changed, only which side each one is.
  IdCopyDraft swapped() => sideIds.length < 2 ? this : _copy(sideIds: List.unmodifiable(sideIds.reversed));

  IdCopyDraft withWatermark(String? text) => IdCopyDraft(
    type: type,
    sideIds: sideIds,
    watermark: text == null || text.trim().isEmpty ? null : text.trim(),
    paper: paper,
    scale: scale,
    compositeId: compositeId,
  );

  IdCopyDraft withComposite(String? id) =>
      IdCopyDraft(type: type, sideIds: sideIds, watermark: watermark, paper: paper, scale: scale, compositeId: id);

  IdCopyDraft _copy({List<String>? sideIds, PdfPageSize? paper, IdCopyScale? scale}) => IdCopyDraft(
    type: type,
    sideIds: sideIds ?? this.sideIds,
    watermark: watermark,
    paper: paper ?? this.paper,
    scale: scale ?? this.scale,
    compositeId: compositeId,
  );

  IdCopyDraft withLayout({PdfPageSize? paper, IdCopyScale? scale}) => _copy(paper: paper, scale: scale);

  /// Keeps the copy pointing at its pages when the draft goes from [before]
  /// to [after] (page ids, in order). A side or the copy page that was
  /// replaced in place, as a retake does, follows to the page now in its
  /// place, and an undo of that follows back. A page that was removed stays
  /// missing, so the review asks for it again.
  IdCopyDraft followPages(List<String> before, List<String> after) {
    if (before.length != after.length) return this;
    final present = after.toSet();
    final earlier = before.toSet();
    String? follow(String? id) {
      if (id == null || present.contains(id)) return id;
      final at = before.indexOf(id);
      return at >= 0 && !earlier.contains(after[at]) ? after[at] : id;
    }

    final sides = [for (final id in sideIds) follow(id)!];
    final composite = follow(compositeId);
    if (listEquals(sides, sideIds) && composite == compositeId) return this;
    return IdCopyDraft(
      type: type,
      sideIds: List.unmodifiable(sides),
      watermark: watermark,
      paper: paper,
      scale: scale,
      compositeId: composite,
    );
  }

  Map<String, Object?> toJson() => {
    'type': type.id,
    'sideIds': sideIds,
    if (watermark != null) 'watermark': watermark,
    'paper': paper.name,
    'scale': scale.name,
    if (compositeId != null) 'compositeId': compositeId,
  };

  /// Null when [json] is not an ID copy this version understands.
  static IdCopyDraft? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = IdCopyType.values.where((t) => t.id == json['type']).firstOrNull;
    if (type == null) return null;
    final sides = json['sideIds'];
    final watermark = json['watermark'];
    final composite = json['compositeId'];
    return IdCopyDraft(
      type: type,
      sideIds: List.unmodifiable(sides is List ? sides.whereType<String>() : const <String>[]),
      watermark: watermark is String ? watermark : null,
      paper: PdfPageSize.values.where((p) => p.name == json['paper']).firstOrNull ?? PdfPageSize.a4,
      scale: IdCopyScale.values.where((s) => s.name == json['scale']).firstOrNull ?? IdCopyScale.actual,
      compositeId: composite is String ? composite : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IdCopyDraft &&
      other.type == type &&
      listEquals(other.sideIds, sideIds) &&
      other.watermark == watermark &&
      other.paper == paper &&
      other.scale == scale &&
      other.compositeId == compositeId;

  @override
  int get hashCode => Object.hash(type, Object.hashAll(sideIds), watermark, paper, scale, compositeId);
}
