import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/photo_import.dart';

/// A set of bundled phone photos to add as pages in a debug build.
class SampleSet {
  const SampleSet({required this.title, required this.subtitle, required this.assets});

  final String title;
  final String subtitle;
  final List<String> assets;
}

/// The phone photos of math revision pages in `sample_photos/`, bundled so
/// batch edit and page detection can be tried on real pages in a debug
/// build without a camera (the emulator camera shows no paper). Each has
/// its own hard case: fingers, torn edges, other sheets, a facing page.
const mathSamples = SampleSet(
  title: 'Add sample pages',
  subtitle: 'The 5 math revision photos, auto-cropped, for testing batch edit',
  assets: [
    'sample_photos/01_revision1_palindrome_lengths.jpg',
    'sample_photos/02_revision2_multiplication.jpg',
    'sample_photos/03_revision3_conversions_shapes.jpg',
    'sample_photos/04_revision4_lengths.jpg',
    'sample_photos/05_revision_grocery_table.jpg',
  ],
);

/// Phone photos of a printed black-and-white book held open on a lap, in
/// `sample_photos/book/`: two-page spreads, curved pages, fingers, busy
/// backgrounds. Picked from real scans on the CPH2661 for sharp text.
const bookSamples = SampleSet(
  title: 'Add book pages',
  subtitle: '20 photos of an open printed book, auto-cropped, for testing every feature',
  assets: [
    'sample_photos/book/01_contents.jpg',
    'sample_photos/book/02_drinking_straw.jpg',
    'sample_photos/book/03_straw_pipette.jpg',
    'sample_photos/book/04_medicine_dropper.jpg',
    'sample_photos/book/05_bend_a_straw.jpg',
    'sample_photos/book/06_straw_wheels.jpg',
    'sample_photos/book/07_center_of_gravity.jpg',
    'sample_photos/book/08_flash_hand.jpg',
    'sample_photos/book/09_more_than_lemonade.jpg',
    'sample_photos/book/10_balloon_soda.jpg',
    'sample_photos/book/11_rock_tester.jpg',
    'sample_photos/book/12_lemon_soda.jpg',
    'sample_photos/book/13_fat_light_meter.jpg',
    'sample_photos/book/14_magnifying_glass.jpg',
    'sample_photos/book/15_mining_salt.jpg',
    'sample_photos/book/16_tough_newspaper.jpg',
    'sample_photos/book/17_why_no_flood.jpg',
    'sample_photos/book/18_lemon_life_saver.jpg',
    'sample_photos/book/19_hard_boiled_egg.jpg',
    'sample_photos/book/20_grandfather_clock.jpg',
  ],
);

/// Every bundled set, in the order they are offered.
const sampleSets = [mathSamples, bookSamples];

/// The math revision photos (the first set).
final samplePageAssets = mathSamples.assets;

/// Copies the photos of [set] to temporary files and returns them as picked
/// photos, ready for the normal photo import.
Future<List<PickedPhoto>> loadSamplePages({AssetBundle? bundle, SampleSet set = mathSamples}) async {
  final from = bundle ?? rootBundle;
  final dir = Directory('${(await getTemporaryDirectory()).path}/sample_pages');
  await dir.create(recursive: true);
  return [for (final asset in set.assets) await _copy(from, asset, dir)];
}

Future<PickedPhoto> _copy(AssetBundle bundle, String asset, Directory dir) async {
  final name = asset.split('/').last;
  final file = File('${dir.path}/$name');
  final data = await bundle.load(asset);
  await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
  return PickedPhoto(path: file.path, name: name);
}
