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
}
