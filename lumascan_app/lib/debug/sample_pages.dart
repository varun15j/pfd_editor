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

/// Phone photos of the "ODDS BOOOK" document scanned on the CPH2661
/// (OnePlus) debug build on 16 October 2026, in `sample_scan_img/odds_book/`:
/// a colour craft book held open, with a laptop screen, cables and feet
/// around it. Test pages for the text PDF (OCR) build.
const oddsBookSamples = SampleSet(
  title: 'Add odds book pages',
  subtitle: '6 photos of an open colour book, auto-cropped, for testing text PDFs',
  assets: [
    'sample_scan_img/odds_book/01_post_box.jpg',
    'sample_scan_img/odds_book/02_ink_pad_stamp.jpg',
    'sample_scan_img/odds_book/03_camera_photos.jpg',
    'sample_scan_img/odds_book/04_binoculars.jpg',
    'sample_scan_img/odds_book/05_rocket_control_panel.jpg',
    'sample_scan_img/odds_book/06_moon_rocket.jpg',
  ],
);

/// Made-up photos for testing page edge detection, in `sample_photos/edge/`:
/// colour pages, black-and-white pages and open books on different surfaces,
/// built from real page content by `tool/make_edge_samples.py`, so the page
/// corners are known exactly (`sample_photos/edge/corners.json`).
const edgeSamples = SampleSet(
  title: 'Add edge test pages',
  subtitle: '19 colour, black and white and book pages, auto-cropped, for testing edge detection',
  assets: [
    'sample_photos/edge/c01_colour_page_dark_wood.jpg',
    'sample_photos/edge/c02_colour_page_beige_table.jpg',
    'sample_photos/edge/c03_pink_paper_concrete.jpg',
    'sample_photos/edge/c04_yellow_paper_light_wood.jpg',
    'sample_photos/edge/c05_blue_form_blue_cloth.jpg',
    'sample_photos/edge/c06_colour_page_carpet_perspective.jpg',
    'sample_photos/edge/c07_colour_page_black_desk_turned.jpg',
    'sample_photos/edge/b01_bw_paper_black_desk.jpg',
    'sample_photos/edge/b02_bw_paper_concrete_shadow.jpg',
    'sample_photos/edge/b03_bw_paper_white_bedsheet.jpg',
    'sample_photos/edge/b04_bw_paper_fingers_wood.jpg',
    'sample_photos/edge/b05_bw_narrow_slip_black_desk.jpg',
    'sample_photos/edge/b06_bw_paper_carpet_grey_photo.jpg',
    'sample_photos/edge/b07_colour_page_wood_grey_photo.jpg',
    'sample_photos/edge/k01_colour_book_spread_wood.jpg',
    'sample_photos/edge/k02_bw_book_spread_cloth.jpg',
    'sample_photos/edge/k03_colour_book_one_page_thumb.jpg',
    'sample_photos/edge/k04_bw_book_one_page_dark.jpg',
    'sample_photos/edge/k05_bw_book_spread_grey_photo.jpg',
  ],
);

/// Camera photos of a colour textbook (NCERT Class 6 Social Science) open on
/// a wooden desk, in `sample_photos/colour_book/`, taken with the LumaScan
/// camera on the CPH2661 (OnePlus) on 26 October 2026: the facing page in
/// view, pens, a pencil case, a laptop, a hand or an arm over some pages,
/// two blurred page turns.
const colourBookSamples = SampleSet(
  title: 'Add colour book pages',
  subtitle: '22 photos of an open colour textbook, auto-cropped, for testing edge detection',
  assets: [
    'sample_photos/colour_book/01_letter_to_student.jpg',
    'sample_photos/colour_book/02_your_journey.jpg',
    'sample_photos/colour_book/03_page_turning_hand.jpg',
    'sample_photos/colour_book/04_constitution_preamble.jpg',
    'sample_photos/colour_book/05_textbook_team.jpg',
    'sample_photos/colour_book/06_why_social_science.jpg',
    'sample_photos/colour_book/07_city_photo.jpg',
    'sample_photos/colour_book/08_cultural_heritage.jpg',
    'sample_photos/colour_book/09_map_components.jpg',
    'sample_photos/colour_book/10_map_symbols.jpg',
    'sample_photos/colour_book/11_globe_chessboard.jpg',
    'sample_photos/colour_book/12_globe_shadow.jpg',
    'sample_photos/colour_book/13_globe_arm_over.jpg',
    'sample_photos/colour_book/14_globe_longitudes.jpg',
    'sample_photos/colour_book/15_globe_left_page.jpg',
    'sample_photos/colour_book/16_globe_hand_blur.jpg',
    'sample_photos/colour_book/17_festivals_photos.jpg',
    'sample_photos/colour_book/18_ellora_caves.jpg',
    'sample_photos/colour_book/19_ellora_think.jpg',
    'sample_photos/colour_book/20_schools_of_thought.jpg',
    'sample_photos/colour_book/21_great_bath.jpg',
    'sample_photos/colour_book/22_india_bharat_chapter.jpg',
  ],
);

/// Every bundled set, in the order they are offered.
const sampleSets = [mathSamples, bookSamples, oddsBookSamples, edgeSamples, colourBookSamples];

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
