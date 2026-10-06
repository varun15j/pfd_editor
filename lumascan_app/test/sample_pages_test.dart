import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/debug/sample_pages.dart';
import 'package:lumascan/imaging/page_detector.dart';
import 'package:lumascan/imaging/rgb_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every sample page is bundled and its page is found', () async {
    for (final asset in samplePageAssets) {
      final data = await rootBundle.load(asset);
      final photo = RgbImage.decode(data.buffer.asUint8List(), maxDimension: 640);
      expect(detectPageQuad(photo), isNotNull, reason: asset);
    }
  });

  test('the open notebook is outlined without the strip of its facing page', () async {
    final data = await rootBundle.load('sample_photos/05_revision_grocery_table.jpg');
    final quad = detectPageQuad(RgbImage.decode(data.buffer.asUint8List(), maxDimension: 640))!;
    // The facing page starts about 85% across the photo.
    expect(quad.tr.x, inInclusiveRange(0.8, 0.9));
    expect(quad.br.x, inInclusiveRange(0.8, 0.9));
    expect(quad.tl.x, lessThan(0.2));
  });

  test('sample pages are copied to files the photo import can read', () async {
    final temp = Directory.systemTemp.createTempSync('lumascan_samples');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => temp.path,
    );
    addTearDown(() => temp.deleteSync(recursive: true));

    final photos = await loadSamplePages();
    expect(photos.map((p) => p.name), [for (final a in samplePageAssets) a.split('/').last]);
    for (final p in photos) {
      expect(File(p.path).lengthSync(), greaterThan(100000), reason: p.name);
    }
  });

  test('the 20 book photos are bundled at 1080 x 1920 and copy for import', () async {
    expect(bookSamples.assets, hasLength(20));
    expect(sampleSets, [mathSamples, bookSamples]);
    for (final asset in bookSamples.assets) {
      final photo = RgbImage.decode((await rootBundle.load(asset)).buffer.asUint8List());
      expect((photo.width, photo.height), (1080, 1920), reason: asset);
    }

    final temp = Directory.systemTemp.createTempSync('lumascan_book');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => temp.path,
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    final photos = await loadSamplePages(set: bookSamples);
    expect(photos.map((p) => p.name), [for (final a in bookSamples.assets) a.split('/').last]);
  });

  test('a flat book page is outlined', () async {
    // 03: one page, flat, nothing over it.
    final data = await rootBundle.load('sample_photos/book/03_straw_pipette.jpg');
    final quad = detectPageQuad(RgbImage.decode(data.buffer.asUint8List(), maxDimension: 640))!;
    expect(quad.tl.x, inInclusiveRange(0.05, 0.2));
    expect(quad.br.x, inInclusiveRange(0.85, 1.0));
  });

  test('a strip of a page is not taken for a page', () async {
    // 05: the detector used to keep only a thin strip at the right edge.
    final data = await rootBundle.load('sample_photos/book/05_bend_a_straw.jpg');
    expect(detectPageQuad(RgbImage.decode(data.buffer.asUint8List(), maxDimension: 640)), isNull);
  });
}
