// Renders the Word feature test document to PNG files for a visual check.
// Run with: PREVIEW_OUT=/some/dir flutter test test/preview
@Tags(['preview'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_docx/luma_docx.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    if (File(f).existsSync()) loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  final out = Platform.environment['PREVIEW_OUT'];
  testWidgets('render pages', (tester) async {
    const lib = '/usr/share/fonts/truetype';
    final sans = ['$lib/crosextra/Carlito-Regular.ttf', '$lib/crosextra/Carlito-Bold.ttf', '$lib/crosextra/Carlito-Italic.ttf', '$lib/crosextra/Carlito-BoldItalic.ttf'];
    final serif = ['$lib/liberation/LiberationSerif-Regular.ttf', '$lib/liberation/LiberationSerif-Bold.ttf', '$lib/liberation/LiberationSerif-Italic.ttf', '$lib/liberation/LiberationSerif-BoldItalic.ttf'];
    final mono = ['$lib/liberation/LiberationMono-Regular.ttf', '$lib/liberation/LiberationMono-Bold.ttf'];
    await tester.runAsync(() async {
      for (final f in ['Calibri', 'Calibri Light', 'sans-serif', 'Roboto', 'Arial', 'Segoe UI']) {
        await _font(f, sans);
      }
      for (final f in ['serif', 'Times New Roman', 'Georgia', 'Cambria', 'Cambria Math', 'Garamond']) {
        await _font(f, serif);
      }
      for (final f in ['monospace', 'Courier New', 'Consolas']) {
        await _font(f, mono);
      }
      await _font('Noto Color Emoji', ['$lib/noto/NotoColorEmoji.ttf']);
      await _font('cursive', ['$lib/dejavu/DejaVuSerif.ttf']);
      await _font('MS Gothic', ['$lib/dejavu/DejaVuSans.ttf']);
      await _font('DejaVu Sans', ['$lib/dejavu/DejaVuSans.ttf', '$lib/dejavu/DejaVuSans-Bold.ttf']);
    });
    final layout = Platform.environment['PREVIEW_LAYOUT'] == 'reflow' ? WordLayout.reflow : WordLayout.pages;
    final doc = WordReader.read(File('test/fixtures/Word_Feature_Test.docx').readAsBytesSync());
    final width = layout == WordLayout.pages ? 640.0 : 412.0;
    await tester.binding.setSurfaceSize(Size(width, 900));
    tester.view.devicePixelRatio = 1.5;
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(body: WordDocumentView(document: doc, options: WordViewOptions(layout: layout))),
        ),
      ),
    );
    await tester.pump();
    final errors = <String>[];
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final max = scroll.position.maxScrollExtent;
    var y = 0.0, i = 0;
    while (out != null && y <= max + 1 && i < 80) {
      scroll.position.jumpTo(y);
      await tester.pump();
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.5);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$out/${layout.name}_${i.toString().padLeft(2, '0')}.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
      y += 860;
      i++;
    }
    expect(errors, isEmpty);
    debugPrint('max scroll $max, shots $i');
  });
}
