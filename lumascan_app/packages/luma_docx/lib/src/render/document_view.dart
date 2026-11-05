import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model.dart';
import 'blocks.dart';
import 'borders.dart';
import 'context.dart';
import 'drawings.dart';

/// Lets an app jump to a heading or bookmark in a [WordDocumentView].
class WordViewController {
  _WordDocumentViewState? _state;

  /// Scrolls to the paragraph with this [WordParagraph.index]. Returns false
  /// when it is not in the view.
  Future<bool> jumpToParagraph(int index) => _state?._jump(index) ?? Future.value(false);


  Future<bool> jumpToBookmark(String name) {
    final index = _state?.widget.document.bookmarks[name];
    return index == null ? Future.value(false) : jumpToParagraph(index);
  }
}

/// Shows a [WordDocument]: as pages ([WordLayout.pages]) or as text that
/// fills the screen ([WordLayout.reflow]). Text can be selected and copied.
///
/// Links inside the document jump by themselves; outside links, notes and
/// comments go to the callbacks so the app decides what to do.
class WordDocumentView extends StatefulWidget {
  const WordDocumentView({
    super.key,
    required this.document,
    this.options = const WordViewOptions(),
    this.controller,
    this.onLinkTap,
    this.onNoteTap,
    this.onCommentTap,
    this.padding = const EdgeInsets.all(12),
    this.background,
    this.jumpDuration = const Duration(milliseconds: 300),
  });

  final WordDocument document;
  final WordViewOptions options;
  final WordViewController? controller;
  final WordLinkCallback? onLinkTap;
  final WordNoteCallback? onNoteTap;
  final WordCommentCallback? onCommentTap;
  final EdgeInsets padding;

  /// Behind the pages; defaults to a light grey like Word's.
  final Color? background;

  /// How long a jump to a heading or bookmark scrolls; zero jumps at once
  /// (for reduced motion).
  final Duration jumpDuration;

  @override
  State<WordDocumentView> createState() => _WordDocumentViewState();
}

/// A piece of a page that shares one column layout.
class _Region {
  _Region(this.section);

  final WordSection section;
  final blocks = <WordBlock>[];
}

class _Page {
  _Page(this.section, {required this.firstOfSection});

  final WordSection section;
  final bool firstOfSection;
  final regions = <_Region>[];
  int number = 1;
  int sectionPages = 1;

  bool get isEmpty => regions.every((r) => r.blocks.isEmpty);
}

class _WordDocumentViewState extends State<WordDocumentView> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  late Set<int> _targets;
  late List<_Page> _pages;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _prepare();
  }

  @override
  void didUpdateWidget(WordDocumentView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (old.document != widget.document) _prepare();
  }

  @override
  void dispose() {
    widget.controller?._state = null;
    _scroll.dispose();
    super.dispose();
  }

  void _prepare() {
    final d = widget.document;
    _targets = {...d.bookmarks.values, for (final h in d.headings) h.paragraphIndex};
    _keys.clear();
    _pages = _paginate(d);
  }

  GlobalKey? _keyFor(int index) => _targets.contains(index) ? _keys.putIfAbsent(index, GlobalKey.new) : null;

  Future<bool> _jump(int index) async {
    final ctx = _keys[index]?.currentContext;
    if (ctx == null) return false;
    await Scrollable.ensureVisible(ctx, duration: widget.jumpDuration, curve: Curves.easeOutCubic, alignment: 0.05);
    return true;
  }

  void _onLink(WordLink link) {
    final anchor = link.anchor;
    if (anchor != null && widget.document.bookmarks.containsKey(anchor)) {
      _jump(widget.document.bookmarks[anchor]!);
      return;
    }
    widget.onLinkTap?.call(link);
  }

  /// Splits sections into pages at hard page breaks and page-starting
  /// section breaks. Word decides the other page ends while it types; a
  /// phone screen does not need them.
  static List<_Page> _paginate(WordDocument d) {
    final pages = <_Page>[];
    _Page? page;
    for (final s in d.sections) {
      final continuous = s.breakType == WordBreakType.continuous || s.breakType == WordBreakType.nextColumn;
      if (page == null || !continuous) {
        page = _Page(s, firstOfSection: true);
        pages.add(page);
      }
      var region = _Region(s);
      page.regions.add(region);
      for (final b in s.blocks) {
        if (b is WordParagraph) {
          var parts = _splitAtPageBreaks(b);
          for (var i = 0; i < parts.length; i++) {
            final part = parts[i];
            final breakBefore = i > 0 || (part.style.pageBreakBefore && !page!.isEmpty);
            if (breakBefore) {
              page = _Page(s, firstOfSection: false);
              pages.add(page);
              region = _Region(s);
              page.regions.add(region);
            }
            region.blocks.add(part);
          }
          parts = const [];
        } else {
          region.blocks.add(b);
        }
      }
    }
    // Page numbers, with restarts and per-section counts.
    var n = 0;
    WordSection? current;
    var sectionStart = 0;
    for (var i = 0; i < pages.length; i++) {
      final p = pages[i];
      if (p.section != current) {
        if (current != null) {
          for (var k = sectionStart; k < i; k++) {
            pages[k].sectionPages = i - sectionStart;
          }
        }
        current = p.section;
        sectionStart = i;
        if (p.section.pageNumberStart != null) n = p.section.pageNumberStart! - 1;
      }
      n++;
      p.number = n;
    }
    for (var k = sectionStart; k < pages.length; k++) {
      pages[k].sectionPages = pages.length - sectionStart;
    }
    return pages;
  }

  static List<WordParagraph> _splitAtPageBreaks(WordParagraph p) {
    if (!p.inlines.any((i) => i is WordBreak && i.kind == WordBreakKind.page)) return [p];
    final parts = <List<WordInline>>[[]];
    for (final i in p.inlines) {
      if (i is WordBreak && i.kind == WordBreakKind.page) {
        parts.add([]);
      } else {
        parts.last.add(i);
      }
    }
    return [
      for (var k = 0; k < parts.length; k++)
        if (k == 0 || parts[k].isNotEmpty || k == parts.length - 1)
          WordParagraph(
            index: k == 0 ? p.index : -1,
            style: p.style,
            inlines: parts[k],
            styleId: p.styleId,
            styleName: p.styleName,
            list: k == 0 ? p.list : null,
            headingLevel: k == 0 ? p.headingLevel : null,
            revision: p.revision,
            bookmarks: k == 0 ? p.bookmarks : const [],
          ),
    ];
  }

  WordRenderContext _context(double unit, double width) => WordRenderContext(
    document: widget.document,
    options: widget.options,
    unit: unit,
    width: width,
    onLink: _onLink,
    onNote: (n) => widget.onNoteTap?.call(n),
    onComment: (c) => widget.onCommentTap?.call(c),
    keyFor: _keyFor,
  );

  @override
  Widget build(BuildContext context) {
    final bg = widget.background ?? const Color(0xFFE9EAEC);
    return ColoredBox(
      color: widget.options.layout == WordLayout.reflow ? Color(widget.document.pageColor ?? 0xFFFFFFFF) : bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = widget.options.layout == WordLayout.pages ? _pagesView(constraints.maxWidth) : _reflowView(constraints.maxWidth);
          return SelectionArea(
            child: SingleChildScrollView(controller: _scroll, padding: widget.padding, child: content),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------ reflow

  Widget _reflowView(double screenWidth) {
    final unit = 1.25 * widget.options.textScale;
    final width = math.max(100.0, screenWidth - widget.padding.horizontal);
    final ctx = _context(unit, width);
    final children = <Widget>[];
    for (var i = 0; i < _pages.length; i++) {
      if (i > 0) children.add(const _PageBreakRule());
      for (final r in _pages[i].regions) {
        children.add(buildWordBlocks(r.blocks, ctx));
      }
    }
    children.add(_notesSection(ctx, [...widget.document.footnotes.values, ...widget.document.endnotes.values]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  // ------------------------------------------------------------ pages

  Widget _pagesView(double screenWidth) {
    final maxPage = _pages.fold<double>(0, (m, p) => math.max(m, p.section.pageWidth));
    final children = <Widget>[];
    for (var i = 0; i < _pages.length; i++) {
      children.add(_page(_pages[i], last: i == _pages.length - 1));
      children.add(const SizedBox(height: 14));
    }
    // Pages are laid out at their size in points, then scaled to the screen.
    return FittedBox(
      fit: BoxFit.fitWidth,
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: maxPage,
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: children),
      ),
    );
  }

  List<WordBlock>? _headerFor(_Page p, Map<String, List<WordBlock>> parts) {
    final s = p.section;
    if (s.titlePage && p.firstOfSection) return parts['first'];
    if (widget.document.evenAndOddHeaders && p.number.isEven) return parts['even'] ?? parts['default'];
    return parts['default'];
  }

  Widget _page(_Page p, {required bool last}) {
    final s = p.section;
    final d = widget.document;
    const unit = 1.0;
    final width = s.contentWidth;
    final ctx = _context(unit, width);
    final pageCtx = ctx.forPage(
      pageNumber: formatPageNumber(p.number, s.pageNumberFormat),
      pageCount: _pages.length,
      sectionPages: p.sectionPages,
    );

    final body = <Widget>[];
    for (final r in p.regions) {
      body.add(_region(r, ctx));
    }
    // Footnotes referenced on this page sit at its foot.
    final noteIds = <String>{};
    for (final r in p.regions) {
      _collectNotes(r.blocks, noteIds);
    }
    final notes = [
      for (final id in noteIds)
        if (d.footnotes[id] != null) d.footnotes[id]!,
    ];
    if (notes.isNotEmpty) body.add(_notesSection(ctx, notes));
    if (last && d.endnotes.isNotEmpty) body.add(_notesSection(ctx, d.endnotes.values.toList()));

    final header = _headerFor(p, s.headers);
    final footer = _headerFor(p, s.footers);
    // Pictures and shapes in the header that sit behind the text are the
    // watermark: drawn in the middle of every page of the section.
    final watermark = <Widget>[];
    List<WordBlock> headerBlocks = const [];
    if (header != null) {
      headerBlocks = [];
      for (final b in header) {
        if (b is WordParagraph) {
          final behind = b.inlines.where(_isBackground).toList();
          if (behind.isNotEmpty) {
            for (final w in behind) {
              watermark.add(_floating(w, pageCtx.withWidth(s.pageWidth)));
            }
            headerBlocks.add(
              WordParagraph(index: -1, style: b.style, inlines: b.inlines.where((i) => !_isBackground(i)).toList(), styleId: b.styleId),
            );
            continue;
          }
        }
        headerBlocks.add(b);
      }
    }

    final centered = s.verticalAlign == WordVerticalPageAlign.center;
    final bottom = s.verticalAlign == WordVerticalPageAlign.bottom;
    final pageColor = Color(d.pageColor ?? 0xFFFFFFFF);
    final borders = s.pageBorders;
    return Container(
      width: s.pageWidth,
      constraints: BoxConstraints(minHeight: s.pageHeight),
      decoration: BoxDecoration(
        color: pageColor,
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Stack(
        children: [
          if (watermark.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: watermark))),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(s.margins.left + s.gutter, s.margins.top, s.margins.right, s.margins.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: math.max(0, s.pageHeight - s.margins.top - s.margins.bottom)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: centered ? MainAxisAlignment.center : (bottom ? MainAxisAlignment.end : MainAxisAlignment.start),
                children: body,
              ),
            ),
          ),
          if (headerBlocks.isNotEmpty)
            Positioned(
              top: s.headerDistance,
              left: s.margins.left + s.gutter,
              right: s.margins.right,
              child: buildWordBlocks(headerBlocks, pageCtx),
            ),
          if (footer != null && footer.isNotEmpty)
            Positioned(
              bottom: s.footerDistance,
              left: s.margins.left + s.gutter,
              right: s.margins.right,
              child: buildWordBlocks(footer, pageCtx),
            ),
          if (borders != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _PageBorderPainter(borders, s, unit),
                ),
              ),
            ),
          if (s.lineNumbers != null)
            Positioned(
              left: math.max(2, s.margins.left - s.lineNumbers!.distance - 14),
              top: s.margins.top,
              child: const _LineNumberHint(),
            ),
        ],
      ),
    );
  }

  static bool _isBackground(WordInline i) {
    final a = switch (i) {
      WordPicture(:final anchor) || WordShape(:final anchor) || WordChart(:final anchor) => anchor,
      _ => null,
    };
    return a != null && (a.behindText || (a.alignH == 'center' && a.alignV == 'center'));
  }

  Widget _floating(WordInline i, WordRenderContext ctx) => switch (i) {
    WordPicture() => WordPictureView(i, ctx),
    WordShape() => WordShapeView(i, ctx, buildWordBlocks),
    WordChart() => WordChartView(i, ctx),
    _ => const SizedBox.shrink(),
  };

  void _collectNotes(List<WordBlock> blocks, Set<String> out) {
    for (final b in blocks) {
      if (b is WordParagraph) {
        for (final i in b.inlines) {
          if (i is WordNoteRef && i.kind == WordNoteKind.footnote && i.id.isNotEmpty) out.add(i.id);
          if (i is WordShape) _collectNotes(i.blocks, out);
        }
      } else if (b is WordTable) {
        for (final r in b.rows) {
          for (final c in r.cells) {
            _collectNotes(c.blocks, out);
          }
        }
      }
    }
  }

  Widget _notesSection(WordRenderContext ctx, List<WordNote> notes) {
    if (notes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: ctx.pt(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(width: ctx.width / 3, height: 0.8, color: const Color(0xFF808080)),
          ),
          SizedBox(height: ctx.pt(4)),
          for (final n in notes) buildWordBlocks(n.blocks, ctx),
        ],
      ),
    );
  }

  /// One run of blocks with the same columns. Column breaks start a new
  /// column; without them the text is shared out evenly.
  Widget _region(_Region r, WordRenderContext ctx) {
    // ignore: parameter_assignments
    final cols = r.section.columns;
    if (cols.count <= 1 || r.blocks.isEmpty) return buildWordBlocks(r.blocks, ctx);
    final n = cols.count;
    final avail = r.section.contentWidth - cols.space * (n - 1);
    final given = cols.widths.fold<double>(0, (a, b) => a + b);
    final widths = cols.widths.length == n && given > 0
        ? [for (final w in cols.widths) w * avail / given]
        : List.filled(n, avail / n);
    final groups = List.generate(n, (_) => <WordBlock>[]);
    final hasBreaks = r.blocks.any((b) => b is WordParagraph && b.inlines.any((i) => i is WordBreak && i.kind == WordBreakKind.column));
    if (hasBreaks) {
      var g = 0;
      for (final b in r.blocks) {
        if (b is WordParagraph && b.inlines.any((i) => i is WordBreak && i.kind == WordBreakKind.column)) {
          final before = <WordInline>[], after = <WordInline>[];
          var seen = false;
          for (final i in b.inlines) {
            if (i is WordBreak && i.kind == WordBreakKind.column) {
              seen = true;
            } else {
              (seen ? after : before).add(i);
            }
          }
          if (before.isNotEmpty) groups[g].add(WordParagraph(index: b.index, style: b.style, inlines: before, styleId: b.styleId, list: b.list));
          g = math.min(g + 1, n - 1);
          if (after.isNotEmpty) groups[g].add(WordParagraph(index: -1, style: b.style, inlines: after, styleId: b.styleId));
        } else {
          groups[g].add(b);
        }
      }
    } else {
      // Long paragraphs are cut at sentence ends so the columns can balance.
      final totalChars = r.blocks.fold<int>(0, (a, b) => a + (b is WordParagraph ? b.text.length : 400));
      final pieces = <WordBlock>[];
      for (final b in r.blocks) {
        if (b is WordParagraph && b.text.length > totalChars / (n * 2) && b.inlines.every((i) => i is WordText)) {
          pieces.addAll(_cutParagraph(b, (totalChars / (n * 3)).ceil()));
        } else {
          pieces.add(b);
        }
      }
      r = _Region(r.section)..blocks.addAll(pieces);
      double weight(WordBlock b) {
        if (b is WordParagraph) return 40 + b.text.length.toDouble();
        return 400;
      }

      final total = r.blocks.fold<double>(0, (a, b) => a + weight(b));
      var acc = 0.0, g = 0;
      final widthTotal = widths.fold<double>(0, (a, b) => a + b);
      var limit = total * widths[0] / widthTotal;
      for (final b in r.blocks) {
        final w = weight(b);
        if (acc + w / 2 > limit && g < n - 1 && groups[g].isNotEmpty) {
          g++;
          limit += total * widths[g] / widthTotal;
        }
        groups[g].add(b);
        acc += w;
      }
    }
    final children = <Widget>[];
    for (var i = 0; i < n; i++) {
      if (i > 0) {
        children.add(
          SizedBox(
            width: cols.space,
            child: cols.separator ? Center(child: Container(width: 0.75, color: const Color(0xFF000000))) : null,
          ),
        );
      }
      children.add(SizedBox(width: widths[i], child: buildWordBlocks(groups[i], ctx.withWidth(widths[i]))));
    }
    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
  }
}

/// Cuts a text-only paragraph into pieces of about [size] characters, at
/// sentence ends, keeping the formatting of each run.
List<WordParagraph> _cutParagraph(WordParagraph p, int size) {
  final out = <WordParagraph>[];
  var current = <WordInline>[];
  var count = 0;
  void flush({required bool last}) {
    if (current.isEmpty) return;
    final first = out.isEmpty;
    out.add(
      WordParagraph(
        index: first ? p.index : -1,
        style: p.style.copyWith(spaceBefore: first ? p.style.spaceBefore : 0, spaceAfter: last ? p.style.spaceAfter : 0),
        inlines: current,
        styleId: p.styleId,
        list: first ? p.list : null,
      ),
    );
    current = [];
    count = 0;
  }

  for (final i in p.inlines) {
    final t = i as WordText;
    final sentences = RegExp(r'[^.!?]*[.!?]+\s*|[^.!?]+$').allMatches(t.text).map((m) => m.group(0)!).toList();
    for (final s in sentences) {
      current.add(WordText(s, t.style, link: t.link, revision: t.revision, commentIds: t.commentIds, field: t.field, contentControl: t.contentControl));
      count += s.length;
      if (count >= size) flush(last: false);
    }
  }
  flush(last: true);
  return out;
}

class _PageBorderPainter extends CustomPainter {
  _PageBorderPainter(this.borders, this.section, this.unit);

  final WordBorders borders;
  final WordSection section;
  final double unit;

  @override
  void paint(Canvas canvas, Size size) {
    final s = section;
    Rect r;
    if (s.pageBordersFromText) {
      r = Rect.fromLTRB(
        s.margins.left + s.gutter - (borders.left?.space ?? 4),
        s.margins.top - (borders.top?.space ?? 1),
        size.width - s.margins.right + (borders.right?.space ?? 4),
        size.height - s.margins.bottom + (borders.bottom?.space ?? 1),
      );
    } else {
      r = Rect.fromLTRB(borders.left?.space ?? 24, borders.top?.space ?? 24, size.width - (borders.right?.space ?? 24), size.height - (borders.bottom?.space ?? 24));
    }
    paintLine(canvas, borders.top, r.topLeft, r.topRight, unit);
    paintLine(canvas, borders.bottom, r.bottomLeft, r.bottomRight, unit);
    paintLine(canvas, borders.left, r.topLeft, r.bottomLeft, unit);
    paintLine(canvas, borders.right, r.topRight, r.bottomRight, unit);
  }

  @override
  bool shouldRepaint(_PageBorderPainter old) => old.borders != borders;
}

/// Word numbers each line; this view marks the section instead.
class _LineNumberHint extends StatelessWidget {
  const _LineNumberHint();

  @override
  Widget build(BuildContext context) => const Tooltip(
    message: 'This section has line numbers in Word',
    child: Text('1', style: TextStyle(inherit: false, fontSize: 8, color: Color(0xFF9E9E9E))),
  );
}

class _PageBreakRule extends StatelessWidget {
  const _PageBreakRule();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        Expanded(child: Divider(color: Color(0xFFBDBDBD))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('Page break', style: TextStyle(inherit: false, fontSize: 11, color: Color(0xFF9E9E9E))),
        ),
        Expanded(child: Divider(color: Color(0xFFBDBDBD))),
      ],
    ),
  );
}
