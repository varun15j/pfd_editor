import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../model.dart';
import 'theme.dart';
import 'xml_util.dart';

/// Character properties gathered from docDefaults, styles and direct
/// formatting. Later [apply] calls win.
class RunProps {
  RunProps();

  String? font;
  double? size;
  bool? bold, italic, strike, dstrike, smallCaps, caps, hidden, outline, shadow, emboss, imprint, rtl;
  WordUnderline? underline;
  int? underlineColor;
  WordVertAlign? vertAlign;
  int? color;
  bool colorAuto = false;
  int? highlight;
  int? shading;
  double? spacing, scale, position;
  WordBorder? border;
  // Word 2010 effects
  int? outlineColor;
  double? outlineWidth;
  int? shadowColor;
  double? shadowBlur, shadowDx, shadowDy;
  int? glowColor;
  double? glowRadius;
  bool? reflection;
  List<int>? gradient;
  int? fillColor;
  String? ligatures, numForm, numSpacing;

  RunProps copy() => RunProps()..merge(this);

  void merge(RunProps o) {
    font = o.font ?? font;
    size = o.size ?? size;
    bold = o.bold ?? bold;
    italic = o.italic ?? italic;
    strike = o.strike ?? strike;
    dstrike = o.dstrike ?? dstrike;
    smallCaps = o.smallCaps ?? smallCaps;
    caps = o.caps ?? caps;
    hidden = o.hidden ?? hidden;
    outline = o.outline ?? outline;
    shadow = o.shadow ?? shadow;
    emboss = o.emboss ?? emboss;
    imprint = o.imprint ?? imprint;
    rtl = o.rtl ?? rtl;
    underline = o.underline ?? underline;
    underlineColor = o.underlineColor ?? underlineColor;
    vertAlign = o.vertAlign ?? vertAlign;
    if (o.color != null || o.colorAuto) {
      color = o.color;
      colorAuto = o.colorAuto;
    }
    highlight = o.highlight ?? highlight;
    shading = o.shading ?? shading;
    spacing = o.spacing ?? spacing;
    scale = o.scale ?? scale;
    position = o.position ?? position;
    border = o.border ?? border;
    outlineColor = o.outlineColor ?? outlineColor;
    outlineWidth = o.outlineWidth ?? outlineWidth;
    shadowColor = o.shadowColor ?? shadowColor;
    shadowBlur = o.shadowBlur ?? shadowBlur;
    shadowDx = o.shadowDx ?? shadowDx;
    shadowDy = o.shadowDy ?? shadowDy;
    glowColor = o.glowColor ?? glowColor;
    glowRadius = o.glowRadius ?? glowRadius;
    reflection = o.reflection ?? reflection;
    gradient = o.gradient ?? gradient;
    fillColor = o.fillColor ?? fillColor;
    ligatures = o.ligatures ?? ligatures;
    numForm = o.numForm ?? numForm;
    numSpacing = o.numSpacing ?? numSpacing;
  }

  void apply(XmlElement? rPr, WordTheme theme) {
    if (rPr == null) return;
    for (final e in rPr.childElements) {
      final ns = nsOf(e);
      if (ns == 'w14') {
        _applyEffect(e, theme);
        continue;
      }
      if (ns != 'w') continue;
      switch (e.name.local) {
        case 'rFonts':
          final f = e.attr('ascii') ?? e.attr('hAnsi');
          final t = e.attr('asciiTheme') ?? e.attr('hAnsiTheme');
          if (f != null) {
            font = f;
          } else if (t != null) {
            font = theme.themeFont(t);
          } else if (e.attr('eastAsia') != null && font == null) {
            font = e.attr('eastAsia');
          }
        case 'sz':
          final v = halfPoints(e.attr('val'));
          if (v != null) size = v;
        case 'b':
          bold = onOff(e);
        case 'i':
          italic = onOff(e);
        case 'strike':
          strike = onOff(e);
        case 'dstrike':
          dstrike = onOff(e);
        case 'smallCaps':
          smallCaps = onOff(e);
        case 'caps':
          caps = onOff(e);
        case 'vanish':
          hidden = onOff(e);
        case 'outline':
          outline = onOff(e);
        case 'shadow':
          shadow = onOff(e);
        case 'emboss':
          emboss = onOff(e);
        case 'imprint':
          imprint = onOff(e);
        case 'rtl':
          rtl = onOff(e);
        case 'u':
          underline = _underline(e.attr('val'));
          underlineColor = hexColor(e.attr('color')) ?? theme.color(e.attr('themeColor'));
        case 'vertAlign':
          vertAlign = switch (e.attr('val')) {
            'superscript' => WordVertAlign.superscript,
            'subscript' => WordVertAlign.subscript,
            _ => WordVertAlign.baseline,
          };
        case 'color':
          final c = colorOf(e, theme);
          if (c == null && e.attr('val') == 'auto') {
            color = null;
            colorAuto = true;
          } else if (c != null) {
            color = c;
            colorAuto = false;
          }
        case 'highlight':
          highlight = highlightColors[e.attr('val')];
        case 'shd':
          shading = shadingOf(e, theme);
        case 'spacing':
          spacing = twips(e.attr('val'));
        case 'w':
          final v = double.tryParse((e.attr('val') ?? '').replaceAll('%', ''));
          if (v != null) scale = v / 100;
        case 'position':
          final v = halfPoints(e.attr('val'));
          if (v != null) position = v;
        case 'bdr':
          border = borderOf(e, theme);
      }
    }
  }

  void _applyEffect(XmlElement e, WordTheme theme) {
    switch (e.name.local) {
      case 'textOutline':
        final fill = e.el('w14', 'solidFill');
        outlineColor = fill == null ? null : theme.drawingColor(fill);
        outlineWidth = emu(e.attr('w'));
        if (outlineColor != null && outlineWidth == 0) outlineWidth = 0.75;
      case 'shadow':
        shadowColor = theme.drawingColor(e) ?? 0x80000000;
        shadowBlur = emu(e.attr('blurRad'));
        final dist = emu(e.attr('dist'));
        final dir = (double.tryParse(e.attr('dir') ?? '') ?? 2700000) / 60000;
        shadowDx = dist * _cosDeg(dir);
        shadowDy = dist * _sinDeg(dir);
      case 'glow':
        glowColor = theme.drawingColor(e) ?? 0x80FFC000;
        glowRadius = emu(e.attr('rad'));
      case 'reflection':
        reflection = true;
      case 'textFill':
        final grad = e.el('w14', 'gradFill');
        if (grad != null) {
          final stops = grad.el('w14', 'gsLst')?.els('w14', 'gs') ?? const <XmlElement>[];
          gradient = [for (final s in stops) theme.drawingColor(s) ?? 0xFF000000];
        }
        final solid = e.el('w14', 'solidFill');
        if (solid != null) fillColor = theme.drawingColor(solid);
      case 'ligatures':
        ligatures = e.attr('val');
      case 'numForm':
        numForm = e.attr('val');
      case 'numSpacing':
        numSpacing = e.attr('val');
    }
  }

  WordRunStyle toStyle() {
    final hasEffects =
        outlineColor != null ||
        shadowColor != null ||
        glowColor != null ||
        (reflection ?? false) ||
        (gradient?.isNotEmpty ?? false) ||
        fillColor != null ||
        ligatures != null ||
        numForm != null ||
        numSpacing != null;
    return WordRunStyle(
      font: font,
      size: size ?? 10,
      bold: bold ?? false,
      italic: italic ?? false,
      underline: underline ?? WordUnderline.none,
      underlineColor: underlineColor,
      strike: strike ?? false,
      doubleStrike: dstrike ?? false,
      vertAlign: vertAlign ?? WordVertAlign.baseline,
      smallCaps: smallCaps ?? false,
      allCaps: caps ?? false,
      color: color,
      highlight: highlight,
      shading: shading,
      hidden: hidden ?? false,
      letterSpacing: spacing ?? 0,
      scale: scale ?? 1,
      position: position ?? 0,
      outline: outline ?? false,
      shadow: shadow ?? false,
      emboss: emboss ?? false,
      imprint: imprint ?? false,
      border: border,
      rtl: rtl ?? false,
      effects: hasEffects
          ? WordTextEffects(
              outlineColor: outlineColor,
              outlineWidth: outlineWidth ?? 0,
              shadowColor: shadowColor,
              shadowBlur: shadowBlur ?? 0,
              shadowDx: shadowDx ?? 0,
              shadowDy: shadowDy ?? 0,
              glowColor: glowColor,
              glowRadius: glowRadius ?? 0,
              reflection: reflection ?? false,
              gradient: gradient ?? const [],
              fillColor: fillColor,
              ligatures: ligatures,
              numberForm: numForm,
              numberSpacing: numSpacing,
            )
          : null,
    );
  }

  static WordUnderline _underline(String? v) => switch (v) {
    null || 'single' => WordUnderline.single,
    'none' => WordUnderline.none,
    'double' => WordUnderline.double,
    'thick' => WordUnderline.thick,
    'words' => WordUnderline.words,
    'dotted' || 'dottedHeavy' => WordUnderline.dotted,
    'dash' || 'dashedHeavy' || 'dashLong' || 'dashLongHeavy' || 'dotDash' || 'dotDotDash' || 'dashDotHeavy' || 'dashDotDotHeavy' =>
      WordUnderline.dashed,
    'wave' || 'wavyHeavy' || 'wavyDouble' => WordUnderline.wave,
    _ => WordUnderline.single,
  };
}

double _cosDeg(double d) => math.cos(d * math.pi / 180);
double _sinDeg(double d) => math.sin(d * math.pi / 180);

/// `w:color`: the RGB value, or the theme colour with its tint or shade.
/// A colour from `w:color` (in `w:val`) or from a border (in `w:color`).
int? colorOf(XmlElement e, WordTheme theme, {String attr = 'val'}) {
  final rgb = hexColor(e.attr(attr));
  if (rgb != null) return rgb;
  final themed = theme.color(e.attr('themeColor'));
  if (themed == null) return null;
  final tint = int.tryParse(e.attr('themeTint') ?? '', radix: 16);
  final shade = int.tryParse(e.attr('themeShade') ?? '', radix: 16);
  if (tint == null && shade == null) return themed;
  return adjustLuminance(themed, tint: tint == null ? null : tint / 255, shade: shade == null ? null : shade / 255);
}

/// `w:shd` to one colour: patterns are mixed into an even tone.
int? shadingOf(XmlElement e, WordTheme theme) {
  final val = e.attr('val') ?? 'clear';
  final fill = hexColor(e.attr('fill')) ?? theme.color(e.attr('themeFill'));
  final color = hexColor(e.attr('color')) ?? theme.color(e.attr('themeColor')) ?? 0xFF000000;
  if (val == 'nil') return null;
  if (val == 'clear') return fill;
  if (val == 'solid') return color;
  final pct = RegExp(r'^pct(\d+)$').firstMatch(val);
  final amount = pct != null
      ? int.parse(pct.group(1)!) / 100
      : val.contains('Stripe') || val.contains('Cross')
      ? (val.startsWith('thin') ? 0.25 : 0.5)
      : 0.5;
  return blend(fill ?? 0xFFFFFFFF, color, amount);
}

WordBorder? borderOf(XmlElement? e, WordTheme theme) {
  if (e == null) return null;
  final style = e.attr('val') ?? 'single';
  final sz = double.tryParse(e.attr('sz') ?? '') ?? 4;
  return WordBorder(
    style: style,
    width: sz / 8,
    color: colorOf(e, theme, attr: 'color') ?? 0xFF000000,
    space: double.tryParse(e.attr('space') ?? '') ?? 0,
  );
}

WordBorders? bordersOf(XmlElement? e, WordTheme theme) {
  if (e == null) return null;
  WordBorder? side(String a, [String? b]) => borderOf(e.w(a) ?? (b == null ? null : e.w(b)), theme);
  return WordBorders(
    top: side('top'),
    left: side('left', 'start'),
    bottom: side('bottom'),
    right: side('right', 'end'),
    insideH: side('insideH'),
    insideV: side('insideV'),
    between: side('between'),
    diagonalDown: side('tl2br'),
    diagonalUp: side('tr2bl'),
  );
}

/// Paragraph properties gathered from docDefaults, styles, numbering and
/// direct formatting.
class ParaProps {
  ParaProps();

  WordAlign? align;
  double? left, right, firstLine, before, after;
  double? lineMultiple, lineExact, lineAtLeast;
  bool lineSet = false;
  WordBorders? borders;
  int? shading;
  bool shadingSet = false;
  Map<double, WordTabStop> tabs = {};
  Set<double> clearedTabs = {};
  bool? rtl, keepNext, keepLines, pageBreakBefore, widowControl, contextualSpacing;
  int? outlineLevel;
  String? numId;
  int? ilvl;
  String? styleId;

  ParaProps copy() => ParaProps()..merge(this);

  void merge(ParaProps o) {
    align = o.align ?? align;
    left = o.left ?? left;
    right = o.right ?? right;
    firstLine = o.firstLine ?? firstLine;
    before = o.before ?? before;
    after = o.after ?? after;
    if (o.lineSet) {
      lineMultiple = o.lineMultiple;
      lineExact = o.lineExact;
      lineAtLeast = o.lineAtLeast;
      lineSet = true;
    }
    borders = borders == null ? o.borders : borders!.merge(o.borders);
    if (o.shadingSet) {
      shading = o.shading;
      shadingSet = true;
    }
    for (final c in o.clearedTabs) {
      tabs.remove(c);
    }
    tabs.addAll(o.tabs);
    rtl = o.rtl ?? rtl;
    keepNext = o.keepNext ?? keepNext;
    keepLines = o.keepLines ?? keepLines;
    pageBreakBefore = o.pageBreakBefore ?? pageBreakBefore;
    widowControl = o.widowControl ?? widowControl;
    contextualSpacing = o.contextualSpacing ?? contextualSpacing;
    outlineLevel = o.outlineLevel ?? outlineLevel;
    numId = o.numId ?? numId;
    ilvl = o.ilvl ?? ilvl;
  }

  void apply(XmlElement? pPr, WordTheme theme) {
    if (pPr == null) return;
    for (final e in pPr.childElements) {
      if (nsOf(e) != 'w') continue;
      switch (e.name.local) {
        case 'pStyle':
          styleId = e.attr('val');
        case 'jc':
          align = switch (e.attr('val')) {
            'center' => WordAlign.center,
            'right' || 'end' => WordAlign.right,
            'both' || 'distribute' || 'mediumKashida' || 'highKashida' || 'lowKashida' || 'thaiDistribute' =>
              WordAlign.justify,
            _ => WordAlign.left,
          };
        case 'ind':
          left = twips(e.attr('left') ?? e.attr('start')) ?? left;
          right = twips(e.attr('right') ?? e.attr('end')) ?? right;
          final hanging = twips(e.attr('hanging'));
          final first = twips(e.attr('firstLine'));
          if (hanging != null) {
            firstLine = -hanging;
          } else if (first != null) {
            firstLine = first;
          }
        case 'spacing':
          before = isTrue(e.attr('beforeAutospacing')) ? 14 : twips(e.attr('before')) ?? before;
          after = isTrue(e.attr('afterAutospacing')) ? 14 : twips(e.attr('after')) ?? after;
          final line = parseNum(e.attr('line'));
          if (line != null) {
            lineSet = true;
            lineMultiple = lineExact = lineAtLeast = null;
            switch (e.attr('lineRule')) {
              case 'exact':
                lineExact = line / 20;
              case 'atLeast':
                lineAtLeast = line / 20;
              default:
                lineMultiple = line / 240;
            }
          }
        case 'pBdr':
          final b = bordersOf(e, theme);
          borders = borders == null ? b : borders!.merge(b);
        case 'shd':
          shading = shadingOf(e, theme);
          shadingSet = true;
        case 'tabs':
          for (final t in e.els('w', 'tab')) {
            final pos = twips(t.attr('pos'));
            if (pos == null) continue;
            final val = t.attr('val') ?? 'left';
            if (val == 'clear') {
              tabs.remove(pos);
              clearedTabs.add(pos);
              continue;
            }
            tabs[pos] = WordTabStop(
              position: pos,
              align: switch (val) {
                'center' => WordTabAlign.center,
                'right' || 'end' => WordTabAlign.right,
                'decimal' => WordTabAlign.decimal,
                'bar' => WordTabAlign.bar,
                _ => WordTabAlign.left,
              },
              leader: t.attr('leader') ?? 'none',
            );
          }
        case 'bidi':
          rtl = onOff(e);
        case 'keepNext':
          keepNext = onOff(e);
        case 'keepLines':
          keepLines = onOff(e);
        case 'pageBreakBefore':
          pageBreakBefore = onOff(e);
        case 'widowControl':
          widowControl = onOff(e);
        case 'contextualSpacing':
          contextualSpacing = onOff(e);
        case 'outlineLvl':
          final v = int.tryParse(e.attr('val') ?? '');
          if (v != null && v < 9) outlineLevel = v;
        case 'numPr':
          numId = e.wVal('numId') ?? numId;
          ilvl = int.tryParse(e.wVal('ilvl') ?? '') ?? ilvl;
      }
    }
  }

  WordParagraphStyle toStyle() => WordParagraphStyle(
    align: rtl == true && (align == null || align == WordAlign.left) ? WordAlign.right : align ?? WordAlign.left,
    indentLeft: left ?? 0,
    indentRight: right ?? 0,
    firstLine: firstLine ?? 0,
    spaceBefore: before ?? 0,
    spaceAfter: after ?? 0,
    lineMultiple: lineMultiple,
    lineExact: lineExact,
    lineAtLeast: lineAtLeast,
    borders: borders == null || borders!.isEmpty ? null : borders,
    shading: shading,
    tabs: (tabs.values.toList()..sort((a, b) => a.position.compareTo(b.position))),
    rtl: rtl ?? false,
    keepNext: keepNext ?? false,
    keepLines: keepLines ?? false,
    pageBreakBefore: pageBreakBefore ?? false,
    widowControl: widowControl ?? true,
    contextualSpacing: contextualSpacing ?? false,
    outlineLevel: outlineLevel,
  );
}

/// One `w:style` from styles.xml.
class StyleDef {
  StyleDef({required this.id, required this.type, this.name, this.basedOn, this.pPr, this.rPr, this.tblPr, this.tcPr, this.conditional = const {}, this.isDefault = false});

  final String id;
  final String type;
  final String? name;
  final String? basedOn;
  final XmlElement? pPr;
  final XmlElement? rPr;
  final XmlElement? tblPr;
  final XmlElement? tcPr;

  /// Table style parts: `firstRow`, `lastRow`, `band1Horz`... to their
  /// `w:tblStylePr` element.
  final Map<String, XmlElement> conditional;
  final bool isDefault;
}

/// styles.xml: docDefaults and all styles, with basedOn chains resolved on
/// demand.
class StyleSheet {
  StyleSheet(this.theme, XmlDocument? xml) {
    if (xml == null) {
      defaultRun.size = 11;
      defaultRun.font = theme.minorFont;
      return;
    }
    final root = xml.rootElement;
    final defaults = root.w('docDefaults');
    defaultRun.font = theme.minorFont;
    defaultRun.apply(defaults?.w('rPrDefault')?.w('rPr'), theme);
    defaultPara.apply(defaults?.w('pPrDefault')?.w('pPr'), theme);
    for (final s in root.els('w', 'style')) {
      final id = s.attr('styleId');
      if (id == null) continue;
      final def = StyleDef(
        id: id,
        type: s.attr('type') ?? 'paragraph',
        name: s.wVal('name'),
        basedOn: s.wVal('basedOn'),
        pPr: s.w('pPr'),
        rPr: s.w('rPr'),
        tblPr: s.w('tblPr'),
        tcPr: s.w('tcPr'),
        conditional: {
          for (final c in s.els('w', 'tblStylePr'))
            if (c.attr('type') != null) c.attr('type')!: c,
        },
        isDefault: isTrue(s.attr('default')),
      );
      styles[id] = def;
      if (def.isDefault) defaults_[def.type] = id;
    }
  }

  final WordTheme theme;
  final RunProps defaultRun = RunProps();
  final ParaProps defaultPara = ParaProps();
  final Map<String, StyleDef> styles = {};
  // ignore: non_constant_identifier_names
  final Map<String, String> defaults_ = {};

  String? get defaultParagraphStyle => defaults_['paragraph'];
  String? get defaultTableStyle => defaults_['table'];

  final _runCache = <String, RunProps>{};
  final _paraCache = <String, ParaProps>{};

  /// The style and its basedOn ancestors, root first.
  List<StyleDef> chain(String? id) {
    final out = <StyleDef>[];
    final seen = <String>{};
    var cur = id;
    while (cur != null && seen.add(cur)) {
      final s = styles[cur];
      if (s == null) break;
      out.insert(0, s);
      cur = s.basedOn;
    }
    return out;
  }

  /// Run properties a style gives (paragraph or character style), without docDefaults.
  RunProps styleRun(String? id) {
    if (id == null) return RunProps();
    return _runCache.putIfAbsent(id, () {
      final p = RunProps();
      for (final s in chain(id)) {
        p.apply(s.rPr, theme);
      }
      return p;
    });
  }

  ParaProps stylePara(String? id) {
    if (id == null) return ParaProps();
    return _paraCache.putIfAbsent(id, () {
      final p = ParaProps();
      for (final s in chain(id)) {
        p.apply(s.pPr, theme);
      }
      p.styleId = id;
      return p;
    });
  }

  String? nameOf(String? id) => id == null ? null : styles[id]?.name;
}
