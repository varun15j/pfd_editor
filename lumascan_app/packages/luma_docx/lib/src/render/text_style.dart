import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../model.dart';
import 'context.dart';

/// Phones rarely have Word's fonts, so each font gets fallbacks of the same
/// kind: serif, sans serif, monospace or script.
List<String> fontFallback(String? font) {
  final f = (font ?? '').toLowerCase();
  const emoji = ['Noto Color Emoji', 'Apple Color Emoji', 'Segoe UI Emoji'];
  const serif = ['serif', 'Noto Serif', 'Times New Roman', 'Georgia'];
  const mono = ['monospace', 'Roboto Mono', 'Courier New', 'Menlo', 'Courier'];
  const script = ['cursive', 'Dancing Script', 'Snell Roundhand', 'Noteworthy'];
  const sans = ['sans-serif', 'Roboto', 'Helvetica Neue', 'Arial'];
  List<String> kind;
  if (RegExp(r'courier|consolas|mono|lucida console|menlo|monaco|code').hasMatch(f)) {
    kind = mono;
  } else if (RegExp(r'script|handwriting|comic|brush|pacifico|cursive|vivaldi|freestyle').hasMatch(f)) {
    kind = script;
  } else if (RegExp(r'times|georgia|cambria|garamond|antiqua|palatino|constantia|baskerville|century|serif|bodoni|rockwell|book').hasMatch(f) &&
      !f.contains('sans')) {
    kind = serif;
  } else {
    kind = sans;
  }
  return [...kind, ...emoji];
}

/// Single line spacing as a multiple of the font size; close to Word's
/// Calibri and Times line heights.
const singleLineHeight = 1.17;

double? lineHeightFor(WordParagraphStyle p, double fontSizePt) {
  if (p.lineExact != null) return (p.lineExact! / fontSizePt).clamp(0.5, 10.0);
  if (p.lineAtLeast != null) {
    final h = p.lineAtLeast! / fontSizePt;
    return h > singleLineHeight ? h : null;
  }
  if (p.lineMultiple != null && (p.lineMultiple! - 1).abs() > 0.01) return singleLineHeight * p.lineMultiple!;
  return null;
}

/// A Word run's look as a Flutter [TextStyle].
TextStyle runTextStyle(
  WordRunStyle s,
  WordRenderContext ctx, {
  WordParagraphStyle? paragraph,
  WordRevision? revision,
  bool commented = false,
  bool forceSize = false,
  double sizeFactor = 1,
}) {
  final size = s.size * sizeFactor;
  var color = Color(s.color ?? 0xFF000000);
  final decorations = <TextDecoration>[];
  TextDecorationStyle? decorationStyle;
  double? thickness;
  Color? decorationColor = s.underlineColor == null ? null : Color(s.underlineColor!);
  if (s.underline != WordUnderline.none) {
    decorations.add(TextDecoration.underline);
    decorationStyle = switch (s.underline) {
      WordUnderline.double => TextDecorationStyle.double,
      WordUnderline.dotted => TextDecorationStyle.dotted,
      WordUnderline.dashed => TextDecorationStyle.dashed,
      WordUnderline.wave => TextDecorationStyle.wavy,
      _ => null,
    };
    if (s.underline == WordUnderline.thick) thickness = 2.2;
  }
  if (s.strike || s.doubleStrike) {
    decorations.add(TextDecoration.lineThrough);
    if (s.doubleStrike) decorationStyle = TextDecorationStyle.double;
  }
  if (revision != null && ctx.options.showMarkup) {
    final rc = reviewerColor(revision.author);
    switch (revision.kind) {
      case WordRevisionKind.insert:
        color = rc;
        decorations.add(TextDecoration.underline);
        decorationColor = rc;
      case WordRevisionKind.moveTo:
        color = const Color(0xFF2E7D32);
        decorations.add(TextDecoration.underline);
        decorationStyle = TextDecorationStyle.double;
        decorationColor = color;
      case WordRevisionKind.delete:
        color = rc;
        decorations.add(TextDecoration.lineThrough);
        decorationColor = rc;
      case WordRevisionKind.moveFrom:
        color = const Color(0xFF2E7D32);
        decorations.add(TextDecoration.lineThrough);
        decorationStyle = TextDecorationStyle.double;
        decorationColor = color;
      case WordRevisionKind.format || WordRevisionKind.paragraph:
        break;
    }
  }
  if (s.hidden) {
    decorations.add(TextDecoration.underline);
    decorationStyle = TextDecorationStyle.dotted;
    color = color.withValues(alpha: 0.6);
  }

  final shadows = <Shadow>[];
  final fx = s.effects;
  if (s.shadow) shadows.add(Shadow(offset: Offset(ctx.pt(1), ctx.pt(1)), color: const Color(0x80000000)));
  if (s.emboss) {
    shadows
      ..add(Shadow(offset: Offset(-ctx.pt(0.6), -ctx.pt(0.6)), color: const Color(0xCCFFFFFF)))
      ..add(Shadow(offset: Offset(ctx.pt(0.6), ctx.pt(0.6)), color: const Color(0x99000000)));
  }
  if (s.imprint) {
    shadows
      ..add(Shadow(offset: Offset(ctx.pt(0.6), ctx.pt(0.6)), color: const Color(0xCCFFFFFF)))
      ..add(Shadow(offset: Offset(-ctx.pt(0.6), -ctx.pt(0.6)), color: const Color(0x99000000)));
  }
  Paint? foreground;
  if (fx != null) {
    if (fx.shadowColor != null) {
      shadows.add(
        Shadow(color: Color(fx.shadowColor!), offset: Offset(ctx.pt(fx.shadowDx), ctx.pt(fx.shadowDy)), blurRadius: ctx.pt(fx.shadowBlur)),
      );
    }
    if (fx.glowColor != null) {
      final glow = Color(fx.glowColor!);
      shadows
        ..add(Shadow(color: glow, blurRadius: ctx.pt(fx.glowRadius)))
        ..add(Shadow(color: glow, blurRadius: ctx.pt(fx.glowRadius / 2)));
    }
    if (fx.fillColor != null) color = Color(fx.fillColor!);
    if (fx.gradient.length >= 2) {
      final w = ctx.pt(size) * 8;
      foreground = Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(w, 0), [for (final c in fx.gradient) Color(c)], [
          for (var i = 0; i < fx.gradient.length; i++) i / (fx.gradient.length - 1),
        ], TileMode.mirror);
    }
    if (fx.outlineColor != null) {
      final oc = Color(fx.outlineColor!);
      final d = ctx.pt(fx.outlineWidth.clamp(0.4, 2.0));
      if (fx.fillColor == null && fx.gradient.isEmpty && s.color == null) {
        foreground = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = d
          ..color = oc;
      } else {
        for (final o in [Offset(d, 0), Offset(-d, 0), Offset(0, d), Offset(0, -d)]) {
          shadows.add(Shadow(color: oc, offset: o));
        }
      }
    }
  }
  if (s.outline && foreground == null) {
    foreground = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ctx.pt(0.6)
      ..color = color;
  }

  final features = <FontFeature>[];
  switch (fx?.ligatures) {
    case 'standard' || 'standardContextual':
      features.add(const FontFeature.enable('liga'));
    case 'contextual':
      features.add(const FontFeature.enable('calt'));
    case 'historical' || 'historicalDiscretional':
      features.add(const FontFeature.enable('hlig'));
    case 'discretional' || 'contextualDiscretional':
      features.add(const FontFeature.enable('dlig'));
    case 'all':
      features.addAll(const [FontFeature.enable('liga'), FontFeature.enable('dlig'), FontFeature.enable('hlig'), FontFeature.enable('calt')]);
  }
  if (fx?.numberForm == 'oldStyle') features.add(const FontFeature.oldstyleFigures());
  if (fx?.numberForm == 'lining') features.add(const FontFeature.liningFigures());
  if (fx?.numberSpacing == 'tabular') features.add(const FontFeature.tabularFigures());
  if (fx?.numberSpacing == 'proportional') features.add(const FontFeature.proportionalFigures());

  Color? background;
  if (s.highlight != null) {
    background = Color(s.highlight!);
  } else if (s.shading != null) {
    background = Color(s.shading!);
  } else if (commented && ctx.options.showComments) {
    background = const Color(0x55FFD54F);
  }

  return TextStyle(
    inherit: false,
    fontFamily: s.font,
    fontFamilyFallback: fontFallback(s.font),
    fontSize: ctx.pt(size),
    fontWeight: s.bold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
    color: foreground == null ? color : null,
    foreground: foreground,
    backgroundColor: background,
    decoration: decorations.isEmpty ? TextDecoration.none : TextDecoration.combine(decorations),
    decorationStyle: decorationStyle,
    decorationColor: decorationColor ?? (foreground == null ? color : null),
    decorationThickness: thickness,
    letterSpacing: s.letterSpacing == 0 ? null : ctx.pt(s.letterSpacing),
    shadows: shadows.isEmpty ? null : shadows,
    fontFeatures: features.isEmpty ? null : features,
    height: paragraph == null ? null : lineHeightFor(paragraph, s.size),
    leadingDistribution: TextLeadingDistribution.even,
    textBaseline: TextBaseline.alphabetic,
  );
}
