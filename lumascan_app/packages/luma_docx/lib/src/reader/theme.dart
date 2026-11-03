import 'package:xml/xml.dart';

import 'xml_util.dart';

/// Theme colours and fonts (Design > Themes), from `word/theme/theme1.xml`.
class WordTheme {
  WordTheme({Map<String, int>? colors, this.majorFont = 'Calibri Light', this.minorFont = 'Calibri'})
    : colors = colors ?? Map.of(_officeColors);

  final Map<String, int> colors;
  final String majorFont;
  final String minorFont;

  static const _officeColors = {
    'dk1': 0xFF000000,
    'lt1': 0xFFFFFFFF,
    'dk2': 0xFF44546A,
    'lt2': 0xFFE7E6E6,
    'accent1': 0xFF4472C4,
    'accent2': 0xFFED7D31,
    'accent3': 0xFFA5A5A5,
    'accent4': 0xFFFFC000,
    'accent5': 0xFF5B9BD5,
    'accent6': 0xFF70AD47,
    'hlink': 0xFF0563C1,
    'folHlink': 0xFF954F72,
  };

  static WordTheme parse(XmlDocument? xml) {
    final theme = WordTheme();
    if (xml == null) return theme;
    final scheme = xml.rootElement.find('a', 'clrScheme');
    if (scheme != null) {
      for (final c in scheme.childElements) {
        final value = c.childElements.firstOrNull;
        if (value == null) continue;
        final rgb = value.name.local == 'sysClr' ? hexColor(value.attr('lastClr')) : hexColor(value.attr('val'));
        if (rgb != null) theme.colors[c.name.local] = rgb;
      }
    }
    String? font(String which) => xml.rootElement.find('a', which)?.el('a', 'latin')?.attr('typeface');
    return WordTheme(
      colors: theme.colors,
      majorFont: font('majorFont') ?? theme.majorFont,
      minorFont: font('minorFont') ?? theme.minorFont,
    );
  }

  /// A Word theme colour name (`accent1`, `text1`, `background2`...) to RGB.
  int? color(String? name) {
    if (name == null) return null;
    const alias = {
      'text1': 'dk1',
      'dark1': 'dk1',
      'tx1': 'dk1',
      'background1': 'lt1',
      'light1': 'lt1',
      'bg1': 'lt1',
      'text2': 'dk2',
      'dark2': 'dk2',
      'tx2': 'dk2',
      'background2': 'lt2',
      'light2': 'lt2',
      'bg2': 'lt2',
      'hyperlink': 'hlink',
      'followedHyperlink': 'folHlink',
    };
    return colors[alias[name] ?? name];
  }

  /// `w:asciiTheme` value (`majorHAnsi`, `minorBidi`...) to a font name.
  String themeFont(String name) => name.startsWith('major') ? majorFont : minorFont;

  /// A DrawingML colour element's parent (`a:solidFill`, `a:gs`, ...) to ARGB.
  int? drawingColor(XmlElement? parent) {
    if (parent == null) return null;
    for (final c in parent.childElements) {
      int? base;
      switch (c.name.local) {
        case 'srgbClr':
          base = hexColor(c.attr('val'));
        case 'schemeClr':
          base = color(c.attr('val'));
        case 'sysClr':
          base = hexColor(c.attr('lastClr'));
        case 'prstClr':
          base = _presetColors[c.attr('val')];
        default:
          continue;
      }
      if (base == null) return null;
      double? pct(String local) {
        final v = c.el('a', local)?.attr('val') ?? c.el('w14', local)?.attr('val');
        return v == null ? null : (double.tryParse(v) ?? 100000) / 100000;
      }

      var out = base;
      final lumMod = pct('lumMod'), lumOff = pct('lumOff'), tint = pct('tint'), shade = pct('shade');
      if (lumMod != null || lumOff != null || tint != null || shade != null) {
        out = adjustLuminance(out, lumMod: lumMod, lumOff: lumOff, tint: tint, shade: shade);
      }
      final alpha = pct('alpha');
      if (alpha != null) out = withAlpha(out, alpha);
      return out;
    }
    return null;
  }

  static const _presetColors = {
    'black': 0xFF000000,
    'white': 0xFFFFFFFF,
    'red': 0xFFFF0000,
    'green': 0xFF008000,
    'blue': 0xFF0000FF,
    'yellow': 0xFFFFFF00,
    'gray': 0xFF808080,
    'orange': 0xFFFFA500,
  };
}
