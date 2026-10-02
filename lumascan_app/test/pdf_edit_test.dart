import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/features/pdf_editor/annotation_layer.dart';
import 'package:lumascan/pdf_edit/annotations.dart';
import 'package:lumascan/pdf_edit/pdf_edit_controller.dart';
import 'package:lumascan/pdf_edit/pdf_flattener.dart';
import 'package:lumascan/pdf_edit/pdf_saver.dart';
import 'package:path/path.dart' as path;

/// Renders source page N as a flat colour so tests can tell pages apart.
class FakeRasterizer implements PdfRasterizer {
  final requests = <List<int>>[];

  @override
  Stream<RasterPage> renderPages(
    String path,
    List<int> pageNumbers, {
    required int longEdge,
    required int jpegQuality,
    String? password,
  }) async* {
    requests.add(pageNumbers);
    for (final n in pageNumbers) {
      final image = img.Image(width: 60, height: 80)..clear(img.ColorRgb8(40 * n, 200, 100));
      yield RasterPage(img.encodeJpg(image), 60, 80);
    }
  }
}

InkAnnotation ink(String id, List<NormPoint> points) =>
    InkAnnotation(id: id, points: points, color: 0xFF000000, width: 0.004);

void main() {
  late ProviderContainer container;
  late Directory tmp;
  late FakeRasterizer rasterizer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pdf_edit_test');
    rasterizer = FakeRasterizer();
    container = ProviderContainer(
      overrides: [
        pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
        pdfRasterizerProvider.overrideWithValue(rasterizer),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  PdfEditController controller() => container.read(pdfEditControllerProvider.notifier);
  PdfEditState state() => container.read(pdfEditControllerProvider);

  void open3() => controller().open(
    path: '/tmp/source.pdf',
    name: 'Lease.pdf',
    pageSizes: const [(612, 792), (595, 842), (792, 612)],
  );

  group('PdfEditController', () {
    test('open lists every source page in order', () {
      open3();
      expect(state().pages.map((p) => p.sourcePage), [1, 2, 3]);
      expect(state().pages[2].aspect, closeTo(792 / 612, 1e-9));
      expect(state().dirty, isFalse);
      expect(state().canUndo, isFalse);
    });

    test('annotations are added, replaced and removed per page, with undo', () {
      open3();
      final pageId = state().pages[1].id;
      controller().addAnnotation(pageId, ink('a', const [NormPoint(0.1, 0.1), NormPoint(0.2, 0.2)]));
      const text = TextAnnotation(id: 't', origin: NormPoint(0.5, 0.5), text: 'Hello', color: 0xFF000000);
      controller().addAnnotation(pageId, text);
      controller().replaceAnnotation(pageId, text.copyWith(text: 'Hi'));
      expect(state().pages[1].annotations, hasLength(2));
      expect((state().pages[1].annotations[1] as TextAnnotation).text, 'Hi');
      expect(state().pages[0].annotations, isEmpty);
      expect(state().dirty, isTrue);

      controller().removeAnnotation(pageId, 'a');
      expect(state().pages[1].annotations.single.id, 't');
      controller().undo();
      expect(state().pages[1].annotations, hasLength(2));
    });

    test('pages reorder and delete, but the last page stays', () {
      open3();
      controller().movePage(0, 2);
      expect(state().pages.map((p) => p.sourcePage), [2, 3, 1]);
      controller().movePage(2, 0);
      expect(state().pages.map((p) => p.sourcePage), [1, 2, 3]);

      expect(controller().deletePage(state().pages[1].id), isTrue);
      expect(controller().deletePage(state().pages[1].id), isTrue);
      expect(state().pages.map((p) => p.sourcePage), [1]);
      expect(controller().deletePage(state().pages[0].id), isFalse);
      expect(state().pages, hasLength(1));

      controller().undo();
      controller().undo();
      expect(state().pages.map((p) => p.sourcePage), [1, 2, 3]);
    });

    test('markSaved clears dirty until the next edit', () {
      open3();
      controller().movePage(0, 1);
      controller().markSaved();
      expect(state().dirty, isFalse);
      controller().undo();
      expect(state().dirty, isTrue);
    });
  });

  group('annotation geometry', () {
    test('signature strokes are normalized to their own box and centred', () {
      final s = SignatureAnnotation.fromPadStrokes(
        id: 's',
        strokes: const [
          [(104.0, 54.0), (204.0, 54.0)],
          [(104.0, 104.0)],
        ],
        color: 0xFF000000,
        pageAspect: 0.75,
        width: 0.4,
      )!;
      // Box is 100+8 wide and 50+8 tall including the 4px pad.
      expect(s.aspectRatio, closeTo(108 / 58, 1e-9));
      expect(s.strokes.first.first.x, closeTo(4 / 108, 1e-9));
      expect(s.strokes.first.first.y, closeTo(4 / 58, 1e-9));
      expect(s.strokes[1].single.y, closeTo(54 / 58, 1e-9));
      expect(s.left, closeTo(0.3, 1e-9));
      expect(s.top + s.heightOn(0.75) / 2, closeTo(0.5, 1e-9));
    });

    test('an empty signature pad gives no annotation', () {
      expect(SignatureAnnotation.fromPadStrokes(id: 's', strokes: const [], color: 0, pageAspect: 1), isNull);
    });

    test('eraser hit test finds the topmost nearby stroke only', () {
      final strokes = <Annotation>[
        ink('low', const [NormPoint(0.1, 0.5), NormPoint(0.9, 0.5)]),
        ink('high', const [NormPoint(0.5, 0.1), NormPoint(0.5, 0.9)]),
      ];
      expect(hitInk(strokes, const NormPoint(0.5, 0.5), aspect: 0.75)?.id, 'high');
      expect(hitInk(strokes, const NormPoint(0.2, 0.505), aspect: 0.75)?.id, 'low');
      expect(hitInk(strokes, const NormPoint(0.2, 0.2), aspect: 0.75), isNull);
    });
  });

  group('saving', () {
    test('file names are made safe and end in .pdf', () {
      expect(PdfEditSaver.safeFileName('Lease_edited.pdf'), 'Lease_edited.pdf');
      expect(PdfEditSaver.safeFileName('a/b:c'), 'a_b_c.pdf');
      expect(PdfEditSaver.safeFileName('  '), 'Document.pdf');
      expect(PdfEditSaver.safeFileName('../x'), 'Document.._x.pdf');
      expect(PdfEditSaver.defaultFileName('Lease.PDF'), 'Lease_edited.pdf');
    });

    test('saves pages in the edited order with their sizes and marks', () async {
      open3();
      final pages = state().pages;
      controller().addAnnotation(pages[0].id, ink('a', const [NormPoint(0.1, 0.1), NormPoint(0.9, 0.9)]));
      controller().addAnnotation(
        pages[0].id,
        const TextAnnotation(id: 't', origin: NormPoint(0.1, 0.8), text: 'Approved', color: 0xFFC62828),
      );
      controller().addAnnotation(
        pages[0].id,
        SignatureAnnotation.fromPadStrokes(
          id: 's',
          strokes: const [
            [(0.0, 0.0), (50.0, 20.0), (100.0, 0.0)],
          ],
          color: 0xFF14213D,
          pageAspect: pages[0].aspect,
        )!,
      );
      controller().movePage(2, 0);
      controller().deletePage(state().pages[2].id); // source page 2

      final progress = <double>[];
      final file = await container
          .read(pdfEditSaverProvider)
          .save(
            sourcePath: '/tmp/source.pdf',
            pages: state().pages,
            quality: ExportQuality.medium,
            fileName: 'Lease_edited',
            onProgress: (d, t) => progress.add(d / t),
          );

      expect(rasterizer.requests.single, [3, 1]);
      expect(file.path, endsWith(path.join('exports', 'Lease_edited.pdf')));
      expect(progress.last, 1.0);
      final bytes = file.readAsBytesSync();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(File('${file.path}.part').existsSync(), isFalse);
      final text = latin1Text(bytes);
      expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 2);
      final boxes = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)')
          .allMatches(text)
          .map((m) => '${m[1]}x${m[2]}');
      expect(boxes.toList(), ['792x612', '612x792']);

      final out = Platform.environment['PDF_EDIT_TEST_OUT'];
      if (out != null) file.copySync(out);
    });

    test('flattening needs at least one page', () {
      expect(() => buildEditedPdf(const []), throwsArgumentError);
    });
  });
}

String latin1Text(Uint8List bytes) => String.fromCharCodes(bytes);
