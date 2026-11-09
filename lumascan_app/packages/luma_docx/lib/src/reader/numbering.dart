import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../model.dart';
import 'symbols.dart';
import 'xml_util.dart';

class NumLevel {
  NumLevel({
    required this.start,
    required this.format,
    required this.text,
    this.pPr,
    this.rPr,
    this.suffix = 'tab',
    this.align = WordAlign.left,
    this.pictureBulletId,
    this.restartAfter,
    this.legal = false,
  });

  final int start;
  final String format;
  final String text;
  final XmlElement? pPr;
  final XmlElement? rPr;
  final String suffix;
  final WordAlign align;
  final String? pictureBulletId;

  /// The level after which this one restarts (`w:lvlRestart`); null for
  /// the next higher level.
  final int? restartAfter;

  /// Legal numbering: every level shown as a decimal.
  final bool legal;
}

class _Num {
  _Num(this.abstractId, this.overrides, this.startOverrides);

  final String abstractId;
  final Map<int, NumLevel> overrides;
  final Map<int, int> startOverrides;
}

/// numbering.xml: list definitions and the running counters while the
/// document is read in order.
class Numbering {
  Numbering(XmlDocument? xml, {Uint8List? Function(String relId)? picture}) {
    if (xml == null) return;
    final root = xml.rootElement;
    for (final pb in root.els('w', 'numPicBullet')) {
      final id = pb.attr('numPicBulletId');
      final blip = pb.find('v', 'imagedata') ?? pb.find('a', 'blip');
      final rel = blip?.attr('id') ?? blip?.attr('embed');
      if (id != null && rel != null && picture != null) {
        final bytes = picture(rel);
        if (bytes != null) _pictureBullets[id] = bytes;
      }
    }
    for (final a in root.els('w', 'abstractNum')) {
      final id = a.attr('abstractNumId');
      if (id == null) continue;
      _abstract[id] = {for (final l in a.els('w', 'lvl')) int.tryParse(l.attr('ilvl') ?? '') ?? 0: _level(l)};
      final link = a.wVal('numStyleLink') ?? a.wVal('styleLink');
      if (link != null) _styleLinks[id] = link;
    }
    for (final n in root.els('w', 'num')) {
      final id = n.attr('numId');
      final abs = n.wVal('abstractNumId');
      if (id == null || abs == null) continue;
      final overrides = <int, NumLevel>{};
      final starts = <int, int>{};
      for (final o in n.els('w', 'lvlOverride')) {
        final lvl = int.tryParse(o.attr('ilvl') ?? '') ?? 0;
        final start = int.tryParse(o.wVal('startOverride') ?? '');
        if (start != null) starts[lvl] = start;
        final l = o.w('lvl');
        if (l != null) overrides[lvl] = _level(l);
      }
      _nums[id] = _Num(abs, overrides, starts);
    }
  }

  final _abstract = <String, Map<int, NumLevel>>{};
  final _styleLinks = <String, String>{};
  final _nums = <String, _Num>{};
  final _pictureBullets = <String, Uint8List>{};

  /// Counter per list: numId when it restarts numbering, else its abstract list.
  final _counters = <String, List<int?>>{};
  final _startedNums = <String>{};

  static NumLevel _level(XmlElement l) => NumLevel(
    start: int.tryParse(l.wVal('start') ?? '') ?? 1,
    format: l.wVal('numFmt') ?? 'decimal',
    text: l.wVal('lvlText') ?? '',
    pPr: l.w('pPr'),
    rPr: l.w('rPr'),
    suffix: l.wVal('suff') ?? 'tab',
    align: switch (l.wVal('lvlJc')) {
      'center' => WordAlign.center,
      'right' || 'end' => WordAlign.right,
      _ => WordAlign.left,
    },
    pictureBulletId: l.wVal('lvlPicBulletId'),
    restartAfter: int.tryParse(l.wVal('lvlRestart') ?? ''),
    legal: onOff(l.w('isLgl')) ?? false,
  );

  NumLevel? level(String numId, int ilvl) {
    final n = _nums[numId];
    if (n == null) return null;
    return n.overrides[ilvl] ?? _abstract[n.abstractId]?[ilvl];
  }

  /// The label for the next paragraph in list [numId] at level [ilvl],
  /// moving the counters on. Null when the list does not exist.
  ({NumLevel level, String text, Uint8List? picture})? next(String numId, int ilvl) {
    final n = _nums[numId];
    if (n == null || numId == '0') return null;
    final lvl = level(numId, ilvl);
    if (lvl == null) return null;
    final key = n.startOverrides.isNotEmpty || n.overrides.isNotEmpty ? 'num:$numId' : 'abs:${n.abstractId}';
    final counters = _counters.putIfAbsent(key, () => List<int?>.filled(9, null));
    if (_startedNums.add(numId)) {
      for (final e in n.startOverrides.entries) {
        if (e.key < 9) counters[e.key] = null;
      }
    }
    int startOf(int l) => n.startOverrides[l] ?? level(numId, l)?.start ?? 1;
    counters[ilvl] = counters[ilvl] == null ? startOf(ilvl) : counters[ilvl]! + 1;
    for (var l = ilvl + 1; l < 9; l++) {
      final restart = level(numId, l)?.restartAfter;
      if (restart == null || restart == 0 || restart > ilvl) counters[l] = null;
    }
    for (var l = 0; l < ilvl; l++) {
      counters[l] ??= startOf(l);
    }
    String text;
    if (lvl.format == 'bullet') {
      final font = lvl.rPr?.w('rFonts')?.attr('ascii') ?? lvl.rPr?.w('rFonts')?.attr('hAnsi');
      text = mapSymbolText(lvl.text, font);
    } else {
      text = lvl.text.replaceAllMapped(RegExp(r'%(\d)'), (m) {
        final l = int.parse(m.group(1)!) - 1;
        if (l < 0 || l > 8) return '';
        final value = counters[l] ?? startOf(l);
        final fmt = lvl.legal ? 'decimal' : (level(numId, l)?.format ?? 'decimal');
        return formatNumber(value, fmt);
      });
    }
    final picture = lvl.pictureBulletId == null ? null : _pictureBullets[lvl.pictureBulletId];
    return (level: lvl, text: text, picture: picture);
  }
}

/// A number in one of Word's number formats.
String formatNumber(int n, String format) {
  switch (format) {
    case 'decimal':
      return '$n';
    case 'decimalZero':
      return n < 10 ? '0$n' : '$n';
    case 'upperRoman':
      return roman(n);
    case 'lowerRoman':
      return roman(n).toLowerCase();
    case 'upperLetter':
      return _letters(n);
    case 'lowerLetter':
      return _letters(n).toLowerCase();
    case 'ordinal':
      return '$n${_ordinalSuffix(n)}';
    case 'cardinalText':
      return _cardinal(n);
    case 'ordinalText':
      return _ordinalText(n);
    case 'decimalEnclosedCircle':
      return n >= 1 && n <= 20 ? String.fromCharCode(0x2460 + n - 1) : '$n';
    case 'decimalEnclosedParen':
      return n >= 1 && n <= 20 ? String.fromCharCode(0x2474 + n - 1) : '($n)';
    case 'chicago':
      const marks = ['*', '†', '‡', '§'];
      return marks[(n - 1) % 4] * ((n - 1) ~/ 4 + 1);
    case 'none':
      return '';
    default:
      return '$n';
  }
}

String roman(int n) {
  if (n <= 0) return '$n';
  const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const symbols = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I'];
  final out = StringBuffer();
  for (var i = 0; i < values.length; i++) {
    while (n >= values[i]) {
      out.write(symbols[i]);
      n -= values[i];
    }
  }
  return out.toString();
}

/// Word repeats the letter after Z: AA, BB, ...
String _letters(int n) {
  if (n <= 0) return '$n';
  final letter = String.fromCharCode(0x41 + (n - 1) % 26);
  return letter * ((n - 1) ~/ 26 + 1);
}

String _ordinalSuffix(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return 'th';
  return switch (n % 10) {
    1 => 'st',
    2 => 'nd',
    3 => 'rd',
    _ => 'th',
  };
}

const _ones = [
  'Zero', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', //
  'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
];
const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

String _cardinal(int n) {
  if (n < 0 || n >= 1000) return '$n';
  if (n < 20) return _ones[n];
  if (n < 100) return _tens[n ~/ 10] + (n % 10 == 0 ? '' : '-${_ones[n % 10]}');
  return '${_ones[n ~/ 100]} Hundred${n % 100 == 0 ? '' : ' ${_cardinal(n % 100)}'}';
}

String _ordinalText(int n) {
  const special = {'One': 'First', 'Two': 'Second', 'Three': 'Third', 'Five': 'Fifth', 'Eight': 'Eighth', 'Nine': 'Ninth', 'Twelve': 'Twelfth'};
  final c = _cardinal(n);
  final parts = c.split(RegExp(r'(?=[ -])'));
  var last = parts.last.trim().replaceFirst('-', '');
  final sep = parts.last.startsWith('-') ? '-' : (parts.length > 1 ? ' ' : '');
  if (special.containsKey(last)) {
    last = special[last]!;
  } else if (last.endsWith('y')) {
    last = '${last.substring(0, last.length - 1)}ieth';
  } else {
    last = '${last}th';
  }
  return [...parts.take(parts.length - 1), '$sep$last'].join();
}
