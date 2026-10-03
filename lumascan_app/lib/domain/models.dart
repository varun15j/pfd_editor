import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Document filter presets. Ids follow docs/document.md so recipes stay
/// compatible when more presets are added later.
enum DocumentFilter {
  original('original', 'Original'),
  magicColor('magic_color', 'Magic Color'),
  grayscale('grayscale', 'Grayscale'),
  blackWhite('black_white', 'B&W');

  const DocumentFilter(this.id, this.label);

  final String id;
  final String label;

  static DocumentFilter fromId(String id) =>
      values.firstWhere((f) => f.id == id, orElse: () => DocumentFilter.original);
}

/// A point normalized to the oriented source image: (0,0) is top-left and
/// (1,1) is bottom-right.
@immutable
class NormPoint {
  const NormPoint(this.x, this.y);

  final double x;
  final double y;

  NormPoint clamp() => NormPoint(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));

  List<double> toJson() => [x, y];

  static NormPoint fromJson(Object? json) {
    final list = json! as List;
    return NormPoint((list[0] as num).toDouble(), (list[1] as num).toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is NormPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// Crop quadrilateral ordered top-left, top-right, bottom-right, bottom-left.
@immutable
class CropQuad {
  const CropQuad(this.tl, this.tr, this.br, this.bl);

  static const full = CropQuad(
    NormPoint(0, 0),
    NormPoint(1, 0),
    NormPoint(1, 1),
    NormPoint(0, 1),
  );

  final NormPoint tl;
  final NormPoint tr;
  final NormPoint br;
  final NormPoint bl;

  List<NormPoint> get points => [tl, tr, br, bl];

  bool get isFull => this == full;

  List<List<double>> toJson() => [for (final p in points) p.toJson()];

  static CropQuad fromJson(Object? json) {
    final pts = [for (final p in json! as List) NormPoint.fromJson(p)];
    return CropQuad(pts[0], pts[1], pts[2], pts[3]);
  }

  CropQuad withPoint(int index, NormPoint p) {
    final pts = [...points];
    pts[index] = p.clamp();
    return CropQuad(pts[0], pts[1], pts[2], pts[3]);
  }

  /// True when the quad is convex, keeps its corners in clockwise TL, TR, BR,
  /// BL order (so the page is not mirrored), and covers at least [minArea] of
  /// the image (LLD section 7 validation rules).
  bool isValid({double minArea = 0.02}) {
    final pts = points;
    for (var i = 0; i < 4; i++) {
      final a = pts[i], b = pts[(i + 1) % 4], c = pts[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross <= 1e-9) return false;
    }
    return area >= minArea;
  }

  double get area {
    final pts = points;
    var sum = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = pts[i], b = pts[(i + 1) % 4];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum.abs() / 2;
  }

  @override
  bool operator ==(Object other) =>
      other is CropQuad &&
      other.tl == tl &&
      other.tr == tr &&
      other.br == br &&
      other.bl == bl;

  @override
  int get hashCode => Object.hash(tl, tr, br, bl);
}

/// Non-destructive edits for a page. The captured original is never changed;
/// every preview and export is rendered from the original plus this recipe.
@immutable
class EditRecipe {
  const EditRecipe({
    this.crop = CropQuad.full,
    this.quarterTurns = 0,
    this.filter = DocumentFilter.original,
  });

  final CropQuad crop;

  /// Clockwise quarter turns applied after the crop, 0..3.
  final int quarterTurns;
  final DocumentFilter filter;

  EditRecipe copyWith({
    CropQuad? crop,
    int? quarterTurns,
    DocumentFilter? filter,
  }) =>
      EditRecipe(
        crop: crop ?? this.crop,
        quarterTurns: (quarterTurns ?? this.quarterTurns) % 4,
        filter: filter ?? this.filter,
      );

  Map<String, Object?> toJson() => {
        if (!crop.isFull) 'crop': crop.toJson(),
        'quarterTurns': quarterTurns,
        'filter': filter.id,
      };

  static EditRecipe fromJson(Map<String, Object?> json) => EditRecipe(
        crop: json['crop'] == null ? CropQuad.full : CropQuad.fromJson(json['crop']),
        quarterTurns: ((json['quarterTurns'] as num?)?.toInt() ?? 0) % 4,
        filter: DocumentFilter.fromId(json['filter'] as String? ?? DocumentFilter.original.id),
      );

  /// Stable key used to cache rendered derivatives.
  String get cacheKey {
    final q = crop.points.map((p) => '${p.x.toStringAsFixed(4)},${p.y.toStringAsFixed(4)}').join(';');
    return '$q|$quarterTurns|${filter.id}';
  }

  @override
  bool operator ==(Object other) =>
      other is EditRecipe &&
      other.crop == crop &&
      other.quarterTurns == quarterTurns &&
      other.filter == filter;

  @override
  int get hashCode => Object.hash(crop, quarterTurns, filter);
}

@immutable
class ScanPage {
  const ScanPage({
    required this.id,
    required this.originalPath,
    this.recipe = const EditRecipe(),
  });

  final String id;

  /// App-owned copy of the captured image. Never modified.
  final String originalPath;
  final EditRecipe recipe;

  ScanPage copyWith({EditRecipe? recipe}) =>
      ScanPage(id: id, originalPath: originalPath, recipe: recipe ?? this.recipe);

  /// [originalPath] is stored by file name only, because the app's private
  /// folder can move between launches (iOS changes it on every update).
  /// [fromJson] resolves it against the current originals folder.
  Map<String, Object?> toJson() => {'id': id, 'file': path.basename(originalPath), 'recipe': recipe.toJson()};

  static ScanPage fromJson(Map<String, Object?> json, {required String originalsDir}) => ScanPage(
        id: json['id']! as String,
        originalPath: path.join(originalsDir, json['file']! as String),
        recipe: EditRecipe.fromJson((json['recipe'] as Map?)?.cast<String, Object?>() ?? const {}),
      );
}

enum PdfPageSize {
  a4('A4'),
  letter('Letter'),
  fitImage('Fit to image');

  const PdfPageSize(this.label);
  final String label;
}

enum ExportQuality {
  high('High', maxDimension: 2400, jpegQuality: 90, bitsPerPixel: 0.9, hint: 'Sharp text, best for printing'),
  medium('Medium', maxDimension: 1700, jpegQuality: 80, bitsPerPixel: 0.6, hint: 'Good for email and sharing'),
  small('Small file', maxDimension: 1200, jpegQuality: 65, bitsPerPixel: 0.4, hint: 'Smallest, for reading on screen');

  const ExportQuality(
    this.label, {
    required this.maxDimension,
    required this.jpegQuality,
    required this.bitsPerPixel,
    required this.hint,
  });

  final String label;
  final int maxDimension;
  final int jpegQuality;

  /// Typical compressed size of a scanned page, used only for size estimates.
  final double bitsPerPixel;
  final String hint;
}
