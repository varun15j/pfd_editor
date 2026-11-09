// The render object keeps private fields with public setters.
// ignore_for_file: prefer_initializing_formals
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../model.dart';
import 'borders.dart';

/// What one tab character does: follow the paragraph's tab stops, or jump
/// to a fixed place (a positional tab).
class TabInfo {
  const TabInfo({this.absoluteAlign, this.leader, required this.leaderStyle});

  final String? absoluteAlign;
  final String? leader;
  final TextStyle leaderStyle;
}

/// One line of a paragraph that has tabs: the text pieces between tabs are
/// placed at the paragraph's tab stops (left, center, right, decimal) with
/// dot, hyphen or underline leaders, and bar tabs draw a line.
class TabLine extends MultiChildRenderObjectWidget {
  const TabLine({
    super.key,
    required this.stops,
    required this.defaultTab,
    required this.tabs,
    this.startOffset = 0,
    this.indentOffset = 0,
    required super.children,
  });

  /// Stops in logical pixels, from the paragraph's left text edge.
  final List<WordTabStop> stops;
  final double defaultTab;

  /// One per tab, between children i and i+1.
  final List<TabInfo> tabs;

  /// Where the first piece starts (first-line indent).
  final double startOffset;

  /// The paragraph's left indent; Word measures tab stops from the margin.
  final double indentOffset;

  @override
  RenderTabLine createRenderObject(BuildContext context) =>
      RenderTabLine(stops: stops, defaultTab: defaultTab, tabs: tabs, startOffset: startOffset, indentOffset: indentOffset);

  @override
  void updateRenderObject(BuildContext context, RenderTabLine renderObject) {
    renderObject
      ..stops = stops
      ..defaultTab = defaultTab
      ..tabs = tabs
      ..startOffset = startOffset
      ..indentOffset = indentOffset;
  }
}

class _TabParentData extends ContainerBoxParentData<RenderBox> {}

class RenderTabLine extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _TabParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _TabParentData> {
  RenderTabLine({
    required List<WordTabStop> stops,
    required double defaultTab,
    required List<TabInfo> tabs,
    required double startOffset,
    required double indentOffset,
  }) : _stops = stops,
       _defaultTab = defaultTab,
       _tabs = tabs,
       _startOffset = startOffset,
       _indentOffset = indentOffset;

  List<WordTabStop> _stops;
  set stops(List<WordTabStop> v) {
    _stops = v;
    markNeedsLayout();
  }

  double _defaultTab;
  set defaultTab(double v) {
    _defaultTab = v;
    markNeedsLayout();
  }

  List<TabInfo> _tabs;
  set tabs(List<TabInfo> v) {
    _tabs = v;
    markNeedsLayout();
  }

  double _startOffset;
  set startOffset(double v) {
    _startOffset = v;
    markNeedsLayout();
  }

  double _indentOffset;
  set indentOffset(double v) {
    _indentOffset = v;
    markNeedsLayout();
  }

  final _leaders = <({double x1, double x2, String leader, TextStyle style})>[];
  double _baseline = 0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TabParentData) child.parentData = _TabParentData();
  }

  List<RenderBox> get _children {
    final out = <RenderBox>[];
    var c = firstChild;
    while (c != null) {
      out.add(c);
      c = childAfter(c);
    }
    return out;
  }

  /// Places the pieces; returns their offsets and the line size.
  ({List<Offset> offsets, Size size, double baseline}) _layout(double width, {required bool dry}) {
    final children = _children;
    final sizes = <Size>[];
    final offsetsX = <double>[];
    _leaders.clear();
    var x = _startOffset;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      var align = WordTabAlign.left;
      var pos = x;
      String leader = 'none';
      if (i > 0) {
        final tab = i - 1 < _tabs.length ? _tabs[i - 1] : null;
        if (tab?.absoluteAlign != null) {
          // Positional tab: relative to the margins.
          pos = switch (tab!.absoluteAlign) {
            'right' => width,
            'center' => width / 2,
            _ => 0,
          };
          align = switch (tab.absoluteAlign) {
            'right' => WordTabAlign.right,
            'center' => WordTabAlign.center,
            _ => WordTabAlign.left,
          };
          leader = tab.leader ?? 'none';
        } else {
          WordTabStop? stop;
          for (final s in _stops) {
            if (s.align == WordTabAlign.bar) continue;
            if (s.position - _indentOffset > x + 0.5) {
              stop = s;
              break;
            }
          }
          if (stop != null) {
            pos = stop.position - _indentOffset;
            align = stop.align;
            leader = stop.leader;
          } else {
            final margin = x + _indentOffset;
            pos = ((margin + 0.5) / _defaultTab).ceil() * _defaultTab - _indentOffset;
            if (pos <= x) pos = x + _defaultTab;
          }
        }
        if (pos > width && align == WordTabAlign.left) pos = x;
      }
      final maxW = math.max(0.0, align == WordTabAlign.left ? width - pos : width - x);
      final constraints = BoxConstraints(maxWidth: maxW);
      final size = dry ? child.getDryLayout(constraints) : (child..layout(constraints, parentUsesSize: true)).size;
      double cx;
      switch (align) {
        case WordTabAlign.right || WordTabAlign.decimal:
          cx = math.max(x, pos - size.width);
        case WordTabAlign.center:
          cx = math.max(x, pos - size.width / 2);
        default:
          cx = pos;
      }
      if (i > 0 && !dry) {
        final tab = i - 1 < _tabs.length ? _tabs[i - 1] : null;
        if (tab != null) _leaders.add((x1: x, x2: cx, leader: leader, style: tab.leaderStyle));
      }
      sizes.add(size);
      offsetsX.add(cx);
      x = cx + size.width;
    }
    var maxBaseline = 0.0, height = 0.0;
    final baselines = <double>[];
    for (var i = 0; i < children.length; i++) {
      final b = dry
          ? (children[i].getDryBaseline(BoxConstraints(maxWidth: sizes[i].width), TextBaseline.alphabetic) ?? sizes[i].height)
          : (children[i].getDistanceToBaseline(TextBaseline.alphabetic) ?? sizes[i].height);
      baselines.add(b);
      maxBaseline = math.max(maxBaseline, b);
    }
    final offsets = <Offset>[];
    for (var i = 0; i < children.length; i++) {
      final dy = maxBaseline - baselines[i];
      offsets.add(Offset(offsetsX[i], dy));
      height = math.max(height, dy + sizes[i].height);
    }
    return (offsets: offsets, size: Size(width, height), baseline: maxBaseline);
  }

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 10000.0;
    final result = _layout(width, dry: false);
    final children = _children;
    for (var i = 0; i < children.length; i++) {
      (children[i].parentData! as _TabParentData).offset = result.offsets[i];
    }
    _baseline = result.baseline;
    size = constraints.constrain(result.size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 10000.0;
    return constraints.constrain(_layout(width, dry: true).size);
  }

  @override
  double computeMinIntrinsicWidth(double height) => _children.fold(0.0, (a, c) => a + c.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _children.fold(0.0, (a, c) => a + c.getMaxIntrinsicWidth(height)) + _defaultTab * _tabs.length + _startOffset;

  @override
  double computeMinIntrinsicHeight(double width) => computeDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _baseline;

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    for (final l in _leaders) {
      paintLeader(canvas, l.leader, offset.dx + l.x1, offset.dx + l.x2, offset.dy + _baseline, l.style);
    }
    for (final s in _stops) {
      if (s.align != WordTabAlign.bar) continue;
      final x = offset.dx + s.position - _indentOffset;
      canvas.drawLine(Offset(x, offset.dy), Offset(x, offset.dy + size.height), Paint()..strokeWidth = 0.8);
    }
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}
