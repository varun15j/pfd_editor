import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/app/theme.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/scanner_service.dart';
import 'package:lumascan/export/pdf_exporter.dart';
import 'package:lumascan/features/filters/filter_screen.dart';
import 'package:lumascan/features/markup/markup_screen.dart';
import 'package:lumascan/features/markup/markup_style.dart';
import 'package:lumascan/features/markup/markup_toolbar.dart';
import 'package:lumascan/features/pages/page_single_view.dart';
import 'package:lumascan/features/pages/pages_screen.dart';
import 'package:lumascan/features/pages/scan_controller.dart';
import 'package:lumascan/features/pdf_editor/annotation_layer.dart';
import 'package:lumascan/imaging/page_renderer.dart';
import 'package:lumascan/imaging/render_service.dart';
import 'package:lumascan/pdf_edit/annotations.dart';

class _FakeScanner implements ScannerService {
  _FakeScanner(this.paths);
  final List<String> paths;

  @override
  Future<List<String>> scan({required ScanSource source, int maxPages = 100}) async => paths;

  @override
  Future<void> cleanUp() async {}
}

/// Shows the original file so widget tests settle without the render isolate.
class _NoRender extends RenderService {
  _NoRender(super.store);

  @override
  Future<RenderedImage> render(ScanPage page, {EditRecipe? recipe, int maxDimension = RenderService.previewSize}) =>
      Future.value(RenderedImage(page.originalPath, 300, 400));
}

const _ink = InkAnnotation(
  id: 'ink1',
  points: [NormPoint(0.1, 0.1), NormPoint(0.5, 0.4)],
  color: 0xFF1E4FD8,
  width: 0.005,
);
const _hl = InkAnnotation(
  id: 'hl1',
  points: [NormPoint(0.2, 0.2), NormPoint(0.8, 0.2)],
  color: 0xFFFFC400,
  width: 0.022,
  highlighter: true,
);
const _text = TextAnnotation(id: 't1', origin: NormPoint(0.1, 0.8), text: 'Paid', color: 0xFFC62828, fontSize: 0.05);
const _sig = SignatureAnnotation(
  id: 's1',
  strokes: [
    [NormPoint(0, 0.5), NormPoint(0.5, 1), NormPoint(1, 0)],
  ],
  left: 0.3,
  top: 0.6,
  width: 0.3,
  aspectRatio: 2,
  color: 0xFF14213D,
);

void main() {
  late Directory tmp;
  late ProviderContainer container;
  var ready = false;

  Future<void> setUpContainer(int pageCount) async {
    tmp = Directory.systemTemp.createTempSync('lumascan_markup');
    final paths = [
      for (var i = 0; i < pageCount; i++)
        (File('${tmp.path}/scan$i.jpg')..writeAsBytesSync(img.encodeJpg(img.Image(width: 30, height: 40)))).path,
    ];
    final store = PageStore(rootDir: () async => tmp);
    container = ProviderContainer(
      overrides: [
        scannerServiceProvider.overrideWithValue(_FakeScanner(paths)),
        pageStoreProvider.overrideWithValue(store),
        renderServiceProvider.overrideWithValue(_NoRender(store)),
      ],
    );
    await container.read(scanControllerProvider.notifier).scan(ScanSource.camera);
    ready = true;
  }

  tearDown(() {
    if (!ready) return;
    ready = false;
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  ScanController controller() => container.read(scanControllerProvider.notifier);
  List<ScanPage> pages() => container.read(scanControllerProvider).pages;

  group('saving marks', () {
    test('every kind of mark survives a JSON round trip', () {
      final back = Annotation.listFromJson(
        jsonDecode(
          jsonEncode([
            for (final a in [_ink, _hl, _text, _sig]) a.toJson(),
          ]),
        ),
      );
      expect(back, hasLength(4));
      final ink = back[0] as InkAnnotation;
      expect((ink.id, ink.color, ink.width, ink.highlighter), ('ink1', 0xFF1E4FD8, 0.005, false));
      expect(ink.points.last, const NormPoint(0.5, 0.4));
      expect((back[1] as InkAnnotation).highlighter, isTrue);
      final text = back[2] as TextAnnotation;
      expect((text.text, text.fontSize, text.origin), ('Paid', 0.05, const NormPoint(0.1, 0.8)));
      final sig = back[3] as SignatureAnnotation;
      expect((sig.left, sig.top, sig.width, sig.aspectRatio), (0.3, 0.6, 0.3, 2.0));
      expect(sig.strokes.single, hasLength(3));
    });

    test('a damaged mark is skipped without losing the others', () {
      final back = Annotation.listFromJson([
        _ink.toJson(),
        {'type': 'ink', 'id': 'broken'},
        {'type': 'sticker'},
        _text.toJson(),
      ]);
      expect(back.map((a) => a.id), ['ink1', 't1']);
    });

    test('a page keeps its marks in the draft file and leaves the key out when there are none', () {
      const plain = ScanPage(id: 'p', originalPath: '/x/p.jpg');
      expect(plain.toJson().containsKey('annotations'), isFalse);

      final marked = plain.copyWith(annotations: [_ink, _text]);
      final back = ScanPage.fromJson(
        jsonDecode(jsonEncode(marked.toJson())) as Map<String, Object?>,
        originalsDir: '/x',
      );
      expect(back.annotations.map((a) => a.id), ['ink1', 't1']);
      // Drafts saved before markup existed still open.
      expect(ScanPage.fromJson(plain.toJson(), originalsDir: '/x').annotations, isEmpty);
    });
  });

  group('marks follow the page', () {
    test('setAnnotations is one undo step and a duplicate carries the marks', () async {
      await setUpContainer(1);
      final id = pages().single.id;
      controller().setAnnotations(id, [_ink, _text]);
      expect(pages().single.annotations, hasLength(2));

      controller().duplicate(id);
      expect(pages().map((p) => p.annotations.length), [2, 2]);

      controller().undo();
      controller().undo();
      expect(pages().single.annotations, isEmpty);
    });

    test('rotating or cropping removes the marks, and undo brings them back', () async {
      await setUpContainer(1);
      final id = pages().single.id;
      controller().setAnnotations(id, [_ink]);

      final turned = pages().single.recipe.copyWith(quarterTurns: 1);
      expect(controller().dropsMarks(id, turned), isTrue);
      controller().rotate(id);
      expect(pages().single.annotations, isEmpty);
      controller().undo();
      expect(pages().single.annotations, hasLength(1));

      const quad = CropQuad(NormPoint(0.1, 0.1), NormPoint(0.9, 0.1), NormPoint(0.9, 0.9), NormPoint(0.1, 0.9));
      controller().updateRecipe(id, pages().single.recipe.copyWith(crop: quad));
      expect(pages().single.annotations, isEmpty);
    });

    test('a filter or brightness change keeps the marks', () async {
      await setUpContainer(2);
      final first = pages().first.id;
      controller().setAnnotations(first, [_ink]);
      final bright = pages().first.recipe.copyWith(filter: DocumentFilter.blackWhite, brightness: 0.3);
      expect(controller().dropsMarks(first, bright), isFalse);
      controller().applyEnhancement(first, bright, alsoPageIds: [pages().last.id]);
      expect(pages().first.annotations, hasLength(1));
      controller().applyFilterToAll(DocumentFilter.grayscale);
      expect(pages().first.annotations, hasLength(1));
    });

    test('copying an enhancement to other pages never touches their marks', () async {
      await setUpContainer(2);
      final second = pages().last.id;
      controller().setAnnotations(second, [_text]);
      final turned = pages().first.recipe.copyWith(quarterTurns: 1, filter: DocumentFilter.blackWhite);
      controller().applyEnhancement(pages().first.id, turned, alsoPageIds: [second]);
      expect(pages().last.annotations, hasLength(1));
      expect(pages().last.recipe.quarterTurns, 0);
    });
  });

  group('shared style', () {
    test('one colour and thickness maps to a pen, highlighter and text size', () {
      const thin = MarkupStyle(size: MarkupSize.thin);
      const thick = MarkupStyle(size: MarkupSize.thick);
      expect(thin.inkWidth(highlighter: false), lessThan(thick.inkWidth(highlighter: false)));
      expect(thin.inkWidth(highlighter: true), lessThan(thick.inkWidth(highlighter: true)));
      expect(thin.fontSize, lessThan(thick.fontSize));
      // A highlighter is always wider than a pen at the same setting.
      for (final s in MarkupSize.values) {
        final style = MarkupStyle(size: s);
        expect(style.inkWidth(highlighter: true), greaterThan(style.inkWidth(highlighter: false)));
      }
    });
  });

  group('toolbar', () {
    Future<void> pumpToolbar(WidgetTester tester, EditorTool tool) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: MarkupToolbar(
              tools: EditorTool.values,
              tool: tool,
              onTool: (_) {},
              style: const MarkupStyle(),
              onStyle: (_) {},
              onSignature: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('scrolls to the selected tool so it is always on screen', (tester) async {
      await pumpToolbar(tester, EditorTool.eraser);
      final screen = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final rect = tester.getRect(find.text('Erase'));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(screen));
    });

    testWidgets('colour and thickness show for pen, highlighter and text only', (tester) async {
      await pumpToolbar(tester, EditorTool.pen);
      expect(find.text('Thick'), findsOneWidget);
      expect(find.byType(InkResponse), findsNWidgets(MarkupStyle.palette.length));

      await pumpToolbar(tester, EditorTool.eraser);
      expect(find.text('Thick'), findsNothing);
    });
  });

  group('markup screen', () {
    Future<void> pumpMarkup(WidgetTester tester, {double textScale = 1}) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildLumaTheme(Brightness.light),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => MarkupScreen(pageId: pages().first.id))),
                    child: const Text('Open markup'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open markup'));
      await tester.pumpAndSettle();
    }

    // The toolbar scrolls on a phone, so bring a tool into view before tapping it.
    Future<void> selectTool(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Future<void> drawStroke(WidgetTester tester) async {
      final rect = tester.getRect(find.byType(AnnotationLayer));
      final gesture = await tester.startGesture(rect.topLeft + Offset(rect.width * 0.3, rect.height * 0.3));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(10, 6));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
    }

    testWidgets('marks are kept on the page when Done is tapped, as one undo step', (tester) async {
      await tester.runAsync(() => setUpContainer(1));
      await pumpMarkup(tester);
      await drawStroke(tester);
      expect(pages().single.annotations, isEmpty, reason: 'nothing is saved before Done');

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(MarkupScreen), findsNothing);
      final ink = pages().single.annotations.single as InkAnnotation;
      expect(ink.points.length, greaterThan(4));
      expect(ink.points.first.x, closeTo(0.3, 0.03));

      controller().undo();
      expect(pages().single.annotations, isEmpty);
    });

    testWidgets('colour and thickness carry over from pen to highlighter to text', (tester) async {
      await tester.runAsync(() => setUpContainer(1));
      await pumpMarkup(tester);

      final red = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == MarkupStyle.palette[2],
      );
      await tester.tap(red);
      await tester.pump();
      await tester.tap(find.text('Thick'));
      await tester.pump();
      await drawStroke(tester);

      await selectTool(tester, 'Highlight');
      await drawStroke(tester);

      await selectTool(tester, 'Text');
      final rect = tester.getRect(find.byType(AnnotationLayer));
      await tester.tapAt(rect.topLeft + Offset(rect.width * 0.2, rect.height * 0.7));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Paid');
      await tester.tap(find.widgetWithText(FilledButton, 'Done').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();

      final marks = pages().single.annotations;
      final pen = marks[0] as InkAnnotation;
      final marker = marks[1] as InkAnnotation;
      final label = marks[2] as TextAnnotation;
      const thick = MarkupStyle(size: MarkupSize.thick);
      const red32 = 0xFFC62828;
      expect((pen.color, pen.width, pen.highlighter), (red32, thick.inkWidth(highlighter: false), false));
      expect((marker.color, marker.width, marker.highlighter), (red32, thick.inkWidth(highlighter: true), true));
      expect((label.color, label.fontSize, label.text), (red32, thick.fontSize, 'Paid'));
    });

    testWidgets('undo inside the screen removes the last mark', (tester) async {
      await tester.runAsync(() => setUpContainer(1));
      await pumpMarkup(tester);
      await drawStroke(tester);
      await drawStroke(tester);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(pages().single.annotations, hasLength(1));
    });

    testWidgets('Back with unsaved marks asks first, and Discard leaves the page unchanged', (tester) async {
      await tester.runAsync(() => setUpContainer(1));
      await pumpMarkup(tester);
      await drawStroke(tester);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard your marks?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(MarkupScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(MarkupScreen), findsNothing);
      expect(pages().single.annotations, isEmpty);
    });

    testWidgets('Back without changes leaves straight away', (tester) async {
      await tester.runAsync(() => setUpContainer(1));
      await pumpMarkup(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(MarkupScreen), findsNothing);
    });

    testWidgets('existing marks open for editing and the eraser removes one', (tester) async {
      await tester.runAsync(() => setUpContainer(1));
      controller().setAnnotations(pages().single.id, [_hl]);
      await pumpMarkup(tester);

      await selectTool(tester, 'Erase');
      final rect = tester.getRect(find.byType(AnnotationLayer));
      await tester.tapAt(rect.topLeft + Offset(rect.width * 0.5, rect.height * 0.2));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(pages().single.annotations, isEmpty);
    });

    testWidgets('fits at 200% text size', (tester) async {
      await tester.runAsync(() => setUpContainer(1));
      await pumpMarkup(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      await selectTool(tester, 'Highlight');
      expect(tester.takeException(), isNull);
    });
  });

  group('marks on the page views', () {
    Future<void> pumpApp(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: buildLumaTheme(Brightness.light), home: home),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the page view draws the marks', (tester) async {
      await tester.runAsync(() => setUpContainer(2));
      controller().setAnnotations(pages().first.id, [_ink, _text, _sig]);
      await pumpApp(tester, const PagesScreen());
      expect(find.byType(PageSingleView), findsOneWidget);
      // The page and its thumbnail in the strip both show the marks.
      expect(find.byType(StaticMarks), findsWidgets);
      expect(find.text('Paid'), findsWidgets);
    });

    testWidgets('Markup is one of the page actions and opens the screen', (tester) async {
      await tester.runAsync(() => setUpContainer(1));
      await pumpApp(tester, const PagesScreen());
      await tester.ensureVisible(find.text('Markup'));
      await tester.tap(find.text('Markup'));
      await tester.pumpAndSettle();
      expect(find.byType(MarkupScreen), findsOneWidget);
    });

    testWidgets('rotating a marked page says the marks were removed and Undo restores them', (tester) async {
      await tester.runAsync(() => setUpContainer(1));
      controller().setAnnotations(pages().single.id, [_ink]);
      await pumpApp(tester, const PagesScreen());
      await tester.ensureVisible(find.text('Rotate'));
      await tester.tap(find.text('Rotate'));
      await tester.pumpAndSettle();
      expect(pages().single.annotations, isEmpty);
      expect(find.text('Markup removed because the page changed'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(pages().single.annotations, hasLength(1));
    });

    testWidgets('the filter screen does not draw marks over its previews', (tester) async {
      await tester.runAsync(() => setUpContainer(1));
      controller().setAnnotations(pages().single.id, [_ink]);
      await pumpApp(tester, FilterScreen(pageId: pages().single.id));
      expect(find.byType(StaticMarks), findsNothing);
    });
  });

  group('export', () {
    // Every deflated stream of the PDF as text, to look at the drawing commands.
    String contentOf(Uint8List pdf) {
      final raw = latin1.decode(pdf);
      final out = StringBuffer();
      for (final m in RegExp(r'stream\r?\n').allMatches(raw)) {
        final end = raw.indexOf('endstream', m.end);
        if (end < 0) continue;
        try {
          out.writeln(latin1.decode(zlib.decode(pdf.sublist(m.end, end)), allowInvalid: true));
        } catch (_) {
          // Not a deflated stream (an image).
        }
      }
      return out.toString();
    }

    final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 150, height: 200)));

    test('marks are flattened over the page at the page size', () async {
      final pdf = await buildPdfFromJpegs(
        [(jpeg, 150, 200)],
        PdfPageSize.fitImage,
        annotations: [
          [_ink, _text],
        ],
      );
      final content = contentOf(pdf);
      // The page is 72 x 96 pt. The pen is 0.005 of the width wide, starts at (0.1, 0.1)
      // from the top-left and the text is 5% of the width tall.
      expect(content, contains('0.36 w'));
      expect(content, contains('7.2 86.4 m'));
      expect(content, contains('3.6 Tf'));
      expect(content, contains('(Paid)'));
    });

    test('marks follow the picture inside the margins of an A4 page', () async {
      final pdf = await buildPdfFromJpegs(
        [(jpeg, 150, 200)],
        PdfPageSize.a4,
        annotations: [
          [_ink],
        ],
      );
      // A4 is 595.28 pt wide. Less 18 pt margins, 150 x 200 is limited by the width, so the
      // picture is 559.28 pt wide and a 0.005 pen is 2.796 pt.
      expect(contentOf(pdf), contains('2.796'));
    });

    test('pages without marks are written as before', () async {
      final plain = await buildPdfFromJpegs([(jpeg, 150, 200)], PdfPageSize.a4);
      final marked = await buildPdfFromJpegs(
        [(jpeg, 150, 200)],
        PdfPageSize.a4,
        annotations: [
          [_ink],
        ],
      );
      expect(contentOf(plain), isNot(contains(' w')));
      expect(marked.length, greaterThan(plain.length));
    });
  });
}
