import 'dart:typed_data';

/// Colours are 0xAARRGGBB integers so the model has no Flutter dependency.
typedef WordColor = int;

/// A Word document read from a .docx file. All formatting is already
/// resolved (styles, themes, numbering), so a renderer only has to draw it.
class WordDocument {
  WordDocument({
    required this.sections,
    this.footnotes = const {},
    this.endnotes = const {},
    this.comments = const [],
    this.properties = const WordProperties(),
    this.pageColor,
    this.evenAndOddHeaders = false,
    this.defaultTabStop = 36,
    this.bookmarks = const {},
    this.headings = const [],
    this.warnings = const [],
  });

  final List<WordSection> sections;

  /// Footnote and endnote text by note id.
  final Map<String, WordNote> footnotes;
  final Map<String, WordNote> endnotes;

  final List<WordComment> comments;
  final WordProperties properties;

  /// Design > Page Color, or null for white.
  final WordColor? pageColor;

  /// Whether odd and even pages have their own headers and footers.
  final bool evenAndOddHeaders;

  /// Distance between Word's automatic tab stops, in points.
  final double defaultTabStop;

  /// Bookmark name to the [WordParagraph.index] of the paragraph that holds it.
  final Map<String, int> bookmarks;

  /// Headings in order, for a navigation pane.
  final List<WordHeading> headings;

  /// Parts of the file that could not be read. The rest of the document is
  /// still shown.
  final List<String> warnings;

  WordComment? comment(String id) {
    for (final c in comments) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// All the text in reading order, one line per paragraph, for search and
  /// for tests.
  String get plainText {
    final out = StringBuffer();
    for (final s in sections) {
      for (final b in s.blocks) {
        b.writePlainText(out);
      }
    }
    return out.toString();
  }
}

class WordHeading {
  const WordHeading({required this.level, required this.text, required this.paragraphIndex});

  /// 0 for Title, 1 for Heading 1, and so on.
  final int level;
  final String text;
  final int paragraphIndex;
}

/// File > Info > Properties, plus Word's statistics and custom properties.
class WordProperties {
  const WordProperties({
    this.title,
    this.subject,
    this.author,
    this.keywords,
    this.description,
    this.category,
    this.lastModifiedBy,
    this.created,
    this.modified,
    this.company,
    this.application,
    this.pages,
    this.words,
    this.custom = const {},
  });

  final String? title;
  final String? subject;
  final String? author;
  final String? keywords;
  final String? description;
  final String? category;
  final String? lastModifiedBy;
  final DateTime? created;
  final DateTime? modified;
  final String? company;
  final String? application;
  final int? pages;
  final int? words;
  final Map<String, String> custom;
}

enum WordBreakType { nextPage, continuous, oddPage, evenPage, nextColumn }

enum WordVerticalPageAlign { top, center, bottom, both }

/// One section: page setup, headers and footers, and its content.
class WordSection {
  WordSection({
    required this.pageWidth,
    required this.pageHeight,
    required this.margins,
    this.headerDistance = 36,
    this.footerDistance = 36,
    this.gutter = 0,
    this.landscape = false,
    this.columns = const WordColumns(),
    this.breakType = WordBreakType.nextPage,
    this.verticalAlign = WordVerticalPageAlign.top,
    this.pageBorders,
    this.pageBordersFromText = true,
    this.lineNumbers,
    this.titlePage = false,
    this.headers = const {},
    this.footers = const {},
    this.pageNumberFormat = 'decimal',
    this.pageNumberStart,
    required this.blocks,
  });

  /// Page size in points.
  final double pageWidth;
  final double pageHeight;
  final WordInsets margins;
  final double headerDistance;
  final double footerDistance;
  final double gutter;
  final bool landscape;
  final WordColumns columns;
  final WordBreakType breakType;
  final WordVerticalPageAlign verticalAlign;
  final WordBorders? pageBorders;

  /// Whether [pageBorders] are measured from the text (true) or the page edge.
  final bool pageBordersFromText;
  final WordLineNumbers? lineNumbers;

  /// Different first page.
  final bool titlePage;

  /// Header and footer content by kind: `default`, `first` and `even`.
  final Map<String, List<WordBlock>> headers;
  final Map<String, List<WordBlock>> footers;

  final String pageNumberFormat;
  final int? pageNumberStart;

  final List<WordBlock> blocks;

  double get contentWidth => pageWidth - margins.left - margins.right - gutter;
}

class WordInsets {
  const WordInsets({this.top = 0, this.right = 0, this.bottom = 0, this.left = 0});

  final double top;
  final double right;
  final double bottom;
  final double left;
}

class WordColumns {
  const WordColumns({this.count = 1, this.space = 36, this.separator = false, this.widths = const []});

  final int count;
  final double space;
  final bool separator;

  /// Widths in points when the columns are not equal; empty when they are.
  final List<double> widths;
}

class WordLineNumbers {
  const WordLineNumbers({this.countBy = 1, this.start = 1, this.distance = 18, this.restart = 'newPage'});

  final int countBy;
  final int start;
  final double distance;
  final String restart;
}

/// One border line. [style] is Word's name, such as `single`, `double`,
/// `dotted`, `dashed`, `thick` or `wave`.
class WordBorder {
  const WordBorder({required this.style, this.width = 0.5, this.color = 0xFF000000, this.space = 0});

  final String style;

  /// Line width in points.
  final double width;
  final WordColor color;

  /// Gap between the border and the text, in points.
  final double space;

  bool get isVisible => style != 'none' && style != 'nil';
}

class WordBorders {
  const WordBorders({
    this.top,
    this.left,
    this.bottom,
    this.right,
    this.insideH,
    this.insideV,
    this.between,
    this.diagonalDown,
    this.diagonalUp,
  });

  final WordBorder? top;
  final WordBorder? left;
  final WordBorder? bottom;
  final WordBorder? right;
  final WordBorder? insideH;
  final WordBorder? insideV;
  final WordBorder? between;

  /// Top-left to bottom-right, and bottom-left to top-right (table cells).
  final WordBorder? diagonalDown;
  final WordBorder? diagonalUp;

  bool get isEmpty =>
      top == null &&
      left == null &&
      bottom == null &&
      right == null &&
      diagonalDown == null &&
      diagonalUp == null;

  /// [other]'s sides win where it has one.
  WordBorders merge(WordBorders? other) {
    if (other == null) return this;
    return WordBorders(
      top: other.top ?? top,
      left: other.left ?? left,
      bottom: other.bottom ?? bottom,
      right: other.right ?? right,
      insideH: other.insideH ?? insideH,
      insideV: other.insideV ?? insideV,
      between: other.between ?? between,
      diagonalDown: other.diagonalDown ?? diagonalDown,
      diagonalUp: other.diagonalUp ?? diagonalUp,
    );
  }

  WordBorders copyWith({
    WordBorder? top,
    WordBorder? left,
    WordBorder? bottom,
    WordBorder? right,
    bool clearTop = false,
    bool clearBottom = false,
    bool clearLeft = false,
    bool clearRight = false,
  }) => WordBorders(
    top: clearTop ? null : top ?? this.top,
    left: clearLeft ? null : left ?? this.left,
    bottom: clearBottom ? null : bottom ?? this.bottom,
    right: clearRight ? null : right ?? this.right,
    insideH: insideH,
    insideV: insideV,
    between: between,
    diagonalDown: diagonalDown,
    diagonalUp: diagonalUp,
  );
}

// ---------------------------------------------------------------- blocks

/// Something that stacks down the page: a paragraph or a table.
sealed class WordBlock {
  const WordBlock();

  void writePlainText(StringBuffer out);
}

enum WordAlign { left, center, right, justify }

enum WordTabAlign { left, center, right, decimal, bar }

class WordTabStop {
  const WordTabStop({required this.position, this.align = WordTabAlign.left, this.leader = 'none'});

  /// From the text's left edge (the page margin), in points.
  final double position;
  final WordTabAlign align;

  /// `none`, `dot`, `hyphen`, `underscore`, `heavy` or `middleDot`.
  final String leader;
}

/// Paragraph formatting, already resolved.
class WordParagraphStyle {
  const WordParagraphStyle({
    this.align = WordAlign.left,
    this.indentLeft = 0,
    this.indentRight = 0,
    this.firstLine = 0,
    this.spaceBefore = 0,
    this.spaceAfter = 0,
    this.lineMultiple,
    this.lineExact,
    this.lineAtLeast,
    this.borders,
    this.shading,
    this.tabs = const [],
    this.rtl = false,
    this.keepNext = false,
    this.keepLines = false,
    this.pageBreakBefore = false,
    this.widowControl = true,
    this.contextualSpacing = false,
    this.outlineLevel,
  });

  final WordAlign align;
  final double indentLeft;
  final double indentRight;

  /// Positive for a first-line indent, negative for a hanging indent.
  final double firstLine;
  final double spaceBefore;
  final double spaceAfter;

  /// Line spacing: a multiple of single (1.5, 2), an exact height in points,
  /// or a minimum height in points. All null means single.
  final double? lineMultiple;
  final double? lineExact;
  final double? lineAtLeast;
  final WordBorders? borders;
  final WordColor? shading;
  final List<WordTabStop> tabs;
  final bool rtl;
  final bool keepNext;
  final bool keepLines;
  final bool pageBreakBefore;
  final bool widowControl;
  final bool contextualSpacing;

  /// 0 for Heading 1, 1 for Heading 2, ...; null for body text.
  final int? outlineLevel;

  WordParagraphStyle copyWith({double? spaceBefore, double? spaceAfter}) => WordParagraphStyle(
    align: align,
    indentLeft: indentLeft,
    indentRight: indentRight,
    firstLine: firstLine,
    spaceBefore: spaceBefore ?? this.spaceBefore,
    spaceAfter: spaceAfter ?? this.spaceAfter,
    lineMultiple: lineMultiple,
    lineExact: lineExact,
    lineAtLeast: lineAtLeast,
    borders: borders,
    shading: shading,
    tabs: tabs,
    rtl: rtl,
    keepNext: keepNext,
    keepLines: keepLines,
    pageBreakBefore: pageBreakBefore,
    widowControl: widowControl,
    contextualSpacing: contextualSpacing,
    outlineLevel: outlineLevel,
  );
}

/// The number or bullet in front of a list paragraph.
class WordListLabel {
  const WordListLabel({
    required this.text,
    required this.style,
    this.picture,
    this.suffix = 'tab',
    this.align = WordAlign.left,
    this.level = 0,
    this.listId,
    this.format = 'decimal',
    this.pattern,
    this.start = 1,
  });

  final String text;
  final WordRunStyle style;

  /// A picture bullet, when the list uses one.
  final Uint8List? picture;

  /// What follows the label: `tab`, `space` or `nothing`.
  final String suffix;
  final WordAlign align;
  final int level;

  /// Which list the paragraph belongs to (Word's numId); paragraphs with
  /// the same id count on together.
  final String? listId;

  /// Number format of this level: `decimal`, `lowerLetter`, `bullet`...
  final String format;

  /// Word's level text, e.g. `%1.%2.` or the bullet character.
  final String? pattern;

  /// The first number of this level.
  final int start;
}

class WordDropCap {
  const WordDropCap({required this.lines, this.inMargin = false});

  final int lines;
  final bool inMargin;
}

enum WordRevisionKind { insert, delete, moveFrom, moveTo, format, paragraph }

/// A tracked change.
class WordRevision {
  const WordRevision({required this.kind, this.author, this.date});

  final WordRevisionKind kind;
  final String? author;
  final DateTime? date;

  bool get removes => kind == WordRevisionKind.delete || kind == WordRevisionKind.moveFrom;
  bool get adds => kind == WordRevisionKind.insert || kind == WordRevisionKind.moveTo;
}

class WordParagraph extends WordBlock {
  WordParagraph({
    required this.index,
    required this.style,
    required this.inlines,
    this.styleId,
    this.styleName,
    this.list,
    this.dropCap,
    this.headingLevel,
    this.revision,
    this.bookmarks = const [],
  });

  /// Position in the document; links and the navigation pane use it.
  final int index;
  WordParagraphStyle style;
  final List<WordInline> inlines;
  final String? styleId;
  final String? styleName;
  final WordListLabel? list;
  final WordDropCap? dropCap;

  /// 0 for Title, 1 for Heading 1, ...; null for body text.
  final int? headingLevel;

  /// Set when the paragraph itself was inserted or its formatting changed
  /// with Track Changes on.
  final WordRevision? revision;
  final List<String> bookmarks;

  String get text {
    final out = StringBuffer();
    for (final i in inlines) {
      i.writePlainText(out);
    }
    return out.toString();
  }

  @override
  void writePlainText(StringBuffer out) {
    if (list != null && list!.text.isNotEmpty) out.write('${list!.text} ');
    out.writeln(text);
  }
}

enum WordCellVAlign { top, center, bottom }

class WordTable extends WordBlock {
  WordTable({
    required this.columns,
    required this.rows,
    this.align = WordAlign.left,
    this.indent = 0,
    this.cellSpacing = 0,
    this.floating = false,
    this.styleId,
  });

  /// Column widths in points, from the table grid.
  final List<double> columns;
  final List<WordTableRow> rows;
  final WordAlign align;
  final double indent;
  final double cellSpacing;

  /// A table placed with text wrapping around it (Table Properties > Around).
  final bool floating;
  final String? styleId;

  double get width => columns.fold(0, (a, b) => a + b);

  @override
  void writePlainText(StringBuffer out) {
    for (final r in rows) {
      out.writeln(
        r.cells
            .where((c) => !c.mergedAway)
            .map((c) {
              final b = StringBuffer();
              for (final block in c.blocks) {
                block.writePlainText(b);
              }
              return b.toString().trim();
            })
            .join('\t'),
      );
    }
  }
}

class WordTableRow {
  WordTableRow({required this.cells, this.header = false, this.cantSplit = false, this.height, this.exactHeight = false, this.revision});

  final List<WordTableCell> cells;

  /// Repeats at the top of each page.
  final bool header;
  final bool cantSplit;
  final double? height;
  final bool exactHeight;

  /// A row inserted or deleted with Track Changes on.
  final WordRevision? revision;
}

class WordTableCell {
  WordTableCell({
    required this.blocks,
    this.colSpan = 1,
    this.rowSpan = 1,
    this.mergedAway = false,
    this.shading,
    this.borders = const WordBorders(),
    this.vAlign = WordCellVAlign.top,
    this.textDirection,
    this.margins = const WordInsets(left: 5.4, right: 5.4),
  });

  final List<WordBlock> blocks;
  final int colSpan;

  /// Rows this cell covers (vertical merge). Cells below it that it covers
  /// have [mergedAway] set and no content.
  int rowSpan;
  final bool mergedAway;
  final WordColor? shading;
  WordBorders borders;
  final WordCellVAlign vAlign;

  /// `btLr` (bottom to top) or `tbRl` (top to bottom); null for normal text.
  final String? textDirection;
  final WordInsets margins;
}

// ---------------------------------------------------------------- inlines

/// Something inside a paragraph: text, a tab, a break, a picture...
sealed class WordInline {
  const WordInline();

  void writePlainText(StringBuffer out) {}
}

enum WordUnderline { none, single, double, thick, dotted, dashed, wave, words }

enum WordVertAlign { baseline, superscript, subscript }

/// Character formatting, already resolved.
class WordRunStyle {
  const WordRunStyle({
    this.font,
    this.size = 11,
    this.bold = false,
    this.italic = false,
    this.underline = WordUnderline.none,
    this.underlineColor,
    this.strike = false,
    this.doubleStrike = false,
    this.vertAlign = WordVertAlign.baseline,
    this.smallCaps = false,
    this.allCaps = false,
    this.color,
    this.highlight,
    this.shading,
    this.hidden = false,
    this.letterSpacing = 0,
    this.scale = 1,
    this.position = 0,
    this.outline = false,
    this.shadow = false,
    this.emboss = false,
    this.imprint = false,
    this.border,
    this.rtl = false,
    this.effects,
  });

  /// Font family as named in the file, such as `Calibri`.
  final String? font;

  /// Size in points.
  final double size;
  final bool bold;
  final bool italic;
  final WordUnderline underline;
  final WordColor? underlineColor;
  final bool strike;
  final bool doubleStrike;
  final WordVertAlign vertAlign;
  final bool smallCaps;
  final bool allCaps;

  /// Null for automatic (black).
  final WordColor? color;
  final WordColor? highlight;
  final WordColor? shading;
  final bool hidden;

  /// Extra space between letters in points (negative is condensed).
  final double letterSpacing;

  /// Horizontal scale, 1 for 100%.
  final double scale;

  /// Raised (positive) or lowered (negative) by this many points.
  final double position;

  /// Legacy effects from Font > Effects.
  final bool outline;
  final bool shadow;
  final bool emboss;
  final bool imprint;
  final WordBorder? border;
  final bool rtl;

  /// Word 2010 text effects: outline, shadow, glow, reflection, gradient, OpenType.
  final WordTextEffects? effects;
}

class WordTextEffects {
  const WordTextEffects({
    this.outlineColor,
    this.outlineWidth = 0,
    this.shadowColor,
    this.shadowBlur = 0,
    this.shadowDx = 0,
    this.shadowDy = 0,
    this.glowColor,
    this.glowRadius = 0,
    this.reflection = false,
    this.gradient = const [],
    this.fillColor,
    this.ligatures,
    this.numberForm,
    this.numberSpacing,
  });

  final WordColor? outlineColor;
  final double outlineWidth;
  final WordColor? shadowColor;
  final double shadowBlur;
  final double shadowDx;
  final double shadowDy;
  final WordColor? glowColor;
  final double glowRadius;
  final bool reflection;

  /// Gradient fill colours, in order; empty for none.
  final List<WordColor> gradient;
  final WordColor? fillColor;

  /// OpenType: `standard`, `contextual`, `historical`, `discretional`, `all`.
  final String? ligatures;

  /// OpenType: `lining` or `oldStyle`.
  final String? numberForm;

  /// OpenType: `proportional` or `tabular`.
  final String? numberSpacing;
}

class WordLink {
  const WordLink({this.url, this.anchor, this.tooltip});

  /// An outside address (web, mailto:, tel:), or null for a link inside the document.
  final String? url;

  /// A bookmark name inside the document.
  final String? anchor;

  /// Hyperlink ScreenTip.
  final String? tooltip;
}

class WordText extends WordInline {
  const WordText(
    this.text,
    this.style, {
    this.link,
    this.revision,
    this.commentIds = const [],
    this.field,
    this.fields = const [],
    this.contentControl,
  });

  final String text;
  final WordRunStyle style;
  final WordLink? link;
  final WordRevision? revision;

  /// Comments whose range covers this text.
  final List<String> commentIds;

  /// The field this text is the result of, such as `PAGE` or `SEQ Figure`.
  final String? field;

  /// Every field this text is the result of, outermost first (a page
  /// number inside a table of contents gives `[TOC..., PAGEREF...]`).
  /// [field] is the last one.
  final List<String> fields;

  /// The kind of content control the text sits in (`richText`, `dropDown`,
  /// `date`, `checkBox`, ...), or null.
  final String? contentControl;

  @override
  void writePlainText(StringBuffer out) {
    if (!style.hidden && !(revision?.removes ?? false)) out.write(text);
  }
}

enum WordBreakKind { line, page, column, textWrapping }

class WordBreak extends WordInline {
  const WordBreak(this.kind);

  final WordBreakKind kind;

  @override
  void writePlainText(StringBuffer out) {
    if (kind == WordBreakKind.line || kind == WordBreakKind.textWrapping) out.write('\n');
  }
}

class WordTab extends WordInline {
  const WordTab(this.style, {this.absoluteAlign, this.leader});

  final WordRunStyle style;

  /// Set for an absolute (positional) tab: `left`, `center` or `right`
  /// of the margin.
  final String? absoluteAlign;
  final String? leader;

  @override
  void writePlainText(StringBuffer out) => out.write('\t');
}

/// Where a floating picture or shape sits and how text wraps around it.
class WordAnchor {
  const WordAnchor({
    this.wrap = 'none',
    this.behindText = false,
    this.alignH,
    this.alignV,
    this.offsetX = 0,
    this.offsetY = 0,
    this.relativeH = 'column',
    this.relativeV = 'paragraph',
  });

  /// `square`, `tight`, `through`, `topAndBottom` or `none` (in front or behind).
  final String wrap;
  final bool behindText;

  /// `left`, `center`, `right`, `inside`, `outside`, or null when [offsetX] is used.
  final String? alignH;
  final String? alignV;
  final double offsetX;
  final double offsetY;
  final String relativeH;
  final String relativeV;
}

/// Shared look of pictures and shapes.
class WordDrawingStyle {
  const WordDrawingStyle({
    this.rotation = 0,
    this.flipH = false,
    this.flipV = false,
    this.outlineColor,
    this.outlineWidth = 0,
    this.outlineDash,
    this.shadow,
  });

  /// Degrees clockwise.
  final double rotation;
  final bool flipH;
  final bool flipV;
  final WordColor? outlineColor;
  final double outlineWidth;
  final String? outlineDash;
  final WordShadow? shadow;
}

class WordShadow {
  const WordShadow({required this.color, this.blur = 4, this.dx = 2, this.dy = 2});

  final WordColor color;
  final double blur;
  final double dx;
  final double dy;
}

/// A picture: PNG, JPEG, GIF or BMP bytes. SVG pictures carry their PNG copy.
class WordPicture extends WordInline {
  const WordPicture({
    required this.bytes,
    required this.width,
    required this.height,
    this.contentType,
    this.altText,
    this.title,
    this.anchor,
    this.look = const WordDrawingStyle(),
    this.crop = const WordInsets(),
    this.grayscale = false,
    this.opacity = 1,
    this.shape,
    this.hasSvg = false,
    this.svg,
  });

  final Uint8List bytes;

  /// Size on the page, in points.
  final double width;
  final double height;
  final String? contentType;
  final String? altText;
  final String? title;

  /// Null for a picture in line with text.
  final WordAnchor? anchor;
  final WordDrawingStyle look;

  /// Cropped away from each side, as a fraction of the picture (0 to 1).
  final WordInsets crop;
  final bool grayscale;
  final double opacity;

  /// Crop to shape: a preset name such as `ellipse` or `roundRect`.
  final String? shape;
  final bool hasSvg;

  /// The SVG version of the picture when the file has one ([bytes] is then
  /// its PNG fallback).
  final Uint8List? svg;
}

/// A shape, text box or WordArt.
class WordShape extends WordInline {
  const WordShape({
    required this.geometry,
    required this.width,
    required this.height,
    this.fill,
    this.gradient = const [],
    this.gradientAngle = 0,
    this.look = const WordDrawingStyle(),
    this.blocks = const [],
    this.anchor,
    this.verticalText,
    this.wordArt,
    this.insets = const WordInsets(left: 7.2, right: 7.2, top: 3.6, bottom: 3.6),
    this.textAnchor = 'top',
    this.name,
  });

  /// Preset geometry: `rect`, `roundRect`, `ellipse`, `triangle`, `diamond`,
  /// `rightArrow`, `star5`, `wedgeRectCallout`, `heart`, `hexagon`, `line`...
  final String geometry;
  final double width;
  final double height;
  final WordColor? fill;
  final List<WordColor> gradient;
  final double gradientAngle;
  final WordDrawingStyle look;

  /// Text inside the shape (text box).
  final List<WordBlock> blocks;
  final WordAnchor? anchor;

  /// `vert` or `vert270` for vertical text, else null.
  final String? verticalText;

  /// WordArt warp preset (`textArchUp`, `textWave1`...), else null.
  final String? wordArt;
  final WordInsets insets;

  /// Vertical text position in the shape: `top`, `ctr` or `b`.
  final String textAnchor;
  final String? name;

  @override
  void writePlainText(StringBuffer out) {
    for (final b in blocks) {
      b.writePlainText(out);
    }
  }
}

enum WordChartKind { column, bar, line, pie, doughnut, area, scatter, other }

class WordChartSeries {
  const WordChartSeries({required this.name, required this.values, this.color, this.pointColors = const []});

  final String name;
  final List<double> values;
  final WordColor? color;
  final List<WordColor?> pointColors;
}

/// A native Word chart, drawn from its data.
class WordChart extends WordInline {
  const WordChart({
    required this.kind,
    required this.width,
    required this.height,
    this.title,
    this.categories = const [],
    this.series = const [],
    this.stacked = false,
    this.anchor,
  });

  final WordChartKind kind;
  final double width;
  final double height;
  final String? title;
  final List<String> categories;
  final List<WordChartSeries> series;
  final bool stacked;
  final WordAnchor? anchor;
}

/// An equation, as a tree of math parts.
class WordEquation extends WordInline {
  const WordEquation(this.root, {this.display = false, this.style = const WordRunStyle()});

  final MathNode root;

  /// A display equation on its own line (centered), not inline with text.
  final bool display;
  final WordRunStyle style;

  @override
  void writePlainText(StringBuffer out) => out.write(root.linear);
}

enum WordNoteKind { footnote, endnote }

/// The number in the text that points to a footnote or endnote.
class WordNoteRef extends WordInline {
  const WordNoteRef({required this.kind, required this.id, required this.label, required this.style});

  final WordNoteKind kind;
  final String id;
  final String label;
  final WordRunStyle style;

  @override
  void writePlainText(StringBuffer out) => out.write(label);
}

/// Where a comment is attached.
class WordCommentMark extends WordInline {
  const WordCommentMark(this.id);

  final String id;
}

/// An object Word stores but this library does not draw (OLE object,
/// SmartArt without a picture, ink...). Shown as a labelled box.
class WordUnsupported extends WordInline {
  const WordUnsupported(this.label, {this.width = 72, this.height = 36});

  final String label;
  final double width;
  final double height;
}

class WordNote {
  const WordNote({required this.id, required this.kind, required this.label, required this.blocks});

  final String id;
  final WordNoteKind kind;
  final String label;
  final List<WordBlock> blocks;
}

class WordComment {
  const WordComment({
    required this.id,
    required this.blocks,
    this.author,
    this.initials,
    this.date,
    this.parentId,
    this.resolved = false,
  });

  final String id;
  final List<WordBlock> blocks;
  final String? author;
  final String? initials;
  final DateTime? date;

  /// The comment this one replies to.
  final String? parentId;
  final bool resolved;

  String get text {
    final out = StringBuffer();
    for (final b in blocks) {
      b.writePlainText(out);
    }
    return out.toString().trim();
  }
}

// ---------------------------------------------------------------- math

/// One part of an equation.
sealed class MathNode {
  const MathNode();

  /// The equation as one line of text, such as `(a+b)/2`.
  String get linear;
}

class MathText extends MathNode {
  const MathText(this.text, {this.plain = false, this.bold = false});

  final String text;

  /// Normal (upright) text instead of math italic.
  final bool plain;
  final bool bold;

  @override
  String get linear => text;
}

class MathRow extends MathNode {
  const MathRow(this.children);

  final List<MathNode> children;

  @override
  String get linear => children.map((c) => c.linear).join();
}

class MathFraction extends MathNode {
  const MathFraction(this.numerator, this.denominator, {this.bar = true, this.linearForm = false});

  final MathNode numerator;
  final MathNode denominator;
  final bool bar;
  final bool linearForm;

  @override
  String get linear => '(${numerator.linear})/(${denominator.linear})';
}

class MathRadical extends MathNode {
  const MathRadical(this.base, {this.degree});

  final MathNode base;
  final MathNode? degree;

  @override
  String get linear => degree == null ? '√(${base.linear})' : '∜(${degree!.linear}, ${base.linear})';
}

class MathScript extends MathNode {
  const MathScript(this.base, {this.sup, this.sub});

  final MathNode base;
  final MathNode? sup;
  final MathNode? sub;

  @override
  String get linear => '${base.linear}${sub == null ? '' : '_(${sub!.linear})'}${sup == null ? '' : '^(${sup!.linear})'}';
}

class MathNary extends MathNode {
  const MathNary(this.operator, this.base, {this.sub, this.sup, this.limitsUnderOver = false});

  final String operator;
  final MathNode base;
  final MathNode? sub;
  final MathNode? sup;
  final bool limitsUnderOver;

  @override
  String get linear =>
      '$operator${sub == null ? '' : '_(${sub!.linear})'}${sup == null ? '' : '^(${sup!.linear})'} ${base.linear}';
}

class MathDelimiter extends MathNode {
  const MathDelimiter(this.items, {this.begin = '(', this.end = ')', this.separator = '|'});

  final List<MathNode> items;
  final String begin;
  final String end;
  final String separator;

  @override
  String get linear => '$begin${items.map((i) => i.linear).join(separator)}$end';
}

class MathMatrix extends MathNode {
  const MathMatrix(this.rows);

  final List<List<MathNode>> rows;

  @override
  String get linear => '[${rows.map((r) => r.map((c) => c.linear).join(' ')).join('; ')}]';
}

class MathFunction extends MathNode {
  const MathFunction(this.name, this.argument);

  final MathNode name;
  final MathNode argument;

  @override
  String get linear => '${name.linear} ${argument.linear}';
}

/// lim under a base (`lim` with `n→∞` below), or a note over it.
class MathLimit extends MathNode {
  const MathLimit(this.base, this.limit, {this.upper = false});

  final MathNode base;
  final MathNode limit;
  final bool upper;

  @override
  String get linear => '${base.linear}${upper ? '^' : '_'}(${limit.linear})';
}

/// An accent or bar over (or bar under) the base.
class MathAccent extends MathNode {
  const MathAccent(this.base, this.mark, {this.below = false});

  final MathNode base;
  final String mark;
  final bool below;

  @override
  String get linear => '${base.linear}$mark';
}
