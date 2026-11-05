import 'package:flutter/material.dart';

import '../model.dart';

/// Draws an equation tree with stacked fractions, radicals, scripts, big
/// operators, brackets and matrices.
class MathView {
  MathView(this.fontSize, this.color);

  final double fontSize;
  final Color color;

  static const _fonts = ['Cambria Math', 'STIX Two Math', 'Noto Sans Math', 'serif', 'Noto Serif', 'Times New Roman'];

  TextStyle _style(double size, {bool italic = false, bool bold = false}) => TextStyle(
    inherit: false,
    fontSize: size,
    color: color,
    fontFamily: 'Cambria Math',
    fontFamilyFallback: _fonts,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    textBaseline: TextBaseline.alphabetic,
    height: 1.15,
  );

  InlineSpan span(MathNode node, [double scale = 1]) {
    final size = fontSize * scale;
    switch (node) {
      case MathText(:final text, :final plain, :final bold):
        // Letters are italic in math, like Word; numbers and operators are not.
        if (plain || !RegExp(r'[A-Za-z]').hasMatch(text) || RegExp(r'^(sin|cos|tan|log|ln|lim|max|min|exp)$').hasMatch(text)) {
          return TextSpan(text: _spaced(text), style: _style(size, bold: bold));
        }
        return TextSpan(text: text, style: _style(size, italic: true, bold: bold));
      case MathRow(:final children):
        return TextSpan(children: [for (final c in children) span(c, scale)]);
      case MathFunction(:final name, :final argument):
        return TextSpan(children: [_plain(name, scale), TextSpan(text: ' ', style: _style(size)), span(argument, scale)]);
      default:
        return WidgetSpan(alignment: PlaceholderAlignment.middle, baseline: TextBaseline.alphabetic, child: widget(node, scale));
    }
  }

  InlineSpan _plain(MathNode n, double scale) {
    if (n is MathText) return TextSpan(text: n.text, style: _style(fontSize * scale));
    return span(n, scale);
  }

  static String _spaced(String t) {
    // Thin spaces around binary operators and relations.
    return t.replaceAllMapped(RegExp(r'([=+<>≤≥≠±×÷→−])'), (m) => ' ${m.group(1)} ');
  }

  Widget _rich(MathNode node, double scale) => Text.rich(span(node, scale), textScaler: TextScaler.noScaling);

  Widget widget(MathNode node, double scale) {
    final size = fontSize * scale;
    final small = scale * 0.7 < 0.5 ? 0.5 : scale * 0.7;
    switch (node) {
      case MathFraction(:final numerator, :final denominator, :final bar, :final linearForm):
        if (linearForm) return _rich(MathRow([numerator, const MathText('/', plain: true), denominator]), scale);
        final inner = scale > 0.8 ? scale * 0.9 : scale;
        return IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: _rich(numerator, inner)),
              Container(height: bar ? (size * 0.06).clamp(0.6, 2.0) : 0, margin: EdgeInsets.symmetric(vertical: size * 0.08, horizontal: size * 0.05), color: color),
              Center(child: _rich(denominator, inner)),
            ],
          ),
        );
      case MathRadical(:final base, :final degree):
        return IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (degree != null) Align(alignment: const Alignment(0, -0.3), child: _rich(degree, small)),
              SizedBox(width: size * 0.6, child: CustomPaint(painter: _RadicalPainter(color, (size * 0.06).clamp(0.6, 2.0)))),
              Container(
                padding: EdgeInsets.only(top: size * 0.12, left: size * 0.05, right: size * 0.05),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: color, width: (size * 0.06).clamp(0.6, 2.0)))),
                child: _rich(base, scale),
              ),
            ],
          ),
        );
      case MathScript(:final base, :final sup, :final sub):
        final scripts = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sup != null) _rich(sup, small),
            if (sup != null && sub != null) SizedBox(height: size * 0.3),
            if (sub != null) _rich(sub, small),
          ],
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _rich(base, scale),
            Transform.translate(
              offset: Offset(size * 0.04, sup != null && sub == null ? -size * 0.4 : (sub != null && sup == null ? size * 0.3 : 0)),
              child: scripts,
            ),
          ],
        );
      case MathNary(:final operator, :final base, :final sub, :final sup, :final limitsUnderOver):
        final op = Text(operator, style: _style(size * 1.6), textScaler: TextScaler.noScaling);
        final opWidget = limitsUnderOver
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [if (sup != null) _rich(sup, small), op, if (sub != null) _rich(sub, small)],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  op,
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [if (sup != null) _rich(sup, small), SizedBox(height: size * 0.6), if (sub != null) _rich(sub, small)],
                  ),
                ],
              );
        return Row(mainAxisSize: MainAxisSize.min, children: [opWidget, SizedBox(width: size * 0.15), _rich(base, scale)]);
      case MathDelimiter(:final items, :final begin, :final end, :final separator):
        final tall = items.any(_isTall);
        final rows = items.whereType<MathMatrix>().fold<int>(1, (m, x) => x.rows.length > m ? x.rows.length : m);
        final bracket = tall ? (rows > 1 ? 1.0 + rows * 0.75 : 2.0) : 1.0;
        Widget br(String c) => c.isEmpty
            ? const SizedBox.shrink()
            : Text(c, style: _style(size * bracket).copyWith(height: 1), textScaler: TextScaler.noScaling);
        final children = <Widget>[br(begin)];
        for (var i = 0; i < items.length; i++) {
          if (i > 0) children.add(br(separator));
          children.add(_rich(items[i], scale));
        }
        children.add(br(end));
        return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: children);
      case MathMatrix(:final rows):
        return Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            for (final r in rows)
              TableRow(
                children: [
                  for (final c in r) Padding(padding: EdgeInsets.symmetric(horizontal: size * 0.3, vertical: size * 0.08), child: Center(child: _rich(c, scale))),
                ],
              ),
          ],
        );
      case MathLimit(:final base, :final limit, :final upper):
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: upper ? [_rich(limit, small), _rich(base, scale)] : [_rich(base, scale), _rich(limit, small)],
        );
      case MathAccent(:final base, :final mark, :final below):
        if (mark == '̅' || mark == '¯' || mark == '‾') {
          return Container(
            decoration: BoxDecoration(
              border: below ? Border(bottom: BorderSide(color: color, width: 1)) : Border(top: BorderSide(color: color, width: 1)),
            ),
            child: _rich(base, scale),
          );
        }
        final markText = Text(_spacingAccent(mark), style: _style(size * 0.9).copyWith(height: 0.6), textScaler: TextScaler.noScaling);
        return Column(mainAxisSize: MainAxisSize.min, children: below ? [_rich(base, scale), markText] : [markText, _rich(base, scale)]);
      default:
        return _rich(node, scale);
    }
  }

  static bool _isTall(MathNode n) => switch (n) {
    MathFraction(:final linearForm) => !linearForm,
    MathMatrix() || MathNary() => true,
    MathRow(:final children) => children.any(_isTall),
    _ => false,
  };

  /// Combining accents shown on their own need a spacing form.
  static String _spacingAccent(String mark) => switch (mark) {
    '̂' => 'ˆ',
    '̃' => '˜',
    '̇' => '˙',
    '̈' => '¨',
    '⃗' => '→',
    '́' => '´',
    '̀' => '`',
    '̌' => 'ˇ',
    _ => mark,
  };
}

class _RadicalPainter extends CustomPainter {
  _RadicalPainter(this.color, this.width);

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(0, h * 0.6)
      ..lineTo(w * 0.25, h * 0.5)
      ..lineTo(w * 0.55, h)
      ..lineTo(w, width / 2);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_RadicalPainter old) => old.color != color;
}
