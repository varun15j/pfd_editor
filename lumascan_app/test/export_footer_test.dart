import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/app_info.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/export/pdf_exporter.dart';

/// The words drawn on the pages of [pdf], from every content stream, with a
/// space between words and a new line between pages, so the text can be
/// searched.
String _pageText(Uint8List pdf) {
  final raw = latin1.decode(pdf);
  final out = StringBuffer();
  for (final m in RegExp(r'stream\r?\n').allMatches(raw)) {
    final end = raw.indexOf('endstream', m.end);
    if (end < 0) continue;
    final bytes = pdf.sublist(m.end, end);
    final String content;
    try {
      content = latin1.decode(zlib.decode(bytes));
    } on Object {
      continue; // an image
    }
    out.writeln([for (final w in RegExp(r'\[\((.*?)\)\]TJ').allMatches(content)) w[1]].join(' '));
  }
  return out.toString();
}

void main() {
  final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 200, height: 280)));
  final twoPages = [(jpeg, 200, 280), (jpeg, 200, 280)];

  test('the watermark names the app from its config', () {
    expect(exportWatermark, 'Scanned with $appName');
  });

  test('Basic keeps the watermark; Pro and Gold drop it and may number pages', () {
    expect(AppPlan.basic.includes(PlanFeature.noWatermark), isFalse);
    expect(AppPlan.basic.includes(PlanFeature.pageNumbers), isFalse);
    for (final plan in [AppPlan.pro, AppPlan.gold]) {
      expect(plan.includes(PlanFeature.noWatermark), isTrue, reason: plan.label);
      expect(plan.includes(PlanFeature.pageNumbers), isTrue, reason: plan.label);
    }
  });

  for (final size in PdfPageSize.values) {
    test('${size.name}: the watermark is printed on every page', () async {
      final pdf = await buildPdfFromJpegs(twoPages, size, footer: const PageFooter(watermark: exportWatermark));
      final text = _pageText(pdf);
      expect(RegExp(RegExp.escape(exportWatermark)).allMatches(text), hasLength(2));
      expect(text, isNot(contains('1 / 2')));
    });
  }

  test('page numbers read "n / total" on each page', () async {
    final pdf = await buildPdfFromJpegs(twoPages, PdfPageSize.a4, footer: const PageFooter(pageNumbers: true));
    final text = _pageText(pdf);
    expect(text, contains('1 / 2'));
    expect(text, contains('2 / 2'));
    expect(text, isNot(contains(exportWatermark)));
  });

  test('without a footer nothing is added to the page', () async {
    final pdf = await buildPdfFromJpegs(twoPages, PdfPageSize.a4);
    final text = _pageText(pdf);
    expect(text, isNot(contains(exportWatermark)));
    expect(text, isNot(contains('1 / 2')));
  });
}
