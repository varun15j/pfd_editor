import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/imaging/page_renderer.dart';
import 'package:lumascan/imaging/render_queue.dart';
import 'package:lumascan/imaging/render_service.dart';

void main() {
  group('RenderQueue', () {
    test('runs at most its concurrency at once, newest request first', () async {
      final queue = RenderQueue(concurrency: 2);
      final gates = <String, Completer<void>>{};
      final order = <String>[];
      Future<String> job(String key) {
        gates[key] = Completer<void>();
        return queue.run(key, () async {
          order.add(key);
          await gates[key]!.future;
          return key;
        });
      }

      final results = [
        for (final k in ['a', 'b', 'c', 'd']) job(k),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(order, ['a', 'b']);
      gates['a']!.complete();
      await results[0];
      await Future<void>.delayed(Duration.zero);
      expect(order, ['a', 'b', 'd'], reason: 'the newest waiting request goes next');
      gates['b']!.complete();
      gates['d']!.complete();
      await Future<void>.delayed(Duration.zero);
      gates['c']!.complete();
      expect(await Future.wait(results), ['a', 'b', 'c', 'd']);
      expect(queue.peakRunning, 2);
    });

    test('asking again for a waiting job moves it to the front and shares its result', () async {
      final queue = RenderQueue(concurrency: 1);
      final gate = Completer<void>();
      final order = <String>[];
      final first = queue.run('busy', () async {
        order.add('busy');
        await gate.future;
        return 0;
      });
      final x = queue.run('x', () async => order.add('x'));
      final y = queue.run('y', () async => order.add('y'));
      final again = queue.run('x', () async => order.add('x twice'));
      gate.complete();
      await Future.wait([first, x, y, again]);
      expect(order, ['busy', 'x', 'y']);
      expect(queue.started, 3);
    });

    test('a failed job reports its error and the queue keeps going', () async {
      final queue = RenderQueue(concurrency: 1);
      final failed = queue.run<int>('bad', () async => throw StateError('broken'));
      final next = queue.run('good', () async => 7);
      await expectLater(failed, throwsStateError);
      expect(await next, 7);
    });
  });

  group('jpegSize', () {
    test('reads the size from the header', () {
      final bytes = img.encodeJpg(img.Image(width: 123, height: 45));
      expect(jpegSize(bytes), (123, 45));
    });

    test('is null for anything that is not a JPEG', () {
      expect(jpegSize(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
      expect(jpegSize(img.encodePng(img.Image(width: 4, height: 4))), isNull);
    });
  });

  group('RenderService', () {
    late Directory tmp;
    late PageStore store;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('render_pipeline');
      store = PageStore(rootDir: () async => tmp);
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    /// A landscape "camera photo" larger than the working preview.
    Future<ScanPage> addPage(String id, {int width = 2400, int height = 1800}) async {
      final photo = img.Image(width: width, height: height);
      img.fill(photo, color: img.ColorRgb8(240, 236, 220));
      img.fillRect(photo, x1: 100, y1: 100, x2: 600, y2: 400, color: img.ColorRgb8(20, 20, 20));
      final source = File('${tmp.path}/camera_$id.jpg')..writeAsBytesSync(img.encodeJpg(photo));
      return ScanPage(id: id, originalPath: await store.importOriginal(source.path, id));
    }

    test('the original is decoded once; every size and recipe renders from the working copies', () async {
      final queue = RenderQueue(concurrency: 2);
      final service = RenderService(store, queue: queue);
      final page = await addPage('p1');

      final thumb = await service.render(page, maxDimension: RenderService.thumbnailSize);
      final preview = await service.render(
        page,
        recipe: const EditRecipe(filter: DocumentFilter.grayscale),
        maxDimension: RenderService.previewSize,
      );
      final tile = await service.render(
        page,
        recipe: const EditRecipe(filter: DocumentFilter.blackWhite),
        maxDimension: 240,
      );

      // One job for the working copies, then one per rendered picture.
      expect(queue.started, 4);
      expect(File(PageStore.workingPreviewPath(page.originalPath)).existsSync(), isTrue);
      expect(File(PageStore.workingSmallPath(page.originalPath)).existsSync(), isTrue);
      expect(thumb.width, RenderService.thumbnailSize);
      expect(preview.width, RenderService.previewSize);
      expect(tile.width, 240);
      expect(jpegSize(File(tile.path).readAsBytesSync()), (tile.width, tile.height));
    });

    test('the working copies keep the page upright and shrink it', () async {
      final service = RenderService(store, queue: RenderQueue(concurrency: 1));
      final page = await addPage('p1', width: 1200, height: 3000);
      final copies = await service.workingCopies(page);
      expect((copies.preview.width, copies.preview.height), (640, RenderService.previewSize));
      expect((copies.small.width, copies.small.height), (256, RenderService.smallSourceSize));
    });

    test('a photo taken sideways is turned upright, the same way by both decoders', () async {
      // Stored landscape with a dark block top-left, and EXIF saying "turn
      // 90° clockwise": upright, it is portrait with the block top-right.
      final photo = img.Image(width: 2000, height: 1000);
      img.fill(photo, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(photo, x1: 0, y1: 0, x2: 400, y2: 400, color: img.ColorRgb8(0, 0, 0));
      photo.exif.imageIfd.orientation = 6;
      final source = File('${tmp.path}/sideways.jpg')..writeAsBytesSync(img.encodeJpg(photo));
      final page = ScanPage(id: 's', originalPath: await store.importOriginal(source.path, 's'));

      bool darkTopRight(String path) {
        final upright = img.decodeJpg(File(path).readAsBytesSync())!;
        final w = upright.width, h = upright.height;
        return upright.getPixel(w - w ~/ 20, h ~/ 20).r < 60 && upright.getPixel(w ~/ 20, h ~/ 20).r > 200;
      }

      final native = await RenderService(store, queue: RenderQueue(concurrency: 1)).workingCopies(page);
      expect((native.preview.width, native.preview.height), (800, RenderService.previewSize));
      expect(darkTopRight(native.preview.path), isTrue);
      expect(darkTopRight(native.small.path), isTrue);

      final dart = await makeWorkingCopies(
        originalPath: page.originalPath,
        previewPath: '${tmp.path}/dart_preview.jpg',
        smallPath: '${tmp.path}/dart_small.jpg',
        previewSize: RenderService.previewSize,
        smallSize: RenderService.smallSourceSize,
      );
      expect((dart.preview.width, dart.preview.height), (native.preview.width, native.preview.height));
      expect(darkTopRight(dart.preview.path), isTrue);
    });

    test('the crop screen gets the working preview itself, with no extra render', () async {
      final queue = RenderQueue(concurrency: 1);
      final service = RenderService(store, queue: queue);
      final page = await addPage('p1');
      final source = await service.source(page);
      expect(source.path, PageStore.workingPreviewPath(page.originalPath));
      expect(queue.started, 1);
    });

    test('after a restart, pictures already on disk are reused without decoding anything', () async {
      final page = await addPage('p1');
      await RenderService(store).render(page, maxDimension: RenderService.thumbnailSize);

      final queue = RenderQueue(concurrency: 1);
      final restarted = RenderService(store, queue: queue);
      final thumb = await restarted.render(page, maxDimension: RenderService.thumbnailSize);
      await restarted.source(page);
      expect(queue.started, 0);
      expect(thumb.width, RenderService.thumbnailSize);
    });

    test('twenty pages opened together never decode more than the queue allows at once', () async {
      final queue = RenderQueue(concurrency: 2);
      final service = RenderService(store, queue: queue);
      final pages = [for (var i = 0; i < 20; i++) await addPage('p$i', width: 800, height: 600)];
      final thumbs = await Future.wait([
        for (final p in pages) service.render(p, maxDimension: RenderService.thumbnailSize),
      ]);
      expect(thumbs, hasLength(20));
      expect(queue.peakRunning, lessThanOrEqualTo(2));
      expect(queue.started, 40, reason: 'one working-copy job and one thumbnail per page');
    });

    test('prepare makes the working copies and thumbnail of new pages in the background', () async {
      final queue = RenderQueue(concurrency: 2);
      final service = RenderService(store, queue: queue);
      final page = await addPage('p1');
      service.prepare([page]);
      // Asking now joins the job already under way.
      await service.render(page, maxDimension: RenderService.thumbnailSize);
      expect(queue.started, 2);
      expect(File(PageStore.workingSmallPath(page.originalPath)).existsSync(), isTrue);
    });

    test('deleting an original deletes its working copies', () async {
      final service = RenderService(store, queue: RenderQueue(concurrency: 1));
      final page = await addPage('p1');
      await service.workingCopies(page);
      await store.deleteOriginal(page.originalPath);
      expect(File(page.originalPath).existsSync(), isFalse);
      expect(File(PageStore.workingPreviewPath(page.originalPath)).existsSync(), isFalse);
      expect(File(PageStore.workingSmallPath(page.originalPath)).existsSync(), isFalse);
    });
  });
}
