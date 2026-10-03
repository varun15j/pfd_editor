import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../pdf_edit/annotations.dart';
import '../markup/markup_style.dart';

enum EditorTool {
  view(Icons.pan_tool_outlined, 'View'),
  select(Icons.open_with, 'Move'),
  pen(Icons.edit_outlined, 'Pen'),
  highlighter(Icons.border_color_outlined, 'Highlight'),
  text(Icons.text_fields, 'Text'),
  eraser(Icons.auto_fix_normal_outlined, 'Erase');

  const EditorTool(this.icon, this.label);
  final IconData icon;
  final String label;

  bool get draws => this == pen || this == highlighter;
}

/// Callbacks from the overlay to the editor. All positions are normalized
/// to the page.
class AnnotationCallbacks {
  const AnnotationCallbacks({
    required this.onAdd,
    required this.onReplace,
    required this.onRemove,
    required this.onPlaceText,
    required this.onEditText,
    required this.onItemMenu,
    required this.newId,
  });

  final void Function(Annotation) onAdd;
  final void Function(Annotation) onReplace;
  final void Function(String id) onRemove;
  final void Function(NormPoint at) onPlaceText;
  final void Function(TextAnnotation) onEditText;
  final void Function(Annotation) onItemMenu;
  final String Function() newId;
}

/// Draws a page's annotations over the page image and turns touches into
/// new marks for the active tool. Sized by its parent to exactly the page.
class AnnotationLayer extends StatefulWidget {
  const AnnotationLayer({
    super.key,
    required this.page,
    required this.tool,
    required this.style,
    required this.callbacks,
  });

  final EditorPage page;
  final EditorTool tool;

  /// Colour and thickness for new pen, highlighter and text marks.
  final MarkupStyle style;
  final AnnotationCallbacks callbacks;

  @override
  State<AnnotationLayer> createState() => _AnnotationLayerState();
}

class _AnnotationLayerState extends State<AnnotationLayer> {
  InkAnnotation? _current;

  NormPoint _norm(Offset local, Size size) => NormPoint(local.dx / size.width, local.dy / size.height).clamp();

  void _startStroke(Offset local, Size size) {
    final highlighter = widget.tool == EditorTool.highlighter;
    setState(() {
      _current = InkAnnotation(
        id: widget.callbacks.newId(),
        points: [_norm(local, size)],
        color: widget.style.color.toARGB32(),
        width: widget.style.inkWidth(highlighter: highlighter),
        highlighter: highlighter,
      );
    });
  }

  void _extendStroke(Offset local, Size size) {
    final c = _current;
    if (c == null) return;
    setState(() => _current = c.withPoint(_norm(local, size)));
  }

  void _endStroke() {
    final c = _current;
    if (c == null) return;
    setState(() => _current = null);
    widget.callbacks.onAdd(c);
  }

  void _erase(Offset local, Size size) {
    final p = _norm(local, size);
    final hit = hitInk(widget.page.annotations, p, aspect: size.width / size.height, tolerance: 0.02);
    if (hit != null) widget.callbacks.onRemove(hit.id);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final annotations = widget.page.annotations;
        final tool = widget.tool;
        final itemsInteractive = tool == EditorTool.select || tool == EditorTool.text;

        Widget? input;
        if (tool.draws) {
          input = GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (d) => _startStroke(d.localPosition, size),
            onPanUpdate: (d) => _extendStroke(d.localPosition, size),
            onPanEnd: (_) => _endStroke(),
            onPanCancel: _endStroke,
          );
        } else if (tool == EditorTool.eraser) {
          input = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _erase(d.localPosition, size),
            onPanUpdate: (d) => _erase(d.localPosition, size),
          );
        } else if (tool == EditorTool.text) {
          input = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => widget.callbacks.onPlaceText(_norm(d.localPosition, size)),
          );
        }

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: InkPainter([...annotations, ?_current]))),
            ),
            // Text boxes and signatures sit above the input layer, so in Text
            // mode a tap on existing text edits it instead of adding a box.
            if (input != null) Positioned.fill(child: input),
            for (final a in annotations)
              if (a is TextAnnotation)
                _MovableItem(
                  key: ValueKey(a.id),
                  left: a.origin.x * size.width,
                  top: a.origin.y * size.height,
                  enabled: itemsInteractive,
                  draggable: tool == EditorTool.select,
                  pageSize: size,
                  onTap: () =>
                      tool == EditorTool.text ? widget.callbacks.onEditText(a) : widget.callbacks.onItemMenu(a),
                  onMoved: (dx, dy) => widget.callbacks.onReplace(
                    a.copyWith(origin: NormPoint(a.origin.x + dx, a.origin.y + dy).clamp()),
                  ),
                  child: annotationText(a, size.width),
                )
              else if (a is SignatureAnnotation)
                _MovableItem(
                  key: ValueKey(a.id),
                  left: a.left * size.width,
                  top: a.top * size.height,
                  enabled: tool == EditorTool.select,
                  draggable: true,
                  pageSize: size,
                  onTap: () => widget.callbacks.onItemMenu(a),
                  onMoved: (dx, dy) => widget.callbacks.onReplace(
                    a.copyWith(left: (a.left + dx).clamp(0.0, 1.0), top: (a.top + dy).clamp(0.0, 1.0)),
                  ),
                  child: annotationSignature(a, size.width),
                ),
          ],
        );
      },
    );
  }
}

/// A text mark as drawn on a page [pageWidth] logical pixels wide.
Widget annotationText(TextAnnotation a, double pageWidth) => Text(
  a.text,
  style: TextStyle(fontSize: a.fontSize * pageWidth, color: Color(a.color), height: 1.15),
);

/// A signature as drawn on a page [pageWidth] logical pixels wide.
Widget annotationSignature(SignatureAnnotation a, double pageWidth) => SizedBox(
  width: a.width * pageWidth,
  height: a.width * pageWidth / a.aspectRatio,
  child: CustomPaint(painter: SignaturePainter(a)),
);

/// Draws a page's marks without taking touches, for page thumbnails and
/// previews. Sized by its parent to exactly the page.
class StaticMarks extends StatelessWidget {
  const StaticMarks(this.annotations, {super.key});

  final List<Annotation> annotations;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(child: CustomPaint(painter: InkPainter(annotations))),
              for (final a in annotations)
                if (a is TextAnnotation)
                  Positioned(
                    left: a.origin.x * size.width,
                    top: a.origin.y * size.height,
                    child: annotationText(a, size.width),
                  )
                else if (a is SignatureAnnotation)
                  Positioned(
                    left: a.left * size.width,
                    top: a.top * size.height,
                    child: annotationSignature(a, size.width),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// A text box or signature that can be tapped (menu or edit) and, in Move
/// mode, dragged. The drag is shown live and committed once on release so
/// a move is a single undo step.
class _MovableItem extends StatefulWidget {
  const _MovableItem({
    super.key,
    required this.left,
    required this.top,
    required this.enabled,
    required this.draggable,
    required this.pageSize,
    required this.onTap,
    required this.onMoved,
    required this.child,
  });

  final double left;
  final double top;
  final bool enabled;
  final bool draggable;
  final Size pageSize;
  final VoidCallback onTap;
  final void Function(double dx, double dy) onMoved;
  final Widget child;

  @override
  State<_MovableItem> createState() => _MovableItemState();
}

class _MovableItemState extends State<_MovableItem> {
  Offset _drag = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final selectable = widget.enabled && widget.draggable;
    return Positioned(
      left: widget.left + _drag.dx,
      top: widget.top + _drag.dy,
      child: IgnorePointer(
        ignoring: !widget.enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onPanUpdate: selectable ? (d) => setState(() => _drag += d.delta) : null,
          onPanEnd: selectable
              ? (_) {
                  final d = _drag;
                  setState(() => _drag = Offset.zero);
                  widget.onMoved(d.dx / widget.pageSize.width, d.dy / widget.pageSize.height);
                }
              : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: selectable
                  ? Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6))
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Paints pen and highlighter strokes.
class InkPainter extends CustomPainter {
  InkPainter(this.annotations);

  final List<Annotation> annotations;

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in annotations) {
      if (a is! InkAnnotation || a.points.isEmpty) continue;
      final color = Color(a.color);
      final paint = Paint()
        ..color = a.highlighter ? color.withValues(alpha: 0.35) : color
        ..strokeWidth = a.width * size.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      Offset at(NormPoint p) => Offset(p.x * size.width, p.y * size.height);
      if (a.points.length == 1) {
        canvas.drawCircle(at(a.points.first), paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(at(a.points.first).dx, at(a.points.first).dy);
      for (final p in a.points.skip(1)) {
        path.lineTo(at(p).dx, at(p).dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(InkPainter old) => old.annotations != annotations;
}

/// Paints a signature's strokes inside its box.
class SignaturePainter extends CustomPainter {
  SignaturePainter(this.signature);

  final SignatureAnnotation signature;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(signature.color)
      ..strokeWidth = size.width * SignatureAnnotation.strokeFraction
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in signature.strokes) {
      if (s.isEmpty) continue;
      final path = Path()..moveTo(s.first.x * size.width, s.first.y * size.height);
      for (final p in s.skip(1)) {
        path.lineTo(p.x * size.width, p.y * size.height);
      }
      if (s.length == 1) {
        canvas.drawCircle(
          Offset(s.first.x * size.width, s.first.y * size.height),
          paint.strokeWidth / 2,
          Paint()..color = paint.color,
        );
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter old) => old.signature != signature;
}

/// Returns the topmost ink stroke within [tolerance] (a fraction of the page
/// width) of [p], or null. [aspect] is page width over height, used to
/// measure distance in true page proportions.
InkAnnotation? hitInk(List<Annotation> annotations, NormPoint p, {required double aspect, double tolerance = 0.02}) {
  // Work in units of page width so x and y distances compare fairly.
  double dist(NormPoint a, NormPoint b) {
    final ax = a.x, ay = a.y / aspect, bx = b.x, by = b.y / aspect, px = p.x, py = p.y / aspect;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
    final cx = ax + t * dx - px, cy = ay + t * dy - py;
    return math.sqrt(cx * cx + cy * cy);
  }

  for (final a in annotations.reversed) {
    if (a is! InkAnnotation || a.points.isEmpty) continue;
    final reach = tolerance + a.width / 2;
    if (a.points.length == 1) {
      if (dist(a.points.first, a.points.first) <= reach) return a;
      continue;
    }
    for (var i = 0; i < a.points.length - 1; i++) {
      if (dist(a.points[i], a.points[i + 1]) <= reach) return a;
    }
  }
  return null;
}
