import 'package:xml/xml.dart';

import '../model.dart';
import 'theme.dart';
import 'xml_util.dart';

/// A chart part (`word/charts/chartN.xml`) to [WordChart] data. The values
/// come from the cache Word saves next to the embedded workbook.
class ChartReader {
  const ChartReader._();

  static WordChart read(XmlDocument xml, WordTheme theme, {required double width, required double height, WordAnchor? anchor}) {
    final chart = xml.rootElement.el('c', 'chart');
    final plot = chart?.el('c', 'plotArea');
    XmlElement? kindEl;
    var kind = WordChartKind.other;
    for (final c in plot?.childElements ?? const <XmlElement>[]) {
      final k = switch (c.name.local) {
        'barChart' || 'bar3DChart' => (c.el('c', 'barDir')?.attr('val') == 'bar') ? WordChartKind.bar : WordChartKind.column,
        'lineChart' || 'line3DChart' => WordChartKind.line,
        'pieChart' || 'pie3DChart' || 'ofPieChart' => WordChartKind.pie,
        'doughnutChart' => WordChartKind.doughnut,
        'areaChart' || 'area3DChart' => WordChartKind.area,
        'scatterChart' || 'bubbleChart' => WordChartKind.scatter,
        _ => null,
      };
      if (k != null) {
        kind = k;
        kindEl = c;
        break;
      }
    }
    final grouping = kindEl?.el('c', 'grouping')?.attr('val');
    final series = <WordChartSeries>[];
    var categories = <String>[];
    for (final s in kindEl?.els('c', 'ser') ?? const <XmlElement>[]) {
      final name = _strings(s.el('c', 'tx')).firstOrNull ?? 'Series ${series.length + 1}';
      final cats = _strings(s.el('c', 'cat') ?? s.el('c', 'xVal'));
      if (categories.isEmpty && cats.isNotEmpty) categories = cats;
      final values = _numbers(s.el('c', 'val') ?? s.el('c', 'yVal'));
      final fill = theme.drawingColor(s.el('c', 'spPr')?.el('a', 'solidFill'));
      final points = <WordColor?>[];
      for (final dp in s.els('c', 'dPt')) {
        final idx = int.tryParse(dp.el('c', 'idx')?.attr('val') ?? '') ?? points.length;
        while (points.length <= idx) {
          points.add(null);
        }
        points[idx] = theme.drawingColor(dp.el('c', 'spPr')?.el('a', 'solidFill'));
      }
      series.add(WordChartSeries(name: name, values: values, color: fill, pointColors: points));
    }
    final titleEl = chart?.el('c', 'title');
    String? title;
    if (titleEl != null) {
      title = titleEl.descendantElements.where((e) => e.name.local == 't' && nsOf(e) == 'a').map((e) => e.innerText).join();
      if (title.isEmpty) title = _strings(titleEl.el('c', 'tx')).firstOrNull;
      if ((title == null || title.isEmpty) && series.length == 1) title = series.first.name;
    }
    return WordChart(
      kind: kind,
      width: width,
      height: height,
      title: title,
      categories: categories,
      series: series,
      stacked: grouping == 'stacked' || grouping == 'percentStacked',
      anchor: anchor,
    );
  }

  static List<String> _strings(XmlElement? e) {
    final cache = e?.find('c', 'strCache') ?? e?.find('c', 'numCache');
    if (cache != null) return _points(cache).map((p) => p ?? '').toList();
    final v = e?.find('c', 'v');
    return v == null ? const [] : [v.innerText];
  }

  static List<double> _numbers(XmlElement? e) {
    final cache = e?.find('c', 'numCache');
    if (cache == null) return const [];
    return _points(cache).map((p) => double.tryParse(p ?? '') ?? 0).toList();
  }

  static List<String?> _points(XmlElement cache) {
    final count = int.tryParse(cache.el('c', 'ptCount')?.attr('val') ?? '');
    final pts = cache.els('c', 'pt').toList();
    final out = List<String?>.filled(count ?? pts.length, null, growable: true);
    for (final p in pts) {
      final idx = int.tryParse(p.attr('idx') ?? '') ?? 0;
      while (out.length <= idx) {
        out.add(null);
      }
      out[idx] = p.el('c', 'v')?.innerText;
    }
    return out;
  }
}
