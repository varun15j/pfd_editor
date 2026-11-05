import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../model.dart';

/// Paints Word borders (single, double, thick, dotted, dashed...) around a
/// box, with optional fill and diagonal lines.
class WordBorderPainter extends CustomPainter {
  WordBorderPainter({required this.borders, required this.unit, this.fill, this.inset = 0});

  final WordBorders? borders;
  final double unit;
  final Color? fill;

  /// Draw the lines this far inside the box (page borders).
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);
    if (fill != null) canvas.drawRect(r, Paint()..color = fill!);
    final b = borders;
    if (b == null) return;
    paintLine(canvas, b.top, r.topLeft, r.topRight, unit);
    paintLine(canvas, b.bottom, r.bottomLeft, r.bottomRight, unit);
    paintLine(canvas, b.left, r.topLeft, r.bottomLeft, unit);
    paintLine(canvas, b.right, r.topRight, r.bottomRight, unit);
    paintLine(canvas, b.diagonalDown, r.topLeft, r.bottomRight, unit);
    paintLine(canvas, b.diagonalUp, r.bottomLeft, r.topRight, unit);
  }

  @override
  bool shouldRepaint(WordBorderPainter old) => old.borders != borders || old.fill != fill || old.unit != unit;
}

void paintLine(Canvas canvas, WordBorder? border, Offset a, Offset b, double unit) {
  if (border == null || !border.isVisible) return;
  final style = border.style;
  var w = (border.width * unit).clamp(0.6, 12.0);
  final color = Color(border.color);
  final paint = Paint()
    ..color = color
    ..strokeWidth = w
    ..style = PaintingStyle.stroke;
  final dir = b - a;
  final len = dir.distance;
  if (len == 0) return;
  final normal = Offset(-dir.dy / len, dir.dx / len);

  void line(Offset p, Offset q, Paint pt) {
    if (style.contains('dot') || style.contains('dash')) {
      final dash = style.contains('dot') && !style.contains('dash') ? w * 1.2 : w * 4;
      final gap = style.contains('dot') && !style.contains('dash') ? w * 1.6 : w * 2.5;
      final path = Path()
        ..moveTo(p.dx, p.dy)
        ..lineTo(q.dx, q.dy);
      for (final m in path.computeMetrics()) {
        var d = 0.0;
        while (d < m.length) {
          canvas.drawPath(m.extractPath(d, (d + dash).clamp(0, m.length)), pt);
          d += dash + gap;
        }
      }
    } else if (style == 'wave' || style == 'doubleWave') {
      final path = Path()..moveTo(p.dx, p.dy);
      final steps = (len / (w * 3)).ceil().clamp(1, 2000);
      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        final base = Offset.lerp(p, q, t)!;
        final off = normal * (i.isOdd ? w : -w);
        path.lineTo(base.dx + off.dx, base.dy + off.dy);
      }
      canvas.drawPath(path, pt);
    } else {
      canvas.drawLine(p, q, pt);
    }
  }

  switch (style) {
    case 'double' || 'triple':
      final thin = Paint()
        ..color = color
        ..strokeWidth = (w / 2).clamp(0.5, 4.0)
        ..style = PaintingStyle.stroke;
      final gap = w.clamp(1.5, 6.0);
      line(a - normal * gap / 2, b - normal * gap / 2, thin);
      line(a + normal * gap / 2, b + normal * gap / 2, thin);
    case final s when s.startsWith('thickThin') || s.startsWith('thinThick'):
      final thin = Paint()
        ..color = color
        ..strokeWidth = (w / 3).clamp(0.5, 3.0)
        ..style = PaintingStyle.stroke;
      final thick = Paint()
        ..color = color
        ..strokeWidth = w
        ..style = PaintingStyle.stroke;
      final gap = w;
      final thickFirst = s.startsWith('thickThin');
      line(a - normal * gap / 2, b - normal * gap / 2, thickFirst ? thick : thin);
      line(a + normal * gap / 2, b + normal * gap / 2, thickFirst ? thin : thick);
    case 'thick':
      paint.strokeWidth = w * 1.5;
      line(a, b, paint);
    case 'threeDEmboss' || 'threeDEngrave' || 'outset' || 'inset':
      final dark = Paint()
        ..color = Color.lerp(color, const Color(0xFF000000), 0.4)!
        ..strokeWidth = w
        ..style = PaintingStyle.stroke;
      final light = Paint()
        ..color = Color.lerp(color, const Color(0xFFFFFFFF), 0.5)!
        ..strokeWidth = w
        ..style = PaintingStyle.stroke;
      line(a - normal * w / 2, b - normal * w / 2, style == 'threeDEngrave' || style == 'inset' ? dark : light);
      line(a + normal * w / 2, b + normal * w / 2, style == 'threeDEngrave' || style == 'inset' ? light : dark);
    default:
      line(a, b, paint);
  }
  w = 0;
}

/// Word's leader characters, drawn between a tab and the text after it.
void paintLeader(Canvas canvas, String leader, double x1, double x2, double baseline, TextStyle style) {
  if (x2 - x1 < 2 || leader == 'none') return;
  final color = style.color ?? const Color(0xFF000000);
  final size = style.fontSize ?? 12;
  if (leader == 'underscore' || leader == 'heavy') {
    canvas.drawLine(
      Offset(x1, baseline + 1),
      Offset(x2, baseline + 1),
      Paint()
        ..color = color
        ..strokeWidth = leader == 'heavy' ? 1.6 : 0.8,
    );
    return;
  }
  final ch = switch (leader) {
    'hyphen' => '-',
    'middleDot' => '·',
    _ => '.',
  };
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: size))
    ..pushStyle(ui.TextStyle(color: color, fontSize: size, fontFamily: style.fontFamily, fontFamilyFallback: style.fontFamilyFallback))
    ..addText(ch);
  final para = builder.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
  final step = (para.maxIntrinsicWidth * 1.4).clamp(2.0, 40.0);
  final top = baseline - para.alphabeticBaseline;
  var x = (x1 / step).ceil() * step;
  while (x + para.maxIntrinsicWidth <= x2 - step * 0.3) {
    canvas.drawParagraph(para, Offset(x, top));
    x += step;
  }
}
