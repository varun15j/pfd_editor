import 'package:xml/xml.dart';

import '../model.dart';
import 'xml_util.dart';

/// Office Math (OMML, `m:oMath`) to a [MathNode] tree.
class MathReader {
  const MathReader._();

  static MathNode read(XmlElement oMath) => _row(oMath);

  static MathNode _row(XmlElement? e) {
    if (e == null) return const MathRow([]);
    final out = <MathNode>[];
    for (final c in e.childElements) {
      final n = _node(c);
      if (n != null) out.add(n);
    }
    return out.length == 1 ? out.first : MathRow(out);
  }

  static String? _prop(XmlElement e, String pr, String local) => e.el('m', pr)?.el('m', local)?.attr('val');

  static MathNode? _node(XmlElement e) {
    final ns = nsOf(e);
    if (ns == 'w') {
      // Word runs inside math (rare): take their text.
      if (e.name.local == 'r') return MathText(e.descendantElements.where((d) => d.name.local == 't').map((t) => t.innerText).join(), plain: true);
      return null;
    }
    if (ns == 'mc' && e.name.local == 'AlternateContent') {
      final choice = e.el('mc', 'Choice') ?? e.el('mc', 'Fallback');
      return choice == null ? null : _row(choice);
    }
    if (ns != 'm') return null;
    switch (e.name.local) {
      case 'r':
        final text = e.els('m', 't').map((t) => t.innerText).join();
        final sty = e.el('m', 'rPr')?.el('m', 'sty')?.attr('val');
        final plain = e.el('m', 'rPr')?.el('m', 'nor') != null || sty == 'p' || sty == 'b';
        return MathText(text, plain: plain, bold: sty == 'b' || sty == 'bi');
      case 'f':
        final type = _prop(e, 'fPr', 'type');
        return MathFraction(_row(e.el('m', 'num')), _row(e.el('m', 'den')), bar: type != 'noBar', linearForm: type == 'lin');
      case 'rad':
        final hide = _prop(e, 'radPr', 'degHide');
        final deg = e.el('m', 'deg');
        final hasDeg = deg != null && deg.childElements.isNotEmpty && hide != '1' && hide != 'on';
        return MathRadical(_row(e.el('m', 'e')), degree: hasDeg ? _row(deg) : null);
      case 'sSup':
        return MathScript(_row(e.el('m', 'e')), sup: _row(e.el('m', 'sup')));
      case 'sSub':
        return MathScript(_row(e.el('m', 'e')), sub: _row(e.el('m', 'sub')));
      case 'sSubSup':
        return MathScript(_row(e.el('m', 'e')), sub: _row(e.el('m', 'sub')), sup: _row(e.el('m', 'sup')));
      case 'sPre':
        return MathRow([MathScript(const MathText(''), sub: _row(e.el('m', 'sub')), sup: _row(e.el('m', 'sup'))), _row(e.el('m', 'e'))]);
      case 'nary':
        final chr = _prop(e, 'naryPr', 'chr') ?? '∫';
        final loc = _prop(e, 'naryPr', 'limLoc');
        final sub = e.el('m', 'sub'), sup = e.el('m', 'sup');
        return MathNary(
          chr,
          _row(e.el('m', 'e')),
          sub: sub == null || sub.childElements.isEmpty ? null : _row(sub),
          sup: sup == null || sup.childElements.isEmpty ? null : _row(sup),
          limitsUnderOver: loc == 'undOvr' || (loc == null && chr != '∫' && chr != '∬' && chr != '∭' && chr != '∮'),
        );
      case 'd':
        final pr = e.el('m', 'dPr');
        String chr(String local, String fallback) {
          final el = pr?.el('m', local);
          if (el == null) return fallback;
          return el.attr('val') ?? '';
        }

        return MathDelimiter(
          [for (final i in e.els('m', 'e')) _row(i)],
          begin: chr('begChr', '('),
          end: chr('endChr', ')'),
          separator: chr('sepChr', '|'),
        );
      case 'm':
        return MathMatrix([
          for (final r in e.els('m', 'mr')) [for (final c in r.els('m', 'e')) _row(c)],
        ]);
      case 'func':
        return MathFunction(_row(e.el('m', 'fName')), _row(e.el('m', 'e')));
      case 'limLow':
        return MathLimit(_row(e.el('m', 'e')), _row(e.el('m', 'lim')));
      case 'limUpp':
        return MathLimit(_row(e.el('m', 'e')), _row(e.el('m', 'lim')), upper: true);
      case 'acc':
        return MathAccent(_row(e.el('m', 'e')), _prop(e, 'accPr', 'chr') ?? '̂');
      case 'bar':
        final pos = _prop(e, 'barPr', 'pos');
        return MathAccent(_row(e.el('m', 'e')), '̅', below: pos == null || pos == 'bot');
      case 'groupChr':
        final pos = _prop(e, 'groupChrPr', 'pos');
        return MathAccent(_row(e.el('m', 'e')), _prop(e, 'groupChrPr', 'chr') ?? '⏟', below: pos != 'top');
      case 'box':
      case 'borderBox':
      case 'phant':
      case 'e':
      case 'oMath':
        return _row(e.el('m', 'e') ?? e);
      case 'eqArr':
        return MathMatrix([
          for (final r in e.els('m', 'e')) [_row(r)],
        ]);
      default:
        return null;
    }
  }
}
