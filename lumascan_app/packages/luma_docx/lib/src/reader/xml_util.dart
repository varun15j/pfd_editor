import 'dart:math' as math;

import 'package:xml/xml.dart';

/// Namespace URIs, by the prefix Word usually gives them. Strict Open XML
/// uses other URIs for the same parts, so both are listed.
const _namespaces = <String, List<String>>{
  'w': [
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
    'http://purl.oclc.org/ooxml/wordprocessingml/main',
  ],
  'a': ['http://schemas.openxmlformats.org/drawingml/2006/main', 'http://purl.oclc.org/ooxml/drawingml/main'],
  'wp': [
    'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
    'http://purl.oclc.org/ooxml/drawingml/wordprocessingDrawing',
  ],
  'pic': ['http://schemas.openxmlformats.org/drawingml/2006/picture', 'http://purl.oclc.org/ooxml/drawingml/picture'],
  'c': ['http://schemas.openxmlformats.org/drawingml/2006/chart', 'http://purl.oclc.org/ooxml/drawingml/chart'],
  'm': ['http://schemas.openxmlformats.org/officeDocument/2006/math', 'http://purl.oclc.org/ooxml/officeDocument/math'],
  'wps': ['http://schemas.microsoft.com/office/word/2010/wordprocessingShape'],
  'wpg': ['http://schemas.microsoft.com/office/word/2010/wordprocessingGroup'],
  'w14': ['http://schemas.microsoft.com/office/word/2010/wordml'],
  'w15': ['http://schemas.microsoft.com/office/word/2012/wordml'],
  'mc': ['http://schemas.openxmlformats.org/markup-compatibility/2006'],
  'v': ['urn:schemas-microsoft-com:vml'],
};

final _prefixByUri = {
  for (final entry in _namespaces.entries)
    for (final uri in entry.value) uri: entry.key,
};

/// The usual prefix of [e]'s namespace (`w`, `a`, `wp`...), or '' when unknown.
String nsOf(XmlElement e) => _prefixByUri[e.name.namespaceUri] ?? '';

bool isEl(XmlElement e, String ns, String local) => e.name.local == local && nsOf(e) == ns;

extension WordXml on XmlElement {
  /// First child element with this namespace prefix and local name.
  XmlElement? el(String ns, String local) {
    for (final c in childElements) {
      if (c.name.local == local && nsOf(c) == ns) return c;
    }
    return null;
  }

  Iterable<XmlElement> els(String ns, String local) =>
      childElements.where((c) => c.name.local == local && nsOf(c) == ns);

  /// Child element `w:<local>`.
  XmlElement? w(String local) => el('w', local);

  /// An attribute by local name, whatever its prefix (`w:val`, `val`...).
  String? attr(String local) {
    for (final a in attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }

  /// The `w:val` of child `w:<local>`.
  String? wVal(String local) => w(local)?.attr('val');

  /// First descendant with this namespace prefix and local name.
  XmlElement? find(String ns, String local) {
    for (final d in descendantElements) {
      if (d.name.local == local && nsOf(d) == ns) return d;
    }
    return null;
  }
}

/// A Word on/off property: `<w:b/>`, `<w:b w:val="true"/>`, `<w:b w:val="0"/>`.
/// Null when the element is missing.
bool? onOff(XmlElement? e) {
  if (e == null) return null;
  final v = e.attr('val');
  return v == null || !(v == '0' || v == 'false' || v == 'off' || v == 'none');
}

double? parseNum(String? s) {
  if (s == null) return null;
  final v = double.tryParse(s);
  if (v != null) return v;
  // Some producers write units, e.g. "12pt" or "0.5in".
  final m = RegExp(r'^(-?[0-9.]+)(pt|in|cm|mm|pc|pi)$').firstMatch(s.trim());
  if (m == null) return null;
  final n = double.parse(m.group(1)!);
  switch (m.group(2)) {
    case 'pt':
      return n * 20;
    case 'in':
      return n * 1440;
    case 'cm':
      return n * 1440 / 2.54;
    case 'mm':
      return n * 144 / 2.54;
    default:
      return n * 240;
  }
}

/// Half-points (font sizes, raised position) to points; also accepts
/// universal measures such as `3pt`.
double? halfPoints(String? s) {
  if (s == null) return null;
  final v = double.tryParse(s);
  if (v != null) return v / 2;
  final t = parseNum(s);
  return t == null ? null : t / 20;
}

/// Twentieths of a point to points.
double? twips(String? s) {
  final v = parseNum(s);
  return v == null ? null : v / 20;
}

/// English Metric Units to points.
double emu(String? s) => (double.tryParse(s ?? '') ?? 0) / 12700;

DateTime? parseDate(String? s) => s == null ? null : DateTime.tryParse(s);

/// `RRGGBB` to an opaque ARGB int; null for `auto` or junk.
int? hexColor(String? s) {
  if (s == null || s == 'auto' || s.length < 6) return null;
  final v = int.tryParse(s.substring(0, 6), radix: 16);
  return v == null ? null : 0xFF000000 | v;
}

// ---------------------------------------------------------------- colours

/// Lightens toward white (tint) or darkens toward black (shade), the way
/// Word applies themeTint and themeShade: in HSL luminance.
int adjustLuminance(int argb, {double? lumMod, double? lumOff, double? tint, double? shade}) {
  final a = (argb >> 24) & 0xFF;
  var (h, s, l) = _toHsl(argb);
  if (lumMod != null) l *= lumMod;
  if (lumOff != null) l += lumOff;
  if (tint != null) l = l * tint + (1 - tint);
  if (shade != null) l *= shade;
  l = l.clamp(0.0, 1.0);
  return (a << 24) | (_fromHsl(h, s, l) & 0xFFFFFF);
}

(double, double, double) _toHsl(int argb) {
  final r = ((argb >> 16) & 0xFF) / 255, g = ((argb >> 8) & 0xFF) / 255, b = (argb & 0xFF) / 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final l = (mx + mn) / 2;
  if (mx == mn) return (0, 0, l);
  final d = mx - mn;
  final s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
  double h;
  if (mx == r) {
    h = (g - b) / d + (g < b ? 6 : 0);
  } else if (mx == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  return (h / 6, s, l);
}

int _fromHsl(double h, double s, double l) {
  double hue(double p, double q, double t) {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  }

  double r, g, b;
  if (s == 0) {
    r = g = b = l;
  } else {
    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    r = hue(p, q, h + 1 / 3);
    g = hue(p, q, h);
    b = hue(p, q, h - 1 / 3);
  }
  int c(double v) => (v * 255).round().clamp(0, 255);
  return 0xFF000000 | (c(r) << 16) | (c(g) << 8) | c(b);
}

/// Mixes [fg] over [bg]; [amount] 0 gives bg, 1 gives fg.
int blend(int bg, int fg, double amount) {
  int ch(int shift) {
    final a = (bg >> shift) & 0xFF, b = (fg >> shift) & 0xFF;
    return (a + (b - a) * amount).round().clamp(0, 255);
  }

  return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

int withAlpha(int argb, double alpha) => ((alpha.clamp(0, 1) * 255).round() << 24) | (argb & 0xFFFFFF);

const highlightColors = <String, int>{
  'yellow': 0xFFFFFF00,
  'green': 0xFF00FF00,
  'cyan': 0xFF00FFFF,
  'magenta': 0xFFFF00FF,
  'blue': 0xFF0000FF,
  'red': 0xFFFF0000,
  'darkBlue': 0xFF000080,
  'darkCyan': 0xFF008080,
  'darkGreen': 0xFF008000,
  'darkMagenta': 0xFF800080,
  'darkRed': 0xFF800000,
  'darkYellow': 0xFF808000,
  'darkGray': 0xFF808080,
  'lightGray': 0xFFC0C0C0,
  'black': 0xFF000000,
  'white': 0xFFFFFFFF,
};

/// An XML boolean attribute: `1`, `true` or `on`.
bool isTrue(String? v) => v == '1' || v == 'true' || v == 'on';
