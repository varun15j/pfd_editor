import 'dart:convert';
import 'dart:io';

import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/ocr.dart';

/// Page [n] of the Word feature test images, with the OCR layout that a
/// perfect engine would report (sample_photos/word_pages/expected.json).
(ScanPage, OcrLayout) wordTestPage(int n) {
  final json = jsonDecode(File('sample_photos/word_pages/expected.json').readAsStringSync()) as Map<String, dynamic>;
  final p = (json['pages'] as List).cast<Map<String, dynamic>>()[n - 1];
  List<double> box(Map<String, dynamic> e) => [for (final v in (e['box'] as List).cast<num>()) v.toDouble()];
  final blocks = <OcrBlock>[];
  for (final b in (p['blocks'] as List).cast<Map<String, dynamic>>()) {
    final lines = [
      for (final l in (b['lines'] as List).cast<Map<String, dynamic>>())
        () {
          final x = box(l);
          return OcrLine(text: l['text'] as String, left: x[0], top: x[1], right: x[2], bottom: x[3]);
        }(),
    ];
    final x = box(b);
    blocks.add(
      OcrBlock(
        text: lines.map((l) => l.text).join('\n'),
        left: x[0],
        top: x[1],
        right: x[2],
        bottom: x[3],
        lines: lines,
      ),
    );
  }
  final page = ScanPage(id: 'p$n', originalPath: 'sample_photos/word_pages/page_${n.toString().padLeft(2, '0')}.jpg');
  return (page, OcrLayout(blocks));
}
