import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/photo_import.dart';

/// The phone photos of math revision pages in `sample_photos/`, bundled so
/// batch edit and page detection can be tried on real pages in a debug
/// build without a camera (the emulator camera shows no paper). Each has
/// its own hard case: fingers, torn edges, other sheets, a facing page.
const samplePageAssets = [
  'sample_photos/01_revision1_palindrome_lengths.jpg',
  'sample_photos/02_revision2_multiplication.jpg',
  'sample_photos/03_revision3_conversions_shapes.jpg',
  'sample_photos/04_revision4_lengths.jpg',
  'sample_photos/05_revision_grocery_table.jpg',
];

/// Copies the bundled sample photos to temporary files and returns them as
/// picked photos, ready for the normal photo import.
Future<List<PickedPhoto>> loadSamplePages({AssetBundle? bundle}) async {
  final from = bundle ?? rootBundle;
  final dir = Directory('${(await getTemporaryDirectory()).path}/sample_pages');
  await dir.create(recursive: true);
  return [for (final asset in samplePageAssets) await _copy(from, asset, dir)];
}

Future<PickedPhoto> _copy(AssetBundle bundle, String asset, Directory dir) async {
  final name = asset.split('/').last;
  final file = File('${dir.path}/$name');
  final data = await bundle.load(asset);
  await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
  return PickedPhoto(path: file.path, name: name);
}
