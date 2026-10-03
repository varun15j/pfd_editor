import 'package:flutter/material.dart';

/// Three stroke and text sizes shared by every markup tool.
enum MarkupSize {
  thin('Thin'),
  medium('Medium'),
  thick('Thick');

  const MarkupSize(this.label);
  final String label;
}

/// The colour and thickness the pen, highlighter and text tools draw with.
/// One style feeds all three, so changing it for one tool keeps it for the
/// next. Widths and font sizes are fractions of the page width, like every
/// other annotation measure.
@immutable
class MarkupStyle {
  const MarkupStyle({this.color = ink, this.size = MarkupSize.medium});

  static const ink = Color(0xFF172D2A);

  /// Dark inks for writing, brighter ones that still read as a highlighter
  /// at 35% opacity.
  static const palette = [
    ink,
    Color(0xFF1E4FD8),
    Color(0xFFC62828),
    Color(0xFF086B61),
    Color(0xFFFFC400),
    Color(0xFFE91E8C),
  ];

  static const _pen = [0.003, 0.005, 0.01];
  static const _highlighter = [0.014, 0.022, 0.034];
  static const _text = [0.028, 0.035, 0.05];

  final Color color;
  final MarkupSize size;

  double inkWidth({required bool highlighter}) => (highlighter ? _highlighter : _pen)[size.index];

  double get fontSize => _text[size.index];

  MarkupStyle copyWith({Color? color, MarkupSize? size}) =>
      MarkupStyle(color: color ?? this.color, size: size ?? this.size);

  @override
  bool operator ==(Object other) => other is MarkupStyle && other.color == color && other.size == size;

  @override
  int get hashCode => Object.hash(color, size);
}
