import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model.dart';
import 'context.dart';

/// Builds the content of a shape (its text box blocks). Set by the block
/// renderer to avoid an import cycle.
typedef BlocksBuilder = Widget Function(List<WordBlock> blocks, WordRenderContext ctx);

/// Shrinks a drawing to fit [maxWidth], keeping its shape.
Size fitSize(double w, double h, double maxWidth) {
  if (w <= 0 || h <= 0) return Size(math.max(w, 1), math.max(h, 1));
  if (w <= maxWidth || maxWidth <= 0) return Size(w, h);
  return Size(maxWidth, h * maxWidth / w);
}

Widget _transformed(Widget child, WordDrawingStyle look) {
  if (look.flipH || look.flipV) {
    child = Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(look.flipH ? -1 : 1, look.flipV ? -1 : 1, 1),
      child: child,
    );
  }
  if (look.rotation != 0) child = Transform.rotate(angle: look.rotation * math.pi / 180, child: child);
  return child;
}

class WordPictureView extends StatelessWidget {
  const WordPictureView(this.picture, this.ctx, {super.key});

  final WordPicture picture;
  final WordRenderContext ctx;

  @override
  Widget build(BuildContext context) {
    final p = picture;
    final size = fitSize(ctx.pt(p.width), ctx.pt(p.height), ctx.width);
    final c = p.crop;
    final keepW = (1 - c.left - c.right).clamp(0.01, 1.0), keepH = (1 - c.top - c.bottom).clamp(0.01, 1.0);
    final fullW = size.width / keepW, fullH = size.height / keepH;
    Widget image = Image.memory(
      p.bytes,
      width: fullW,
      height: fullH,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => WordPlaceholder(label: p.altText ?? 'Picture', width: fullW, height: fullH),
    );
    if (c.left != 0 || c.top != 0 || c.right != 0 || c.bottom != 0) {
      image = ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: fullW,
          maxWidth: fullW,
          minHeight: fullH,
          maxHeight: fullH,
          child: Transform.translate(offset: Offset(-c.left * fullW, -c.top * fullH), child: image),
        ),
      );
    }
    image = SizedBox(width: size.width, height: size.height, child: image);
    if (p.grayscale) {
      image = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: image,
      );
    }
    switch (p.shape) {
      case 'ellipse':
        image = ClipOval(child: image);
      case 'roundRect' || 'snipRoundRect' || 'round2SameRect':
        image = ClipRRect(borderRadius: BorderRadius.circular(math.min(size.width, size.height) * 0.16), child: image);
    }
    if (p.opacity < 1) image = Opacity(opacity: p.opacity.clamp(0, 1), child: image);
    final look = p.look;
    if (look.outlineColor != null || look.shadow != null) {
      final shape = p.shape == 'ellipse' ? BoxShape.circle : BoxShape.rectangle;
      image = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          shape: shape,
          border: look.outlineColor == null ? null : Border.all(color: Color(look.outlineColor!), width: ctx.pt(look.outlineWidth).clamp(0.5, 20)),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: shape,
            boxShadow: look.shadow == null
                ? null
                : [
                    BoxShadow(
                      color: Color(look.shadow!.color),
                      blurRadius: ctx.pt(look.shadow!.blur),
                      offset: Offset(ctx.pt(look.shadow!.dx), ctx.pt(look.shadow!.dy)),
                    ),
                  ],
          ),
          child: image,
        ),
      );
    }
    image = _transformed(image, look);
    final label = p.altText ?? p.title;
    return label == null || label.isEmpty ? image : Semantics(image: true, label: label, child: image);
  }
}

class WordPlaceholder extends StatelessWidget {
  const WordPlaceholder({super.key, required this.label, required this.width, required this.height});

  final String label;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFF1F1F1),
      border: Border.all(color: const Color(0xFFBDBDBD)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Text(
        label,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        maxLines: 3,
        style: const TextStyle(fontSize: 11, color: Color(0xFF616161)),
      ),
    ),
  );
}

class WordShapeView extends StatelessWidget {
  const WordShapeView(this.shape, this.ctx, this.buildBlocks, {super.key});

  final WordShape shape;
  final WordRenderContext ctx;
  final BlocksBuilder buildBlocks;

  @override
  Widget build(BuildContext context) {
    final s = shape;
    final size = fitSize(ctx.pt(s.width), ctx.pt(s.height), ctx.width);
    final vertical = s.verticalText != null;
    final innerW = math.max(1.0, (vertical ? size.height : size.width) - ctx.pt(s.insets.left + s.insets.right));
    Widget? text;
    if (s.blocks.isNotEmpty) {
      text = buildBlocks(s.blocks, ctx.withWidth(innerW));
      text = Padding(
        padding: EdgeInsets.fromLTRB(ctx.pt(s.insets.left), ctx.pt(s.insets.top), ctx.pt(s.insets.right), ctx.pt(s.insets.bottom)),
        child: text,
      );
      if (vertical) {
        text = RotatedBox(quarterTurns: s.verticalText == 'vert270' || s.verticalText == 'wordArtVertRtl' ? 3 : 1, child: SizedBox(width: size.height, child: text));
      }
      text = Align(
        alignment: switch (s.textAnchor) {
          'ctr' => Alignment.center,
          'b' => Alignment.bottomCenter,
          _ => Alignment.topCenter,
        },
        child: text,
      );
    }
    final isLine = s.geometry == 'line' || s.geometry.contains('Connector');
    Widget body = CustomPaint(
      painter: ShapePainter(
        geometry: s.geometry,
        fill: s.fill == null ? null : Color(s.fill!),
        gradient: s.gradient.map(Color.new).toList(),
        gradientAngle: s.gradientAngle,
        outline: s.look.outlineColor == null ? null : Color(s.look.outlineColor!),
        outlineWidth: ctx.pt(s.look.outlineWidth),
        dash: s.look.outlineDash,
        shadow: s.look.shadow,
        unit: ctx.unit,
        flipH: s.look.flipH,
        flipV: s.look.flipV,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: size.width, maxWidth: size.width, minHeight: isLine ? math.max(size.height, 2) : size.height),
        child: text,
      ),
    );
    if (s.look.rotation != 0) body = Transform.rotate(angle: s.look.rotation * math.pi / 180, child: body);
    return body;
  }
}

/// Draws Word's preset shapes.
class ShapePainter extends CustomPainter {
  ShapePainter({
    required this.geometry,
    this.fill,
    this.gradient = const [],
    this.gradientAngle = 0,
    this.outline,
    this.outlineWidth = 1,
    this.dash,
    this.shadow,
    this.unit = 1,
    this.flipH = false,
    this.flipV = false,
  });

  final String geometry;
  final Color? fill;
  final List<Color> gradient;
  final double gradientAngle;
  final Color? outline;
  final double outlineWidth;
  final String? dash;
  final WordShadow? shadow;
  final double unit;
  final bool flipH;
  final bool flipV;

  static Path pathFor(String geometry, Size size) {
    final w = size.width, h = size.height;
    final p = Path();
    Offset o(double x, double y) => Offset(x * w, y * h);
    void poly(List<Offset> pts) {
      p.addPolygon(pts, true);
    }

    switch (geometry) {
      case 'ellipse' || 'flowChartConnector' || 'donut' || 'smileyFace' || 'cloud' || 'cloudCallout':
        p.addOval(Offset.zero & size);
      case 'roundRect' || 'flowChartAlternateProcess' || 'round2SameRect' || 'snipRoundRect':
        p.addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(math.min(w, h) * 0.1667)));
      case 'triangle' || 'flowChartExtract':
        poly([o(0.5, 0), o(1, 1), o(0, 1)]);
      case 'rtTriangle':
        poly([o(0, 0), o(1, 1), o(0, 1)]);
      case 'diamond' || 'flowChartDecision':
        poly([o(0.5, 0), o(1, 0.5), o(0.5, 1), o(0, 0.5)]);
      case 'parallelogram' || 'flowChartInputOutput':
        poly([o(0.25, 0), o(1, 0), o(0.75, 1), o(0, 1)]);
      case 'trapezoid':
        poly([o(0.25, 0), o(0.75, 0), o(1, 1), o(0, 1)]);
      case 'pentagon' || 'homePlate':
        poly([o(0, 0), o(0.8, 0), o(1, 0.5), o(0.8, 1), o(0, 1)]);
      case 'chevron':
        poly([o(0, 0), o(0.75, 0), o(1, 0.5), o(0.75, 1), o(0, 1), o(0.25, 0.5)]);
      case 'hexagon':
        poly([o(0.25, 0), o(0.75, 0), o(1, 0.5), o(0.75, 1), o(0.25, 1), o(0, 0.5)]);
      case 'octagon':
        poly([o(0.3, 0), o(0.7, 0), o(1, 0.3), o(1, 0.7), o(0.7, 1), o(0.3, 1), o(0, 0.7), o(0, 0.3)]);
      case 'rightArrow':
        poly([o(0, 0.25), o(0.6, 0.25), o(0.6, 0), o(1, 0.5), o(0.6, 1), o(0.6, 0.75), o(0, 0.75)]);
      case 'leftArrow':
        poly([o(1, 0.25), o(0.4, 0.25), o(0.4, 0), o(0, 0.5), o(0.4, 1), o(0.4, 0.75), o(1, 0.75)]);
      case 'upArrow':
        poly([o(0.25, 1), o(0.25, 0.4), o(0, 0.4), o(0.5, 0), o(1, 0.4), o(0.75, 0.4), o(0.75, 1)]);
      case 'downArrow':
        poly([o(0.25, 0), o(0.25, 0.6), o(0, 0.6), o(0.5, 1), o(1, 0.6), o(0.75, 0.6), o(0.75, 0)]);
      case 'leftRightArrow':
        poly([o(0, 0.5), o(0.2, 0), o(0.2, 0.25), o(0.8, 0.25), o(0.8, 0), o(1, 0.5), o(0.8, 1), o(0.8, 0.75), o(0.2, 0.75), o(0.2, 1)]);
      case 'plus' || 'mathPlus':
        poly([o(0.35, 0), o(0.65, 0), o(0.65, 0.35), o(1, 0.35), o(1, 0.65), o(0.65, 0.65), o(0.65, 1), o(0.35, 1), o(0.35, 0.65), o(0, 0.65), o(0, 0.35), o(0.35, 0.35)]);
      case 'star4' || 'star5' || 'star6' || 'star7' || 'star8' || 'star10' || 'star12' || 'star16' || 'star24':
        final n = int.parse(geometry.substring(4));
        final pts = <Offset>[];
        final inner = n == 4 ? 0.38 : (n == 5 ? 0.38 : 0.5);
        for (var i = 0; i < n * 2; i++) {
          final r = i.isEven ? 0.5 : 0.5 * inner;
          final a = -math.pi / 2 + i * math.pi / n;
          pts.add(o(0.5 + r * math.cos(a), 0.5 + r * math.sin(a)));
        }
        poly(pts);
      case 'heart':
        p
          ..moveTo(w * 0.5, h * 0.25)
          ..cubicTo(w * 0.5, h * -0.05, w * -0.1, h * 0.0, w * 0.0, h * 0.35)
          ..cubicTo(w * 0.05, h * 0.6, w * 0.4, h * 0.8, w * 0.5, h)
          ..cubicTo(w * 0.6, h * 0.8, w * 0.95, h * 0.6, w, h * 0.35)
          ..cubicTo(w * 1.1, h * 0.0, w * 0.5, h * -0.05, w * 0.5, h * 0.25)
          ..close();
      case 'wedgeRectCallout' || 'wedgeRoundRectCallout' || 'borderCallout1' || 'callout1':
        p
          ..moveTo(0, 0)
          ..lineTo(w, 0)
          ..lineTo(w, h * 0.8)
          ..lineTo(w * 0.45, h * 0.8)
          ..lineTo(w * 0.2, h * 1.15)
          ..lineTo(w * 0.25, h * 0.8)
          ..lineTo(0, h * 0.8)
          ..close();
      case 'wedgeEllipseCallout':
        p
          ..addOval(Rect.fromLTWH(0, 0, w, h * 0.85))
          ..addPolygon([o(0.25, 0.7), o(0.15, 1.1), o(0.4, 0.8)], true);
      case 'can' || 'flowChartMagneticDisk':
        p
          ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.elliptical(w / 2, h * 0.12)))
          ..addOval(Rect.fromLTWH(0, 0, w, h * 0.24));
      case 'line' || 'straightConnector1' || 'bentConnector2' || 'bentConnector3' || 'curvedConnector3':
        p
          ..moveTo(0, 0)
          ..lineTo(w, h);
      default:
        p.addRect(Offset.zero & size);
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (flipH || flipV) {
      canvas.translate(flipH ? size.width : 0, flipV ? size.height : 0);
      canvas.scale(flipH ? -1 : 1, flipV ? -1 : 1);
    }
    final path = pathFor(geometry, size);
    final isLine = geometry == 'line' || geometry.contains('Connector');
    if (shadow != null && !isLine) {
      canvas.drawShadow(path.shift(Offset(shadow!.dx * unit, shadow!.dy * unit)), Color(shadow!.color), shadow!.blur * unit / 2, false);
    }
    if (!isLine && (fill != null || gradient.length >= 2)) {
      final paint = Paint();
      if (gradient.length >= 2) {
        final a = gradientAngle * math.pi / 180;
        final c = size.center(Offset.zero);
        final d = Offset(math.cos(a), math.sin(a)) * (size.longestSide / 2);
        paint.shader = LinearGradient(colors: gradient).createShader(Rect.fromPoints(c - d, c + d));
      } else {
        paint.color = fill!;
      }
      canvas.drawPath(path, paint);
    }
    if (outline != null && outlineWidth > 0) {
      final paint = Paint()
        ..color = outline!
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.5, outlineWidth);
      if (dash != null && dash != 'solid') {
        final on = dash!.contains('dot') && !dash!.contains('ash') ? paint.strokeWidth : paint.strokeWidth * (dash!.startsWith('lg') ? 8 : 4);
        final off = paint.strokeWidth * 3;
        for (final m in path.computeMetrics()) {
          var d = 0.0;
          while (d < m.length) {
            canvas.drawPath(m.extractPath(d, math.min(m.length, d + on)), paint);
            d += on + off;
          }
        }
      } else {
        canvas.drawPath(path, paint);
      }
      if (isLine) {
        // Arrow head at the end, as Word's default for connectors with tailEnd.
        final end = Offset(size.width, size.height);
        final dir = end / math.max(1, end.distance);
        final n = Offset(-dir.dy, dir.dx);
        final head = paint.strokeWidth * 4;
        canvas.drawPath(
          Path()
            ..moveTo(end.dx, end.dy)
            ..lineTo(end.dx - dir.dx * head + n.dx * head / 2, end.dy - dir.dy * head + n.dy * head / 2)
            ..lineTo(end.dx - dir.dx * head - n.dx * head / 2, end.dy - dir.dy * head - n.dy * head / 2)
            ..close(),
          Paint()..color = outline!,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ShapePainter old) => old.geometry != geometry || old.fill != fill || old.outline != outline;
}

// ---------------------------------------------------------------- charts

const _palette = [
  Color(0xFF4472C4),
  Color(0xFFED7D31),
  Color(0xFFA5A5A5),
  Color(0xFFFFC000),
  Color(0xFF5B9BD5),
  Color(0xFF70AD47),
  Color(0xFF264478),
  Color(0xFF9E480E),
];

class WordChartView extends StatelessWidget {
  const WordChartView(this.chart, this.ctx, {super.key});

  final WordChart chart;
  final WordRenderContext ctx;

  @override
  Widget build(BuildContext context) {
    final size = fitSize(ctx.pt(chart.width), ctx.pt(chart.height), ctx.width);
    final label = '${chart.title ?? 'Chart'}: ${chart.series.map((s) => '${s.name} ${s.values.join(', ')}').join('; ')}';
    return Semantics(
      label: label,
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFD9D9D9))),
        child: CustomPaint(painter: ChartPainter(chart, ctx.unit)),
      ),
    );
  }
}

class ChartPainter extends CustomPainter {
  ChartPainter(this.chart, this.unit);

  final WordChart chart;
  final double unit;

  TextPainter _text(String s, double size, {Color color = const Color(0xFF595959), FontWeight weight = FontWeight.w400}) =>
      TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: weight, fontFamilyFallback: const ['sans-serif', 'Roboto'])),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 400 * unit);

  Color _seriesColor(int i) => chart.series[i].color == null ? _palette[i % _palette.length] : Color(chart.series[i].color!);

  @override
  void paint(Canvas canvas, Size size) {
    final pad = 8 * unit;
    var top = pad;
    final fs = 9 * unit;
    if (chart.title != null && chart.title!.isNotEmpty) {
      final t = _text(chart.title!, 12 * unit, color: const Color(0xFF404040), weight: FontWeight.w600);
      t.paint(canvas, Offset((size.width - t.width) / 2, top));
      top += t.height + 4 * unit;
    }
    final pie = chart.kind == WordChartKind.pie || chart.kind == WordChartKind.doughnut;
    // Legend along the bottom.
    final legendItems = pie
        ? [for (var i = 0; i < chart.categories.length; i++) (chart.categories[i], _pointColor(i))]
        : [for (var i = 0; i < chart.series.length; i++) (chart.series[i].name, _seriesColor(i))];
    final legendH = legendItems.isEmpty ? 0.0 : fs * 1.8;
    if (legendItems.isNotEmpty) {
      var x = pad;
      final painters = [for (final l in legendItems) _text(l.$1, fs)];
      final total = painters.fold<double>(0, (a, p) => a + p.width + fs * 2);
      x = math.max(pad, (size.width - total) / 2);
      final y = size.height - pad - legendH / 2;
      for (var i = 0; i < legendItems.length; i++) {
        canvas.drawRect(Rect.fromLTWH(x, y - fs / 3, fs * 0.7, fs * 0.7), Paint()..color = legendItems[i].$2);
        painters[i].paint(canvas, Offset(x + fs, y - painters[i].height / 2));
        x += painters[i].width + fs * 2;
      }
    }
    final plot = Rect.fromLTRB(pad, top, size.width - pad, size.height - pad - legendH - 2 * unit);
    if (chart.series.isEmpty || plot.height <= 0) return;
    if (pie) {
      _pie(canvas, plot);
    } else {
      _axes(canvas, plot, fs);
    }
  }

  Color _pointColor(int i) {
    final s = chart.series.isEmpty ? null : chart.series.first;
    final c = s != null && i < s.pointColors.length ? s.pointColors[i] : null;
    return c == null ? _palette[i % _palette.length] : Color(c);
  }

  void _pie(Canvas canvas, Rect plot) {
    final values = chart.series.first.values;
    final total = values.fold<double>(0, (a, b) => a + b.abs());
    if (total == 0) return;
    final r = math.min(plot.width, plot.height) / 2;
    final c = plot.center;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i].abs() / total * math.pi * 2;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, true, Paint()..color = _pointColor(i));
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        sweep,
        true,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      final mid = start + sweep / 2;
      final pct = _text('${(values[i] / total * 100).round()}%', 8 * unit, color: Colors.white, weight: FontWeight.w600);
      pct.paint(canvas, c + Offset(math.cos(mid), math.sin(mid)) * r * 0.62 - Offset(pct.width / 2, pct.height / 2));
      start += sweep;
    }
    if (chart.kind == WordChartKind.doughnut) canvas.drawCircle(c, r * 0.5, Paint()..color = Colors.white);
  }

  void _axes(Canvas canvas, Rect plot, double fs) {
    final n = chart.series.fold<int>(0, (m, s) => math.max(m, s.values.length));
    if (n == 0) return;
    var maxV = 0.0, minV = 0.0;
    for (var i = 0; i < n; i++) {
      var stack = 0.0;
      for (final s in chart.series) {
        final v = i < s.values.length ? s.values[i] : 0.0;
        if (chart.stacked) {
          stack += v;
          maxV = math.max(maxV, stack);
        } else {
          maxV = math.max(maxV, v);
          minV = math.min(minV, v);
        }
      }
    }
    if (maxV == minV) maxV = minV + 1;
    final step = _niceStep((maxV - minV) / 5);
    maxV = (maxV / step).ceil() * step;
    minV = (minV / step).floor() * step;
    final horizontal = chart.kind == WordChartKind.bar;
    final labelW = [for (var v = minV; v <= maxV + step / 2; v += step) _text(_fmt(v), fs).width].fold<double>(0, math.max);
    final catH = fs * 1.6;
    final area = horizontal
        ? Rect.fromLTRB(plot.left + _catWidth(fs), plot.top, plot.right, plot.bottom - catH)
        : Rect.fromLTRB(plot.left + labelW + 4 * unit, plot.top, plot.right, plot.bottom - catH);
    final grid = Paint()
      ..color = const Color(0xFFD9D9D9)
      ..strokeWidth = 0.8;
    double valuePos(double v) => horizontal
        ? area.left + (v - minV) / (maxV - minV) * area.width
        : area.bottom - (v - minV) / (maxV - minV) * area.height;
    for (var v = minV; v <= maxV + step / 2; v += step) {
      final t = _text(_fmt(v), fs);
      if (horizontal) {
        final x = valuePos(v);
        canvas.drawLine(Offset(x, area.top), Offset(x, area.bottom), grid);
        t.paint(canvas, Offset(x - t.width / 2, area.bottom + 2 * unit));
      } else {
        final y = valuePos(v);
        canvas.drawLine(Offset(area.left, y), Offset(area.right, y), grid);
        t.paint(canvas, Offset(area.left - t.width - 4 * unit, y - t.height / 2));
      }
    }
    final band = (horizontal ? area.height : area.width) / n;
    for (var i = 0; i < n; i++) {
      final cat = i < chart.categories.length ? chart.categories[i] : '${i + 1}';
      final t = _text(cat, fs);
      if (horizontal) {
        t.paint(canvas, Offset(area.left - t.width - 4 * unit, area.top + band * (i + 0.5) - t.height / 2));
      } else {
        t.paint(canvas, Offset(area.left + band * (i + 0.5) - t.width / 2, area.bottom + 2 * unit));
      }
    }
    final zero = valuePos(0);
    if (chart.kind == WordChartKind.line || chart.kind == WordChartKind.area || chart.kind == WordChartKind.scatter) {
      for (var si = 0; si < chart.series.length; si++) {
        final s = chart.series[si];
        final path = Path();
        for (var i = 0; i < s.values.length; i++) {
          final p = Offset(area.left + band * (i + 0.5), valuePos(s.values[i]));
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
          canvas.drawCircle(p, 2.5 * unit, Paint()..color = _seriesColor(si));
        }
        if (chart.kind == WordChartKind.area && s.values.isNotEmpty) {
          final fill = Path.from(path)
            ..lineTo(area.left + band * (s.values.length - 0.5), zero)
            ..lineTo(area.left + band * 0.5, zero)
            ..close();
          canvas.drawPath(fill, Paint()..color = _seriesColor(si).withValues(alpha: 0.5));
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = _seriesColor(si)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * unit,
        );
      }
      return;
    }
    final groups = chart.stacked ? 1 : chart.series.length;
    final barBand = band * 0.7 / groups;
    for (var i = 0; i < n; i++) {
      var stackBase = 0.0;
      for (var si = 0; si < chart.series.length; si++) {
        final s = chart.series[si];
        if (i >= s.values.length) continue;
        final v = s.values[i];
        final from = chart.stacked ? stackBase : 0.0;
        final to = from + v;
        stackBase = chart.stacked ? to : 0;
        final g = chart.stacked ? 0 : si;
        final start = band * i + band * 0.15 + barBand * g;
        final rect = horizontal
            ? Rect.fromLTRB(valuePos(math.min(from, to)), area.top + start, valuePos(math.max(from, to)), area.top + start + barBand)
            : Rect.fromLTRB(area.left + start, valuePos(math.max(from, to)), area.left + start + barBand, valuePos(math.min(from, to)));
        final pc = i < s.pointColors.length ? s.pointColors[i] : null;
        canvas.drawRect(rect, Paint()..color = pc == null ? _seriesColor(si) : Color(pc));
      }
    }
  }

  double _catWidth(double fs) =>
      chart.categories.fold<double>(0, (m, c) => math.max(m, _text(c, fs).width)) + 6 * unit;

  static double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final n = raw / mag;
    final nice = n <= 1 ? 1 : (n <= 2 ? 2 : (n <= 5 ? 5 : 10));
    return nice * mag;
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  bool shouldRepaint(ChartPainter old) => old.chart != chart || old.unit != unit;
}
