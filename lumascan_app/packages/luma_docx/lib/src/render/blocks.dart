import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../model.dart';
import '../reader/numbering.dart' show formatNumber;
import 'borders.dart';
import 'context.dart';
import 'drawings.dart';
import 'math_view.dart';
import 'tab_line.dart';
import 'text_style.dart';

/// Draws a list of blocks (paragraphs and tables) top to bottom.
Widget buildWordBlocks(List<WordBlock> blocks, WordRenderContext ctx) {
  final children = <Widget>[];
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    final prev = i > 0 ? blocks[i - 1] : null;
    final next = i + 1 < blocks.length ? blocks[i + 1] : null;
    if (b is WordParagraph) {
      if (_isHiddenParagraph(b, ctx)) continue;
      // A drop cap is its own paragraph in the file; draw it beside the next one.
      if (b.dropCap != null && next is WordParagraph) {
        children.add(_DropCap(cap: b, body: next, ctx: ctx, before: prev, after: i + 2 < blocks.length ? blocks[i + 2] : null));
        i++;
        continue;
      }
      children.add(WordParagraphView(b, ctx, previous: prev, next: next));
    } else if (b is WordTable) {
      children.add(WordTableView(b, ctx));
    }
  }
  return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
}

bool _isHiddenParagraph(WordParagraph p, WordRenderContext ctx) {
  if (ctx.options.showHidden || p.inlines.isEmpty || p.list != null) return false;
  return p.inlines.every((i) => i is WordText && i.style.hidden);
}

bool _sameBorders(WordBorders? a, WordBorders? b) {
  if (a == null || b == null) return false;
  bool same(WordBorder? x, WordBorder? y) =>
      (x == null && y == null) || (x != null && y != null && x.style == y.style && x.color == y.color && x.width == y.width);
  return same(a.top, b.top) && same(a.left, b.left) && same(a.bottom, b.bottom) && same(a.right, b.right);
}

class _DropCap extends StatelessWidget {
  const _DropCap({required this.cap, required this.body, required this.ctx, this.before, this.after});

  final WordParagraph cap;
  final WordParagraph body;
  final WordRenderContext ctx;
  final WordBlock? before;
  final WordBlock? after;

  @override
  Widget build(BuildContext context) {
    final texts = cap.inlines.whereType<WordText>().toList();
    if (texts.isEmpty) return WordParagraphView(body, ctx, previous: before, next: after);
    final bodyFont = body.inlines.whereType<WordText>().firstOrNull?.style.size ?? 11;
    final lines = cap.dropCap!.lines;
    final capStyle = runTextStyle(texts.first.style, ctx).copyWith(
      fontSize: ctx.pt(bodyFont * singleLineHeight * lines * 0.92),
      height: 1,
    );
    final letter = Text(texts.map((t) => t.text).join(), style: capStyle, textScaler: TextScaler.noScaling);
    return Padding(
      padding: EdgeInsets.only(top: ctx.pt(body.style.spaceBefore), left: cap.dropCap!.inMargin ? 0 : ctx.pt(body.style.indentLeft)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cap.dropCap!.inMargin) Transform.translate(offset: Offset(-ctx.pt(bodyFont * 3), 0), child: letter) else letter,
          SizedBox(width: ctx.pt(cap.dropCap!.inMargin ? 0 : 3)),
          Expanded(
            child: WordParagraphView(
              body,
              ctx.withWidth(ctx.width * 0.8),
              previous: cap,
              next: after,
              spaceBefore: 0,
              indentOverride: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// One paragraph: list label, text with all its runs, tabs, inline
/// pictures, floating pictures beside it, borders and shading.
class WordParagraphView extends StatefulWidget {
  const WordParagraphView(this.paragraph, this.ctx, {super.key, this.previous, this.next, this.spaceBefore, this.indentOverride});

  final WordParagraph paragraph;
  final WordRenderContext ctx;
  final WordBlock? previous;
  final WordBlock? next;
  final double? spaceBefore;
  final double? indentOverride;

  @override
  State<WordParagraphView> createState() => _WordParagraphViewState();
}

class _WordParagraphViewState extends State<WordParagraphView> {
  final _recognizers = <GestureRecognizer>[];

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  WordParagraph get p => widget.paragraph;
  WordRenderContext get ctx => widget.ctx;

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final r = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(r);
    return r;
  }

  WordRunStyle get _markStyle {
    for (final i in p.inlines) {
      if (i is WordText) return i.style;
      if (i is WordTab) return i.style;
    }
    return p.list?.style ?? const WordRunStyle();
  }

  String _fieldText(WordText t) {
    final code = t.field?.trim().split(RegExp(r'\s+')).first.toUpperCase();
    switch (code) {
      case 'PAGE':
        return ctx.pageNumber ?? t.text;
      case 'NUMPAGES':
        return ctx.pageCount?.toString() ?? t.text;
      case 'SECTIONPAGES':
        return ctx.sectionPages?.toString() ?? t.text;
    }
    return t.text;
  }

  List<InlineSpan> _textSpans(WordText t) {
    final s = t.style;
    if (s.hidden && !ctx.options.showHidden) return const [];
    final rev = t.revision;
    if (rev != null && !ctx.options.showMarkup && rev.removes) return const [];
    var text = _fieldText(t);
    if (s.allCaps) text = text.toUpperCase();
    var style = runTextStyle(s, ctx, paragraph: p.style, revision: rev, commented: t.commentIds.isNotEmpty);
    if (t.contentControl != null && t.contentControl != 'buildingBlock' && style.backgroundColor == null) {
      style = style.copyWith(backgroundColor: const Color(0x1F1E88E5));
    }
    GestureRecognizer? recognizer;
    final link = t.link;
    if (link != null) {
      recognizer = _tap(() => ctx.onLink(link));
    }
    final special = s.vertAlign != WordVertAlign.baseline || s.position != 0 || s.scale != 1 || s.border != null;
    if (special) {
      final sub = s.vertAlign == WordVertAlign.subscript, sup = s.vertAlign == WordVertAlign.superscript;
      final small = sub || sup;
      Widget w = Text(
        text,
        style: small ? style.copyWith(fontSize: style.fontSize! * 0.65, height: 1) : style.copyWith(height: 1),
        textScaler: TextScaler.noScaling,
      );
      if (s.scale != 1) {
        final tp = TextPainter(text: TextSpan(text: text, style: style.copyWith(height: 1)), textDirection: TextDirection.ltr, textScaler: TextScaler.noScaling)..layout();
        w = SizedBox(
          width: tp.width * s.scale,
          height: tp.height,
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: 0,
            maxWidth: tp.width + 1,
            child: Transform(transform: Matrix4.diagonal3Values(s.scale, 1, 1), alignment: Alignment.centerLeft, child: w),
          ),
        );
        tp.dispose();
      }
      if (s.border != null) {
        w = Container(
          padding: EdgeInsets.symmetric(horizontal: ctx.pt(1.5)),
          decoration: BoxDecoration(border: Border.all(color: Color(s.border!.color), width: ctx.pt(s.border!.width).clamp(0.5, 4))),
          child: w,
        );
      }
      final dy = -ctx.pt(s.position) + (sup ? -ctx.pt(s.size * 0.33) : (sub ? ctx.pt(s.size * 0.12) : 0));
      if (dy != 0) w = Transform.translate(offset: Offset(0, dy), child: w);
      if (recognizer != null) {
        final onTap = (recognizer as TapGestureRecognizer).onTap;
        w = GestureDetector(onTap: onTap, child: w);
      }
      return [WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: w)];
    }
    if (s.smallCaps && text.contains(RegExp(r'[a-z]'))) {
      final spans = <InlineSpan>[];
      final small = style.copyWith(fontSize: style.fontSize! * 0.78);
      for (final m in RegExp(r'[a-z]+|[^a-z]+').allMatches(text)) {
        final part = m.group(0)!;
        final lower = RegExp(r'^[a-z]').hasMatch(part);
        spans.add(TextSpan(text: lower ? part.toUpperCase() : part, style: lower ? small : style, recognizer: recognizer));
      }
      return spans;
    }
    return [TextSpan(text: text, style: style, recognizer: recognizer, semanticsLabel: null)];
  }

  InlineSpan? _span(WordInline i) {
    switch (i) {
      case WordText():
        final spans = _textSpans(i);
        if (spans.isEmpty) return null;
        return spans.length == 1 ? spans.first : TextSpan(children: spans);
      case WordBreak():
        return TextSpan(text: '\n', style: runTextStyle(_markStyle, ctx, paragraph: p.style));
      case WordTab():
        return TextSpan(text: '\t', style: runTextStyle(i.style, ctx));
      case WordPicture():
        return WidgetSpan(alignment: PlaceholderAlignment.bottom, child: WordPictureView(i, ctx));
      case WordShape():
        return WidgetSpan(alignment: PlaceholderAlignment.bottom, child: WordShapeView(i, ctx, buildWordBlocks));
      case WordChart():
        return WidgetSpan(alignment: PlaceholderAlignment.bottom, child: WordChartView(i, ctx));
      case WordEquation():
        final color = Color(i.style.color ?? 0xFF000000);
        return MathView(ctx.pt(i.style.size), color).span(i.root);
      case WordNoteRef():
        final notes = i.kind == WordNoteKind.footnote ? ctx.document.footnotes : ctx.document.endnotes;
        final note = notes[i.id];
        final style = runTextStyle(i.style, ctx).copyWith(fontSize: ctx.pt(i.style.size * 0.65), height: 1, color: note == null ? null : const Color(0xFF1565C0));
        Widget w = Transform.translate(offset: Offset(0, -ctx.pt(i.style.size * 0.33)), child: Text(i.label, style: style, textScaler: TextScaler.noScaling));
        if (note != null) w = GestureDetector(onTap: () => ctx.onNote(note), child: w);
        return WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: w);
      case WordCommentMark():
        if (!ctx.options.showComments) return null;
        final c = ctx.document.comment(i.id);
        if (c == null) return null;
        final color = reviewerColor(c.author);
        final n = ctx.document.comments.indexOf(c) + 1;
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: () => ctx.onComment(c),
            child: Semantics(
              button: true,
              label: 'Comment by ${c.author ?? 'someone'}: ${c.text}',
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: ctx.pt(1)),
                padding: EdgeInsets.symmetric(horizontal: ctx.pt(2.5), vertical: ctx.pt(0.5)),
                decoration: BoxDecoration(color: color.withValues(alpha: c.resolved ? 0.35 : 0.9), borderRadius: BorderRadius.circular(ctx.pt(3))),
                child: Text(
                  '${c.initials ?? (c.author?.isNotEmpty ?? false ? c.author![0] : 'C')}$n',
                  style: TextStyle(inherit: false, fontSize: ctx.pt(6.5), color: Colors.white, fontWeight: FontWeight.w700),
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ),
          ),
        );
      case WordUnsupported():
        return WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: WordPlaceholder(label: i.label, width: math.min(ctx.pt(i.width), ctx.width), height: ctx.pt(i.height)),
        );
    }
  }

  bool _isFloating(WordInline i) => switch (i) {
    WordPicture(:final anchor) || WordShape(:final anchor) || WordChart(:final anchor) => anchor != null,
    _ => false,
  };

  WordAnchor? _anchorOf(WordInline i) => switch (i) {
    WordPicture(:final anchor) || WordShape(:final anchor) || WordChart(:final anchor) => anchor,
    _ => null,
  };

  Widget _floatWidget(WordInline i, WordRenderContext c) => switch (i) {
    WordPicture() => WordPictureView(i, c),
    WordShape() => WordShapeView(i, c, buildWordBlocks),
    WordChart() => WordChartView(i, c),
    _ => const SizedBox.shrink(),
  };

  Widget _rich(List<InlineSpan> spans, {required TextAlign align, required TextDirection dir, TextStyle? base}) {
    final mark = runTextStyle(_markStyle, ctx, paragraph: p.style);
    StrutStyle? strut;
    if (p.style.lineExact != null) {
      strut = StrutStyle(fontSize: mark.fontSize, height: lineHeightFor(p.style, _markStyle.size), forceStrutHeight: true, leadingDistribution: TextLeadingDistribution.even);
    }
    if (spans.isEmpty) spans = [TextSpan(text: '​', style: mark)];
    return Text.rich(
      TextSpan(children: spans, style: base ?? mark),
      textAlign: align,
      textDirection: dir,
      textScaler: TextScaler.noScaling,
      strutStyle: strut,
    );
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final st = p.style;
    final dir = st.rtl ? TextDirection.rtl : TextDirection.ltr;
    final align = switch (st.align) {
      WordAlign.center => TextAlign.center,
      WordAlign.right => st.rtl ? TextAlign.left : TextAlign.right,
      WordAlign.justify => TextAlign.justify,
      WordAlign.left => st.rtl ? TextAlign.right : TextAlign.left,
    };
    final indentLeft = widget.indentOverride ?? st.indentLeft;
    final hasList = p.list != null;
    // First line start relative to the other lines (negative = hanging).
    final firstLine = hasList ? 0.0 : st.firstLine;
    final padLeft = hasList ? math.max(0.0, indentLeft + st.firstLine) : math.max(0.0, indentLeft + math.min(0.0, firstLine));
    final contentWidth = math.max(20.0, ctx.width - ctx.pt(padLeft + st.indentRight) - (hasList ? ctx.pt(-st.firstLine) : 0));
    final inner = ctx.withWidth(contentWidth);

    // Split floating objects and display equations from the text flow.
    final floats = <WordInline>[];
    final flow = <WordInline>[];
    final displayMath = <WordEquation>[];
    for (final i in p.inlines) {
      if (_isFloating(i)) {
        floats.add(i);
      } else if (i is WordEquation && i.display) {
        displayMath.add(i);
      } else {
        flow.add(i);
      }
    }
    final innerState = _InnerSpans(this, inner);
    Widget content;
    final hasTabs = flow.any((i) => i is WordTab);
    if (hasTabs) {
      // Lines split at manual breaks, pieces split at tabs.
      final lines = <List<WordInline>>[[]];
      for (final i in flow) {
        if (i is WordBreak && (i.kind == WordBreakKind.line || i.kind == WordBreakKind.textWrapping)) {
          lines.add([]);
        } else {
          lines.last.add(i);
        }
      }
      final hanging = !hasList && firstLine < 0;
      final stops = [
        for (final s in st.tabs) WordTabStop(position: ctx.pt(s.position), align: s.align, leader: s.leader),
        if (hanging) WordTabStop(position: ctx.pt(indentLeft)),
        if (hasList && p.list!.suffix == 'tab') WordTabStop(position: ctx.pt(indentLeft)),
      ]..sort((a, b) => a.position.compareTo(b.position));
      final rows = <Widget>[];
      for (var li = 0; li < lines.length; li++) {
        final segments = <List<InlineSpan>>[[]];
        final tabs = <TabInfo>[];
        for (final i in lines[li]) {
          if (i is WordTab) {
            segments.add([]);
            tabs.add(TabInfo(absoluteAlign: i.absoluteAlign, leader: i.leader, leaderStyle: runTextStyle(i.style, ctx)));
          } else {
            final s = innerState.span(i);
            if (s != null) segments.last.add(s);
          }
        }
        final start = li == 0 ? math.max(0.0, ctx.pt(firstLine)) : (hanging ? ctx.pt(-firstLine) : 0.0);
        rows.add(
          TabLine(
            stops: stops,
            defaultTab: ctx.pt(ctx.document.defaultTabStop),
            tabs: tabs,
            startOffset: li == 0 && hanging ? 0 : start,
            indentOffset: ctx.pt(padLeft),
            children: [for (final s in segments) _rich(s, align: TextAlign.left, dir: dir)],
          ),
        );
      }
      content = rows.length == 1
          ? rows.first
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: rows);
    } else {
      final spans = <InlineSpan>[];
      if (firstLine > 0) spans.add(WidgetSpan(child: SizedBox(width: ctx.pt(firstLine), height: 1)));
      for (final i in flow) {
        final s = innerState.span(i);
        if (s != null) spans.add(s);
      }
      content = _rich(spans, align: align, dir: dir);
    }

    if (displayMath.isNotEmpty) {
      final eqs = [
        for (final m in displayMath)
          Padding(
            padding: EdgeInsets.symmetric(vertical: ctx.pt(3)),
            child: Center(child: Text.rich(MathView(ctx.pt(m.style.size), Color(m.style.color ?? 0xFF000000)).span(m.root), textScaler: TextScaler.noScaling)),
          ),
      ];
      final onlyMath = flow.every((i) => i is WordText && i.text.trim().isEmpty || i is WordBreak);
      content = onlyMath ? Column(mainAxisSize: MainAxisSize.min, children: eqs) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [content, ...eqs]);
    }

    if (hasList) {
      final l = p.list!;
      final labelStyle = runTextStyle(l.style, ctx, paragraph: st);
      Widget label = l.picture != null
          ? Image.memory(l.picture!, width: ctx.pt(l.style.size * 0.8), height: ctx.pt(l.style.size * 0.8), errorBuilder: (_, _, _) => Text('•', style: labelStyle))
          : Text(l.text, style: labelStyle, textScaler: TextScaler.noScaling, textDirection: dir);
      final hangW = ctx.pt(-st.firstLine);
      if (l.suffix == 'tab' && hangW > 0) {
        label = ConstrainedBox(
          constraints: BoxConstraints(minWidth: hangW),
          child: Align(widthFactor: 1, alignment: l.align == WordAlign.right ? Alignment.centerRight : (l.align == WordAlign.center ? Alignment.center : Alignment.centerLeft), child: label),
        );
        label = Padding(padding: EdgeInsets.only(right: ctx.pt(2)), child: label);
      } else if (l.suffix == 'space') {
        label = Padding(padding: EdgeInsets.only(right: ctx.pt(l.style.size * 0.3)), child: label);
      }
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        textDirection: dir,
        children: [label, Expanded(child: content)],
      );
    }

    // Floating pictures: beside the text when text wraps around them,
    // otherwise on their own line.
    if (floats.isNotEmpty) {
      final above = <Widget>[];
      final behind = <Widget>[], inFront = <Widget>[];
      Widget? left, right;
      for (final f in floats) {
        final a = _anchorOf(f)!;
        final side = a.alignH ?? (a.offsetX > ctx.width / ctx.unit / 3 ? 'right' : 'left');
        final wraps = a.wrap == 'square' || a.wrap == 'tight' || a.wrap == 'through';
        final fw = _floatWidget(f, inner.withWidth(contentWidth * (wraps ? 0.5 : 1)));
        if (a.wrap == 'none') {
          // Behind or in front of the text: drawn over the paragraph
          // without moving its text, the way Word does.
          final dx = a.relativeH == 'column' || a.relativeH == 'character' ? ctx.pt(a.offsetX) : 0.0;
          final dy = a.relativeV == 'paragraph' || a.relativeV == 'line' ? ctx.pt(a.offsetY) : 0.0;
          final child = IgnorePointer(ignoring: a.behindText, child: fw);
          final placed = side == 'center' || side == 'right'
              ? Positioned(
                  top: dy,
                  left: 0,
                  right: 0,
                  child: Align(alignment: side == 'center' ? Alignment.topCenter : Alignment.topRight, child: child),
                )
              : Positioned(top: dy, left: dx.clamp(0, contentWidth), child: child);
          (a.behindText ? behind : inFront).add(placed);
          continue;
        }
        if (wraps && (side == 'left' || side == 'inside') && left == null) {
          left = Padding(padding: EdgeInsets.only(right: ctx.pt(9), bottom: ctx.pt(4)), child: fw);
        } else if (wraps && (side == 'right' || side == 'outside') && right == null) {
          right = Padding(padding: EdgeInsets.only(left: ctx.pt(9), bottom: ctx.pt(4)), child: fw);
        } else {
          above.add(
            Padding(
              padding: EdgeInsets.symmetric(vertical: ctx.pt(3)),
              child: Align(
                alignment: switch (side) {
                  'center' => Alignment.center,
                  'right' || 'outside' => Alignment.centerRight,
                  _ => a.relativeH == 'page' || a.relativeH == 'margin' ? (a.offsetX > contentWidth / ctx.unit / 3 ? Alignment.center : Alignment.centerLeft) : Alignment.centerLeft,
                },
                child: fw,
              ),
            ),
          );
        }
      }
      if (left != null || right != null) {
        content = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [?left, Expanded(child: content), ?right]);
      }
      if (above.isNotEmpty) {
        content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [...above, content]);
      }
      if (behind.isNotEmpty || inFront.isNotEmpty) {
        content = Stack(clipBehavior: Clip.none, children: [...behind, content, ...inFront]);
      }
    }

    // Borders and shading (merged with neighbours that have the same borders).
    var borders = st.borders;
    final prev = widget.previous, next = widget.next;
    if (borders != null) {
      final joinUp = prev is WordParagraph && _sameBorders(prev.style.borders, borders);
      final joinDown = next is WordParagraph && _sameBorders(next.style.borders, borders);
      if (joinUp) borders = borders.copyWith(top: borders.between, clearTop: borders.between == null);
      if (joinDown) borders = borders.copyWith(clearBottom: true);
    }
    if (borders != null || st.shading != null) {
      double pad(WordBorder? b) => b == null || !b.isVisible ? ctx.pt(1) : ctx.pt(b.space + b.width) + 1;
      content = CustomPaint(
        painter: WordBorderPainter(borders: borders, unit: ctx.unit, fill: st.shading == null ? null : Color(st.shading!)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad(borders?.left), pad(borders?.top), pad(borders?.right), pad(borders?.bottom)),
          child: content,
        ),
      );
    }

    // Space before and after, with contextual spacing between paragraphs of the same style.
    var before = widget.spaceBefore ?? st.spaceBefore;
    var after = st.spaceAfter;
    if (st.contextualSpacing) {
      if (prev is WordParagraph && prev.styleId == p.styleId) before = 0;
      if (next is WordParagraph && next.styleId == p.styleId) after = 0;
    }
    Widget out = Padding(
      padding: EdgeInsetsDirectional.only(
        start: ctx.pt(padLeft),
        end: ctx.pt(math.max(0, st.indentRight)),
        top: ctx.pt(before),
        bottom: ctx.pt(after),
      ),
      child: content,
    );
    if (st.indentRight < 0 || indentLeft < 0) {
      // Negative indents reach into the margin.
      out = Transform.translate(offset: Offset(ctx.pt(math.min(0, indentLeft)), 0), child: out);
    }

    // Change bar in the margin for tracked changes.
    final changed = ctx.options.showMarkup &&
        (p.revision != null || p.inlines.any((i) => i is WordText && i.revision != null) || false);
    if (changed) {
      final author = p.revision?.author ?? p.inlines.whereType<WordText>().firstWhere((t) => t.revision != null).revision!.author;
      out = Stack(
        clipBehavior: Clip.none,
        children: [
          out,
          Positioned(left: -ctx.pt(10), top: ctx.pt(before), bottom: ctx.pt(after), child: Container(width: math.max(1.2, ctx.pt(1)), color: reviewerColor(author))),
        ],
      );
    }
    final key = ctx.keyFor(p.index);
    return key == null ? out : KeyedSubtree(key: key, child: out);
  }
}

/// Builds spans for an inner width (inline pictures fit the text column).
class _InnerSpans {
  _InnerSpans(this.state, this.ctx);

  final _WordParagraphViewState state;
  final WordRenderContext ctx;

  InlineSpan? span(WordInline i) {
    if (i is WordPicture) return WidgetSpan(alignment: PlaceholderAlignment.bottom, child: WordPictureView(i, ctx));
    if (i is WordShape) return WidgetSpan(alignment: PlaceholderAlignment.bottom, child: WordShapeView(i, ctx, buildWordBlocks));
    if (i is WordChart) return WidgetSpan(alignment: PlaceholderAlignment.bottom, child: WordChartView(i, ctx));
    return state._span(i);
  }
}

// ---------------------------------------------------------------- tables

class WordTableView extends StatelessWidget {
  const WordTableView(this.table, this.ctx, {super.key});

  final WordTable table;
  final WordRenderContext ctx;

  @override
  Widget build(BuildContext context) {
    final t = table;
    final indent = ctx.pt(t.indent).clamp(-ctx.width / 2, ctx.width / 2);
    final avail = math.max(40.0, ctx.width - math.max(0, indent));
    var cols = [for (final c in t.columns) ctx.pt(c)];
    final total = cols.fold<double>(0, (a, b) => a + b);
    if (total > avail && total > 0) cols = [for (final c in cols) c * avail / total];
    final spacing = ctx.pt(t.cellSpacing);
    final rows = <Widget>[];
    for (final row in t.rows) {
      if (row.revision?.removes == true && !ctx.options.showMarkup) continue;
      var col = 0;
      final cells = <Widget>[];
      for (final cell in row.cells) {
        final span = cell.colSpan.clamp(1, 64);
        var w = 0.0;
        for (var k = col; k < col + span && k < cols.length; k++) {
          w += cols[k];
        }
        if (col >= cols.length) w = cols.isEmpty ? 40 : cols.last;
        col += span;
        cells.add(_cell(cell, w, spacing, clip: row.exactHeight && row.height != null));
      }
      Widget r = IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: cells),
      );
      if (row.height != null && row.height! > 0) {
        r = row.exactHeight
            ? SizedBox(height: ctx.pt(row.height!), child: r)
            : ConstrainedBox(constraints: BoxConstraints(minHeight: ctx.pt(row.height!)), child: r);
      }
      if (row.revision != null && ctx.options.showMarkup) {
        final color = row.revision!.removes ? const Color(0x22E53935) : const Color(0x2243A047);
        r = Container(color: color, child: r);
      }
      rows.add(r);
    }
    Widget out = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: rows);
    if (spacing > 0) out = Padding(padding: EdgeInsets.all(spacing / 2), child: out);
    out = Align(
      alignment: switch (t.align) {
        WordAlign.center => Alignment.center,
        WordAlign.right => Alignment.centerRight,
        _ => Alignment.centerLeft,
      },
      child: out,
    );
    if (indent > 0) out = Padding(padding: EdgeInsets.only(left: indent), child: out);
    return Padding(padding: EdgeInsets.only(bottom: ctx.pt(2)), child: out);
  }

  Widget _cell(WordTableCell cell, double width, double spacing, {bool clip = false}) {
    final m = cell.margins;
    final rotated = cell.textDirection == 'btLr' || cell.textDirection == 'tbRl' || cell.textDirection == 'tbRlV';
    final innerW = math.max(10.0, width - ctx.pt(m.left + m.right) - spacing);
    Widget content = cell.blocks.isEmpty ? const SizedBox.shrink() : buildWordBlocks(cell.blocks, ctx.withWidth(rotated ? 400 : innerW));
    if (rotated) {
      content = RotatedBox(quarterTurns: cell.textDirection == 'btLr' ? 3 : 1, child: IntrinsicWidth(child: content));
    }
    content = Padding(padding: EdgeInsets.fromLTRB(ctx.pt(m.left), ctx.pt(m.top), ctx.pt(m.right), ctx.pt(m.bottom)), child: content);
    if (clip) {
      // A row with an exact height cuts off what does not fit, as in Word.
      content = ClipRect(
        child: OverflowBox(
          minHeight: 0,
          maxHeight: double.infinity,
          alignment: switch (cell.vAlign) {
            WordCellVAlign.center => Alignment.center,
            WordCellVAlign.bottom => Alignment.bottomCenter,
            WordCellVAlign.top => Alignment.topCenter,
          },
          child: content,
        ),
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: rotated ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
        mainAxisAlignment: switch (cell.vAlign) {
          WordCellVAlign.center => MainAxisAlignment.center,
          WordCellVAlign.bottom => MainAxisAlignment.end,
          WordCellVAlign.top => MainAxisAlignment.start,
        },
        children: [content],
      );
    }
    Widget box = CustomPaint(
      foregroundPainter: WordBorderPainter(borders: cell.borders, unit: ctx.unit),
      child: Container(color: cell.shading == null ? null : Color(cell.shading!), child: content),
    );
    if (spacing > 0) box = Padding(padding: EdgeInsets.all(spacing / 2), child: box);
    return SizedBox(width: width, child: box);
  }
}

/// Formats a page number the way the section asks (i, ii, iii or 1, 2, 3).
String formatPageNumber(int n, String format) => formatNumber(n, format);
